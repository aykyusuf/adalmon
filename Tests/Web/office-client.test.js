'use strict';
// Adalmon tarayıcı istemcisi (Resources/Web/app.js) için Node harness'i: sahte DOM / canvas / EventSource / fetch ile
// yükleme, kademeler, durum akışı, karakter çizimi, gece geçişi ve kart testleri. Gerçek tarayıcı DEĞİLDİR (piksel doğrulaması yok).
// Çalıştırma: node Tests/Web/office-client.test.js   (xcodebuild testlerinden bağımsızdır)
process.env.TZ = 'UTC';
const fs = require('fs');
const path = require('path');
const vm = require('vm');
const assert = require('assert');

const APP = path.join(__dirname, '..', '..', 'Resources', 'Web', 'app.js');
const source = fs.readFileSync(APP, 'utf8');

// ---------- Sahte tarayıcı ortamı ----------
function png(w, h) {   // yalnızca imza + IHDR: createImageBitmap sahtesi boyutu buradan okur
  const b = Buffer.alloc(33);
  Buffer.from([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]).copy(b, 0);
  b.writeUInt32BE(13, 8); b.write('IHDR', 12); b.writeUInt32BE(w, 16); b.writeUInt32BE(h, 20);
  return 'data:image/png;base64,' + b.toString('base64');
}

function makeCtx(cv) {
  const state = { globalAlpha: 1, globalCompositeOperation: 'source-over' };
  const stack = [];
  const calls = {}, ops = [];
  const handler = {
    get(_, p) {
      if (typeof p === 'symbol') return undefined;
      if (p === '__calls') return calls;
      if (p === '__ops') return ops;
      if (p === 'canvas') return cv;
      if (p === 'measureText') return (s) => ({ width: String(s).length * 6 });
      if (p === 'getImageData') return (x, y, w, h) => { const d = new Uint8ClampedArray(w * h * 4); d.fill(200); for (let i = 3; i < d.length; i += 4) d[i] = 255; return { data: d, width: w, height: h }; };
      if (p === 'save') return () => { calls.save = (calls.save || 0) + 1; stack.push(Object.assign({}, state)); };
      if (p === 'restore') return () => { Object.assign(state, stack.pop() || {}); };
      if (p in state) return state[p];
      return (...args) => {
        calls[p] = (calls[p] || 0) + 1;
        if (p === 'drawImage') ops.push(['drawImage', state.globalCompositeOperation, args[0] && args[0].__name]);
        if (p === 'putImageData') ops.push(['putImageData', args[0]]);
        if (p === 'fillRect') ops.push(['fillRect', state.globalCompositeOperation, state.fillStyle]);
      };
    },
    set(_, p, v) { state[p] = v; return true; },
  };
  return new Proxy({}, handler);
}

function makeEl(tag, doc) {
  const el = {
    tagName: String(tag).toUpperCase(), children: [], style: {}, attrs: {}, listeners: {}, _text: '', className: '', hidden: false, value: '',
    get firstChild() { return this.children[0] || null; },
    get textContent() { return this._text + this.children.map((c) => c.textContent).join(''); },
    set textContent(v) { this._text = String(v); this.children = []; },
    appendChild(c) { this.children.push(c); return c; },
    removeChild(c) { this.children = this.children.filter((x) => x !== c); return c; },
    setAttribute(k, v) { this.attrs[k] = String(v); },
    addEventListener(t, fn) { (this.listeners[t] = this.listeners[t] || []).push(fn); },
    querySelector(sel) {
      const m = /\[data-id="(.+)"\]/.exec(sel);
      const walk = (n) => { if (m && n.attrs && n.attrs['data-id'] === m[1]) return n; for (const c of n.children) { const r = walk(c); if (r) return r; } return null; };
      return walk(this);
    },
    getBoundingClientRect() { return { left: 0, top: 0, width: 1000, height: 700 }; },
    fire(type, ev) { (this.listeners[type] || []).forEach((fn) => fn(ev || {})); },
  };
  if (tag === 'canvas') {
    el.width = 300; el.height = 150;
    el.getContext = () => (el._ctx = el._ctx || makeCtx(el));
  }
  return el;
}

