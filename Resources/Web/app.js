'use strict';
// Adalmon ofis (tarayıcı): vanilla JS + Canvas 2D, dış istek yok. Sahne verisi /v1/layout'tan (Swift tek doğruluk kaynağı),
// canlı durum /v1/stream (SSE) üzerinden gelir. Balon metinleri, koltuk atamaları ve davranışlar sunucudan hazır gelir.
(() => {
  const T = 16;
  const params = new URLSearchParams(location.search);
  let token = params.get('t') || sessionStorage.getItem('adalmon-token') || '';
  if (params.get('t')) {
    sessionStorage.setItem('adalmon-token', token);
    history.replaceState(null, '', location.pathname); // token adres çubuğunda/geçmişte kalmasın
  }

  const $ = (id) => document.getElementById(id);
  const canvas = $('scene');
  const ctx = canvas.getContext('2d');
  const els = { dot: $('dot'), conn: $('conn'), counts: $('counts'), empty: $('empty'), error: $('error'), back: $('back') };

  let layout = null;
  const images = new Map();      // dosya -> ImageBitmap
  const tinted = new Map();      // karakter+rozet -> canvas
  const tileCache = new Map();   // renklendirilmiş karo -> canvas
  const artCache = new Map();    // art adı -> canvas (ya da canvas dizisi)
  const tierData = new Map();    // kademe -> {bg, dynamic[], seatById, ...}
  const rooms = new Map();
  let state = null;
  let skew = 0;                  // sunucu saati - yerel saat
  let initialized = false;
  let focusId = null;
  let hitRects = [];
  let dpr = window.devicePixelRatio || 1;
  let S = 1;

  const now = () => Date.now() + skew;

  // ---------- Ağ ----------
  async function api(path) {
    const res = await fetch(path, { headers: { 'X-Adalmon-Token': token }, cache: 'no-store' });
    if (!res.ok) throw new Error(String(res.status));
    return res;
  }

  function loadImage(file) {
    if (!images.has(file)) {
      // Düzen JSON'u mobilya dosyalarını klasör öneki olmadan verir ("PC/PC_FRONT_OFF.png"): bilinen kök yoksa furniture/ varsay.
      const rooted = /^(characters|furniture|floors|walls|carpets|generated)\//.test(file) ? file : 'furniture/' + file;
      images.set(file, api('/assets/' + rooted).then((r) => r.blob()).then((b) => createImageBitmap(b)));
    }
    return images.get(file);
  }

  function showError(text) { els.error.textContent = text; els.error.hidden = !text; }

  // ---------- Piksel yardımcıları ----------
  function hslToRgb(h, s, l) {
    const c = (1 - Math.abs(2 * l - 1)) * s;
    const hp = (h - Math.floor(h)) * 6;
    const x = c * (1 - Math.abs((hp % 2) - 1));
    const k = Math.floor(hp);
    const [r, g, b] = [[c, x, 0], [x, c, 0], [0, c, x], [0, x, c], [x, 0, c], [c, 0, x]][Math.min(5, k)];
    const m = l - c / 2;
    return [(r + m) * 255, (g + m) * 255, (b + m) * 255];
  }

  function newCanvas(w, h) {
    const c = document.createElement('canvas');
    c.width = w; c.height = h;
    return c;
  }

  // Swift'teki OfficeTileColor.colorize ile aynı formül (Photoshop "colorize").
  function colorized(img, sx, sy, w, h, color) {
    const key = img.__k + ':' + sx + ',' + sy + ':' + color.join(',');
    if (tileCache.has(key)) return tileCache.get(key);
    const c = newCanvas(w, h);
    const g = c.getContext('2d', { willReadFrequently: true });
    g.drawImage(img, sx, sy, w, h, 0, 0, w, h);
    const data = g.getImageData(0, 0, w, h);
    const [hh, ss, bb, cc] = color;
    for (let i = 0; i < data.data.length; i += 4) {
      if (data.data[i + 3] === 0) continue;
      let l = (0.299 * data.data[i] + 0.587 * data.data[i + 1] + 0.114 * data.data[i + 2]) / 255;
      if (cc !== 0) l = 0.5 + (l - 0.5) * ((100 + cc) / 100);
      if (bb !== 0) l += bb / 200;
      l = Math.min(1, Math.max(0, l));
      const [r, gg, b] = hslToRgb(hh / 360, Math.min(1, Math.max(0, ss / 100)), l);
      data.data[i] = r; data.data[i + 1] = gg; data.data[i + 2] = b;
    }
    g.putImageData(data, 0, 0);
    tileCache.set(key, c);
    return c;
  }

  function paintArt(def) {
    const rows = def.rows;
    const w = Math.max(...rows.map((r) => r.length));
    const c = newCanvas(w, rows.length);
    const g = c.getContext('2d');
    rows.forEach((row, y) => {
      for (let x = 0; x < row.length; x++) {
        const color = def.palette[row[x]];
        if (color) { g.fillStyle = color; g.fillRect(x, y, 1, 1); }
      }
    });
    return c;
  }

  function art(name) {
    if (!artCache.has(name)) {
      const def = layout.art[name];
      artCache.set(name, Array.isArray(def) ? def.map(paintArt) : paintArt(def));
    }
    return artCache.get(name);
  }

  const rgbCss = (c, a) => `rgba(${Math.round(c[0] * 255)},${Math.round(c[1] * 255)},${Math.round(c[2] * 255)},${a === undefined ? 1 : a})`;

  // Karakter sayfası + rozet tonu (SpriteKit colorBlendFactor gibi: renk, alfa korunarak karıştırılır).
  function characterSheet(badge) {
    const ap = layout.appearance[badge] || layout.appearance.unknown;
    const key = ap.character + ':' + badge;
    if (!tinted.has(key)) {
      const img = images.get(layout.characters.file.replace('%d', ap.character)).__v;
      const c = newCanvas(img.width, img.height);
      const g = c.getContext('2d');
      g.drawImage(img, 0, 0);
      g.globalCompositeOperation = 'source-atop';
      g.globalAlpha = ap.tintBlend;
      g.fillStyle = rgbCss(ap.tint);
      g.fillRect(0, 0, c.width, c.height);
      tinted.set(key, c);
    }
    return tinted.get(key);
  }

  // ---------- Düzen hazırlığı ----------
  async function prepare() {
    layout = await (await api('/v1/layout')).json();
    const files = new Set(['walls/wall_0.png']);
    Object.values(layout.appearance).forEach((a) => files.add(layout.characters.file.replace('%d', a.character)));
    Object.values(layout.furniture).forEach((f) => { files.add(f.file); (f.pcOn || []).forEach((p) => files.add(p)); });
    Object.values(layout.tiers).forEach((t) => {
      for (let i = 0; i < t.tiles.length; i += 4) if (t.tiles[i] === 2) files.add(layout.files.floor.replace('%d', t.tiles[i + 1]));
    });
    await Promise.all([...files].map(async (f) => {
      const img = await loadImage(f);
      img.__k = f;
      images.set(f, Object.assign(Promise.resolve(img), { __v: img }));
    }));
    for (const [key, t] of Object.entries(layout.tiers)) tierData.set(key, buildTier(key, t));
  }

  const img = (file) => images.get(file).__v;

  function buildTier(key, t) {
    const b = t.bounds;
    const w = (b.maxCol - b.minCol + 1) * T, h = (b.maxRow - b.minRow + 1) * T;
    const bg = newCanvas(w, h);
    const g = bg.getContext('2d');
    g.imageSmoothingEnabled = false;
    const wall = img('walls/wall_0.png');
    for (let r = b.minRow; r <= b.maxRow; r++) {
      for (let c = b.minCol; c <= b.maxCol; c++) {
        const i = (r * t.cols + c) * 4;
        const kind = t.tiles[i], dx = (c - b.minCol) * T, dy = (r - b.minRow) * T;
        const color = t.tiles[i + 3] >= 0 ? t.colors[t.tiles[i + 3]] : null;
        if (kind === 2) {
          const f = img(layout.files.floor.replace('%d', t.tiles[i + 1]));
          g.drawImage(color ? colorized(f, 0, 0, T, T, color) : f, dx, dy);
        } else if (kind === 1) {
          const mask = t.tiles[i + 2];
          const sx = (mask % 4) * 16, sy = Math.floor(mask / 4) * 32;
          g.drawImage(color ? colorized(wall, sx, sy, 16, 32, color) : wall, color ? 0 : sx, color ? 0 : sy, 16, 32, dx, dy - 16, 16, 32);
        }
      }
    }
    const dynamic = [];
    const sorted = t.furniture.slice().sort((a, c) => a.z - c.z);
    for (const p of sorted) {
      if (p.z < 0) drawFurniture(g, p, t, null); else dynamic.push(p);
    }
    const seatById = new Map(t.seats.map((s) => [s.id, s]));
    const placementByIndex = new Map(t.furniture.map((p) => [p.i, p]));
    return { key, t, bg, w, h, dynamic, seatById, placementByIndex };
  }

  function drawFurniture(g, p, t, frameFile) {
    const a = layout.furniture[p.asset];
    const image = img(frameFile || a.file);
    const x = (p.col - t.bounds.minCol) * T, y = (p.row - t.bounds.minRow) * T;
    if (p.mirrored) {
      g.save(); g.translate(x + a.w, y); g.scale(-1, 1); g.drawImage(image, 0, 0); g.restore();
    } else {
      g.drawImage(image, x, y);
    }
  }

  // ---------- Odalar ve karakterler ----------
  const tileX = (td, col) => (col - td.t.bounds.minCol) * T + 8;
  const tileY = (td, row) => (row - td.t.bounds.minRow + 1) * T - 1;   // ayak noktası
  const pt = (td, c) => ({ x: tileX(td, c[0]), y: tileY(td, c[1]) });

  function newRoom(r) {
    return { id: r.id, tierKey: r.tier, td: tierData.get(r.tier), actors: new Map(), title: r.title, badge: r.badge, badgeLabel: r.badgeLabel,
             group: r.group, overflow: 0, leaving: false, alpha: 1, leaveAt: 0, rect: null, scale: 1 };
  }

  function newActor(room, m, seat, instant) {
    const td = room.td;
    const a = { id: m.id, room, member: m, seat, path: [], goal: 'seat', x: 0, y: 0, dir: seat.facing, atSeat: false, execMode: null,
                strollUntil: 0, wait: 0, leaving: false, alpha: 1, born: now(), walkT: 0, prevStatus: m.status };
    a.exec = seat.kind === 'executive';
    if (instant) { placeInstant(a); } else {
      const d = pt(td, td.t.door);
      a.x = d.x; a.y = d.y; a.dir = 'left'; a.goal = 'seat';
      a.path = [pt(td, td.t.entrance)].concat(seat.enter.map((c) => pt(td, c)));
      a.alpha = 0;
    }
    return a;
  }

  function placeInstant(a) {
    const td = a.room.td;
    a.path = [];
    if (a.exec && execDesired(a) === 'board' && td.t.board) {
      const p = pt(td, td.t.board); a.x = p.x; a.y = p.y; a.dir = 'up'; a.execMode = 'board'; a.atSeat = false; a.goal = 'board';
    } else {
      const p = pt(td, [a.seat.col, a.seat.row]); a.x = p.x; a.y = p.y; a.dir = a.seat.facing; a.atSeat = true; a.goal = 'seat'; a.execMode = 'seated';
    }
  }

  function execDesired(a) {
    const st = a.member.status;
    if (st === 'thinking' || st === 'tool') return 'board';
    if (st === 'permission') return 'stroll';
    return now() < a.strollUntil ? 'stroll' : 'seated';
  }

  function routeToBoard(a) {
    const td = a.room.td;
    a.goal = 'board'; a.wait = 0;
    if (a.atSeat && a.seat.toBoard) a.path = a.seat.toBoard.map((c) => pt(td, c)); else a.path = [pt(td, td.t.board)];
    a.atSeat = false;
  }

  function routeToSeat(a) {
    const td = a.room.td;
    a.goal = 'seat';
    const back = a.seat.toBoard ? a.seat.toBoard.slice(0, -1).reverse().map((c) => pt(td, c)) : [];
    a.path = [pt(td, td.t.board)].concat(back, [pt(td, [a.seat.col, a.seat.row])]);
  }

  function setExecMode(a, mode) {
    if (a.execMode === mode || !a.room.td.t.board) return;
    a.execMode = mode;
    if (mode === 'seated') routeToSeat(a);
    else if (a.atSeat) routeToBoard(a);
    else { a.goal = 'board'; a.path = [pt(a.room.td, a.room.td.t.board)]; }
    if (mode === 'stroll') a.goal = 'stroll-start';
  }

  function strollStep(a) {
    const td = a.room.td, t = td.t;
    const boardRow = t.board[1];
    const tiles = t.zoneTiles.filter((c) => c[1] === boardRow);
    const here = Math.round((a.x - 8) / T) + t.bounds.minCol;
    let pool = tiles.filter((c) => c[0] !== here && Math.abs(c[0] - here) >= 4 && Math.abs(c[0] - here) <= 6);
    if (!pool.length) {
      const others = tiles.filter((c) => c[0] !== here);
      const far = Math.max(0, ...others.map((c) => Math.abs(c[0] - here)));
      pool = far >= 2 ? others.filter((c) => Math.abs(c[0] - here) === far) : others;
    }
    if (!pool.length) { a.wait = 2; return; }
    const target = pool[Math.floor(Math.random() * pool.length)];
    a.path = [pt(td, target)];
    a.goal = 'stroll';
  }

  function startLeave(a) {
    if (a.leaving) return;
    const td = a.room.td, t = td.t;
    a.leaving = true; a.goal = 'out'; a.atSeat = false;
    const door = pt(td, t.door), ent = pt(td, t.entrance);
    const seatPath = a.seat.enter.slice(0, -1).reverse().map((c) => pt(td, c));
    const nearSeat = Math.abs(a.x - tileX(td, a.seat.col)) < 1 && Math.abs(a.y - tileY(td, a.seat.row)) < 1;
    a.path = (nearSeat ? seatPath.concat([ent]) : [ent]).concat([door]);
  }

  function arrive(a) {
    if (a.goal === 'out') { a.done = true; return; }
    if (a.goal === 'seat') {
      a.atSeat = true; a.dir = a.seat.facing;
      if (a.exec) a.execMode = 'seated';   // asıl mod güncelleme döngüsünde (updateActor) uygulanır
    } else if (a.goal === 'board') {
      a.dir = 'up';
    } else if (a.goal === 'stroll-start' || a.goal === 'stroll') {
      a.dir = 'down'; a.wait = 1.5 + Math.random() * 2.5; a.goal = 'stroll-idle';
    }
  }

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
      }
    }
  }

  const moving = (a) => a.path.length > 0;

  function applyMember(room, a, m) {
    const old = a.member.status;
    a.member = m;
    if (a.exec) {
      const wasWorking = old === 'thinking' || old === 'tool' || old === 'permission';
      const working = m.status === 'thinking' || m.status === 'tool' || m.status === 'permission';
      if (working) a.strollUntil = 0; else if (wasWorking) a.strollUntil = now() + layout.strollSeconds * 1000;
      setExecMode(a, execDesired(a));
    }
  }

  function updateRoom(room, r, instant) {
    room.title = r.title; room.badge = r.badge; room.badgeLabel = r.badgeLabel; room.group = r.group; room.overflow = r.overflow;
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

  function apply(s) {
    skew = s.now - Date.now();
    state = s;
    const ids = new Set();
    for (const r of s.rooms) {
      ids.add(r.id);
      if (!tierData.has(r.tier)) continue;
      let room = rooms.get(r.id);
      let instant = !initialized;
      if (room && (room.tierKey !== r.tier || r.reseated)) { rooms.delete(r.id); room = null; instant = true; }
      if (!room) { room = newRoom(r); room.td = tierData.get(r.tier); rooms.set(r.id, room); }
      updateRoom(room, r, instant);
    }
    for (const [id, room] of rooms) {
      if (!ids.has(id) && !room.leaving) { room.leaving = true; room.leaveAt = performance.now(); room.actors.forEach(startLeave); }
    }
    initialized = true;
    if (focusId && !rooms.has(focusId)) focusId = null;
    updateBar();
    layoutRooms();
  }

  function updateBar() {
    const n = state ? state.rooms.length : 0;
    els.counts.textContent = state ? `${state.sessions} oturum · ${state.agents} ajan · ${state.working} çalışıyor` : '';
    els.empty.hidden = n > 0;
    els.back.hidden = !focusId;
  }

  // ---------- Yerleşim ----------
  const PLAQUE_H = () => Math.round(26 * dpr);
  const GAP = () => Math.round(14 * dpr);

  function layoutRooms() {
    const list = [...rooms.values()];
    hitRects = [];
    if (!list.length) return;
    const W = canvas.width, H = canvas.height;
    const shown = focusId && rooms.has(focusId) ? [rooms.get(focusId)] : list;
    const cw = Math.max(...shown.map((r) => r.td.w)), ch = Math.max(...shown.map((r) => r.td.h));
    const gap = GAP(), ph = PLAQUE_H();
    let best = null;
    for (let cols = 1; cols <= shown.length; cols++) {
      const rows = Math.ceil(shown.length / cols);
      // ölçek: hücre = oda + levha + boşluk
      const sx = Math.floor((W - gap * (cols + 1)) / (cols * cw));
      const sy = Math.floor((H - gap * (rows + 1) - ph * rows) / (rows * ch));
      const sc = Math.max(1, Math.min(sx, sy, 8 * Math.max(1, Math.round(dpr))));
      if (!best || sc > best.sc || (sc === best.sc && cols * rows < best.cols * best.rows)) best = { cols, rows, sc };
    }
    S = best.sc;
    const cellW = cw * S + gap, cellH = ch * S + ph + gap;
    const totalW = best.cols * cellW - gap, totalH = best.rows * cellH - gap;
    const x0 = Math.round((W - totalW) / 2), y0 = Math.max(0, Math.round((H - totalH) / 2));
    shown.forEach((room, i) => {
      const col = i % best.cols, row = Math.floor(i / best.cols);
      const cellX = x0 + col * cellW, cellY = y0 + row * cellH;
      const x = cellX + Math.round((cw * S - room.td.w * S) / 2), y = cellY + ph + Math.round((ch * S - room.td.h * S) / 2);
      room.rect = { x, y, w: room.td.w * S, h: room.td.h * S, px: cellX, py: cellY, pw: cw * S, ph: ch * S + ph };
      hitRects.push(room);
    });
    for (const room of list) if (!shown.includes(room)) room.rect = null;
  }

  // ---------- Çizim ----------
  function roundRect(x, y, w, h, r) {
    ctx.beginPath();
    if (ctx.roundRect) ctx.roundRect(x, y, w, h, r); else ctx.rect(x, y, w, h);
  }

  function frameFor(a) {
    const c = layout.characters;
    if (moving(a)) return c.walkCycle[Math.floor(a.walkT / 0.125) % 4];
    let pose = 'stand';
    if (a.exec) {
      if (a.execMode === 'board') pose = 'typing';
      else if (a.atSeat) pose = 'sitting';
    } else if (a.atSeat) {
      pose = a.member.pose || 'sitting';
    }
    if (pose === 'typing') return c.frames.typing[Math.floor(performance.now() / 280) % 2];
    if (pose === 'reading') return c.frames.reading[Math.floor(performance.now() / 600) % 2];
    return c.frames.stand;
  }

  function upright(a) {
    return moving(a) || (a.exec && a.execMode !== 'seated') || (!a.atSeat && !a.exec);
  }

  function bubbleOf(a) {
    const m = a.member;
    if (a.leaving || moving(a)) return null;
    if (m.alert) return { alert: true };
    if (!m.bubble) return null;
    if (m.activityAt && now() - m.activityAt >= layout.bubbleLifetime * 1000) return null;
    return { text: m.bubble };
  }

  function drawActor(a, td) {
    const c = layout.characters, ap = layout.appearance[a.member.badge] || layout.appearance.unknown;
    const sheet = characterSheet(a.member.badge);
    const frame = frameFor(a);
    const row = c.rows[a.dir === 'left' ? 'left' : a.dir];
    const k = ap.small && S >= 2 ? (S - 1) / S : 1;
    const w = c.frameWidth * k, h = c.frameHeight * k;
    const drop = upright(a) ? 0 : c.sitDrop;
    const x = Math.round(a.x), y = Math.round(a.y) + drop;
    ctx.save();
    ctx.globalAlpha *= a.alpha;
    ctx.translate(x, y);
    if (a.dir === 'left') ctx.scale(-1, 1);
    ctx.drawImage(sheet, frame * c.frameWidth, row * c.frameHeight, c.frameWidth, c.frameHeight, -w / 2, -h, w, h);
    ctx.restore();
    // aksesuar (baş üstü)
    const still = !moving(a);
    const low = still && (!upright(a) || (a.member.pose === 'reading'));
    const headTop = (low ? 28 : 30) * k - drop;
    if (ap.accessory !== 'none') {
      const acc = art(ap.accessory);
      ctx.save();
      ctx.globalAlpha *= a.alpha;
      ctx.drawImage(acc, Math.round(a.x - acc.width * k / 2), Math.round(a.y - (headTop - 1) - acc.height * k / 2), acc.width * k, acc.height * k);
      ctx.restore();
    }
    return { headTop, x: a.x, y: a.y };
  }

  function drawRoom(room, now_ms) {
    const r = room.rect, td = room.td;
    if (!r) return;
    const overlays = [];
    ctx.save();
    ctx.globalAlpha = room.alpha;
    ctx.setTransform(S, 0, 0, S, r.x, r.y);
    ctx.imageSmoothingEnabled = false;
    ctx.drawImage(td.bg, 0, 0);
    const items = [];
    const b = td.t.bounds;
    const occupiedPC = new Map();
    const boardActor = [...room.actors.values()].find((a) => a.exec && a.execMode === 'board' && !moving(a));
    for (const a of room.actors.values()) {
      if (a.atSeat && a.seat.pc !== undefined && a.member.pcOn) occupiedPC.set(a.seat.pc, a);
    }
    for (const p of td.dynamic) {
      items.push({ z: p.z, fn: () => {
        let file = null;
        const a = layout.furniture[p.asset];
        if (a.pcOn && occupiedPC.has(p.i)) file = a.pcOn[Math.floor(now_ms / 450) % a.pcOn.length];
        drawFurniture(ctx, p, td.t, file);
      } });
    }
    const door = td.t.door;
    items.push({ z: (door[1] + 1) * T - 8, fn: () => ctx.drawImage(art('door'), (door[0] - b.minCol) * T, (door[1] - b.minRow + 1) * T - 32) });
    if (boardActor && td.t.boardIndex !== undefined && td.placementByIndex.has(td.t.boardIndex)) {
      const p = td.placementByIndex.get(td.t.boardIndex);
      const frames = art('boardWrite'), o = layout.art.boardWriteOrigin;
      items.push({ z: (p.row + 2) * T + 0.1, fn: () => ctx.drawImage(frames[Math.floor(now_ms / 500) % frames.length],
        (p.col - b.minCol) * T + o[0], (p.row - b.minRow) * T + o[1]) });
    }
    for (const a of room.actors.values()) {
      items.push({ z: a.y + b.minRow * T + 1.5, fn: () => { overlays.push({ a, info: drawActor(a, td) }); } });
    }
    items.sort((p, q) => p.z - q.z).forEach((i) => i.fn());
    ctx.restore();
    ctx.globalAlpha = 1;

    // ekran uzayında: etiketler ve balonlar
    ctx.save();
    ctx.globalAlpha = room.alpha;
    const px = (wx) => r.x + wx * S, py = (wy) => r.y + wy * S;
    for (const { a, info } of overlays) {
      if (a.alpha <= 0.01) continue;
      drawLabel(a, px(info.x), py(info.y));
    }
    for (const { a, info } of overlays) {
      const bub = bubbleOf(a);
      if (!bub || a.alpha < 0.9) continue;
      drawBubble(bub, px(info.x), py(info.y - info.headTop), r);
    }
    ctx.restore();
    drawPlaque(room);
  }

  function drawLabel(a, sx, sy) {
    const g = layout.groupColors[a.room.group % layout.groupColors.length];
    const text = a.member.label || '';
    const fs = Math.round(9 * dpr);
    ctx.font = `${fs}px -apple-system, system-ui, sans-serif`;
    const tw = Math.ceil(ctx.measureText(text).width), padX = Math.round(4 * dpr), h = Math.round(13 * dpr), stripe = Math.max(2, Math.round(2 * dpr));
    const w = tw + padX * 2;
    const x = Math.round(sx - w / 2), y = Math.round(sy + 3 * S + 2 * dpr);
    ctx.fillStyle = 'rgba(20,22,30,0.82)';
    roundRect(x, y, w, h, Math.round(3 * dpr)); ctx.fill();
    ctx.fillStyle = rgbCss(g);
    ctx.fillRect(x + padX, y + h - stripe - 1, w - padX * 2, stripe);
    ctx.fillStyle = '#fff';
    ctx.textBaseline = 'middle'; ctx.textAlign = 'center';
    ctx.fillText(text, sx, y + (h - stripe) / 2);
  }

  function drawBubble(bub, sx, sy, r) {
    if (bub.alert) {
      const al = art('alertBubble'), k = S;
      const bob = Math.sin(performance.now() / 190) * k;
      ctx.drawImage(al, Math.round(sx + 7 * k), Math.round(sy + 8 * k - al.height * k + bob), al.width * k, al.height * k);
      return;
    }
    const fs = Math.round(11 * dpr);
    ctx.font = `${fs}px -apple-system, system-ui, sans-serif`;
    const pad = Math.round(6 * dpr), tw = Math.ceil(ctx.measureText(bub.text).width);
    const w = tw + pad * 2, h = Math.round(18 * dpr), tail = Math.round(5 * dpr);
    let x = Math.round(sx - 4 * dpr);
    if (x + w > r.x + r.w) x = r.x + r.w - w;
    if (x < r.x) x = r.x;
    const y = Math.round(sy - h - tail - 2 * dpr);
    ctx.fillStyle = '#fff'; ctx.strokeStyle = '#222'; ctx.lineWidth = Math.max(1, Math.round(dpr));
    roundRect(x, y, w, h, Math.round(5 * dpr)); ctx.fill(); ctx.stroke();
    const tx = Math.min(Math.max(sx, x + pad), x + w - pad);
    ctx.beginPath(); ctx.moveTo(tx - tail, y + h - 1); ctx.lineTo(tx, y + h + tail); ctx.lineTo(tx + tail, y + h - 1); ctx.closePath();
    ctx.fill(); ctx.stroke();
    ctx.fillStyle = '#fff'; ctx.fillRect(tx - tail + 1, y + h - 1, tail * 2 - 2, 2);
    ctx.fillStyle = '#1a1a1a'; ctx.textBaseline = 'middle'; ctx.textAlign = 'left';
    ctx.fillText(bub.text, x + pad, y + h / 2 + 1);
  }

  function drawPlaque(room) {
    const r = room.rect, ph = PLAQUE_H();
    const g = layout.groupColors[room.group % layout.groupColors.length];
    const ap = layout.appearance[room.badge] || layout.appearance.unknown;
    ctx.save();
    ctx.globalAlpha = room.alpha;
    const fs = Math.round(12 * dpr), bfs = Math.round(9 * dpr);
    ctx.font = `600 ${fs}px -apple-system, system-ui, sans-serif`;
    const name = room.title || '';
    const nameW = Math.min(Math.ceil(ctx.measureText(name).width), r.w - Math.round(90 * dpr));
    let shown = name;
    while (shown.length > 1 && ctx.measureText(shown).width > nameW) shown = shown.slice(0, -1);
    if (shown !== name) shown = shown.slice(0, -1) + '…';
    ctx.font = `700 ${bfs}px -apple-system, system-ui, sans-serif`;
    const badge = ap.badgeText, bw = Math.ceil(ctx.measureText(badge).width) + Math.round(10 * dpr);
    const pad = Math.round(8 * dpr), h = Math.round(20 * dpr), y = r.y - ph + Math.round(2 * dpr);
    ctx.font = `600 ${fs}px -apple-system, system-ui, sans-serif`;
    const w = Math.min(r.w, Math.ceil(ctx.measureText(shown).width) + bw + pad * 3 + Math.round(6 * dpr));
    ctx.fillStyle = 'rgba(20,22,30,0.88)';
    roundRect(r.x, y, w, h, h / 2); ctx.fill();
    ctx.fillStyle = rgbCss(g);
    roundRect(r.x, y, Math.round(5 * dpr), h, Math.round(2 * dpr)); ctx.fill();
    ctx.fillStyle = '#fff'; ctx.textBaseline = 'middle'; ctx.textAlign = 'left';
    ctx.fillText(shown, r.x + Math.round(12 * dpr), y + h / 2 + 1);
    const nx = r.x + Math.round(12 * dpr) + Math.ceil(ctx.measureText(shown).width) + Math.round(8 * dpr);
    ctx.fillStyle = rgbCss(ap.tint);
    roundRect(nx, y + Math.round(4 * dpr), bw, h - Math.round(8 * dpr), Math.round(4 * dpr)); ctx.fill();
    ctx.fillStyle = '#fff'; ctx.textAlign = 'center';
    ctx.font = `700 ${bfs}px -apple-system, system-ui, sans-serif`;
    ctx.fillText(badge, nx + bw / 2, y + h / 2 + 1);
    if (room.overflow > 0) {
      const t = `+${room.overflow}`;
      ctx.font = `700 ${fs}px -apple-system, system-ui, sans-serif`;
      const tw = Math.ceil(ctx.measureText(t).width) + Math.round(12 * dpr);
      ctx.fillStyle = '#ff8a00';
      roundRect(r.x + r.w - tw, y, tw, h, h / 2); ctx.fill();
      ctx.fillStyle = '#fff'; ctx.textAlign = 'center';
      ctx.fillText(t, r.x + r.w - tw / 2, y + h / 2 + 1);
    }
    ctx.restore();
  }

  // ---------- Döngü ----------
  let raf = 0, last = 0, hiddenAt = 0;

  function tick(dt) {
    for (const [id, room] of rooms) {
      for (const [aid, a] of room.actors) {
        updateActor(a, dt);
        if (a.done) { room.actors.delete(aid); continue; }
      }
      if (room.leaving) {
        if (room.actors.size === 0) {
          room.alpha = Math.max(0, room.alpha - dt * 1.5);
          if (room.alpha === 0) { rooms.delete(id); layoutRooms(); }
        }
      }
    }
  }

  function draw(ts) {
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    ctx.imageSmoothingEnabled = false;
    for (const room of rooms.values()) drawRoom(room, ts);
    ctx.setTransform(1, 0, 0, 1, 0, 0);
  }

  function frame(ts) {
    raf = 0;
    if (document.hidden || !layout) return;
    const anyMoving = [...rooms.values()].some((r) => [...r.actors.values()].some(moving));
    const interval = anyMoving ? 1000 / 30 : 1000 / 12;      // CPU: hareket yoksa ≈12 fps
    if (ts - last >= interval - 1) {
      const dt = Math.min((ts - last) / 1000, 0.25);
      last = ts;
      tick(dt);
      draw(Date.now());
    }
    raf = requestAnimationFrame(frame);
  }

  function startLoop() { if (!raf) { last = 0; raf = requestAnimationFrame(frame); } }

  document.addEventListener('visibilitychange', () => {
    if (document.hidden) { hiddenAt = Date.now(); return; }
    // Gizliyken çizim durdu: uzun süre sonra hareketleri hemen tamamla.
    if (Date.now() - hiddenAt > 2000) {
      for (const room of rooms.values()) for (const a of room.actors.values()) {
        const p = a.path.length ? a.path[a.path.length - 1] : null;
        if (p) { a.x = p.x; a.y = p.y; a.path = []; arrive(a); }
      }
    }
    startLoop();
  });

  // ---------- Boyut, etkileşim ----------
  function resize() {
    dpr = window.devicePixelRatio || 1;
    const rect = canvas.getBoundingClientRect();
    canvas.width = Math.max(1, Math.round(rect.width * dpr));
    canvas.height = Math.max(1, Math.round(rect.height * dpr));
    layoutRooms();
  }
  let resizeQueued = false;
  window.addEventListener('resize', () => {
    if (resizeQueued) return;
    resizeQueued = true;
    requestAnimationFrame(() => { resizeQueued = false; resize(); });
  });

  canvas.addEventListener('click', (e) => {
    const rect = canvas.getBoundingClientRect();
    const x = (e.clientX - rect.left) * dpr, y = (e.clientY - rect.top) * dpr;
    if (focusId) return;
    const hit = hitRects.find((r) => r.rect && x >= r.rect.px && x <= r.rect.px + r.rect.pw && y >= r.rect.py && y <= r.rect.py + r.rect.ph);
    if (hit) { focusId = hit.id; updateBar(); layoutRooms(); }
  });
  canvas.addEventListener('mousemove', (e) => {
    const rect = canvas.getBoundingClientRect();
    const x = (e.clientX - rect.left) * dpr, y = (e.clientY - rect.top) * dpr;
    const over = !focusId && hitRects.some((r) => r.rect && x >= r.rect.px && x <= r.rect.px + r.rect.pw && y >= r.rect.py && y <= r.rect.py + r.rect.ph);
    canvas.style.cursor = over && hitRects.length > 0 ? 'zoom-in' : 'default';
  });
  function unfocus() { if (focusId) { focusId = null; updateBar(); layoutRooms(); } }
  window.addEventListener('keydown', (e) => { if (e.key === 'Escape') unfocus(); });
  els.back.addEventListener('click', unfocus);

  // ---------- SSE ----------
  let source = null, retry = 1000, failures = 0;

  function setConn(kind, text) {
    els.dot.className = 'dot ' + kind;
    els.conn.textContent = text;
  }

  function connect() {
    if (source) source.close();
    setConn('wait', failures ? 'yeniden bağlanıyor…' : 'bağlanıyor…');
    source = new EventSource('/v1/stream?t=' + encodeURIComponent(token));
    source.onopen = () => { retry = 1000; failures = 0; setConn('on', 'bağlı'); showError(''); };
    source.onmessage = (e) => {
      try { apply(JSON.parse(e.data)); } catch (err) { /* bozuk olay yok sayılır */ }
    };
    source.onerror = () => {
      source.close(); source = null;
      failures += 1;
      setConn(failures > 6 ? 'off' : 'wait', 'yeniden bağlanıyor…');
      if (failures > 6) showError('Adalmon\'a ulaşılamıyor. Adalmon açık değilse ya da adres/oturum anahtarı değiştiyse, Ayarlar > Claude ajanları > "Tarayıcıda aç" ile yeniden açın.');
      setTimeout(connect, retry);
      retry = Math.min(retry * 2, 30000);
    };
  }

  // ---------- Başlangıç ----------
  (async () => {
    try {
      resize();
      await prepare();
      startLoop();
      connect();
    } catch (err) {
      setConn('off', 'bağlanamadı');
      showError('Sayfa verisi alınamadı (' + err.message + '). Tarayıcı görünümü kapalı olabilir ya da oturum anahtarı geçersiz: Adalmon > Ayarlar > Claude ajanları > "Tarayıcıda aç" ile yeniden açın.');
    }
  })();
})();
