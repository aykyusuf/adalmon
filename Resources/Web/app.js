'use strict';
// Adalmon ofis (tarayıcı): vanilla JS + Canvas 2D, dış istek yok. Sahne verisi /v1/layout'tan (Swift tek doğruluk kaynağı),
// canlı durum /v1/stream (SSE) üzerinden gelir. Balon metinleri, koltuk atamaları, roller ve boşta varyantları sunucudan hazır gelir.
// Görünüm: modern VEKTÖR tema (docs/OFFICE-V4.md): pişirilmiş 4x oda arka planları, karakter atlası + gömlek maskesi, gece/gündüz ışığı.
//
// Bölümler: Ağ/çözme · Karakter atlası · Işık · Odalar ve oyuncular · Yerleşim/kamera · Çizim · Kart/ipucu · Döngü · Etkileşim · SSE · Başlangıç
(() => {
  const T = 16;
  const TEST = globalThis.__ADALMON_TEST__ || null;
  const params = new URLSearchParams(location.search);
  let token = params.get('t') || sessionStorage.getItem('adalmon-token') || '';
  if (params.get('t')) {
    sessionStorage.setItem('adalmon-token', token);
    history.replaceState(null, '', location.pathname); // token adres çubuğunda/geçmişte kalmasın
  }
  const store = {
    get(k) { try { return localStorage.getItem(k); } catch (e) { return null; } },
    set(k, v) { try { localStorage.setItem(k, v); } catch (e) { /* özel mod */ } },
  };

  const $ = (id) => document.getElementById(id);
  const canvas = $('scene');
  const ctx = canvas.getContext('2d');
  const els = { dot: $('dot'), conn: $('conn'), counts: $('counts'), empty: $('empty'), error: $('error'), back: $('back'),
                light: $('light'), loading: $('loading'), loadingText: $('loadingText'), tip: $('tip'), card: $('card'),
                dock: $('dock'), fs: $('fs'), pills: $('pills'), pillL: $('pillL'), pillR: $('pillR'), pillTime: $('pillTime'), pillDay: $('pillDay') };

  let layout = null;
  let assets = null;             // çözülmüş görseller (ImageBitmap) ve dizinler
  const tierData = new Map();    // kademe -> {bg, w, h, ox, oy, dynamic[], seatById, ...}
  const rooms = new Map();
  let state = null;
  let skew = 0;                  // sunucu saati - yerel saat
  let initialized = false;
  let focusId = null;
  let hitRooms = [];
  let hitActors = [];
  let hitBoards = [];
  let hitRacks = [];
  let dpr = 1;
  let U = 1;                     // arayüz ölçeği (piksel): dpr * ekran yüksekliğine göre 1x (900 px) .. 2x
  let S = 1;
  let needsRedraw = true;
  let selected = null;           // açık kart: {a}
  let hover = null;

  const nowMs = () => Date.now();
  const serverNow = () => Date.now() + skew;
  const clamp = (v, lo, hi) => Math.min(hi, Math.max(lo, v));

  // ---------- Küçük yardımcılar ----------
  function hash32(s) {
    let h = 2166136261 >>> 0;
    for (let i = 0; i < s.length; i++) { h ^= s.charCodeAt(i); h = Math.imul(h, 16777619) >>> 0; }
    return h >>> 0;
  }
  function rng(seed) {
    let a = (typeof seed === 'string' ? hash32(seed) : seed) >>> 0;
    return () => {
      a = (a + 0x6D2B79F5) >>> 0;
      let t = a;
      t = Math.imul(t ^ (t >>> 15), t | 1);
      t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
  }
  function hexRgb(hex) {
    const m = /^#?([0-9a-f]{6})$/i.exec(hex || '');
    const n = m ? parseInt(m[1], 16) : 0x888888;
    return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
  }
  const rgbCss = (c, a) => `rgba(${Math.round(c[0] * 255)},${Math.round(c[1] * 255)},${Math.round(c[2] * 255)},${a === undefined ? 1 : a})`;
  const hexCss = (hex, a) => { const c = hexRgb(hex); return `rgba(${c[0]},${c[1]},${c[2]},${a === undefined ? 1 : a})`; };
  function newCanvas(w, h) {
    const c = document.createElement('canvas');
    c.width = w; c.height = h;
    return c;
  }
  const fmtDur = (ms) => {
    const s = Math.max(0, Math.floor(ms / 1000));
    const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), sec = s % 60;
    const p = (n) => String(n).padStart(2, '0');
    return h > 0 ? `${h}:${p(m)}:${p(sec)}` : `${p(m)}:${p(sec)}`;
  };

  // ---------- Ağ ve çözme ----------
  class HttpError extends Error { constructor(status) { super(String(status)); this.status = status; } }

  async function api(path) {
    const res = await fetch(path, { headers: { 'X-Adalmon-Token': token }, cache: 'no-store' });
    if (!res.ok) throw new HttpError(res.status);
    return res;
  }

  function describeError(err) {
    const st = err && err.status;
    if (st === 401) return 'Oturum anahtarı geçersiz ya da süresi dolmuş (401). Adalmon > Ayarlar > Claude ajanları > "Tarayıcıda aç" ile sayfayı yeniden açın.';
    if (st === 404) return 'Ofis verisi bulunamadı (404): tarayıcı görünümü kapalı olabilir ya da Adalmon ofis varlıklarını yükleyememiş. Ayarlar > Claude ajanları bölümünü kontrol edin.';
    return 'Sayfa verisi alınamadı (' + (err && err.message ? err.message : 'bilinmeyen hata') + '). Adalmon açık değilse ya da oturum anahtarı değiştiyse "Tarayıcıda aç" ile yeniden açın.';
  }

  function showError(text) { els.error.textContent = text; els.error.hidden = !text; }
  function setLoading(text) {
    if (!els.loading) return;
    els.loading.hidden = !text;
    if (els.loadingText) els.loadingText.textContent = text || '';
  }

  // CSP `connect-src 'self'` data: adreslerine fetch'i engeller: base64'ü elle çöz, Blob'tan ImageBitmap üret.
  function dataToBlob(uri) {
    const i = uri.indexOf(',');
    if (i < 0) throw new Error('geçersiz veri adresi');
    const bin = atob(uri.slice(i + 1));
    const bytes = new Uint8Array(bin.length);
    for (let k = 0; k < bin.length; k++) bytes[k] = bin.charCodeAt(k);
    return new Blob([bytes], { type: 'image/png' });
  }

  async function decode(name, uri, opts) {
    try {
      if (typeof uri !== 'string' || uri.indexOf('data:') !== 0) throw new Error('veri yok');
      const blob = dataToBlob(uri);
      try { return await createImageBitmap(blob, opts); } catch (e) { if (!opts) throw e; return await createImageBitmap(blob); }
    } catch (e) {
      throw new Error(name + ' çözülemedi (' + (e && e.message ? e.message : e) + ')');
    }
  }

  // ---------- Hazırlık ----------
  async function prepare() {
    setLoading('Ofis yükleniyor…');
    layout = await (await api('/v1/layout')).json();
    const v = layout.v3 && layout.v3.vector;
    if (layout.theme !== 'vector' || !v || !v.characters || !v.characters.atlas || !v.backgrounds) {
      throw new Error('vektör tema verisi yok: bu Adalmon sürümü yalnızca eski piksel temayı gönderiyor, Adalmon\'u güncelleyin');
    }
    const scale = v.scale || 4;
    assets = { scale, bg: {}, furn: {}, gen: {}, boardWrite: [], boardOrigin: v.boardWriteOrigin || [5, 12], door: null, winDay: null, winNight: null,
               atlas: null, acc: null };
    const jobs = [];
    const job = (name, uri, assign, opts) => jobs.push({ name, uri, assign, opts });
    for (const [tier, b] of Object.entries(v.backgrounds)) job('backgrounds.' + tier, b.image, (bmp) => { assets.bg[tier] = { bmp, windows: b.windows || [] }; });
    for (const [id, uri] of Object.entries(v.furniture || {})) job('furniture.' + id, uri, (bmp) => { assets.furn[id] = bmp; });
    for (const [led, uri] of Object.entries((v.rack && v.rack.dots) || {})) job('rack.' + led, uri, (bmp) => { assets.rackDots = assets.rackDots || {}; assets.rackDots[led] = bmp; });
    for (const [id, uri] of Object.entries(v.generated || {})) job('generated.' + id, uri, (bmp) => { assets.gen[id] = bmp; });
    job('door', v.door, (bmp) => { assets.door = bmp; });
    (v.boardWrite || []).forEach((uri, i) => job('boardWrite[' + i + ']', uri, (bmp) => { assets.boardWrite[i] = bmp; }));
    job('windowDay', v.windowDay, (bmp) => { assets.winDay = bmp; });
    job('windowNight', v.windowNight, (bmp) => { assets.winNight = bmp; });
    const ch = v.characters;
    const cell = ch.cell || [96, 128];
    const index = new Map();
    for (const e of ch.atlas.index) index.set(e.look + '|' + e.direction + '|' + e.frame, e);
    const accIndex = new Map();
    if (ch.accessories) for (const e of ch.accessories.index) accIndex.set(e.name + '|' + e.direction, e);
    assets.atlas = { img: null, mask: null, index, cellW: cell[0], cellH: cell[1] };
    job('characters.atlas.image', ch.atlas.image, (bmp) => { assets.atlas.img = bmp; });
    job('characters.atlas.mask', ch.atlas.mask, (bmp) => { assets.atlas.mask = bmp; }, { colorSpaceConversion: 'none', premultiplyAlpha: 'none' });
    if (ch.accessories) {
      assets.acc = { img: null, index: accIndex };
      job('characters.accessories.image', ch.accessories.image, (bmp) => { assets.acc.img = bmp; });
    }
    let done = 0;
    const queue = jobs.slice();
    const worker = async () => {
      while (queue.length) {
        const j = queue.shift();
        j.assign(await decode(j.name, j.uri, j.opts));
        done += 1;
        setLoading(`Ofis yükleniyor… (${done}/${jobs.length})`);
      }
    };
    await Promise.all([worker(), worker(), worker(), worker()]);
    for (const [key, t] of Object.entries(layout.tiers)) {
      if (!assets.bg[key]) throw new Error('backgrounds.' + key + ' eksik');
      tierData.set(key, buildTier(key, t));
    }
    initLighting();
    setLoading('');
  }

  function buildTier(key, t) {
    const a = assets.bg[key];
    const b = t.bounds;
    const td = { key, t, bg: a.bmp, w: a.bmp.width / assets.scale, h: a.bmp.height / assets.scale, ox: b.minCol * T, oy: b.minRow * T,
                 windows: a.windows, dynamic: [], seatById: new Map(t.seats.map((s) => [s.id, s])), placementByIndex: new Map(),
                 blocked: null, doorTile: t.door, board: t.board || null, rack: t.rack || null };
    const sorted = t.furniture.slice().sort((p, q) => p.z - q.z);
    for (const p of sorted) {
      td.placementByIndex.set(p.i, p);
      if (p.z >= 0) td.dynamic.push(p);          // z < 0: oda arka planına pişirilmiş
    }
    td.boardPlacement = t.boardIndex !== undefined ? td.placementByIndex.get(t.boardIndex) || null : null;
    return td;
  }

  // ---------- Karakter atlası ----------
  const sheetCache = new Map();
  let scratchA = null, scratchM = null, accNightCanvas = null;

  function scratch(which, w, h) {
    let c = which === 'a' ? scratchA : scratchM;
    if (!c || c.width !== w || c.height !== h) {
      c = newCanvas(w, h);
      if (which === 'a') scratchA = c; else scratchM = c;
    }
    const g = c.getContext('2d', { willReadFrequently: true });
    g.clearRect(0, 0, w, h);
    return { c, g };
  }

  function liftFactors() {
    const m = lightParams().multiplyColor;
    return m.map((x) => Math.pow(1 / Math.max(0.05, x), 0.8));
  }

  // Gömlek rengi: rgb * lerp(beyaz, gömlek, maske); gece: sahne çarpanının (0.8 üssü) tersi ile aydınlatma (macOS `nightGrade` ile aynı mantık).
  function bakeSheet(look, shirtHex, night) {
    const key = look + '|' + shirtHex + '|' + (night ? 1 : 0);
    const hit = sheetCache.get(key);
    if (hit) return hit;
    const A = assets.atlas, rowH = A.cellH * 3, W = A.img.width;
    const a = scratch('a', W, rowH);
    a.g.drawImage(A.img, 0, look * rowH, W, rowH, 0, 0, W, rowH);
    const data = a.g.getImageData(0, 0, W, rowH);
    let mk = null;
    if (A.mask) {
      const m = scratch('m', W, rowH);
      m.g.drawImage(A.mask, 0, look * rowH, W, rowH, 0, 0, W, rowH);
      mk = m.g.getImageData(0, 0, W, rowH).data;
    }
    const sh = hexRgb(shirtHex).map((v) => v / 255);
    const lift = night ? liftFactors() : [1, 1, 1];
    const d = data.data;
    for (let i = 0; i < d.length; i += 4) {
      if (d[i + 3] === 0) continue;
      const m = mk ? mk[i] / 255 : 0;
      for (let c = 0; c < 3; c++) d[i + c] = clamp(d[i + c] * ((1 - m) + m * sh[c]) * lift[c], 0, 255);
    }
    const out = newCanvas(W, rowH);
    out.getContext('2d').putImageData(data, 0, 0);
    if (sheetCache.size >= 48) sheetCache.delete(sheetCache.keys().next().value);
    sheetCache.set(key, out);
    return out;
  }

  function accessorySource(night) {
    if (!night) return assets.acc.img;
    if (!accNightCanvas) {
      const W = assets.acc.img.width, H = assets.acc.img.height;
      const a = scratch('a', W, H);
      a.g.drawImage(assets.acc.img, 0, 0);
      const data = a.g.getImageData(0, 0, W, H);
      const lift = liftFactors(), d = data.data;
      for (let i = 0; i < d.length; i += 4) if (d[i + 3]) for (let c = 0; c < 3; c++) d[i + c] = clamp(d[i + c] * lift[c], 0, 255);
      accNightCanvas = newCanvas(W, H);
      accNightCanvas.getContext('2d').putImageData(data, 0, 0);
    }
    return accNightCanvas;
  }

  // Karakter görünümü: sunucudan gelen appearance/role (tint, aksesuar) kullanılır; JS'te eşleme tablosu yoktur.
  function lookOf(m) {
    const ap = m.appearance || (layout.appearance && (layout.appearance[m.badge] || layout.appearance.unknown)) || {};
    const role = m.role || {};
    let acc = role.accessory !== undefined ? role.accessory : ap.accessory;
    if (!acc || acc === 'none') acc = null;
    let shirt = ap.tint || role.tint || '#8A8F98';
    if (acc === 'vest') shirt = '#F2EBD8';      // yelek altı açık gömlek (yelek rengi atlasa sabit pişirilmiş)
    return { look: clamp(ap.character || 0, 0, 5), shirt, acc, small: !!ap.small };
  }

  const DIR_ROW = { down: 0, up: 1, right: 2, left: 2 };

  // Ayak noktası (x, y) mantıksal birim, oda uzayında. frame: atlas kare dizini.
  function drawSprite(look, shirt, dir, frame, acc, x, y, k, alpha, night) {
    const C = layout.v3.vector.characters, A = assets.atlas;
    const e = A.index.get(look + '|' + DIR_ROW[dir] + '|' + frame);
    if (!e) return;
    const sheet = bakeSheet(look, shirt, night);
    const fw = C.frameWidth * k, fh = C.frameHeight * k;
    ctx.save();
    ctx.globalAlpha *= alpha;
    ctx.translate(x, y);
    if (dir === 'left') ctx.scale(-1, 1);
    ctx.drawImage(sheet, e.x, e.y - look * A.cellH * 3, e.w, e.h, -fw / 2, -fh, fw, fh);
    if (acc && assets.acc) {
      const ae = assets.acc.index.get(acc + '|' + DIR_ROW[dir]);
      const bob = (C.bob && C.bob[frame]) || 0;
      if (ae) ctx.drawImage(accessorySource(night), ae.x, ae.y, ae.w, ae.h, -fw / 2, -fh + bob * k, fw, fh);
    }
    ctx.restore();
  }

  // ---------- Işık (gece / gündüz) ----------
  const DEFAULT_LIGHT = { multiplyColor: [0.60, 0.66, 0.88], washColor: [0.05, 0.10, 0.34], washAlpha: 0.22, bulbAlpha: 0.38, poolAlpha: 0.40,
                          boardAlpha: 0.30, screenAlpha: 0.9, windowAlpha: 0.22 };
  const light = { mode: 'auto', level: 0, serverNight: null, trustServer: false, cfg: { nightStartHour: 19, nightStartMinute: 30, nightEndHour: 6, nightEndMinute: 30 } };

  function lightParams() { return Object.assign({}, DEFAULT_LIGHT, layout && layout.v3 && layout.v3.vector && layout.v3.vector.lighting); }

  function initLighting() {
    const saved = store.get('adalmon-light');
    light.mode = saved === 'day' || saved === 'night' ? saved : 'auto';
    const base = layout.v3 && layout.v3.lighting;
    if (base) Object.assign(light.cfg, { nightStartHour: base.nightStartHour, nightStartMinute: base.nightStartMinute, nightEndHour: base.nightEndHour, nightEndMinute: base.nightEndMinute });
    if (els.light) els.light.value = light.mode;
    light.level = wantNight() ? 1 : 0;
  }

  function localNight(date) {
    const d = date || new Date();
    const c = light.cfg, m = d.getHours() * 60 + d.getMinutes();
    const s = c.nightStartHour * 60 + c.nightStartMinute, e = c.nightEndHour * 60 + c.nightEndMinute;
    return s > e ? (m >= s || m < e) : (m >= s && m < e);
  }

  function wantNight() {
    if (light.mode === 'day') return false;
    if (light.mode === 'night') return true;
    return light.trustServer && light.serverNight !== null ? light.serverNight : localNight();
  }

  function applyServerLighting(l) {
    if (!l) return;
    Object.assign(light.cfg, { nightStartHour: l.nightStartHour, nightStartMinute: l.nightStartMinute, nightEndHour: l.nightEndHour, nightEndMinute: l.nightEndMinute });
    light.serverNight = typeof l.resolvedNight === 'boolean' ? l.resolvedNight : null;
    light.trustServer = light.serverNight !== null && light.serverNight !== localNight();   // fark varsa sunucu esas
  }

  // 1 sn crossfade; seviye değiştiyse true.
  function stepLight(dt) {
    const target = wantNight() ? 1 : 0;
    if (light.level === target) return false;
    light.level = target > light.level ? Math.min(target, light.level + dt) : Math.max(target, light.level - dt);
    return true;
  }
  const lightAnimating = () => light.level !== (wantNight() ? 1 : 0);
  const uiNight = () => light.level > 0.5;

  // ---------- Odalar ve oyuncular ----------
  const pt = (c) => ({ x: c[0] * T + 8, y: (c[1] + 1) * T - 1 });   // karo alt-orta (mutlak mantıksal)
  const tileOf = (x, y) => [Math.floor(x / T), Math.floor((y + 1) / T) - 1];

  function newRoom(r) {
    return { id: r.id, tierKey: r.tier, td: tierData.get(r.tier), actors: new Map(), title: r.title, badge: r.badge, badgeLabel: r.badgeLabel,
             group: r.group, overflow: 0, leaving: false, alpha: 1, rect: null, computers: r.computers || {}, fade: null, fresh: null,
             cleaner: newCleaner(r), carrier: null, extras: [], trail: [], rack: r.rack || null, shells: r.shells || null };
  }

  function newCleaner(r) {
    const seed = (r.cleaner && r.cleaner.seed) || r.id;
    const c = r.cleaner || {};
    const lo = (c.intervalMin || 90) * 1000, hi = (c.intervalMax || 180) * 1000;
    const rnd = rng('cleaner|' + seed);
    return { rnd, lo, hi, next: nowMs() + lo + rnd() * (hi - lo), entity: null, laneRows: c.laneRows || [] };
  }

  function newActor(room, m, seat, instant) {
    const td = room.td;
    const a = { id: m.id, room, member: m, seat, path: [], goal: 'seat', x: 0, y: 0, dir: seat.facing, atSeat: false, execMode: null, strollUntil: 0,
                wait: 0, leaving: false, alpha: 1, walkT: 0, exec: seat.kind === 'executive', idle: null, look: 0, lookNext: 0, rnd: rng(room.id + '|' + m.id) };
    if (instant) { placeInstant(a); } else {
      const d = pt(td.doorTile);
      a.x = d.x; a.y = d.y; a.dir = 'left'; a.goal = 'seat';
      a.path = [pt(td.t.entrance)].concat(seat.enter.map(pt));
      a.alpha = 0;
    }
    return a;
  }

  // Yönetici tahta karosu zemin değilse (duvar karosu) ilk bölge karosuna düşer: duvarın içinde görünmesin.
  function boardTile(td) {
    const t = td.t;
    if (!t.board) return null;
    const i = (t.board[1] * t.cols + t.board[0]) * 4;
    if (t.tiles[i] === 2) return t.board;
    const z = (t.zoneTiles || []).find((c) => t.tiles[(c[1] * t.cols + c[0]) * 4] === 2);
    return z || t.board;
  }

  function placeInstant(a) {
    const td = a.room.td;
    a.path = [];
    if (a.exec && execDesired(a) === 'board' && td.t.board) {
      const p = pt(boardTile(td)); a.x = p.x; a.y = p.y; a.dir = 'up'; a.execMode = 'board'; a.atSeat = false; a.goal = 'board';
    } else {
      const p = pt([a.seat.col, a.seat.row]); a.x = p.x; a.y = p.y; a.dir = a.seat.facing; a.atSeat = true; a.goal = 'seat'; a.execMode = 'seated';
    }
  }

  function execDesired(a) {
    const st = a.member.status;
    if (st === 'thinking' || st === 'tool') return 'board';
    if (st === 'permission') return 'stroll';
    return nowMs() < a.strollUntil ? 'stroll' : 'seated';
  }

  function routeToBoard(a) {
    const td = a.room.td;
    a.goal = 'board'; a.wait = 0;
    if (a.atSeat && a.seat.toBoard) a.path = a.seat.toBoard.map(pt); else a.path = [pt(boardTile(td))];
    a.atSeat = false;
  }

  function routeToSeat(a) {
    const td = a.room.td;
    a.goal = 'seat';
    const back = a.seat.toBoard ? a.seat.toBoard.slice(0, -1).reverse().map(pt) : [];
    a.path = [pt(boardTile(td))].concat(back, [pt([a.seat.col, a.seat.row])]);
  }

  function setExecMode(a, mode) {
    if (a.execMode === mode || !a.room.td.t.board) return;
    a.execMode = mode;
    if (mode === 'seated') routeToSeat(a);
    else if (a.atSeat) routeToBoard(a);
    else { a.goal = 'board'; a.path = [pt(boardTile(a.room.td))]; }
    if (mode === 'stroll') a.goal = 'stroll-start';
  }

  // Yönetici bölgesinde basit yatay volta.
  function strollStep(a) {
    const td = a.room.td, t = td.t;
    const row = boardTile(td)[1];
    const tiles = (t.zoneTiles || []).filter((c) => c[1] === row);
    const here = Math.round((a.x - 8) / T);
    let pool = tiles.filter((c) => Math.abs(c[0] - here) >= 4 && Math.abs(c[0] - here) <= 6);
    if (!pool.length) {
      const others = tiles.filter((c) => c[0] !== here);
      const far = Math.max(0, ...others.map((c) => Math.abs(c[0] - here)));
      pool = far >= 2 ? others.filter((c) => Math.abs(c[0] - here) === far) : others;
    }
    if (!pool.length) { a.wait = 2; return; }
    a.path = [pt(pool[Math.floor(a.rnd() * pool.length)])];
    a.goal = 'stroll';
  }

  function startLeave(a) {
    if (a.leaving) return;
    const td = a.room.td;
    a.leaving = true; a.goal = 'out'; a.atSeat = false; a.idle = null;
    const door = pt(td.doorTile), ent = pt(td.t.entrance);
    const seatPath = a.seat.enter.slice(0, -1).reverse().map(pt);
    const nearSeat = Math.abs(a.x - (a.seat.col * T + 8)) < 1 && Math.abs(a.y - ((a.seat.row + 1) * T - 1)) < 1;
    a.path = (nearSeat ? seatPath.concat([ent]) : [ent]).concat([door]);
  }

  function arrive(a) {
    if (a.goal === 'out') { a.done = true; return; }
    if (a.goal === 'seat') {
      a.atSeat = true; a.dir = a.seat.facing;
      if (a.exec) a.execMode = 'seated';
    } else if (a.goal === 'board') {
      a.dir = 'up'; a.lookNext = nowMs() + 3000 + a.rnd() * 2000;
    } else if (a.goal === 'stroll-start' || a.goal === 'stroll') {
      a.dir = 'down'; a.wait = 1.5 + a.rnd() * 2.5; a.goal = 'stroll-idle';
    }
  }

  const moving = (a) => a.path.length > 0;
  const isWorking = (m) => m.status === 'thinking' || m.status === 'tool' || m.status === 'permission';

  function updateActor(a, dt) {
    if (a.alpha < 1 && !a.leaving) a.alpha = Math.min(1, a.alpha + dt * 4);
    if (a.leaving && a.path.length === 0) { a.alpha = Math.max(0, a.alpha - dt * 4); if (a.alpha === 0) a.done = true; }
    if (a.path.length) {
      let step = 64 * dt;                       // 4 karo/sn
      while (step > 0 && a.path.length) {
        const p = a.path[0], dx = p.x - a.x, dy = p.y - a.y, d = Math.hypot(dx, dy);
        if (d <= step) { a.x = p.x; a.y = p.y; a.path.shift(); step -= d; } else {
          a.x += (dx / d) * step; a.y += (dy / d) * step; step = 0;
        }
        if (d > 0.01) a.dir = Math.abs(dx) > Math.abs(dy) ? (dx > 0 ? 'right' : 'left') : (dy > 0 ? 'down' : 'up');
      }
      a.walkT += dt;
      if (!a.path.length) arrive(a);
      return;
    }
    if (a.exec && !a.leaving) {
      const desired = execDesired(a);
      if (a.execMode !== desired) setExecMode(a, desired);
      else if (a.execMode === 'stroll' && a.goal === 'stroll-idle') {
        a.wait -= dt;
        if (a.wait <= 0) strollStep(a);
      } else if (a.execMode === 'stroll' && a.goal === 'stroll-start') {
        arrive(a);
      } else if (a.execMode === 'board' && a.goal === 'board') {
        // tahtada yazarken 3-5 sn aralıkla ajanlara bakar (aşağı yön karesi)
        const t = nowMs();
        if (!a.look && t >= a.lookNext) { a.look = t + 1200; }
        else if (a.look && t >= a.look) { a.look = 0; a.lookNext = t + 3000 + a.rnd() * 2000; }
      }
    }
  }

  function applyMember(room, a, m) {
    const old = a.member;
    a.member = m;
    if (a.exec) {
      const wasWorking = isWorking(old);
      if (isWorking(m)) a.strollUntil = 0; else if (wasWorking) a.strollUntil = nowMs() + (layout.strollSeconds || 60) * 1000;
      setExecMode(a, execDesired(a));
    }
    if (isWorking(m) && a.idle) a.idle.active = null;
  }

  function updateRoom(room, r, instant) {
    room.title = r.title; room.badge = r.badge; room.badgeLabel = r.badgeLabel; room.group = r.group; room.overflow = r.overflow;
    room.computers = r.computers || room.computers;
    room.rack = r.rack || null; room.shells = r.shells || null;
    const seen = new Set();
    for (const m of r.members) {
      if (m.seat === undefined || m.overflow) continue;
      seen.add(m.id);
      let a = room.actors.get(m.id);
      const seat = room.td.seatById.get(m.seat);
      if (!seat) continue;
      if (a && a.seat.id !== seat.id) { room.actors.delete(m.id); a = null; }
      if (!a) { a = newActor(room, m, seat, instant); room.actors.set(m.id, a); }
      else applyMember(room, a, m);
    }
    for (const [id, a] of room.actors) if (!seen.has(id)) startLeave(a);
  }

  // Kademe büyümesi: oda ve oyuncular kalır, eski zemin 0.4 sn soluklaşır, yeni masalar belirir, taşıyıcı koliyle girer.
  function growRoom(room, r) {
    const oldTd = room.td, nd = tierData.get(r.tier);
    const grew = nd.t.stations > oldTd.t.stations;
    room.td = nd; room.tierKey = r.tier;
    for (const a of room.actors.values()) {
      const seat = nd.seatById.get(a.seat.id);
      if (seat) a.seat = seat;
    }
    if (!grew) return;
    room.fade = { old: oldTd, t: 0 };
    const had = new Set(oldTd.dynamic.map((p) => p.asset + '@' + p.col + ',' + p.row));
    room.fresh = { keys: new Set(nd.dynamic.filter((p) => !had.has(p.asset + '@' + p.col + ',' + p.row)).map((p) => p.asset + '@' + p.col + ',' + p.row)), t: 0, started: false };
    const oldBlocks = (oldTd.t.blocks || []).length;
    const stops = (nd.t.blocks || []).filter((b) => b.i >= oldBlocks).map((b) => [b.col + 1, b.row + 2]);
    startCarrier(room, stops);
  }

  function apply(s) {
    skew = s.now - Date.now();
    state = s;
    applyServerLighting(s.lighting);
    const ids = new Set();
    for (const r of s.rooms) {
      ids.add(r.id);
      if (!tierData.has(r.tier)) continue;
      let room = rooms.get(r.id);
      let instant = !initialized;
      if (room && r.reseated) { rooms.delete(r.id); room = null; instant = true; }
      if (!room) { room = newRoom(r); rooms.set(r.id, room); }
      else if (room.tierKey !== r.tier) growRoom(room, r);
      room.leaving = false;
      updateRoom(room, r, instant);
    }
    for (const [id, room] of rooms) {
      if (!ids.has(id) && !room.leaving) { room.leaving = true; room.actors.forEach(startLeave); }
    }
    initialized = true;
    if (focusId && !rooms.has(focusId)) focusId = null;
    updateBar();
    layoutRooms();
    refreshCard();
    kick();
  }

  function updateBar() {
    const n = state ? state.rooms.length : 0;
    els.counts.textContent = summaryText(state);
    els.empty.hidden = n > 0;
    els.back.hidden = !focusId;
    renderPillSummary();
    renderDock();
  }

  // Uykuda (küçültülmüş) oturumlar: yalnızca gösterim; açmak Adalmon uygulamasından yapılır. Metin textContent ile yazılır.
  function idleText(since, now) {
    const s = Math.max(0, Math.floor((now - since) / 1000));
    if (s < 3600) return Math.max(1, Math.floor(s / 60)) + ' dk';
    if (s < 86400) return Math.floor(s / 3600) + ' sa';
    return Math.floor(s / 86400) + ' g';
  }

  function renderDock() {
    const el = els.dock;
    if (!el) return;
    const list = (state && state.minimized) || [];
    const key = list.map((m) => m.id + '|' + m.label + '|' + m.status).join(';');
    el.hidden = list.length === 0;
    if (el.dataset.key === key && el.dataset.at === String(Math.floor(Date.now() / 60000))) return;
    el.dataset.key = key;
    el.dataset.at = String(Math.floor(Date.now() / 60000));
    while (el.firstChild) el.removeChild(el.firstChild);
    if (!list.length) return;
    const title = document.createElement('span');
    title.className = 'dockTitle';
    title.textContent = 'Uykuda';
    el.appendChild(title);
    const now = Date.now() + skew;
    for (const m of list) {
      const chip = document.createElement('span');
      chip.className = 'dockChip';
      chip.title = m.label + ' · ' + (m.badgeLabel || '') + ' · ' + (m.statusLabel || '');
      const dot = document.createElement('i');
      dot.className = 'dockDot ' + (m.status || 'idle');
      const name = document.createElement('b');
      name.textContent = m.label;
      const idle = document.createElement('em');
      idle.textContent = idleText(m.lastEventAt || now, now);
      chip.appendChild(dot); chip.appendChild(name); chip.appendChild(idle);
      el.appendChild(chip);
    }
  }

  // ---------- Yürüme ızgarası (temizlikçi / taşıyıcı) ----------
  function blockedSet(td) {
    if (td.blocked) return td.blocked;
    const t = td.t, set = new Set();
    for (let r = 0; r < t.rows; r++) for (let c = 0; c < t.cols; c++) if (t.tiles[(r * t.cols + c) * 4] !== 2) set.add(c + ',' + r);
    for (const p of t.furniture) {
      const a = layout.furniture[p.asset];
      if (!a || a.onWall || a.onSurface) continue;
      for (let dy = a.bg || 0; dy < a.fh; dy++) for (let dx = 0; dx < a.fw; dx++) set.add((p.col + dx) + ',' + (p.row + dy));
    }
    for (const s of t.seats) set.delete(s.col + ',' + s.row);
    set.delete(t.entrance.join(',')); set.delete(t.door.join(','));
    td.blocked = set;
    return set;
  }

  function bfs(td, from, to) {
    const blocked = blockedSet(td), key = (c) => c[0] + ',' + c[1];
    if (key(from) === key(to)) return [];
    const prev = new Map([[key(from), null]]);
    const q = [from];
    for (let i = 0; i < q.length; i++) {
      const cur = q[i];
      for (const [dx, dy] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
        const n = [cur[0] + dx, cur[1] + dy], k = key(n);
        if (prev.has(k) || (blocked.has(k) && k !== key(to))) continue;
        if (n[0] < 0 || n[1] < 0 || n[0] >= td.t.cols || n[1] >= td.t.rows) continue;
        prev.set(k, cur);
        if (k === key(to)) {
          const out = [];
          for (let c = n; c; c = prev.get(key(c))) out.unshift(c);
          return out.slice(1);
        }
        q.push(n);
      }
    }
    return null;
  }

  function walkVia(td, tiles) {
    const out = [];
    for (let i = 1; i < tiles.length; i++) {
      const seg = bfs(td, tiles[i - 1], tiles[i]);
      (seg || [tiles[i]]).forEach((c) => out.push(pt(c)));
    }
    return out;
  }

  // ---------- Temizlikçi ve taşıyıcı (yerel simülasyon) ----------
  function laneEnds(td, row) {
    const t = td.t, blocked = blockedSet(td);
    let lo = null, hi = null;
    for (let c = 0; c < t.cols; c++) if (t.tiles[(row * t.cols + c) * 4] === 2 && !blocked.has(c + ',' + row)) { if (lo === null) lo = c; hi = c; }
    return lo === null ? null : [lo, hi];
  }

  function startCleaner(room) {
    const td = room.td, cl = room.cleaner;
    const rows = (cl.laneRows || []).slice().sort((p, q) => q - p);
    const ent = td.t.entrance, door = td.t.door;
    const tiles = [door, ent];
    let leftToRight = false;
    for (const row of rows) {
      const ends = laneEnds(td, row);
      if (!ends) continue;
      const a = leftToRight ? ends[0] : ends[1], b = leftToRight ? ends[1] : ends[0];
      tiles.push([a, row], [b, row]);
      leftToRight = !leftToRight;
    }
    tiles.push(ent, door);
    const start = pt(door);
    const rb = layout.v3 && layout.v3.cleaner && layout.v3.cleaner.robot;
    // Vektör görünümde temizlik robot süpürgeyle yapılır (görsel hazırsa); yoksa eski temizlikçi.
    const robot = !!(rb && assets.gen && assets.gen[rb.body]);
    cl.entity = { x: start.x, y: start.y, dir: 'left', path: walkVia(td, tiles), walkT: 0, alpha: 1, kind: 'cleaner', look: 1, shirt: '#2673FA', acc: 'apron',
                  robot, speed: robot ? rb.pxPerSecond : undefined };
    cl.entity.path.push({ x: start.x, y: start.y, last: true });
  }

  function startCarrier(room, stops) {
    if (!stops.length) return;
    const td = room.td, door = td.t.door, ent = td.t.entrance;
    const pts = [];
    let from = ent;
    const first = walkVia(td, [door, ent]);
    first.forEach((p) => pts.push(p));
    for (const s of stops) {
      walkVia(td, [from, s]).forEach((p) => pts.push(p));
      pts[pts.length - 1].drop = true;
      from = s;
    }
    walkVia(td, [from, ent, door]).forEach((p) => pts.push(p));
    pts.push({ x: pt(door).x, y: pt(door).y, last: true });
    const d = pt(door);
    room.carrier = { x: d.x, y: d.y, dir: 'left', path: pts, walkT: 0, alpha: 1, kind: 'carrier', look: 1, shirt: '#E68C26', acc: 'hardhat', pause: 0 };
  }

  function stepEntity(e, dt) {
    if (e.pause > 0) { e.pause -= dt; return e.pause <= 0 ? 'resume' : null; }
    let step = (e.speed || 64) * dt, ev = null;
    while (step > 0 && e.path.length) {
      const p = e.path[0], dx = p.x - e.x, dy = p.y - e.y, d = Math.hypot(dx, dy);
      if (d <= step) {
        e.x = p.x; e.y = p.y; e.path.shift(); step -= d;
        if (p.drop) { e.pause = 0.5; ev = 'drop'; step = 0; }
        if (p.last) ev = 'done';
      } else { e.x += (dx / d) * step; e.y += (dy / d) * step; step = 0; }
      if (d > 0.01) e.dir = Math.abs(dx) > Math.abs(dy) ? (dx > 0 ? 'right' : 'left') : (dy > 0 ? 'down' : 'up');
    }
    e.walkT += dt;
    return ev;
  }

  // Robot süpürge: gövde + ezilip dönen yan fırça + nefes alan LED (macOS sahnesiyle aynı çizim).
  function drawRobot(e, ox, oy, night) {
    const rb = layout.v3.cleaner.robot, body = assets.gen[rb.body], brush = assets.gen[rb.brush];
    const sc = assets.scale, bw = body.width / sc, bh = body.height / sc;
    const x = e.x - ox, y = e.y - oy + Math.sin(e.walkT * 35) * 0.2, k = 1.35;
    ctx.save();
    if (night) ctx.globalAlpha *= 0.82;
    ctx.drawImage(body, x - (bw * k) / 2, y - bh * k * 0.9, bw * k, bh * k);
    if (brush) {
      const w = brush.width / sc, h = brush.height / sc;
      ctx.save(); ctx.translate(x + 5.2 * k, y - 2.0 * k); ctx.scale(k, 0.5 * k); ctx.rotate(-e.walkT * (Math.PI * 2 / 0.38));
      ctx.drawImage(brush, -w / 2, -h / 2, w, h);
      ctx.restore();
    }
    ctx.globalCompositeOperation = 'lighter';
    ctx.globalAlpha *= 0.25 + 0.75 * (0.5 + 0.5 * Math.sin(e.walkT * (Math.PI / 0.6)));
    ctx.fillStyle = '#42e08a';
    ctx.fillRect(x + 2.8 * k, y - 3.8 * k, 1.3 * k, 0.9 * k);
    ctx.restore();
  }

  function stepRoomExtras(room, dt) {
    const cl = room.cleaner;
    if (cl.entity) {
      const tile = tileOf(cl.entity.x, cl.entity.y);
      const ev = stepEntity(cl.entity, dt);
      const last = room.trail[room.trail.length - 1];
      if (!last || last.c !== tile[0] + ',' + tile[1]) room.trail.push({ c: tile[0] + ',' + tile[1], x: tile[0] * T, y: tile[1] * T + 8, t: 3.2, soft: !!cl.entity.robot });
      if (ev === 'done') { cl.entity = null; cl.next = nowMs() + cl.lo + cl.rnd() * (cl.hi - cl.lo); }
    }
    for (const tr of room.trail) tr.t -= dt;
    if (room.trail.length && room.trail[0].t <= 0) room.trail = room.trail.filter((tr) => tr.t > 0);
    if (room.carrier) {
      const ev = stepEntity(room.carrier, dt);
      if (ev === 'drop' && room.fresh && !room.fresh.started) room.fresh.started = true;
      if (ev === 'done') room.carrier = null;
    }
    if (room.fade) { room.fade.t += dt / 0.4; if (room.fade.t >= 1) room.fade = null; }
    if (room.fresh && room.fresh.started) { room.fresh.t += dt / 0.4; if (room.fresh.t >= 1) room.fresh = null; }
    else if (room.fresh && !room.carrier) room.fresh = null;
  }

  // ---------- Boşta varyantları ve zamanlayıcılar ----------
  function idleEligible(a) {
    const m = a.member;
    return !a.exec && a.atSeat && a.seat.kind === 'desk' && !moving(a) && !a.leaving && a.alpha >= 1 && !isWorking(m) && !m.alert &&
           (m.status === 'idle' || m.status === 'done') && m.idleVariant && m.idleVariant.sequence && m.idleVariant.sequence.length > 0;
  }

  // Tek dizi: sunucudaki sıra döngüyle oynanır; aralarda statik bekleme (ucuz zamanlayıcı).
  function scheduleActors(t) {
    let changed = false;
    for (const room of rooms.values()) {
      if (!room.rect || room.leaving) continue;
      let active = 0;
      for (const a of room.actors.values()) if (a.idle && a.idle.active) active += 1;
      for (const a of room.actors.values()) {
        if (!idleEligible(a)) { if (a.idle) { if (a.idle.active) changed = true; a.idle = null; } continue; }
        const seqn = a.member.idleVariant.sequence;
        if (!a.idle) a.idle = { n: 0, next: t + 3000 + a.rnd() * 6000, active: null };
        const id = a.idle;
        if (id.active && t >= id.active.end) {
          id.active = null; active -= 1; changed = true;
          id.next = t + 8000 + a.rnd() * 14000;
        } else if (!id.active && t >= id.next && active < 2) {
          const item = seqn[id.n % seqn.length];
          id.n += 1;
          id.active = { variant: item.variant, start: t, end: t + (item.seconds || 6) * 1000 };
          active += 1; changed = true;
        }
      }
      const cl = room.cleaner;
      if (!cl.entity && !room.carrier && !document.hidden && t >= cl.next) { startCleaner(room); changed = true; }
    }
    return changed;
  }

  // ---------- Yerleşim ve kamera ----------
  const PLAQUE_H = () => Math.round(30 * U);
  const GAP = () => Math.round(14 * U);
  // Pano yerleşimi (OfficePanoLayout.swift portu): kenar boşluğu yatay %2, dikey %3 (başlık levhası hücreye dahil).
  const PANO = { insetX: 0.02, insetY: 0.03 };
  const uiScaleOf = (cssHeight) => clamp((cssHeight || 0) / 900, 1, 2);   // OfficePanoLayout.uiScale

  // Saf hesap: n adet cw x ch oda, W x H piksel. Sütun sayısı en büyük ölçeği verir; sonra odalar eşit aralıkla dağıtılır
  // (çok geniş ekranda aralık büyür, kenar boşluğundan küçük olamaz), satırlar dikeyde ortalanır; tek oda sığdırılıp ortalanır.
  function panoArrange(W, H, n, cw, ch, gap, ph, maxScale) {
    const mx = Math.round(W * PANO.insetX), my = Math.round(H * PANO.insetY);
    let best = null;
    for (let cols = 1; cols <= n; cols++) {
      const rowsN = Math.ceil(n / cols);
      const sx = (W - 2 * mx - gap * (cols - 1)) / (cols * cw);
      const sy = (H - 2 * my - gap * (rowsN - 1) - ph * rowsN) / (rowsN * ch);
      const sc = clamp(Math.min(sx, sy), 0.25, maxScale);
      if (!best || sc > best.sc + 1e-6 || (Math.abs(sc - best.sc) <= 1e-6 && cols * rowsN < best.cols * best.rows)) best = { cols, rows: rowsN, sc };
    }
    const sc = best.sc, cellW = cw * sc, cellH = ch * sc + ph;
    let gapX = gap;
    if (best.cols > 1) {
      gapX = (W - best.cols * cellW) / (best.cols + 1);
      if (gapX < mx) gapX = (W - 2 * mx - best.cols * cellW) / (best.cols - 1);
      gapX = Math.max(gap, gapX);
    }
    const gapY = best.rows > 1 ? Math.max(gap, (H - 2 * my - best.rows * cellH) / (best.rows + 1)) : 0;
    const usedY = best.rows * cellH + gapY * (best.rows - 1);
    const y0 = my + Math.max(0, (H - 2 * my - usedY) / 2);
    const cells = [];
    for (let i = 0; i < n; i++) {
      const col = i % best.cols, row = Math.floor(i / best.cols);
      const inRow = Math.min(best.cols, n - row * best.cols);
      const rowW = inRow * cellW + gapX * (inRow - 1);
      cells.push({ x: Math.round(Math.max(mx, (W - rowW) / 2) + col * (cellW + gapX)), y: Math.round(y0 + row * (cellH + gapY)) });
    }
    return { cols: best.cols, rows: best.rows, sc, cellW, cellH, mx, my, gapX, gapY, cells };
  }

  // Kesirli ölçek: pencereye sığdır ve ortala (en çok 8x CSS pikseli); oda ızgarası en büyük ölçeği veren sütun sayısıyla seçilir.
  function layoutRooms() {
    const list = [...rooms.values()];
    hitRooms = [];
    if (!list.length) return;
    const W = canvas.width, H = canvas.height;
    const shown = focusId && rooms.has(focusId) ? [rooms.get(focusId)] : list;
    const cw = Math.max(...shown.map((r) => r.td.w)), ch = Math.max(...shown.map((r) => r.td.h));
    const ph = PLAQUE_H();
    const arr = panoArrange(W, H, shown.length, cw, ch, GAP(), ph, 8 * dpr);
    S = arr.sc;
    shown.forEach((room, i) => {
      const cellX = arr.cells[i].x, cellY = arr.cells[i].y;
      const w = Math.round(room.td.w * S), h = Math.round(room.td.h * S);
      const x = Math.round(cellX + (cw * S - w) / 2), y = Math.round(cellY + ph + (ch * S - h) / 2);
      room.rect = { x, y, w, h, px: cellX, py: cellY, pw: cw * S, ph: ch * S + ph };
      hitRooms.push(room);
    });
    for (const room of list) if (!shown.includes(room)) room.rect = null;
    needsRedraw = true;
  }

  // ---------- Çizim ----------
  function roundRect(x, y, w, h, r) {
    ctx.beginPath();
    if (ctx.roundRect) ctx.roundRect(x, y, w, h, r); else ctx.rect(x, y, w, h);
  }

  function pill(x, y, w, h, fill, stroke, shadow) {
    ctx.save();
    if (shadow) { ctx.shadowColor = 'rgba(8,10,18,0.28)'; ctx.shadowBlur = 5 * U; ctx.shadowOffsetY = 1.2 * U; }
    ctx.fillStyle = fill;
    roundRect(x, y, w, h, h / 2); ctx.fill();
    ctx.restore();
    if (stroke) { ctx.strokeStyle = stroke; ctx.lineWidth = Math.max(1, 0.5 * U); roundRect(x + 0.5, y + 0.5, w - 1, h - 1, h / 2); ctx.stroke(); }
  }

  const dropOf = (a) => (a.atSeat && !moving(a) ? layout.v3.vector.characters.sitDrop : 0);

  // Kare ve yön: durum animasyonu sunucudan gelen pose/alert/idleVariant'a göre; çeviri tablosu yok.
  function poseOf(a, t) {
    const F = layout.v3.vector.characters.frames, wc = layout.v3.vector.characters.walkCycle;
    if (moving(a)) return { frame: wc[Math.floor(a.walkT / 0.125) % wc.length], dir: a.dir };
    const m = a.member;
    if (a.exec && a.execMode === 'board' && a.goal === 'board') {
      if (a.look) return { frame: F.stand, dir: 'down' };
      return { frame: F.boardWrite[Math.floor(t / 400) % 2], dir: 'up' };
    }
    if (a.exec && a.execMode === 'stroll') return { frame: F.stand, dir: a.dir };
    if (!a.atSeat) return { frame: F.stand, dir: a.dir };
    if (m.alert) return { frame: F.raiseHand[Math.floor(t / 450) % 2], dir: a.dir };
    const act = a.idle && a.idle.active;
    if (act) {
      if (act.variant === 'read') return { frame: F.reading[Math.floor(t / 650) % 2], dir: a.dir };
      if (act.variant === 'coffee') return { frame: F.coffee[Math.floor(t / 700) % 2], dir: a.dir };
      if (act.variant === 'yawn') return { frame: Math.floor(t / 500) % 2 ? F.stand : F.yawn, dir: a.dir };
      if (act.variant === 'zzz') return { frame: F.sleep, dir: a.dir };
    }
    if (m.pose === 'typing') return { frame: F.typing[Math.floor(t / 280) % 2], dir: a.dir };
    if (m.pose === 'reading') return { frame: F.reading[Math.floor(t / 600) % 2], dir: a.dir };
    return { frame: F.stand, dir: a.dir };
  }

  function bubbleOf(a) {
    const m = a.member;
    if (a.leaving || moving(a) || !a.atSeat && !a.exec) return null;
    if (m.alert) return { kind: 'alert' };
    const act = a.idle && a.idle.active;
    if (act && act.variant === 'zzz') return { kind: 'zzz' };
    if (m.bubble) {
      if (m.activityAt && serverNow() - m.activityAt >= (layout.bubbleLifetime || 6) * 1000) return null;
      return { kind: 'text', text: m.bubble };
    }
    if (m.status === 'thinking') return { kind: 'think' };
    return null;
  }

  function computerName(room, p) {
    if (room.computers && room.computers[p.i]) return room.computers[p.i];
    for (const a of room.actors.values()) if (a.seat.pc === p.i && a.member.appearance && a.member.appearance.computer) return a.member.appearance.computer.name;
    return 'imac_silver';
  }

  // Sunucu rafı LED'leri: statik (yanıp sönme yok). Raf gövdesi arka plana pişirilmiştir; yalnızca LED'ler çizilir.
  function drawRack(room, td) {
    const R = layout.v3.vector.rack, dots = assets.rackDots;
    if (!td.rack || !R || !dots) return;
    const leds = (room.rack && room.rack.leds) || [];
    for (let i = 0; i < R.ledCount; i++) {
      const img = dots[leds[i] || 'off'];
      if (img) ctx.drawImage(img, td.rack.col * T - td.ox + R.dotX, td.rack.row * T - td.oy + R.dotY + R.dotDy * i, R.dotW, R.dotH);
    }
  }

  function drawRoom(room, t) {
    const r = room.rect, td = room.td;
    if (!r) return;
    const lv = light.level, night = lv > 0.5, L = lightParams(), sc = assets.scale, ox = td.ox, oy = td.oy;
    const overlays = [];
    ctx.save();
    ctx.beginPath(); ctx.rect(r.x, r.y, r.w, r.h); ctx.clip();
    ctx.setTransform(S, 0, 0, S, r.x, r.y);
    ctx.imageSmoothingEnabled = true; ctx.imageSmoothingQuality = 'high';
    ctx.globalAlpha = room.alpha;
    if (room.fade) {
      ctx.drawImage(room.fade.old.bg, 0, 0, room.fade.old.w, room.fade.old.h);
      ctx.globalAlpha = room.alpha * clamp(room.fade.t, 0, 1);
    }
    ctx.drawImage(td.bg, 0, 0, td.w, td.h);                                // zemin + duvar + sabit mobilya: tek çizim
    ctx.globalAlpha = room.alpha;
    drawRack(room, td);
    if (lv > 0.001 && assets.winNight) {
      ctx.globalAlpha = room.alpha * lv;
      for (const w of td.windows) ctx.drawImage(assets.winNight, w[0], w[1], w[2], w[3]);
      ctx.globalAlpha = room.alpha;
    }

    const pcOn = new Map();
    let boardActor = null;
    for (const a of room.actors.values()) {
      if (a.atSeat && a.seat.pc !== undefined && a.member.pcOn) pcOn.set(a.seat.pc, a);
      if (a.exec && a.execMode === 'board' && a.goal === 'board' && !moving(a)) boardActor = a;
    }
    const items = [];
    for (const p of td.dynamic) {
      items.push({ z: p.z, fn: () => {
        const isPc = p.asset.indexOf('PC_') === 0;
        const key = p.asset + '@' + p.col + ',' + p.row;
        let img;
        if (isPc) {
          const name = computerName(room, p);
          img = assets.gen[name + (pcOn.has(p.i) ? '_on' + (1 + Math.floor(t / 450) % 3) : '_off')];
        } else img = assets.furn[p.asset];
        if (!img) return;
        const w = img.width / sc, h = img.height / sc;
        let x = p.col * T - ox, y = p.row * T - oy, al = room.alpha;
        if (room.fresh && room.fresh.keys.has(key)) {
          const k = room.fresh.started ? clamp(room.fresh.t, 0, 1) : 0;
          if (k <= 0) return;
          al *= k; y -= (1 - k) * 10;
        }
        ctx.globalAlpha = al;
        if (p.mirrored) { ctx.save(); ctx.translate(x + w, y); ctx.scale(-1, 1); ctx.drawImage(img, 0, 0, w, h); ctx.restore(); } else ctx.drawImage(img, x, y, w, h);
        ctx.globalAlpha = room.alpha;
      } });
    }
    if (assets.door) {
      const d = td.doorTile, w = assets.door.width / sc, h = assets.door.height / sc;
      items.push({ z: (d[1] + 1) * T - 8, fn: () => ctx.drawImage(assets.door, d[0] * T - ox, (d[1] + 1) * T - h - oy, w, h) });
    }
    if (boardActor && td.boardPlacement && assets.boardWrite.length) {
      const p = td.boardPlacement, o = assets.boardOrigin, fr = assets.boardWrite[Math.floor(t / 500) % assets.boardWrite.length];
      items.push({ z: -1, fn: () => ctx.drawImage(fr, p.col * T - ox + o[0], p.row * T - oy + o[1], fr.width / sc, fr.height / sc) });
    }
    const entityDraw = (e) => items.push({ z: e.y + 1.5, fn: () => {
      const moving_ = e.path.length > 0 && !(e.pause > 0);
      const wc = layout.v3.vector.characters.walkCycle, F = layout.v3.vector.characters.frames;
      const frame = e.kind === 'carrier' ? F.carry[Math.floor(e.walkT / 0.125) % 3] : wc[Math.floor(e.walkT / 0.125) % wc.length];
      if (e.robot) { drawRobot(e, ox, oy, night); return; }
      drawSprite(e.look, e.shirt, e.dir, moving_ ? frame : F.stand, e.acc, e.x - ox, e.y - oy, 1, room.alpha, night);
      if (e.kind === 'cleaner' && assets.gen.mop) {
        const mop = assets.gen.mop, mw = mop.width / sc, mh = mop.height / sc;
        ctx.save(); ctx.translate(e.x - ox + (e.dir === 'left' ? -7 : 7), e.y - oy);
        ctx.rotate(Math.sin(e.walkT * 6) * 0.18);
        ctx.drawImage(mop, -mw / 2, -mh, mw, mh);
        ctx.restore();
      } else if (e.kind === 'carrier' && assets.gen.box) {
        const bx = assets.gen.box;
        ctx.drawImage(bx, e.x - ox - bx.width / sc / 2, e.y - oy - 22, bx.width / sc, bx.height / sc);
      }
    } });
    if (room.cleaner.entity) entityDraw(room.cleaner.entity);
    if (room.carrier) entityDraw(room.carrier);
    for (const a of room.actors.values()) {
      items.push({ z: a.y + 1.5, fn: () => {
        if (a.alpha <= 0.01) return;
        const ap = lookOf(a.member), pose = poseOf(a, t);
        const k = ap.small && S / dpr >= 2 ? (S / dpr - 1) / (S / dpr) : 1;
        const drop = dropOf(a);
        drawSprite(ap.look, ap.shirt, pose.dir, pose.frame, ap.acc, a.x - ox, a.y - oy + drop, k, a.alpha * room.alpha, night);
        overlays.push({ a, k, drop, lk: ap });
      } });
    }
    items.sort((p, q) => p.z - q.z).forEach((i) => i.fn());
    ctx.globalAlpha = room.alpha;

    // iz (temizlikçi): kısa süre parlayan açık şerit
    if (room.trail.length) {
      ctx.save(); ctx.globalCompositeOperation = 'lighter';
      for (const tr of room.trail) {
        ctx.globalAlpha = room.alpha * clamp(tr.t / 3.2, 0, 1) * (tr.soft ? 0.3 : 0.28);
        if (tr.soft) { ctx.fillStyle = '#9ccbff'; ctx.beginPath(); ctx.ellipse(tr.x - ox + 8, tr.y - oy + 3.5, 10, 4.5, 0, 0, Math.PI * 2); ctx.fill(); }
        else { ctx.fillStyle = '#ffffff'; ctx.fillRect(tr.x - ox + 1, tr.y - oy, 14, 7); }
      }
      ctx.restore();
    }

    if (lv > 0.001) drawNight(room, td, L, lv, t, pcOn);
    ctx.restore();

    // ekran uzayı: etiketler, balonlar, oda kartı
    ctx.save();
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.globalAlpha = room.alpha;
    const bubbles = [], shown = [];
    for (const o of overlays) {
      const a = o.a;
      const sx = r.x + (a.x - ox) * S, sy = r.y + (a.y - oy + o.drop) * S;
      hitActors.push({ a, x: sx - 9 * S * o.k, y: sy - 30 * S * o.k, w: 18 * S * o.k, h: 31 * S * o.k });
      if (a.alpha <= 0.01) continue;
      shown.push({ o, sx, sy });
    }
    // Etiketler: aynı odadakilerin çakışma çözümü (OfficeLabelLayout portu), sonra çizim; balonlar etiketleri engel sayar.
    const labelPlace = resolveRoomLabels(room, shown);
    const obstacles = [];
    for (const sh of shown) {
      const a = sh.o.a;
      obstacles.push(drawLabel(a, sh.o.lk, sh.sx, sh.sy, labelPlace.get(a.member.id)));
      const bub = bubbleOf(a);
      if (bub && a.alpha >= 0.9) bubbles.push({ a, bub, sx: sh.sx, hy: sh.sy - 29 * S * sh.o.k });
    }
    drawBubbles(bubbles, r, t, obstacles);
    if (td.rack) hitRacks.push({ room, x: r.x + (td.rack.col * T - ox) * S, y: r.y + (td.rack.row * T - oy) * S, w: td.rack.w * S, h: td.rack.h * S });
    if (td.boardPlacement) {
      const p = td.boardPlacement, def = layout.furniture[p.asset] || { w: 32, h: 32 };
      hitBoards.push({ room, x: r.x + (p.col * T - ox) * S, y: r.y + (p.row * T - oy) * S, w: def.w * S, h: def.h * S });
    }
    ctx.restore();
    drawPlaque(room);
  }

  // Gece: multiply örtü + lacivert wash + additive ışık havuzları; lamba sprite'ları örtünün üstünde.
  function drawNight(room, td, L, lv, t, pcOn) {
    const ox = td.ox, oy = td.oy, sc = assets.scale, ra = room.alpha * lv;
    const m = L.multiplyColor.map((c) => Math.round(c * 255));
    ctx.save();
    ctx.globalCompositeOperation = 'multiply';
    ctx.globalAlpha = ra;
    ctx.fillStyle = `rgb(${m[0]},${m[1]},${m[2]})`;
    ctx.fillRect(0, 0, td.w, td.h);
    ctx.globalCompositeOperation = 'source-over';
    ctx.globalAlpha = ra * L.washAlpha;
    ctx.fillStyle = rgbCss(L.washColor);
    ctx.fillRect(0, 0, td.w, td.h);
    ctx.globalCompositeOperation = 'lighter';
    const glow = (name, w, h, cx, cy, alpha) => {
      const g = assets.gen[name];
      if (!g) return;
      ctx.globalAlpha = ra * alpha;
      ctx.drawImage(g, cx - w / 2, cy - h / 2, w, h);
    };
    glow('vglow_bulb', td.w * 1.3, td.h * 1.15, td.w / 2, td.h * 0.45, L.bulbAlpha);
    const lamps = (td.t.lamps || []).map((l) => ({ x: l.col * T - ox + l.dx, y: l.row * T - oy + l.dy }));
    for (const l of lamps) glow('vglow_pool', 64, 36, l.x, l.y + 3, L.poolAlpha);
    if (td.boardPlacement) glow('vglow_pool', 60, 36, td.boardPlacement.col * T - ox + 16, td.boardPlacement.row * T - oy + 14, L.boardAlpha);
    for (const w of td.windows) glow('vglow_moon', 26, 44, w[0] + w[2] / 2, w[1] + w[3] / 2 + 22, L.windowAlpha);
    for (const [pc] of pcOn) {
      const p = td.placementByIndex.get(pc);
      if (p) glow('vglow_screen', 30, 20, p.col * T - ox + 8, p.row * T - oy + 6, L.screenAlpha);
    }
    ctx.globalCompositeOperation = 'source-over';
    ctx.globalAlpha = ra;
    const lampImg = assets.gen.lamp;
    if (lampImg) for (const l of lamps) ctx.drawImage(lampImg, l.x - lampImg.width / sc / 2, l.y + 1 - lampImg.height / sc, lampImg.width / sc, lampImg.height / sc);
    ctx.restore();
  }

  function labelText(m) {
    const text = m.kind === 'subagent' && m.role && m.role.name ? m.role.name : (m.label || '');
    return text.length > 22 ? text.slice(0, 21) + '…' : text;
  }

  // ---------- Etiket çakışma çözümü (Sources/App/Office/OfficeLabelLayout.swift portu) ----------
  // Soldan sağa yerleştirme; çakışan etiket en çok 2 kademe (16 px) kaydırılır; yetmezse tüm odada metin biçimi kısalır:
  // tam ad -> `eklenti:` öneki atılmış ad -> 14 karakter + "…"; yine olmazsa en az örtüşen kademe. Kademe yönü: web'de etiket
  // ayakların ALTINDA durduğu için kademeler aşağı doğrudur (macOS'ta baş üstü olduğundan yukarı).
  const LABEL = { maxLevel: 2, shortLimit: 14 };

  function labelVariants(title) {
    const out = [title];
    const stripped = title.includes(':') && !title.startsWith('★') ? title.slice(title.lastIndexOf(':') + 1) : title;
    if (stripped && !out.includes(stripped)) out.push(stripped);
    const short = stripped.length <= LABEL.shortLimit ? stripped : stripped.slice(0, LABEL.shortLimit - 1) + '…';
    if (!out.includes(short)) out.push(short);
    return out;
  }

  // Ekran pikseli; items: { id, x (merkez), y (kademe 0 üst kenarı), widths[] }. Kademe adımı/yükseklik/boşluk dpr ile ölçeklenir.
  function labelRect(item, variant, level, m) {
    const w = item.widths[Math.min(variant, item.widths.length - 1)] + m.margin;
    return { x: item.x - w / 2, y: item.y + level * m.step, w, h: m.height };
  }

  const rectsOverlap = (p, q) => p.x < q.x + q.w && q.x < p.x + p.w && p.y < q.y + q.h && q.y < p.y + p.h;
  function overlapArea(p, q) {
    const w = Math.min(p.x + p.w, q.x + q.w) - Math.max(p.x, q.x), h = Math.min(p.y + p.h, q.y + q.h) - Math.max(p.y, q.y);
    return w > 0 && h > 0 ? w * h : 0;
  }

  function resolveLabels(items, m) {
    const sorted = items.filter((i) => i.widths.length).sort((p, q) => (p.x - q.x) || (p.y - q.y) || (p.id < q.id ? -1 : p.id > q.id ? 1 : 0));
    if (!sorted.length) return { placements: new Map(), overlaps: 0 };
    const stages = Math.max(...sorted.map((i) => i.widths.length));
    let result = new Map();
    for (let stage = 0; stage < stages; stage++) {
      const last = stage === stages - 1;
      const placed = [], out = new Map();
      let failed = false;
      for (const item of sorted) {
        const variant = Math.min(stage, item.widths.length - 1);
        let chosen = null;
        for (let level = 0; level <= LABEL.maxLevel; level++) {
          const r = labelRect(item, variant, level, m);
          if (!placed.some((p) => rectsOverlap(p, r))) { chosen = level; break; }
        }
        if (chosen === null) {
          failed = true;
          if (!last) break;
          let best = { level: 0, area: Infinity };   // kabul edilen çakışma: en az kesişim alanı, eşitlikte en düşük kademe
          for (let level = 0; level <= LABEL.maxLevel; level++) {
            const r = labelRect(item, variant, level, m);
            const area = placed.reduce((acc, p) => acc + overlapArea(p, r), 0);
            if (area < best.area - 0.0001) best = { level, area };
          }
          chosen = best.level;
        }
        out.set(item.id, { variant, level: chosen });
        placed.push(labelRect(item, variant, chosen, m));
      }
      if (!failed || last) result = out;
      if (!failed) break;
    }
    const rects = sorted.map((i) => { const p = result.get(i.id); return p ? labelRect(i, p.variant, p.level, m) : null; }).filter(Boolean);
    let overlaps = 0;
    for (let i = 0; i < rects.length; i++) for (let j = i + 1; j < rects.length; j++) if (rectsOverlap(rects[i], rects[j])) overlaps++;
    return { placements: result, overlaps };
  }

  const labelMetrics = () => ({ step: Math.round(16 * U), height: Math.round(15 * U), margin: Math.round(2 * U) });

  function labelFont() { return `600 ${Math.round(10 * U)}px -apple-system, system-ui, sans-serif`; }

  // Pil genişliği: yazı + dolgular (drawLabel ile aynı hesap).
  function labelWidth(text) {
    ctx.font = labelFont();
    return Math.ceil(ctx.measureText(text).width) + Math.round(6 * U) * 2 + Math.round(3 * U) * 2 + Math.round(3 * U);
  }

  // Yalnızca üye/metin/konum/ölçek (ve U) değişince yeniden hesaplanır; kararsız (yürüyen/ayrılan) oyuncular dışarıda kalır.
  function resolveRoomLabels(room, shown) {
    const cands = shown.filter((sh) => !moving(sh.o.a) && !sh.o.a.leaving);
    const key = cands.map((sh) => `${sh.o.a.member.id}|${labelText(sh.o.a.member)}|${Math.round(sh.sx)}|${Math.round(sh.sy)}`).join(';') + `@${S}/${U}`;
    if (room.labelCache && room.labelCache.key === key) return room.labelCache.map;
    const items = cands.map((sh) => {
      const variants = labelVariants(labelText(sh.o.a.member));
      return { id: sh.o.a.member.id, x: Math.round(sh.sx), y: Math.round(sh.sy + 2 * U), variants, widths: variants.map(labelWidth) };
    });
    const res = resolveLabels(items, labelMetrics());
    const map = new Map();
    for (const it of items) { const p = res.placements.get(it.id); if (p) map.set(it.id, { text: it.variants[p.variant], level: p.level }); }
    room.labelCache = { key, map, overlaps: res.overlaps };
    return map;
  }

  function drawLabel(a, lk, sx, sy, place) {
    const m = a.member, text = place ? place.text : labelText(m), night = uiNight();
    ctx.font = labelFont();
    const tw = Math.ceil(ctx.measureText(text).width), h = Math.round(15 * U), pad = Math.round(6 * U), dot = Math.round(3 * U);
    const w = tw + pad * 2 + dot * 2 + Math.round(3 * U);
    const x = Math.round(sx - w / 2), y = Math.round(sy + 2 * U) + (place ? place.level * Math.round(16 * U) : 0);
    pill(x, y, w, h, night ? 'rgba(27,33,50,0.9)' : 'rgba(255,255,255,0.92)', night ? 'rgba(255,255,255,0.2)' : 'rgba(17,20,28,0.16)', true);
    const dotColor = m.kind === 'subagent' && m.role ? (m.role.tint || lk.shirt) : (m.appearance && m.appearance.tint) || lk.shirt;
    ctx.fillStyle = dotColor;
    ctx.beginPath(); ctx.arc(x + pad + dot, y + h / 2, dot, 0, Math.PI * 2); ctx.fill();
    ctx.fillStyle = night ? '#E8ECF5' : '#1B2030';
    ctx.textBaseline = 'middle'; ctx.textAlign = 'left';
    ctx.fillText(text, x + pad + dot * 2 + Math.round(3 * U), y + h / 2 + 0.5);
    return { x, y, w, h };
  }

  // Konuşma balonları: beyaz yuvarlak gövde + kuyruk + gölge; komşu balonla çakışan yukarı kayar.
  function drawBubbles(list, room, t, obstacles) {
    const placed = (obstacles || []).slice();
    list.sort((p, q) => p.sx - q.sx || p.hy - q.hy);
    const fs = Math.round(10.5 * U);
    const tail = Math.round(4 * U), bh = Math.round(16 * U), pad = Math.round(7 * U), tip = Math.round(4 * U);
    ctx.font = `500 ${fs}px -apple-system, system-ui, sans-serif`;
    for (const b of list) {
      const isText = b.bub.kind === 'text';
      let w, h;
      if (isText) { w = Math.ceil(ctx.measureText(b.bub.text).width) + pad * 2; h = bh; } else {
        const g = assets.gen[b.bub.kind === 'alert' ? 'bubble_alert' : b.bub.kind === 'think' ? 'bubble_think' : 'zzz'];
        if (!g) continue;
        b.img = g; w = g.width / assets.scale * S; h = g.height / assets.scale * S;
      }
      let x = Math.round(b.sx - (isText ? tip : w / 2));
      if (x + w > room.x + room.w) x = room.x + room.w - w;
      if (x < room.x) x = room.x;
      const bob = b.bub.kind === 'alert' ? Math.sin(t / 190) * S : b.bub.kind === 'zzz' ? Math.sin(t / 400) * S : 0;
      let y = Math.round(b.hy - h - (isText ? tail : 0) - 2 * U + bob);
      for (let i = 0; i < 8; i++) {
        const hit = placed.some((p) => x < p.x + p.w + 1 && x + w + 1 > p.x && y < p.y + p.h + 1 && y + h + (isText ? tail : 0) + 1 > p.y);
        if (hit) y -= h + (isText ? tail : 0) + Math.round(1 * U); else break;
      }
      placed.push({ x, y, w, h: h + (isText ? tail : 0) });
      if (!isText) { ctx.drawImage(b.img, x, y, w, h); continue; }
      ctx.save();
      ctx.shadowColor = 'rgba(8,10,18,0.3)'; ctx.shadowBlur = 5 * U; ctx.shadowOffsetY = 1.5 * U;
      ctx.fillStyle = 'rgba(255,255,255,0.98)';
      roundRect(x, y, w, h, Math.round(7 * U)); ctx.fill();
      const tx = clamp(b.sx, x + pad, x + w - pad);
      ctx.beginPath(); ctx.moveTo(tx - tail, y + h - 1); ctx.lineTo(tx, y + h + tail); ctx.lineTo(tx + tail, y + h - 1); ctx.closePath(); ctx.fill();
      ctx.restore();
      ctx.fillStyle = '#2B2F3A'; ctx.textBaseline = 'middle'; ctx.textAlign = 'left';
      ctx.fillText(b.bub.text, x + pad, y + h / 2 + 0.5);
    }
  }

  // Oda başlık kartı: ad + model rozeti + oturum renginde alt çizgi; "+N" taşan ajan rozeti.
  function drawPlaque(room) {
    const r = room.rect, night = uiNight();
    if (!r) return;
    const g = layout.groupColors[room.group % layout.groupColors.length];
    const ap = layout.appearance[room.badge] || layout.appearance.unknown || { badgeText: '', tintHex: '#888888' };
    ctx.save();
    ctx.globalAlpha = room.alpha;
    // Claude'a yakın editoryal serif (sistemin serif'i; Claude'un kendi yazı tipleri lisanslıdır, kullanılmaz).
    const SERIF = 'ui-serif, "New York", "Iowan Old Style", "Palatino Linotype", Georgia, serif';
    const fs = Math.round(13.5 * U), bfs = Math.round(10.5 * U), h = Math.round(24 * U), y = r.y - Math.round(30 * U), padX = Math.round(10 * U);
    ctx.font = `600 ${fs}px ${SERIF}`;
    const rawBadge = ap.badgeText || '';
    const badge = rawBadge && rawBadge !== '?' ? rawBadge.charAt(0) + rawBadge.slice(1).toLowerCase() : rawBadge;
    const spark = badge && badge !== '?' ? '\u2726 ' : '';
    ctx.font = `italic 600 ${bfs}px ${SERIF}`;
    const bw = badge ? Math.ceil(ctx.measureText(spark + badge).width) + Math.round(13 * U) : 0;
    ctx.font = `600 ${fs}px ${SERIF}`;
    const maxName = Math.max(40, r.w - bw - padX * 3 - Math.round(44 * U));
    let shown = room.title || '';
    while (shown.length > 1 && ctx.measureText(shown).width > maxName) shown = shown.slice(0, -1);
    if (shown !== (room.title || '')) shown = shown.slice(0, -1) + '\u2026';
    const nameW = Math.ceil(ctx.measureText(shown).width);
    const w = Math.min(r.w, nameW + bw + padX * 2 + (bw ? Math.round(8 * U) : 0));
    ctx.save();
    ctx.shadowColor = 'rgba(8,10,18,0.35)'; ctx.shadowBlur = 6 * U; ctx.shadowOffsetY = 1.5 * U;
    ctx.fillStyle = night ? 'rgba(43,38,34,0.97)' : 'rgba(251,247,239,0.98)';
    roundRect(r.x, y, w, h, Math.round(10 * U)); ctx.fill();
    ctx.restore();
    ctx.lineWidth = 1; ctx.strokeStyle = night ? 'rgba(255,233,208,0.20)' : 'rgba(74,59,42,0.20)';
    roundRect(r.x + 0.5, y + 0.5, w - 1, h - 1, Math.round(10 * U)); ctx.stroke();
    ctx.fillStyle = rgbCss(g);
    ctx.fillRect(r.x + Math.round(10 * U), y + h - Math.round(3 * U), w - Math.round(20 * U), Math.max(1, Math.round(1.8 * U)));
    ctx.fillStyle = night ? '#F4EEE4' : '#2A2118'; ctx.textBaseline = 'middle'; ctx.textAlign = 'left';
    ctx.font = `600 ${fs}px ${SERIF}`;
    ctx.fillText(shown, r.x + padX, y + h / 2 - 1 * U);
    if (badge) {
      const bx = r.x + padX + nameW + Math.round(8 * U), bh = Math.round(16 * U), by = y + (h - bh) / 2 - 1 * U;
      const tint = ap.tintHex || '#888';
      ctx.save(); ctx.globalAlpha = room.alpha * (night ? 0.26 : 0.18); ctx.fillStyle = tint;
      roundRect(bx, by, bw, bh, bh / 2); ctx.fill(); ctx.restore();
      ctx.textAlign = 'left';
      ctx.font = `italic 600 ${bfs}px ${SERIF}`;
      const tx = bx + Math.round(6.5 * U), ty = by + bh / 2 + 0.5;
      if (spark) { ctx.fillStyle = tint; ctx.font = `700 ${bfs}px ${SERIF}`; ctx.fillText('\u2726', tx, ty); }
      const sw = spark ? Math.ceil(ctx.measureText('\u2726 ').width) : 0;
      ctx.font = `italic 600 ${bfs}px ${SERIF}`;
      ctx.fillStyle = night ? tint : tint; ctx.globalAlpha = room.alpha;
      ctx.fillText(badge, tx + sw, ty);
    }
    if (room.overflow > 0) {
      const txt = `+${room.overflow}`;
      ctx.font = `700 ${fs}px -apple-system, system-ui, sans-serif`;
      const tw = Math.ceil(ctx.measureText(txt).width) + Math.round(14 * U);
      pill(r.x + r.w - tw, y, tw, h, '#FF8A00', null, true);
      ctx.fillStyle = '#fff'; ctx.textAlign = 'center';
      ctx.fillText(txt, r.x + r.w - tw / 2, y + h / 2);
    }
    ctx.restore();
  }

  // ---------- Arka plan (pano): önbellekli ofscreen görseller ----------
  // OfficeBackdrop.swift paleti/çizimi: gündüz krem->bej + tahta deseni + vinyet; gece lacivert->mor-lacivert + yıldız + bokeh.
  // Görsel boyut/tema değişince BİR KEZ çizilir; her karede yalnızca drawImage (gündüz/gece geçişi light.level ile 1 sn crossfade).
  const BACKDROP = {
    day: { top: [0.984, 0.957, 0.902], bottom: [0.902, 0.835, 0.722], glow: [1.0, 0.953, 0.855], glowAlpha: 0.55, vignette: [0.66, 0.54, 0.36], vignetteAlpha: 0.20, plankAlpha: 0.08, stars: 0, bokeh: 0 },
    night: { top: [0.039, 0.063, 0.188], bottom: [0.145, 0.106, 0.290], glow: [1.0, 0.69, 0.40], glowAlpha: 0.13, vignette: [0.012, 0.016, 0.06], vignetteAlpha: 0.50, plankAlpha: 0, stars: 170, bokeh: 16 },
    maxEdge: 1280,
  };
  const backdropCache = new Map();
  const shadowCache = new Map();
  const cacheStats = { backdrops: 0, shadows: 0 };

  // En-boy oranı 0.05'lik kovalara yuvarlanır; en uzun kenar 1280 (canvas'a gerilerek çizilir).
  function backdropSize(W, H) {
    const aspect = Math.min(4, Math.max(0.4, W / Math.max(H, 1)));
    const bucket = Math.round(aspect * 20), a = bucket / 20, M = BACKDROP.maxEdge;
    if (a >= 1) return { w: M, h: Math.max(1, Math.round(M / a)), bucket };
    return { w: Math.max(1, Math.round(M * a)), h: M, bucket };
  }
  const backdropKey = (night, W, H) => { const s = backdropSize(W, H); return (night ? 'n' : 'd') + s.w + 'x' + s.h; };

  function renderBackdrop(night, w, h) {
    const p = night ? BACKDROP.night : BACKDROP.day, c = newCanvas(w, h), g = c.getContext('2d');
    const s = h / 720, rnd = rng(7);
    const range = (lo, hi) => lo + (hi - lo) * rnd();
    let grad = g.createLinearGradient(w * 0.15, 0, w * 0.85, h);
    grad.addColorStop(0, rgbCss(p.top)); grad.addColorStop(1, rgbCss(p.bottom));
    g.fillStyle = grad; g.fillRect(0, 0, w, h);
    if (p.plankAlpha > 0) {
      const rowsN = 9, ph = h / rowsN, pw = w / 4.2;
      for (let r = 0; r < rowsN; r++) {
        if (r % 2 === 0) { g.fillStyle = rgbCss([0.45, 0.32, 0.16], p.plankAlpha * 0.45); g.fillRect(0, r * ph, w, ph); }
        g.fillStyle = rgbCss([0.45, 0.32, 0.16], p.plankAlpha);
        g.fillRect(0, r * ph, w, Math.max(1, s));
        for (let x = -range(0, pw); x < w; x += pw * range(0.85, 1.15)) g.fillRect(x, r * ph, Math.max(1, s), ph);
      }
    }
    const radial = (cx, cy, r, stops) => {
      const rg = g.createRadialGradient(cx, cy, 0, cx, cy, r);
      for (const [at, col] of stops) rg.addColorStop(at, col);
      g.fillStyle = rg; g.fillRect(cx - r, cy - r, r * 2, r * 2);
    };
    radial(w / 2, h * 0.52, Math.max(w, h) * 0.62, [[0, rgbCss(p.glow, p.glowAlpha)], [1, rgbCss(p.glow, 0)]]);
    for (let i = 0; i < p.stars; i++) {
      const x = range(0, w), y = h * Math.pow(rnd(), 1.6), r = range(0.6, 1.7) * s;
      g.fillStyle = rgbCss([0.86, 0.9, 1], range(0.10, 0.42));
      g.beginPath(); g.arc(x, y, r, 0, Math.PI * 2); g.fill();
    }
    const tones = [[1, 0.72, 0.42], [0.45, 0.8, 0.95], [0.72, 0.55, 1]];
    for (let i = 0; i < p.bokeh; i++) {
      const low = i % 3 !== 0, x = range(0, w), y = low ? range(h * 0.7, h) : range(0, h * 0.7), r = range(9, 28) * s, tone = tones[i % tones.length];
      radial(x, y, r, [[0.55, rgbCss(tone, range(0.05, 0.10))], [1, rgbCss(tone, 0)]]);
    }
    const vr = Math.hypot(w, h) / 2;
    const vg = g.createRadialGradient(w / 2, h / 2, 0, w / 2, h / 2, vr);
    vg.addColorStop(0, rgbCss(p.vignette, 0)); vg.addColorStop(0.55, rgbCss(p.vignette, 0)); vg.addColorStop(1, rgbCss(p.vignette, p.vignetteAlpha));
    g.fillStyle = vg; g.fillRect(0, 0, w, h);
    return c;
  }

  function getBackdrop(night, W, H) {
    const key = backdropKey(night, W, H), hit = backdropCache.get(key);
    if (hit) return hit;
    const s = backdropSize(W, H), img = renderBackdrop(night, s.w, s.h);
    if (backdropCache.size >= 6) backdropCache.delete(backdropCache.keys().next().value);
    backdropCache.set(key, img);
    cacheStats.backdrops += 1;
    return img;
  }

  function drawBackdrop() {
    const W = canvas.width, H = canvas.height, lv = light.level;
    ctx.globalAlpha = 1;
    if (lv < 0.999) ctx.drawImage(getBackdrop(false, W, H), 0, 0, W, H);
    if (lv > 0.001) { ctx.globalAlpha = lv < 0.999 ? lv : 1; ctx.drawImage(getBackdrop(true, W, H), 0, 0, W, H); ctx.globalAlpha = 1; }
  }

  // Oda çevresi: gündüz yumuşak gölge, gece sıcak amber parıltı (OfficeRoomShadow). Boyut/tema başına bir kez çizilir.
  const shadowPad = (r) => Math.round(clamp(Math.min(r.w, r.h) * 0.1, 10 * dpr, 56 * dpr));
  function getRoomShadow(w, h, pad, night) {
    const key = w + 'x' + h + 'p' + pad + (night ? 'n' : 'd'), hit = shadowCache.get(key);
    if (hit) return hit;
    const c = newCanvas(w + pad * 2, h + pad * 2), g = c.getContext('2d');
    g.shadowColor = night ? 'rgba(255,178,97,0.40)' : 'rgba(77,51,20,0.38)';
    g.shadowBlur = pad * 0.9;
    g.shadowOffsetX = 0; g.shadowOffsetY = night ? 0 : pad * 0.28;
    g.fillStyle = '#000'; g.fillRect(pad, pad, w, h);
    g.shadowColor = 'rgba(0,0,0,0)'; g.shadowBlur = 0; g.shadowOffsetY = 0;
    g.globalCompositeOperation = 'destination-out';
    g.fillRect(pad, pad, w, h);
    if (shadowCache.size >= 16) shadowCache.delete(shadowCache.keys().next().value);
    shadowCache.set(key, c);
    cacheStats.shadows += 1;
    return c;
  }

  function drawRoomShadow(room) {
    const r = room.rect;
    if (!r || room.alpha <= 0.001) return;
    const lv = light.level, pad = shadowPad(r);
    for (const night of [false, true]) {
      const a = room.alpha * (night ? lv : 1 - lv);
      if (a <= 0.001) continue;
      ctx.globalAlpha = a;
      ctx.drawImage(getRoomShadow(r.w, r.h, pad, night), r.x - pad, r.y - pad);
    }
    ctx.globalAlpha = 1;
  }

  function draw(t) {
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.globalAlpha = 1;
    ctx.globalCompositeOperation = 'source-over';
    drawBackdrop();
    syncPanoTheme();
    hitActors = []; hitBoards = []; hitRacks = [];
    for (const room of rooms.values()) drawRoomShadow(room);
    ctx.globalAlpha = 1;
    for (const room of rooms.values()) drawRoom(room, t);
    ctx.setTransform(1, 0, 0, 1, 0, 0);
  }

  // ---------- Kart ve ipucu ----------
  function el(tag, cls, text) {
    const e = document.createElement(tag);
    if (cls) e.className = cls;
    if (text !== undefined) e.textContent = text;
    return e;
  }

  const roleName = (m) => (m.kind === 'session' ? 'ana ajan' : (m.role && m.role.name) || m.label || 'alt ajan');
  const modelLabel = (m) => { const ap = layout.appearance[m.badge] || layout.appearance.unknown; return ap ? ap.badgeText || ap.label || '' : ''; };

  function buildCard(a) {
    const m = a.member, room = a.room;
    const root = el('div', 'cardBody');
    const head = el('div', 'cardHead');
    const dot = el('span', 'cardDot');
    dot.style.background = (m.appearance && m.appearance.tint) || '#888';
    head.appendChild(dot);
    head.appendChild(el('span', 'cardTitle', m.kind === 'session' ? (room.title || m.label || '') : labelText(m)));
    const close = el('button', 'cardClose', '×');
    close.setAttribute('type', 'button');
    close.setAttribute('aria-label', 'Kartı kapat');
    close.addEventListener('click', closeCard);
    head.appendChild(close);
    root.appendChild(head);
    const sub = el('div', 'cardSub');
    sub.appendChild(el('span', '', roleName(m)));
    const badge = el('span', 'cardBadge', modelLabel(m));
    const ap = layout.appearance[m.badge] || layout.appearance.unknown;
    if (ap && ap.tintHex) badge.style.background = ap.tintHex;
    sub.appendChild(badge);
    root.appendChild(sub);
    const row = (k, v, id) => {
      const r = el('div', 'cardRow');
      r.appendChild(el('span', 'cardKey', k));
      const val = el('span', 'cardVal', v);
      if (id) val.setAttribute('data-id', id);
      r.appendChild(val);
      root.appendChild(r);
      return val;
    };
    row('Durum', m.statusLabel || m.status || '');
    if (m.activity) row('Araç', m.activity);
    if (m.target) row('Hedef', m.target);
    row(m.kind === 'session' ? 'Çalışma süresi' : 'Son etkinlik', cardTimerText(m), 'timer');
    if (m.kind === 'subagent') row('Bağlı oturum', room.title || '');
    if (m.kind === 'session') {
      const subs = (room.members || []).filter((x) => x.kind === 'subagent');
      row('Alt ajanlar', String(subs.length));
      if (subs.length) {
        const list = el('ul', 'cardList');
        subs.slice(0, 12).forEach((s) => list.appendChild(el('li', '', `${labelText(s)} · ${s.statusLabel || s.status}`)));
        root.appendChild(list);
      }
      appendShells(root, room);
    }
    return root;
  }

  // Kartta "Arka plan işlemleri": yalnızca ad, süre, CPU, RAM (komut satırı yok); N>12 ise "+K daha".
  function appendShells(root, room) {
    const sh = room.shells;
    if (!sh) return;
    root.appendChild(el('div', 'cardKey', sh.known ? `Arka plan işlemleri (${sh.count})` : 'İşlem bilgisi yok (eski oturum)'));
    if (!sh.known) return;
    const list = el('ul', 'cardList');
    (sh.items || []).slice(0, 12).forEach((i) => list.appendChild(el('li', '', `${i.name} · ${fmtShellAge(i.ageSec)} · %${i.cpu < 10 ? Number(i.cpu).toFixed(1) : Math.round(i.cpu)} · ${i.rssMB} MB`)));
    if (sh.hidden > 0) list.appendChild(el('li', '', `+${sh.hidden} daha`));
    root.appendChild(list);
    root.appendChild(el('div', 'cardKey', 'Yalnızca işlem adı gösterilir'));
  }
  function fmtShellAge(sec) {
    if (sec < 60) return sec + ' sn';
    const m = Math.floor(sec / 60);
    return m < 60 ? m + ' dk' : (m % 60 ? Math.floor(m / 60) + ' sa ' + (m % 60) + ' dk' : Math.floor(m / 60) + ' sa');
  }

  function cardTimerText(m) {
    if (m.kind === 'session' && m.startedAt) return fmtDur(serverNow() - m.startedAt);
    if (m.activityAt) return fmtDur(serverNow() - m.activityAt) + ' önce';
    return '–';
  }

  let cardTimer = 0;
  function openCard(a) {
    selected = a;
    renderCard();
    if (!cardTimer) cardTimer = setInterval(tickCard, 1000);
    kick();
  }
  function renderCard() {
    if (!els.card) return;
    if (!selected) { els.card.hidden = true; return; }
    const a = selected;
    a.room.members = state ? ((state.rooms.find((r) => r.id === a.room.id) || {}).members || []) : [];
    while (els.card.firstChild) els.card.removeChild(els.card.firstChild);
    els.card.appendChild(buildCard(a));
    els.card.hidden = false;
  }
  function tickCard() {
    if (!selected || !els.card || els.card.hidden) return;
    const v = els.card.querySelector ? els.card.querySelector('[data-id="timer"]') : null;
    if (v) v.textContent = cardTimerText(selected.member);
  }
  function refreshCard() {
    if (!selected) return;
    const live = selected.room.actors.get(selected.id);
    if (!live || live !== selected) { closeCard(); return; }
    renderCard();
  }
  function closeCard() {
    selected = null;
    if (els.card) els.card.hidden = true;
    if (cardTimer) { clearInterval(cardTimer); cardTimer = 0; }
  }

  function tipText(a) {
    const m = a.member;
    const name = labelText(m), role = roleName(m);
    return [name, role === name ? null : role, modelLabel(m), m.statusLabel || m.status].filter(Boolean).join(' · ');
  }

  // ---------- Döngü ----------
  let raf = 0, last = 0, hiddenAt = 0, lastSig = '';

  function advance(dt) {
    stepLight(dt);
    let layoutDirty = false;
    for (const [id, room] of rooms) {
      for (const [aid, a] of room.actors) {
        updateActor(a, dt);
        if (a.done) { room.actors.delete(aid); if (selected === a) closeCard(); }
      }
      stepRoomExtras(room, dt);
      if (room.leaving && room.actors.size === 0) {
        room.alpha = Math.max(0, room.alpha - dt * 1.5);
        if (room.alpha === 0) { rooms.delete(id); layoutDirty = true; }
      }
    }
    scheduleActors(nowMs());
    if (layoutDirty) { if (focusId && !rooms.has(focusId)) focusId = null; updateBar(); layoutRooms(); }
  }

  // Hareket eden / animasyonlu bir şey var mı? Yoksa çizim durur (statik), yalnızca durum değişince yeniden çizilir.
  function animating() {
    if (lightAnimating()) return true;
    for (const room of rooms.values()) {
      if (room.leaving || room.fade || room.fresh || room.carrier || room.cleaner.entity || room.trail.length) return true;
      for (const a of room.actors.values()) {
        const m = a.member;
        if (moving(a) || a.alpha < 1 || a.leaving || isWorking(m) || (a.idle && a.idle.active) || (a.exec && a.execMode === 'board') || (a.atSeat && m.pcOn)) return true;
        if (a.exec && a.execMode === 'stroll') return true;
      }
    }
    return false;
  }

  function anyMoving() {
    for (const room of rooms.values()) {
      if (room.carrier || room.cleaner.entity) return true;
      for (const a of room.actors.values()) if (moving(a)) return true;
    }
    return false;
  }

  function bubbleSig() {
    let s = '';
    for (const room of rooms.values()) for (const a of room.actors.values()) { const b = bubbleOf(a); if (b) s += a.id + ':' + b.kind + ':' + (b.text || '') + ';'; }
    return s;
  }

  function frame(ts) {
    raf = 0;
    if (document.hidden || !layout) return;
    const anim = animating();
    if (!anim && !needsRedraw) return;                       // statik: döngü durur; durum/zamanlayıcı kick() ile uyandırır
    const interval = anyMoving() ? 1000 / 15 : 1000 / 12;    // CPU: en çok ≈12-15 fps
    if (last && ts - last < interval - 1) { raf = requestAnimationFrame(frame); return; }
    const dt = last ? Math.min((ts - last) / 1000, 0.25) : 0.05;
    last = ts;
    advance(dt);
    draw(nowMs());
    needsRedraw = false;
    lastSig = bubbleSig();
    raf = requestAnimationFrame(frame);
  }

  function kick() {
    needsRedraw = true;
    if (!raf && !document.hidden && layout) { last = 0; raf = requestAnimationFrame(frame); }
  }

  // Statik modda yalnızca ucuz bir 1 sn kalp atışı: boşta varyantı / temizlikçi / balon süresi / ışık değişimi için uyandırır.
  function heartbeat() {
    if (document.hidden || !layout || raf) return;
    let wake = scheduleActors(nowMs());
    if (lightAnimating()) wake = true;
    const sig = bubbleSig();
    if (sig !== lastSig) { lastSig = sig; wake = true; }
    if (wake) kick();
  }

  document.addEventListener('visibilitychange', () => {
    if (document.hidden) {
      hiddenAt = nowMs();
      if (raf) { cancelAnimationFrame(raf); raf = 0; }
      stopClock();
      return;
    }
    if (pillsOn()) { renderClock(); startClock(); }
    const away = nowMs() - hiddenAt;
    if (away > 2000) {
      // Gizliyken çizim durdu: hareketleri hemen tamamla, temizlikçi/taşıyıcı sahnesini bırak (zamanlayıcılar öteleniyor).
      for (const room of rooms.values()) {
        for (const a of room.actors.values()) {
          const p = a.path.length ? a.path[a.path.length - 1] : null;
          if (p) { a.x = p.x; a.y = p.y; a.path = []; arrive(a); }
        }
        room.cleaner.entity = null; room.cleaner.next += away; room.carrier = null; room.fade = null; room.fresh = null; room.trail = [];
      }
    }
    kick();
  });

  // ---------- Boyut ve etkileşim ----------
  function resize() {
    dpr = Math.min(2, window.devicePixelRatio || 1);
    const rect = canvas.getBoundingClientRect();
    uiK = uiScaleOf(rect.height);
    U = dpr * uiK;
    canvas.width = Math.max(1, Math.round(rect.width * dpr));
    canvas.height = Math.max(1, Math.round(rect.height * dpr));
    for (const p of [els.pillL, els.pillR]) if (p) p.style.fontSize = (12.5 * uiK) + 'px';
    layoutRooms();
    kick();
  }
  let resizeQueued = false, uiK = 1;
  function queueResize() {
    if (resizeQueued) return;
    resizeQueued = true;
    requestAnimationFrame(() => { resizeQueued = false; resize(); });
  }
  window.addEventListener('resize', queueResize);

  function toCanvas(e) {
    const rect = canvas.getBoundingClientRect();
    return { x: (e.clientX - rect.left) * (canvas.width / (rect.width || 1)), y: (e.clientY - rect.top) * (canvas.height / (rect.height || 1)) };
  }
  const inside = (p, r) => p.x >= r.x && p.x <= r.x + r.w && p.y >= r.y && p.y <= r.y + r.h;
  const pickActor = (p) => { for (let i = hitActors.length - 1; i >= 0; i--) if (inside(p, hitActors[i])) return hitActors[i].a; return null; };
  const pickBoard = (p) => hitBoards.find((b) => inside(p, b)) || null;
  const pickRack = (p) => hitRacks.find((b) => inside(p, b)) || null;
  const rackTip = (room) => (room.rack && room.rack.tooltip) || '';
  const pickRoom = (p) => hitRooms.find((r) => r.rect && inside(p, { x: r.rect.px, y: r.rect.py, w: r.rect.pw, h: r.rect.ph })) || null;

  function setFocus(id) {
    focusId = id;
    updateBar(); layoutRooms(); kick();
  }
  function unfocus() { if (focusId) setFocus(null); }
  function escape() {
    if (selected) { closeCard(); kick(); return true; }
    if (focusId) { unfocus(); return true; }
    return false;
  }

  canvas.addEventListener('click', (e) => {
    const p = toCanvas(e);
    const a = pickActor(p);
    if (a) { openCard(a); return; }
    const b = pickBoard(p) || pickRack(p);
    if (b) {
      const ex = [...b.room.actors.values()].find((x) => x.exec);
      if (ex) { openCard(ex); return; }
    }
    const room = pickRoom(p);
    if (room && !focusId) { closeCard(); setFocus(room.id); return; }
    if (!room) { closeCard(); unfocus(); } else closeCard();
    kick();
  });
  canvas.addEventListener('dblclick', (e) => {
    const p = toCanvas(e);
    const a = pickActor(p);
    const room = a ? a.room : pickRoom(p);
    if (room && !focusId) setFocus(room.id);
  });
  canvas.addEventListener('pointermove', (e) => {
    if (e.pointerType === 'touch') return;
    const p = toCanvas(e);
    const a = pickActor(p);
    hover = a;
    const rk = a ? null : pickRack(p);
    const over = a || rk || pickBoard(p) || (!focusId && pickRoom(p));
    canvas.style.cursor = over ? 'pointer' : 'default';
    if (els.tip) {
      if (rk) { els.tip.textContent = rackTip(rk.room); els.tip.style.left = Math.round(e.clientX + 12) + 'px'; els.tip.style.top = Math.round(e.clientY + 14) + 'px'; els.tip.hidden = false; } else if (a) { els.tip.textContent = tipText(a); els.tip.style.left = Math.round(e.clientX + 12) + 'px'; els.tip.style.top = Math.round(e.clientY + 14) + 'px'; els.tip.hidden = false; } else els.tip.hidden = true;
    }
  });
  canvas.addEventListener('pointerleave', () => { hover = null; if (els.tip) els.tip.hidden = true; });
  window.addEventListener('keydown', (e) => {
    wakeBar();
    if ((e.key === 'f' || e.key === 'F') && !e.ctrlKey && !e.metaKey && !e.altKey && !isFormTarget(e.target)) { toggleFullscreen(); return; }
    if (e.key === 'Escape') { escape(); return; }
    if ((e.key === ' ' || e.code === 'Space') && (!e.target || e.target === document.body || e.target === canvas)) {
      if (escape()) e.preventDefault();
    }
  });
  els.back.addEventListener('click', () => { closeCard(); unfocus(); });
  if (els.light) {
    els.light.addEventListener('change', () => {
      light.mode = els.light.value === 'day' || els.light.value === 'night' ? els.light.value : 'auto';
      store.set('adalmon-light', light.mode);
      kick();
    });
  }

  // ---------- Tam ekran, otomatik gizlenen çubuk, köşe pill'leri (DOM; çizim döngüsünü uyandırmaz) ----------
  const IDLE_MS = 3000, BAR_ZONE = 44;
  const pano = { fs: false, idle: false, lastAct: 0, pointerY: Infinity, idleTimer: 0, clockTimer: 0, night: null };
  const PILLS_KEY = 'adalmon-pano-pills';
  const DAYS_TR = ['Paz', 'Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt'];
  const MONTHS_TR = ['Oca', 'Şub', 'Mar', 'Nis', 'May', 'Haz', 'Tem', 'Ağu', 'Eyl', 'Eki', 'Kas', 'Ara'];
  const SHIFT = { stepMs: 300000, max: 8, cycle: [[0, 0], [1, 0], [1, 1], [0, 1]] };   // OfficePanoBurnIn: 5 dk, 4 konum

  function setClass(el, name, on) {
    if (!el) return;
    const parts = String(el.className || '').split(/\s+/).filter(Boolean), i = parts.indexOf(name);
    if (on && i < 0) parts.push(name); else if (!on && i >= 0) parts.splice(i, 1); else return;
    el.className = parts.join(' ');
  }
  const isFormTarget = (t) => !!t && (t.tagName === 'SELECT' || t.tagName === 'INPUT' || t.tagName === 'TEXTAREA');

  const summaryText = (s) => (s ? `${s.sessions} oturum · ${s.agents} ajan · ${s.working} çalışıyor` : '');
  const timeText = (d) => String(d.getHours()).padStart(2, '0') + ':' + String(d.getMinutes()).padStart(2, '0');
  const dayText = (d) => `${DAYS_TR[d.getDay()]} ${d.getDate()} ${MONTHS_TR[d.getMonth()]}`;
  function burnInOffset(ms) {
    const step = Math.floor(ms / SHIFT.stepMs), p = SHIFT.cycle[((step % SHIFT.cycle.length) + SHIFT.cycle.length) % SHIFT.cycle.length];
    return { dx: p[0] * SHIFT.max, dy: p[1] * SHIFT.max };
  }

  const isFullscreen = () => !!document.fullscreenElement;
  function toggleFullscreen() {
    try {
      if (document.fullscreenElement) {
        const p = document.exitFullscreen && document.exitFullscreen();
        if (p && p.catch) p.catch(() => {});
        return;
      }
      const root = document.documentElement || document.body;
      const p = root && root.requestFullscreen && root.requestFullscreen();
      if (p && p.catch) p.catch(() => {});
    } catch (e) { /* tam ekran reddedildi */ }
  }

  function applyIdleClass() {
    setClass(document.body, 'idle', pano.fs && pano.idle);     // çubuk solar, imleç gizlenir
  }
  function scheduleIdle(ms) {
    if (pano.idleTimer) return;
    pano.idleTimer = setTimeout(idleCheck, ms);
  }
  // Tek zamanlayıcı: etkinlik oldukça yeniden kurulmaz, süre dolunca kalan süreye bakılır; imleç üst kenardaysa çubuk kalır.
  function idleCheck() {
    pano.idleTimer = 0;
    if (!pano.fs) return;
    const rest = pano.lastAct + IDLE_MS - nowMs();
    if (rest > 0) { scheduleIdle(rest); return; }
    if (pano.pointerY <= BAR_ZONE) { scheduleIdle(IDLE_MS); return; }
    pano.idle = true;
    applyIdleClass();
  }
  function wakeBar() {
    pano.lastAct = nowMs();
    if (pano.idle) { pano.idle = false; applyIdleClass(); }
    if (pano.fs) scheduleIdle(IDLE_MS);
  }
  function onFullscreenChange() {
    pano.fs = isFullscreen();
    setClass(document.body, 'fs', pano.fs);
    if (els.fs) els.fs.textContent = pano.fs ? 'Tam ekrandan çık' : 'Tam ekran';
    pano.idle = false;
    if (!pano.fs && pano.idleTimer) { clearTimeout(pano.idleTimer); pano.idleTimer = 0; }
    applyIdleClass();
    wakeBar();
    applyPills();
    queueResize();
  }

  function pillsOn() {
    const v = store.get(PILLS_KEY);
    return v === 'on' ? true : v === 'off' ? false : pano.fs;     // varsayılan: yalnızca tam ekranda açık
  }
  function renderPillSummary() {
    if (!els.pillL) return;
    els.pillL.textContent = summaryText(state);
    els.pillL.hidden = !pillsOn() || !els.pillL.textContent;
  }
  function renderClock() {
    const d = new Date(), o = burnInOffset(d.getTime());
    if (els.pillTime) els.pillTime.textContent = timeText(d);
    if (els.pillDay) els.pillDay.textContent = dayText(d);
    if (els.pillL) els.pillL.style.transform = `translate(${o.dx}px, ${o.dy}px)`;
    if (els.pillR) els.pillR.style.transform = `translate(${-o.dx}px, ${o.dy}px)`;
  }
  function startClock() {
    if (pano.clockTimer || document.hidden) return;
    pano.clockTimer = setTimeout(clockTick, 60000 - (nowMs() % 60000) + 20);   // bir sonraki dakika sınırı
  }
  function stopClock() {
    if (pano.clockTimer) { clearTimeout(pano.clockTimer); pano.clockTimer = 0; }
  }
  function clockTick() {
    pano.clockTimer = 0;
    if (document.hidden || !pillsOn()) return;
    renderClock();
    startClock();
  }
  function applyPills() {
    const on = pillsOn();
    setClass(document.body, 'pills', on);
    if (els.pills) els.pills.checked = on;
    if (els.pillR) els.pillR.hidden = !on;
    renderPillSummary();
    if (on) { renderClock(); startClock(); } else stopClock();
  }
  // Gündüz/gece görünümü (yalnızca eşik geçilince DOM'a dokunur).
  function syncPanoTheme() {
    const n = uiNight();
    if (pano.night === n) return;
    pano.night = n;
    setClass(els.pillL, 'night', n); setClass(els.pillR, 'night', n);
  }

  document.addEventListener('fullscreenchange', onFullscreenChange);
  for (const type of ['pointermove', 'pointerdown', 'wheel']) {
    document.addEventListener(type, (e) => { if (type === 'pointermove' && e && typeof e.clientY === 'number') pano.pointerY = e.clientY; wakeBar(); });
  }
  if (els.fs) {
    if (document.fullscreenEnabled === false) els.fs.hidden = true;
    els.fs.addEventListener('click', toggleFullscreen);
  }
  if (els.pills) {
    els.pills.addEventListener('change', () => { store.set(PILLS_KEY, els.pills.checked ? 'on' : 'off'); applyPills(); });
  }
  applyPills();

  // ---------- SSE ----------
  let source = null, retry = 1000, failures = 0;

  function setConn(kind, text) {
    els.dot.className = 'dot ' + kind;
    els.conn.textContent = text;
  }

  async function probe() {
    try { await api('/v1/state'); } catch (err) { if (err && err.status) showError(describeError(err)); }
  }

  function connect() {
    if (source) source.close();
    setConn('wait', failures ? 'yeniden bağlanıyor…' : 'bağlanıyor…');
    source = new EventSource('/v1/stream?t=' + encodeURIComponent(token));
    source.onopen = () => { retry = 1000; failures = 0; setConn('on', 'bağlı'); showError(''); };
    source.onmessage = (e) => {
      try { apply(JSON.parse(e.data)); } catch (err) { if (TEST) TEST.lastError = err; /* bozuk olay yok sayılır */ }
    };
    source.onerror = () => {
      source.close(); source = null;
      failures += 1;
      setConn(failures > 6 ? 'off' : 'wait', 'yeniden bağlanıyor…');
      if (failures >= 2) probe();
      if (failures > 6) showError('Adalmon\'a ulaşılamıyor. Adalmon açık değilse ya da adres/oturum anahtarı değiştiyse, Ayarlar > Claude ajanları > "Tarayıcıda aç" ile yeniden açın.');
      setTimeout(connect, retry);
      retry = Math.min(retry * 2, 30000);
    };
  }

  // ---------- Başlangıç ----------
  async function boot() {
    try {
      resize();
      await prepare();
      setInterval(heartbeat, 1000);
      kick();
      connect();
    } catch (err) {
      setLoading('');
      setConn('off', 'bağlanamadı');
      showError(err && err.status ? describeError(err) : 'Ofis yüklenemedi: ' + (err && err.message ? err.message : err));
    }
  }

  if (TEST) {
    TEST.api = { apply, layoutRooms, frame, advance, draw, animating, prepare, buildCard, openCard, closeCard, escape, setFocus, bakeSheet, heartbeat, scheduleActors,
                 rooms, tierData, light, labelVariants, resolveLabels, labelMetrics, wantNight, localNight, applyServerLighting, stepLight, poseOf, bubbleOf, lookOf, startCleaner, bfs, boardTile,
                 panoArrange, uiScaleOf, backdropSize, backdropKey, getBackdrop, getRoomShadow, cacheStats, backdropCache, summaryText, timeText, dayText, burnInOffset,
                 toggleFullscreen, onFullscreenChange, wakeBar, idleCheck, pillsOn, applyPills, renderClock, clockTick, isFormTarget, pano, resize,
                 get U() { return U; }, get S() { return S; }, get assets() { return assets; }, get layout() { return layout; }, get selected() { return selected; },
                 get focusId() { return focusId; }, get hitActors() { return hitActors; }, get hitBoards() { return hitBoards; }, get hitRacks() { return hitRacks; }, get raf() { return raf; }, get needsRedraw() { return needsRedraw; },
                 set needsRedraw(v) { needsRedraw = v; } };
  }
  const started = boot();
  if (TEST) TEST.ready = started;
})();