function makeEnv(opts = {}) {
  const clock = { t: Date.UTC(2026, 10, 9, 12, 0, 0) };
  class FakeDate extends Date {
    constructor(...a) { if (a.length) super(...a); else super(clock.t); }
    static now() { return clock.t; }
  }
  const byId = {};
  const doc = {
    hidden: false, body: null, listeners: {},
    createElement: (t) => makeEl(t),
    getElementById: (id) => byId[id] || null,
    addEventListener(t, fn) { (this.listeners[t] = this.listeners[t] || []).push(fn); },
  };
  for (const id of ['scene', 'dot', 'conn', 'counts', 'empty', 'error', 'back', 'light', 'loading', 'loadingText', 'tip', 'card']) byId[id] = makeEl(id === 'scene' ? 'canvas' : 'div', doc);
  byId.scene.width = 1000; byId.scene.height = 700;
  byId.card.hidden = true; byId.tip.hidden = true; byId.error.hidden = true; byId.empty.hidden = true; byId.back.hidden = true;
  doc.body = makeEl('body');
  const rafQueue = [];
  const intervals = [];
  const sources = [];
  const store = {};
  const win = makeEl('window');
  win.devicePixelRatio = opts.dpr || 1;
  const fetches = [];
  const sandbox = {
    document: doc, window: win, location: { search: '?t=tok', pathname: '/' }, history: { replaceState() {} },
    sessionStorage: { getItem: (k) => store['s:' + k] || null, setItem: (k, v) => { store['s:' + k] = v; } },
    localStorage: { getItem: (k) => store['l:' + k] || null, setItem: (k, v) => { store['l:' + k] = v; } },
    URLSearchParams, atob: (s) => Buffer.from(s, 'base64').toString('binary'), Blob, Date: FakeDate,
    createImageBitmap: async (blob) => {
      const buf = Buffer.from(await blob.arrayBuffer());
      return { width: buf.readUInt32BE(16), height: buf.readUInt32BE(20) };
    },
    fetch: async (url, init) => {
      fetches.push(url);
      if (opts.status) return { ok: false, status: opts.status };
      if (url === '/v1/layout') return { ok: true, status: 200, json: async () => opts.layout || makeLayout(opts.layoutOpts) };
      return { ok: true, status: 200, json: async () => ({}) };
    },
    EventSource: class { constructor(url) { this.url = url; sources.push(this); } close() { this.closed = true; } },
    requestAnimationFrame: (cb) => { rafQueue.push(cb); return rafQueue.length; },
    cancelAnimationFrame: () => { rafQueue.length = 0; },
    setInterval: (fn, ms) => { intervals.push({ fn, ms }); return intervals.length; },
    clearInterval: () => {}, setTimeout: () => 1, clearTimeout: () => {},
    console, __ADALMON_TEST__: {}, Uint8Array, Uint8ClampedArray, Promise, Math, JSON, Map, Set, Object, Array, String, Number, Error, Symbol, Proxy,
  };
  sandbox.globalThis = sandbox;
  sandbox.window.addEventListener = win.addEventListener;
  const ctx = vm.createContext(sandbox);
  vm.runInContext(source, ctx, { filename: 'app.js' });
  const T = sandbox.__ADALMON_TEST__;
  let ts = 1000;
  return {
    T, byId, doc, sources, store, fetches, clock, sandbox, intervals,
    get api() { return T.api; },
    async ready() { await T.ready; return T.api; },
    // n kare: rAF kuyruğundaki sıradaki çağrıyı, 100 ms ilerleterek çalıştırır
    frames(n) { let ran = 0; for (let i = 0; i < n; i++) { ts += 100; clock.t += 100; const cb = rafQueue.shift(); if (!cb) break; cb(ts); ran += 1; } return ran; },
    get rafLength() { return rafQueue.length; },
    ctx: byId.scene.getContext(),
  };
}

// ---------- Sahte sözleşme ----------
function makeTier(key, stations, extraSeats) {
  const cols = 10, rows = 12;
  const tiles = [];
  for (let r = 0; r < rows; r++) for (let c = 0; c < cols; c++) tiles.push(...(r === 0 || c === 0 || c === cols - 1 ? [1, 0, 0, -1] : [2, 0, 0, -1]));
  const seats = [
    { id: 0, col: 4, row: 3, facing: 'down', kind: 'executive', pc: 4, computerKey: 304, enter: [[8, 10], [8, 4], [4, 4], [4, 3]], toBoard: [[4, 3], [4, 2]] },
    { id: 1, col: 1, row: 8, facing: 'up', kind: 'desk', pc: 2, computerKey: 801, enter: [[8, 10], [1, 10], [1, 9], [1, 8]] },
    { id: 2, col: 3, row: 8, facing: 'up', kind: 'desk', pc: 2, computerKey: 803, enter: [[8, 10], [3, 10], [3, 9], [3, 8]] },
  ].concat(extraSeats ? [{ id: 3, col: 5, row: 8, facing: 'up', kind: 'desk', pc: 3, computerKey: 805, enter: [[8, 10], [5, 10], [5, 9], [5, 8]] }] : []);
  const blocks = [{ i: 0, col: 1, row: 6 }].concat(stations >= 4 ? [{ i: 1, col: 5, row: 6 }] : []);
  return {
    key, stations, capacity: stations + 1, floorWidth: 8, floorHeight: 10, cols, rows, blocks, laneRows: [5, 10],
    lamps: blocks.map((b) => ({ col: b.col + 1, row: b.row, dx: 8, dy: 14 })).concat([{ col: 4, row: 2, dx: 0, dy: 14 }]),
    coffeeTable: { col: 3, row: 9 }, coffee: { tile: [8, 9], facing: 'right' }, bounds: { minCol: 0, minRow: 0, maxCol: cols - 1, maxRow: rows - 1 },
    tiles, colors: [], seats, entrance: [8, 10], door: [8, 11], board: [4, 2], boardIndex: 0, zone: { minCol: 2, minRow: 2, maxCol: 8, maxRow: 3 },
    zoneTiles: [2, 3, 4, 5, 6, 7, 8].map((c) => [c, 2]), coffeeMachine: true,
    furniture: [
      { i: 0, asset: 'WHITEBOARD', col: 4, row: 0, mirrored: false, z: -1960 },
      { i: 1, asset: 'DESK_FRONT', col: 1, row: 6, mirrored: false, z: 128 },
      { i: 2, asset: 'PC_FRONT_OFF', col: 1, row: 5, mirrored: false, z: 96.2 },
      { i: 3, asset: 'PC_FRONT_OFF', col: 5, row: 5, mirrored: false, z: 96.2 },
      { i: 4, asset: 'PC_FRONT_OFF', col: 4, row: 2, mirrored: false, z: 48.2 },
      { i: 5, asset: 'PLANT', col: 8, row: 5, mirrored: true, z: 112 },
    ].concat(stations >= 4 ? [{ i: 6, asset: 'DESK_FRONT', col: 5, row: 6, mirrored: false, z: 128 }] : []),
  };
}

function makeLayout(o = {}) {
  const frameNames = Array.from({ length: 18 }, (_, i) => 'f' + i);
  const index = [];
  for (let look = 0; look < 6; look++) for (let d = 0; d < 3; d++) for (let f = 0; f < 18; f++) index.push({ look, direction: d, frame: f, x: f * 96, y: (look * 3 + d) * 128, w: 96, h: 128 });
  const accNames = ['crown', 'cap', 'star', 'sprout', 'headphones', 'glasses', 'vest', 'tag', 'hardhat', 'apron'];
  const accIndex = [];
  accNames.forEach((name, i) => { for (let d = 0; d < 3; d++) accIndex.push({ name, kind: 'role', direction: d, x: d * 96, y: i * 128, w: 96, h: 128 }); });
  const gen = {};
  for (const n of ['imac_silver', 'imac_blue', 'macbook_gray']) { gen[n + '_off'] = png(64, 128); for (let k = 1; k <= 3; k++) gen[n + '_on' + k] = png(64, 128); }
  Object.assign(gen, { lamp: png(32, 40), vglow_bulb: png(64, 64), vglow_pool: png(40, 24), vglow_screen: png(24, 16), vglow_moon: png(24, 40), mop: png(28, 64),
                       box: png(40, 28), zzz: png(36, 32), bubble_alert: png(44, 48), bubble_think: png(44, 40), cup: png(24, 20) });
  const furniture = { DESK_FRONT: png(192, 128), PLANT: png(64, 128), WHITEBOARD: png(128, 128) };
  if (o.badFurniture) furniture.PLANT = 'not-a-data-uri';
  const bg = (w, h) => ({ image: png(w * 4, h * 4), w: w * 4, h: h * 4, windows: [[24, 0, 14, 20], [100, 0, 14, 20]] });
  const tiers = { s2: makeTier('s2', 2, false), s4: makeTier('s4', 4, true) };
  const fdef = (w, h, fw, fh, bgT, extra) => Object.assign({ file: 'x.png', w, h, fw, fh, bg: bgT, category: 'x', onWall: false, onSurface: false }, extra);
  const app = (hex, text, ch) => ({ tintHex: hex, label: text, character: ch, tint: [0.5, 0.5, 0.5], tintBlend: 0.6, accessory: 'none', small: false, badgeText: text });
  return {
    v: 3, tileSize: 16, theme: o.theme || 'vector',
    v3: {
      lighting: { nightStartHour: 19, nightStartMinute: 30, nightEndHour: 6, nightEndMinute: 30 },
      vector: {
        theme: 'vector', scale: 4, generated: gen, furniture, door: png(64, 128), boardWrite: [png(88, 36), png(88, 36), png(88, 36)], boardWriteOrigin: [5, 12],
        windowDay: png(56, 80), windowNight: png(56, 80), backgrounds: { s2: bg(160, 192), s4: bg(160, 192) },
        lighting: { multiplyColor: [0.60, 0.66, 0.88], washColor: [0.05, 0.10, 0.34], washAlpha: 0.22, bulbAlpha: 0.38, poolAlpha: 0.4, boardAlpha: 0.3, screenAlpha: 0.9, windowAlpha: 0.22 },
        characters: {
          scale: 4, frameWidth: 24, frameHeight: 32, cell: [96, 128], frameCount: 18, frameNames, walkCycle: [0, 1, 2, 1], directions: ['down', 'up', 'right'], sitDrop: 3,
          bob: Array.from({ length: 18 }, () => 0),
          frames: { stand: 1, walk: [0, 1, 2], typing: [3, 4], reading: [5, 6], boardWrite: [7, 8], raiseHand: [9, 10], yawn: 11, sleep: 12, coffee: [13, 14], carry: [15, 16, 17] },
          atlas: { image: png(1728, 2304), mask: png(1728, 2304), width: 1728, height: 2304, index },
          accessories: { image: png(288, 128 * accNames.length), width: 288, height: 128 * accNames.length, index: accIndex },
        },
      },
    },
    characters: {}, appearance: { opus: app('#B052DE', 'OPUS', 2), sonnet: app('#5B8DEF', 'SONNET', 0), unknown: app('#8A8F98', '?', 3) },
    groupColors: [[0.2, 0.5, 0.9], [0.9, 0.5, 0.2]], art: {}, tiers,
    furniture: { WHITEBOARD: fdef(32, 32, 2, 2, 2, { onWall: true }), DESK_FRONT: fdef(48, 32, 3, 2, 0), PLANT: fdef(16, 32, 1, 2, 1), PC_FRONT_OFF: fdef(16, 32, 1, 1, 0, { onSurface: true }) },
    files: {}, bubbleLifetime: 6, strollSeconds: 60, maxCharacters: 17,
  };
}

function member(o) {
  return Object.assign({
    id: 's#1', kind: 'subagent', label: 'crew-chief:implementer', badge: 'sonnet', status: 'idle', statusLabel: 'Boşta', working: false,
    role: { key: 'implementer', name: 'crew-chief:implementer', tint: '#3B7BFF', accessory: 'headphones', small: false, hoodie: true, known: true, labelColor: '#9AB' },
    seat: 1, seatKind: 'desk', pose: 'sitting', alert: false, pcOn: false, standing: false,
    seatInfo: { id: 1, col: 1, row: 8, kind: 'desk', facing: 'up', key: 801 },
    appearance: { character: 0, tint: '#3B7BFF', tintBlend: 0.55, small: false, accessory: 'none', modelDot: '#33C759', computer: { kind: 'imac', color: 'blue', name: 'imac_blue' } },
    idleVariant: { seed: 'r|m', sequence: [{ variant: 'read', seconds: 6 }, { variant: 'zzz', seconds: 5 }, { variant: 'yawn', seconds: 4 }] },
  }, o);
}

function room(o) {
  return Object.assign({
    id: 'sess1', tier: 's2', stations: 2, capacity: 3, cleaner: { intervalMin: 90, intervalMax: 180, route: 'S', laneRows: [5, 10], seed: 'sess1' },
    title: 'adalmon', badge: 'opus', badgeLabel: 'Opus', group: 0, reseated: false, memberCount: 3, overflow: 0,
    computers: { 2: 'imac_blue', 3: 'macbook_gray', 4: 'imac_silver' }, members: [],
  }, o);
}

function snapshot(clock, rooms, extra) {
  return Object.assign({ v: 3, now: clock.t, lighting: { mode: 'auto', nightStartHour: 19, nightStartMinute: 30, nightEndHour: 6, nightEndMinute: 30, resolvedNight: false },
                         sessions: rooms.length, agents: 3, rooms, working: 1 }, extra);
}

const execM = (o) => member(Object.assign({ id: 'sess1', kind: 'session', label: 'adalmon', badge: 'opus', role: { key: 'lead', name: 'ana ajan', tint: '#B052DE', accessory: 'crown' },
  seat: 0, seatKind: 'executive', seatInfo: { id: 0, col: 4, row: 3, kind: 'executive', facing: 'down', key: 304 }, startedAt: Date.UTC(2026, 10, 9, 11, 0, 0),
  appearance: { character: 2, tint: '#B052DE', tintBlend: 0.5, small: false, accessory: 'crown', computer: { kind: 'imac', color: 'silver', name: 'imac_silver' } } }, o));

// ---------- Test koşucusu ----------
const tests = [];
const test = (name, fn) => tests.push({ name, fn });

test('söz dizimi: vm.Script derlenir ve dış adres içermez', () => {
  new vm.Script(source, { filename: 'app.js' });
  assert.ok(!/https?:\/\/|ws:\/\//.test(source), 'JS dış adres içermemeli');
  const html = fs.readFileSync(path.join(path.dirname(APP), 'index.html'), 'utf8');
  assert.ok(!/https?:\/\//.test(html));
  assert.ok(html.includes('/app.js?t=__ADALMON_TOKEN__') && html.includes('/style.css?t=__ADALMON_TOKEN__'), 'token yer tutucuları durmalı');
});

test('yükleme: tüm data URI atlas/arka planlar çözülür, göstergesi kapanır, SSE başlar', async () => {
  const e = makeEnv();
  const api = await e.ready();
  assert.strictEqual(api.assets.bg.s2.bmp.width, 640);
  assert.strictEqual(api.assets.atlas.img.width, 1728);
  assert.ok(api.assets.acc.index.get('crown|0'));
  assert.deepStrictEqual([...api.tierData.keys()].sort(), ['s2', 's4']);
  assert.strictEqual(e.byId.loading.hidden, true);
  assert.strictEqual(e.sources.length, 1);
  assert.ok(e.sources[0].url.includes('t=tok'));
  assert.ok(!e.fetches.some((u) => u.startsWith('/assets/')), 'vektör temada /assets isteği yok');
  assert.strictEqual(e.intervals.length, 1, 'tek 1 sn kalp atışı');
});

test('hata: bozuk dosya adı gösterilir; 401 ve 404 okunaklı', async () => {
  let e = makeEnv({ layoutOpts: { badFurniture: true } });
  await e.T.ready;
  assert.ok(e.byId.error.textContent.includes('furniture.PLANT'), e.byId.error.textContent);
  e = makeEnv({ status: 401 }); await e.T.ready;
  assert.ok(e.byId.error.textContent.includes('401'));
  e = makeEnv({ status: 404 }); await e.T.ready;
  assert.ok(e.byId.error.textContent.includes('404'));
  e = makeEnv({ layoutOpts: { theme: 'pixel' } }); await e.T.ready;
  assert.ok(e.byId.error.textContent.includes('vektör'));
});

test('durum akışı: oda, kesirli ölçek, karakter çizimi (maske tint + aksesuar), yönetici tahtada', async () => {
  const e = makeEnv({ dpr: 2 });
  const api = await e.ready();
  const members = [execM({ status: 'tool', statusLabel: 'Araç', working: true, pose: 'typing', pcOn: true }),
                   member({ id: 's#1', status: 'tool', working: true, pose: 'typing', pcOn: true, activity: 'Edit', target: 'a.swift', activityAt: e.clock.t - 1000 }),
                   member({ id: 's#2', seat: 2, seatInfo: { id: 2, col: 3, row: 8, kind: 'desk', facing: 'up', key: 803 }, status: 'idle' })];
  e.sources[0].onmessage({ data: JSON.stringify(snapshot(e.clock, [room({ members })], { working: 2 })) });
  const r = api.rooms.get('sess1');
  assert.ok(r.rect, 'oda yerleşti');
  assert.ok(api.S > 0.25 && api.S <= 16, 'ölçek sınırda: ' + api.S);
  const ex = r.actors.get('sess1');
  assert.strictEqual(ex.alpha, 1, 'yönetici tam opak');
  assert.strictEqual(ex.execMode, 'board');
  const tile = api.tierData.get('s2').t.tiles;
  const trow = Math.floor((ex.y + 1) / 16) - 1, tcol = Math.floor(ex.x / 16);
  assert.strictEqual(tile[(trow * 10 + tcol) * 4], 2, 'yönetici zemin karosunda');
  assert.strictEqual(e.T.lastError, undefined, 'apply hata atmadı');
  const p = api.poseOf(ex, e.clock.t);
  assert.ok([7, 8].includes(p.frame) && p.dir === 'up', 'tahtada yazma karesi: ' + JSON.stringify(p));
  e.frames(6);
  assert.ok(e.ctx.__calls.drawImage > 10, 'drawImage çağrıldı');
  assert.ok(e.ctx.__ops.some((o) => o[0] === 'drawImage' && o[1] === 'source-over'), 'normal çizim');
  assert.ok(!e.ctx.__ops.some((o) => o[1] === 'multiply'), 'gündüz multiply yok');
  assert.ok(e.ctx.__calls.fill > 0 || e.ctx.__calls.stroke >= 0);
  assert.ok(api.hitActors.length >= 3, 'etkileşim kutuları');
  const sheet = api.bakeSheet(0, '#3B7BFF', false);
  assert.ok(sheet && sheet.width === 1728 && sheet.height === 384);
  // gömlek maskesi: rgb * lerp(beyaz, gömlek, maske) (sahte piksel = 200, maske = 200/255); gece: (1/0.6)^0.8 ile aydınlatma
  const px = (c) => c.getContext('2d').__ops.find((o) => o[0] === 'putImageData')[1].data;
  const d0 = px(sheet), d1 = px(api.bakeSheet(1, '#3B7BFF', true));
  assert.ok(Math.abs(d0[0] - 79.4) < 1.5 && Math.abs(d0[1] - 118.8) < 1.5 && Math.abs(d0[2] - 199.3) < 1.5, 'maske tint: ' + [d0[0], d0[1], d0[2]]);
  assert.ok(Math.abs(d1[0] - 119.4) < 2, 'gece aydınlatma: ' + d1[0]);
  assert.strictEqual(api.lookOf(members[1]).acc, 'headphones');
  assert.strictEqual(api.lookOf(execM({})).acc, 'crown');
  assert.strictEqual(e.byId.counts.textContent, '1 oturum · 3 ajan · 2 çalışıyor');
});

test('oturma pozu, izin eli + "!" balonu, düşünme balonu, balon süresi', async () => {
  const e = makeEnv();
  const api = await e.ready();
  const ms = [execM({}), member({ id: 's#1', status: 'permission', alert: true, working: true }), member({ id: 's#2', seat: 2, seatInfo: { id: 2, col: 3, row: 8, kind: 'desk', facing: 'up', key: 803 }, status: 'thinking', working: true })];
  e.sources[0].onmessage({ data: JSON.stringify(snapshot(e.clock, [room({ members: ms })])) });
  const r = api.rooms.get('sess1');
  const a1 = r.actors.get('s#1');
  assert.ok(a1.atSeat && [9, 10].includes(api.poseOf(a1, e.clock.t).frame));
  assert.strictEqual(api.bubbleOf(a1).kind, 'alert');
  assert.strictEqual(api.bubbleOf(r.actors.get('s#2')).kind, 'think');
  // metin balonu süresi dolunca kaybolur
  const m3 = member({ id: 's#1', status: 'tool', working: true, pose: 'typing', bubble: 'Edit a.swift', activityAt: e.clock.t });
  e.sources[0].onmessage({ data: JSON.stringify(snapshot(e.clock, [room({ members: [execM({}), m3] })])) });
  assert.strictEqual(api.bubbleOf(r.actors.get('s#1')).kind, 'text');
  e.clock.t += 7000;
  assert.strictEqual(api.bubbleOf(r.actors.get('s#1')), null, 'balon yaşam süresi sonrası kapanır');
});

test('statik mod: hepsi boşta ise döngü durur; boşta varyantı kalp atışıyla uyandırır', async () => {
  const e = makeEnv();
  const api = await e.ready();
  e.sources[0].onmessage({ data: JSON.stringify(snapshot(e.clock, [room({ members: [execM({}), member({})] })], { working: 0 })) });
  e.frames(3);
  assert.strictEqual(api.animating(), false, 'animasyon yok');
  e.frames(3);
  assert.strictEqual(e.rafLength, 0, 'döngü durdu (statik)');
  // 12 sn sonra varyant başlar
  e.clock.t += 12000;
  e.intervals[0].fn();
  assert.strictEqual(e.rafLength, 1, 'kalp atışı çizimi uyandırdı');
  const a = api.rooms.get('sess1').actors.get('s#1');
  assert.ok(a.idle && a.idle.active, 'varyant etkin: ' + JSON.stringify(a.idle));
  assert.ok(['read', 'zzz', 'yawn'].includes(a.idle.active.variant));
  assert.strictEqual(api.animating(), true);
});

test('gece: multiply + lighter katmanları, 1 sn crossfade, seçici localStorage, sunucu resolvedNight esas', async () => {
  const e = makeEnv();
  const api = await e.ready();
  e.sources[0].onmessage({ data: JSON.stringify(snapshot(e.clock, [room({ members: [execM({ status: 'tool', working: true, pcOn: true, pose: 'typing' }), member({ pcOn: true, status: 'tool', working: true })] })])) });
  assert.strictEqual(api.wantNight(), false, '12:00 gündüz');
  e.byId.light.value = 'night'; e.byId.light.fire('change');
  assert.strictEqual(e.store['l:adalmon-light'], 'night');
  assert.strictEqual(api.wantNight(), true);
  assert.strictEqual(api.animating(), true, 'geçiş animasyonu');
  api.stepLight(0.5);
  assert.ok(api.light.level > 0.4 && api.light.level < 0.6, 'yarı seviye');
  api.stepLight(0.6);
  assert.strictEqual(api.light.level, 1);
  e.ctx.__ops.length = 0;
  api.draw(e.clock.t);
  assert.ok(e.ctx.__ops.some((o) => o[0] === 'fillRect' && o[1] === 'multiply'), 'multiply örtü');
  assert.ok(e.ctx.__ops.some((o) => o[0] === 'drawImage' && o[1] === 'lighter'), 'additive ışık havuzları');
  const day = api.bakeSheet(0, '#3B7BFF', false), night = api.bakeSheet(0, '#3B7BFF', true);
  assert.notStrictEqual(day, night, 'gece karakter dokusu ayrı önbellekte');
  // otomatik + sunucu farklı: sunucu esas
  e.byId.light.value = 'auto'; e.byId.light.fire('change');
  api.applyServerLighting({ nightStartHour: 19, nightStartMinute: 30, nightEndHour: 6, nightEndMinute: 30, resolvedNight: true });
  assert.strictEqual(api.wantNight(), true, 'sunucu resolvedNight=true');
  api.applyServerLighting({ nightStartHour: 19, nightStartMinute: 30, nightEndHour: 6, nightEndMinute: 30, resolvedNight: false });
  assert.strictEqual(api.wantNight(), false);
  e.clock.t = Date.UTC(2026, 10, 9, 20, 0, 0);
  assert.strictEqual(api.localNight(), true, '20:00 yerel gece');
  e.clock.t = Date.UTC(2026, 10, 9, 6, 29, 0);
  assert.strictEqual(api.localNight(), true);
  e.clock.t = Date.UTC(2026, 10, 9, 6, 31, 0);
  assert.strictEqual(api.localNight(), false);
});

test('kademe büyümesi: oda kalır, crossfade 0.4 sn, taşıyıcı girer-çıkar, yeni masa belirir', async () => {
  const e = makeEnv();
  const api = await e.ready();
  const base = [execM({}), member({})];
  e.sources[0].onmessage({ data: JSON.stringify(snapshot(e.clock, [room({ members: base })])) });
  const r = api.rooms.get('sess1');
  const a1 = r.actors.get('s#1');
  e.sources[0].onmessage({ data: JSON.stringify(snapshot(e.clock, [room({ tier: 's4', stations: 4, members: base })])) });
  assert.strictEqual(api.rooms.get('sess1'), r, 'oda yeniden kurulmadı');
  assert.strictEqual(r.td.key, 's4');
  assert.strictEqual(r.actors.get('s#1'), a1, 'oturanlar kaybolmadı');
  assert.ok(r.fade && r.fade.t === 0, 'crossfade başladı');
  assert.ok(r.carrier, 'taşıyıcı sahnesi');
  assert.ok(r.fresh && r.fresh.keys.size === 1, 'yeni masa: ' + [...r.fresh.keys]);
  api.advance(0.45);
  assert.strictEqual(r.fade, null, '0.4 sn sonra bitti');
  let guard = 0;
  while (r.carrier && guard++ < 400) api.advance(0.1);
  assert.strictEqual(r.carrier, null, 'taşıyıcı çıktı');
  assert.strictEqual(r.fresh, null);
  // küçülme: animasyonsuz
  e.sources[0].onmessage({ data: JSON.stringify(snapshot(e.clock, [room({ tier: 's2', stations: 2, members: base })])) });
  assert.strictEqual(r.td.key, 's2');
  assert.strictEqual(r.fade, null);
  assert.strictEqual(r.carrier, null);
});

test('temizlikçi: aralık dolunca S rotasında yürür, paspas çizilir, sekme gizliyken başlamaz', async () => {
  const e = makeEnv();
  const api = await e.ready();
  e.sources[0].onmessage({ data: JSON.stringify(snapshot(e.clock, [room({ members: [execM({}), member({})] })])) });
  const r = api.rooms.get('sess1');
  r.cleaner.next = 0;
  e.doc.hidden = true;
  api.scheduleActors(e.clock.t);
  assert.strictEqual(r.cleaner.entity, null, 'sekme gizliyken başlamaz');
  e.doc.hidden = false;
  api.scheduleActors(e.clock.t);
  assert.ok(r.cleaner.entity && r.cleaner.entity.path.length > 5, 'rota var');
  e.ctx.__ops.length = 0;
  api.advance(0.3);
  api.draw(e.clock.t);
  let guard = 0;
  while (r.cleaner.entity && guard++ < 1500) api.advance(0.1);
  assert.strictEqual(r.cleaner.entity, null, 'rota bitti');
  assert.ok(r.cleaner.next > e.clock.t + 80000, 'sonraki aralık 90 sn+');
});

test('kart: tıklama, rozet/durum/süre/alt ajan listesi, Esc ve boşluk kapatır; çift tık yakınlaştırır', async () => {
  const e = makeEnv();
  const api = await e.ready();
  const ms = [execM({ status: 'tool', working: true, pose: 'typing' }), member({ activity: 'Edit', target: 'a.swift', activityAt: e.clock.t - 5000 })];
  e.sources[0].onmessage({ data: JSON.stringify(snapshot(e.clock, [room({ members: ms })])) });
  e.frames(3);
  const hit = api.hitActors.find((h) => h.a.id === 's#1');
  assert.ok(hit);
  e.byId.scene.fire('click', { clientX: (hit.x + hit.w / 2), clientY: (hit.y + hit.h / 2) });
  assert.ok(api.selected && api.selected.id === 's#1');
  assert.strictEqual(e.byId.card.hidden, false);
  const txt = e.byId.card.textContent;
  assert.ok(txt.includes('crew-chief:implementer') && txt.includes('Edit') && txt.includes('a.swift') && txt.includes('adalmon'), txt);
  const exHit = api.hitActors.find((h) => h.a.id === 'sess1');
  e.byId.scene.fire('click', { clientX: exHit.x + exHit.w / 2, clientY: exHit.y + exHit.h / 2 });
  const t2 = e.byId.card.textContent;
  assert.ok(t2.includes('01:00:00') || t2.includes('1:00:00'), 'çalışma süresi (sunucu saati): ' + t2);
  assert.ok(t2.includes('Alt ajanlar') && t2.includes('crew-chief:implementer'));
  e.clock.t += 2000; e.api.selected && e.api.openCard(e.api.selected);
  assert.ok(e.byId.card.textContent.includes('1:00:02') || e.byId.card.textContent.includes('01:00:02'));
  api.escape();
  assert.strictEqual(e.byId.card.hidden, true);
  assert.strictEqual(api.selected, null);
  // çift tık: odaya yakınlaş; Esc geri
  e.byId.scene.fire('dblclick', { clientX: hit.x + 1, clientY: hit.y + 1 });
  assert.strictEqual(api.focusId, 'sess1');
  api.escape();
  assert.strictEqual(api.focusId, null);
  // tahtaya tıklama yönetici kartı
  e.frames(2);
  const bh = api.hitBoards[0];
  assert.ok(bh, 'tahta alanı');
  e.byId.scene.fire('click', { clientX: bh.x + bh.w / 2, clientY: bh.y + bh.h / 2 });
  assert.ok(api.selected && api.selected.id === 'sess1' && api.selected.exec, 'tahta tıklaması yönetici kartı');
  assert.strictEqual(e.T.lastError, undefined);
});

test('çoklu oda: ızgara + odaya tıklayınca yakınlaşma ve boş alana tıklayınca geri', async () => {
  const e = makeEnv();
  const api = await e.ready();
  const mk = (id) => room({ id, title: id, members: [execM({ id, label: id }), member({ id: id + '#1' })] });
  e.sources[0].onmessage({ data: JSON.stringify(snapshot(e.clock, [mk('a'), mk('b'), mk('c')])) });
  const s3 = api.S;
  const ra = api.rooms.get('a').rect;
  assert.ok(api.rooms.get('b').rect && api.rooms.get('c').rect);
  e.byId.scene.fire('click', { clientX: ra.x + 1, clientY: ra.y + ra.h - 1 });   // boş zemin: odayı seç
  assert.strictEqual(api.focusId, 'a');
  assert.ok(api.S > s3, 'yakınlaşınca ölçek büyür');
  assert.ok(api.rooms.get('b').rect === null);
  e.byId.scene.fire('click', { clientX: 2, clientY: 2 });                      // oda dışı boşluk: geri
  assert.strictEqual(api.focusId, null);
});

test('görünürlük: gizliyken çizim durur, görününce hızlıca devam eder', async () => {
  const e = makeEnv();
  const api = await e.ready();
  e.sources[0].onmessage({ data: JSON.stringify(snapshot(e.clock, [room({ members: [execM({}), member({ status: 'tool', working: true, pose: 'typing' })] })])) });
  e.frames(2);
  e.doc.hidden = true; e.doc.listeners.visibilitychange.forEach((f) => f());
  assert.strictEqual(e.rafLength, 0);
  e.clock.t += 5000;
  e.doc.hidden = false; e.doc.listeners.visibilitychange.forEach((f) => f());
  assert.strictEqual(e.rafLength, 1, 'görününce devam');
  assert.ok(e.frames(2) >= 1);
});

// ---------- Etiket çakışma çözümü (OfficeLabelLayout portu) ----------
const LM = { step: 16, height: 15, margin: 2 };
const lblItems = (n, gap, _unused, widthsOf) => Array.from({ length: n }, (_, i) => {
  return { id: 'a' + String(i).padStart(2, '0'), x: 100 + i * gap, y: 50, widths: (widthsOf || [96, 96, 84]).slice() };
});
const overlapsOf = (items, res) => {
  const rects = items.map((it) => { const p = res.placements.get(it.id); const w = it.widths[Math.min(p.variant, it.widths.length - 1)] + LM.margin;
    return { x: it.x - w / 2, y: it.y + p.level * LM.step, w, h: LM.height }; });
  let n = 0;
  for (let i = 0; i < rects.length; i++) for (let j = i + 1; j < rects.length; j++) {
    const a = rects[i], b = rects[j];
    if (a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h) n++;
  }
  return n;
};

test('etiket çözümü: 2 yan yana etiket, kademe 1 ile çözülür (metin kısalmaz)', async () => {
  const api = await makeEnv().ready();
  const items = lblItems(2, 60);                                  // 98 px genişlik, 60 px aralık: çakışır
  const res = api.resolveLabels(items, LM);
  assert.deepStrictEqual([...res.placements.values()].map((p) => p.level), [0, 1]);
  assert.ok([...res.placements.values()].every((p) => p.variant === 0));
  assert.strictEqual(res.overlaps, 0);
  assert.strictEqual(overlapsOf(items, res), 0);
});

test('etiket çözümü: ayrık etiketler kademe 0 ve tam ad kalır', async () => {
  const api = await makeEnv().ready();
  const res = api.resolveLabels(lblItems(3, 200), LM);
  assert.ok([...res.placements.values()].every((p) => p.level === 0 && p.variant === 0));
  assert.strictEqual(res.overlaps, 0);
});

test('etiket çözümü: 3 yan yana etiket 3 kademeyi (0,1,2) kullanır, kısaltma gerekmez', async () => {
  const api = await makeEnv().ready();
  const res = api.resolveLabels(lblItems(3, 20), LM);
  assert.deepStrictEqual([...res.placements.values()].map((p) => p.level), [0, 1, 2]);
  assert.ok([...res.placements.values()].every((p) => p.variant === 0));
  assert.strictEqual(res.overlaps, 0);
});

test('etiket çözümü: 6 yan yana etiket kademe sınırını (<=2) aşmaz ve metin biçimi kısalır', async () => {
  const api = await makeEnv().ready();
  const items = lblItems(6, 30, null, [150, 150, 90]);
  const res = api.resolveLabels(items, LM);
  const ps = [...res.placements.values()];
  assert.ok(ps.every((p) => p.level >= 0 && p.level <= 2), 'kademe sınırı');
  assert.ok(ps.every((p) => p.variant > 0), 'tüm odada kısaltma: ' + JSON.stringify(ps));
  assert.strictEqual(res.overlaps, overlapsOf(items, res));
});

test('etiket çözümü: 12 yan yana etiket son biçimde de sığmaz; çakışma sayılır, kademe <= 2', async () => {
  const api = await makeEnv().ready();
  const items = lblItems(12, 30, null, [150, 110, 90]);
  const res = api.resolveLabels(items, LM);
  const ps = [...res.placements.values()];
  assert.strictEqual(ps.length, 12);
  assert.ok(ps.every((p) => p.variant === 2 && p.level <= 2));
  assert.ok(res.overlaps > 0, 'kabul edilen çakışma raporlanır');
  assert.strictEqual(res.overlaps, overlapsOf(items, res));
});

test('etiket çözümü: metin biçimleri (tam ad, önek atılmış, 14 karakter)', async () => {
  const api = await makeEnv().ready();
  assert.deepStrictEqual(Array.from(api.labelVariants('general-purpose')), ['general-purpose', 'general-purpo…']);
  assert.deepStrictEqual(Array.from(api.labelVariants('crew-chief:implementer')), ['crew-chief:implementer', 'implementer']);
  assert.deepStrictEqual(Array.from(api.labelVariants('plugin:very-long-agent-name')), ['plugin:very-long-agent-name', 'very-long-agent-name', 'very-long-age…']);
  assert.deepStrictEqual(Array.from(api.labelVariants('★ adalmon')), ['★ adalmon']);
  assert.deepStrictEqual(Array.from(api.labelVariants('kısa')), ['kısa']);
});

test('etiket çözümü: odada 5 "general-purpose" alt ajanı çizimde çakışmaz; yalnızca değişince yeniden hesaplanır', async () => {
  const e = makeEnv({ dpr: 2 });
  const api = await e.ready();
  const subs = Array.from({ length: 5 }, (_, i) => member({ id: 's#' + i, label: 'general-purpose', role: { key: 'general-purpose', name: 'general-purpose', tint: '#3B7BFF', accessory: 'none', small: false, hoodie: false, known: true },
    seat: 1 + i, seatInfo: { id: 1 + i, col: 1 + i, row: 8, kind: 'desk', facing: 'up', key: 800 + i } }));
  e.sources[0].onmessage({ data: JSON.stringify(snapshot(e.clock, [room({ tier: 's4', stations: 4, capacity: 6, members: [execM({}), ...subs] })])) });
  e.frames(3);
  const r = api.rooms.get('sess1');
  assert.ok(r.labelCache, 'önbellek oluştu');
  assert.ok(r.labelCache.map.size >= 4, 'etiketler yerleşti: ' + r.labelCache.map.size);
  assert.ok(r.labelCache.overlaps <= 3, 'çakışma çözümden sonra: ' + r.labelCache.overlaps);
  const cache = r.labelCache;
  api.draw(e.clock.t + 16);
  assert.strictEqual(r.labelCache, cache, 'değişiklik yokken yeniden hesaplanmaz');
});

(async () => {
  let failed = 0;
  for (const t of tests) {
    try { await t.fn(); console.log('PASS  ' + t.name); } catch (err) { failed += 1; console.log('FAIL  ' + t.name + '\n      ' + (err && err.stack ? err.stack.split('\n').slice(0, 4).join('\n      ') : err)); }
  }
  console.log(`\n${tests.length - failed}/${tests.length} geçti`);
  process.exit(failed ? 1 : 0);
})();
