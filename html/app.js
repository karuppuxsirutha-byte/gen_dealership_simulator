'use strict';

/* ==========================================================================
   Utilities
   ========================================================================== */
const RES = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'gen_dealership';
const $ = (s, r = document) => r.querySelector(s);
const $$ = (s, r = document) => [...r.querySelectorAll(s)];

async function post(name, data = {}) {
  try {
    const res = await fetch(`https://${RES}/${name}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json; charset=UTF-8' },
      body: JSON.stringify(data),
    });
    const text = await res.text();
    return text ? JSON.parse(text) : null;
  } catch (e) {
    return null;
  }
}

const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const clone = (o) => JSON.parse(JSON.stringify(o ?? null));
const arr = (x) => (Array.isArray(x) ? x : x && typeof x === 'object' ? Object.values(x) : []);

let moneyFmt = new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD', maximumFractionDigits: 0 });
function setCurrency(code) {
  try { moneyFmt = new Intl.NumberFormat('en-US', { style: 'currency', currency: code || 'USD', maximumFractionDigits: 0 }); } catch (e) { /* keep USD */ }
}
const fmtMoney = (n) => (n == null ? '—' : moneyFmt.format(n));
const fmtCoords = (c) => (c ? `${(+c.x).toFixed(2)}, ${(+c.y).toFixed(2)}, ${(+c.z).toFixed(2)}  ·  ${Math.round(c.w)}°` : null);
const imgUrl = (model) => `https://docs.fivem.net/vehicles/${encodeURIComponent(model)}.webp`;
const thumb = (model) => `<img src="${imgUrl(model)}" alt="" onerror="this.replaceWith(Object.assign(document.createElement('span'),{className:'ph',textContent:'🚗'}))">`;

function toast(msg, type = 'info') {
  const el = document.createElement('div');
  el.className = `toast ${type}`;
  el.textContent = msg;
  $('#toasts').appendChild(el);
  setTimeout(() => el.classList.add('out'), 3200);
  setTimeout(() => el.remove(), 3600);
}

let modalResolve = null;
function askConfirm(title, text, okLabel = 'Confirm', danger = false, html = null) {
  $('#m-title').textContent = title;
  if (html) $('#m-text').innerHTML = html;
  else $('#m-text').textContent = text;
  const ok = $('#m-ok');
  ok.textContent = okLabel;
  ok.className = `btn ${danger ? 'danger' : 'primary'}`;
  $('#modal').classList.remove('hidden');
  return new Promise((resolve) => { modalResolve = resolve; });
}
function closeModal(value) {
  $('#modal').classList.add('hidden');
  if (modalResolve) { const r = modalResolve; modalResolve = null; r(value); }
}
$('#m-ok').addEventListener('click', () => closeModal(true));
$('#m-cancel').addEventListener('click', () => closeModal(false));

/* ==========================================================================
   Theme (Config.UI)
   ========================================================================== */
const UI = { accent: '#3d8bff', speedUnit: 'kmh' };

function shade(hex, amount) {
  const n = parseInt(hex.slice(1), 16);
  const c = (v) => Math.max(0, Math.min(255, Math.round(v + 255 * amount)));
  return `rgb(${c(n >> 16)}, ${c((n >> 8) & 255)}, ${c(n & 255)})`;
}

function applyTheme(ui) {
  Object.assign(UI, ui || {});
  if (!/^#[0-9a-f]{6}$/i.test(UI.accent)) return;
  const n = parseInt(UI.accent.slice(1), 16);
  const root = document.documentElement.style;
  root.setProperty('--accent', UI.accent);
  root.setProperty('--accent-2', shade(UI.accent, -0.12));
  root.setProperty('--accent-rgb', `${n >> 16}, ${(n >> 8) & 255}, ${n & 255}`);
}

post('nuiReady').then(applyTheme);

/* ==========================================================================
   State
   ========================================================================== */
const S = {
  categories: [],
  catLabel: {},
  defaults: { blip: { enabled: true, sprite: 326, color: 3, scale: 0.8 }, previewModel: 'adder' },
  limits: { maxDisplays: 30, maxVehicles: 250 },
  creator: { open: false, list: [], current: null, dirty: false, tab: 'general', filter: '' },
  shop: null,
  features: {},
};

function setCategories(list) {
  S.categories = arr(list);
  S.catLabel = Object.fromEntries(S.categories.map((c) => [c.id, c.label]));
}
const catOptions = (selected) => S.categories.map((c) => `<option value="${esc(c.id)}" ${c.id === selected ? 'selected' : ''}>${esc(c.label)}</option>`).join('');

function normalizeDealership(d) {
  d = clone(d);
  d.vehicles = arr(d.vehicles);
  d.displays = arr(d.displays);
  d.job = d.job || '';
  d.blip = Object.assign({}, S.defaults.blip, d.blip || {});
  d.shop = d.shop || null;
  d.spawn = d.spawn || null;
  d.testdrive = d.testdrive || null;
  d.delivery = d.delivery || null;
  d.preview = d.preview || null;
  d.business = Object.assign({ owned: false, ownerName: '', price: 0 }, d.business || {});
  return d;
}

function closeAll() {
  $$('.window').forEach((w) => w.classList.add('hidden'));
  closeModal(false);
  S.creator.open = false;
  S.shop = null;
  document.dispatchEvent(new Event('ui:closed'));
}
const anyWindowOpen = () => $$('.window').some((w) => !w.classList.contains('hidden'));

async function requestClose() {
  if (S.creator.open && S.creator.dirty) {
    const ok = await askConfirm('Discard changes?', 'You have unsaved changes to this dealership.', 'Discard', true);
    if (!ok) return;
    S.creator.current = null;
    markDirty(false);
  }
  closeAll();
  post('close');
}
$$('[data-close]').forEach((b) => b.addEventListener('click', requestClose));

/* ==========================================================================
   CREATOR
   ========================================================================== */
const LOCATIONS = [
  { key: 'shop', title: 'Catalogue point', desc: 'Players press E here to browse. The map blip is placed here too.', required: true, vehicle: false },
  { key: 'spawn', title: 'Delivery spawn', desc: 'Where purchased vehicles are delivered.', required: true, vehicle: true },
  { key: 'testdrive', title: 'Test drive spawn', desc: 'Optional. Falls back to the delivery spawn.', required: false, vehicle: true },
  { key: 'preview', title: '3D preview stage', desc: 'Optional. Where the shop shows the rotating preview car (only the viewer sees it). Falls back to the delivery spawn.', required: false, vehicle: true },
  { key: 'delivery', title: 'Stock drop-off', desc: 'Optional. Logistics drivers park ordered stock here. Falls back to the delivery spawn.', required: false, vehicle: true },
];

function openCreator(data) {
  setCategories(data.categories);
  setCurrency(data.currency);
  if (data.defaults) S.defaults = Object.assign(S.defaults, data.defaults);
  if (data.limits) S.limits = Object.assign(S.limits, data.limits);
  S.creator.list = arr(data.dealerships).map(normalizeDealership);
  S.creator.open = true;

  // Keep the dealership being edited if it still exists (e.g. after re-opening)
  if (S.creator.current && S.creator.current.id != null) {
    const fresh = S.creator.list.find((d) => d.id === S.creator.current.id);
    if (!S.creator.dirty) S.creator.current = fresh ? clone(fresh) : null;
  }

  $('#v-cat').innerHTML = catOptions('other');
  $$('.window:not(#offer)').forEach((w) => w.classList.add('hidden'));
  $('#creator').classList.remove('hidden');
  renderCreator();
}

function markDirty(v = true) {
  S.creator.dirty = v;
  $('#c-dirty').textContent = v ? 'Unsaved changes' : '';
}

async function guardDirty() {
  if (!S.creator.dirty) return true;
  const ok = await askConfirm('Discard changes?', 'You have unsaved changes to the current dealership.', 'Discard', true);
  if (ok) markDirty(false);
  return ok;
}

function renderCreator() {
  renderCreatorList();
  renderCreatorForm();
}

function renderCreatorList() {
  const f = S.creator.filter.toLowerCase();
  const cur = S.creator.current;
  const items = [];
  if (cur && cur.id == null) {
    items.push(`<li class="list-item active"><div class="li-title">${esc(cur.label || 'New dealership')} <span class="tag">new</span></div><div class="li-sub">not saved yet</div></li>`);
  }
  S.creator.list
    .filter((d) => !f || d.label.toLowerCase().includes(f) || d.name.toLowerCase().includes(f))
    .forEach((d) => {
      items.push(`<li class="list-item ${cur && cur.id === d.id ? 'active' : ''}" data-id="${d.id}">
        <div class="li-title"><span>${esc(d.label)}</span>${d.job ? `<span class="tag">${esc(d.job)}</span>` : ''}</div>
        <div class="li-sub">${esc(d.name)} · ${d.vehicles.length} vehicle${d.vehicles.length === 1 ? '' : 's'} · ${d.displays.length} on display</div>
      </li>`);
    });
  $('#c-list').innerHTML = items.join('') || '<li class="muted pad">No dealerships yet.</li>';
}

$('#c-list').addEventListener('click', async (e) => {
  const li = e.target.closest('[data-id]');
  if (!li) return;
  const id = Number(li.dataset.id);
  if (S.creator.current && S.creator.current.id === id) return;
  if (!(await guardDirty())) return;
  S.creator.current = clone(S.creator.list.find((d) => d.id === id));
  markDirty(false);
  renderCreator();
});

$('#c-filter').addEventListener('input', (e) => { S.creator.filter = e.target.value; renderCreatorList(); });

$('#c-new').addEventListener('click', async () => {
  if (!(await guardDirty())) return;
  S.creator.current = normalizeDealership({ id: null, name: '', label: 'New Dealership', vehicles: [], displays: [] });
  S.creator.tab = 'general';
  markDirty(true);
  renderCreator();
  $('[data-field="label"]').focus();
});

/* ---------- tabs ---------- */
$('#c-tabs').addEventListener('click', (e) => {
  const b = e.target.closest('[data-tab]');
  if (!b) return;
  S.creator.tab = b.dataset.tab;
  renderTabs();
});

function renderTabs() {
  $$('#c-tabs [data-tab]').forEach((b) => b.classList.toggle('active', b.dataset.tab === S.creator.tab));
  $$('#c-form [data-pane]').forEach((p) => p.classList.toggle('hidden', p.dataset.pane !== S.creator.tab));
  const d = S.creator.current;
  if (!d) return;
  const missing = LOCATIONS.filter((l) => l.required && !d[l.key]).length;
  const tl = $('#t-loc');
  tl.textContent = missing ? `${missing} missing` : '✓';
  tl.className = `badge ${missing ? 'warn' : 'good'}`;
  $('#t-veh').textContent = d.vehicles.length;
  $('#t-show').textContent = d.displays.length;
}

/* ---------- form ---------- */
function getPath(obj, path) { return path.split('.').reduce((o, k) => (o ? o[k] : undefined), obj); }
function setPath(obj, path, value) {
  const keys = path.split('.');
  const last = keys.pop();
  const target = keys.reduce((o, k) => (o[k] = o[k] || {}), obj);
  target[last] = value;
}

function renderCreatorForm() {
  const d = S.creator.current;
  $('#c-empty').classList.toggle('hidden', !!d);
  $('#c-form').classList.toggle('hidden', !d);
  if (!d) return;

  $$('[data-field]').forEach((el) => {
    const v = getPath(d, el.dataset.field);
    if (el.type === 'checkbox') el.checked = v !== false;
    else el.value = v ?? '';
  });
  $('#c-delete').classList.toggle('hidden', d.id == null);
  $('#c-owner').innerHTML = d.business.owned
    ? `<span>${esc(d.business.ownerName || 'Unknown')}</span><button class="btn ghost sm danger-text" id="c-revoke">Revoke ownership</button>`
    : '<span class="muted">State-owned (no player owner)</span>';

  renderTabs();
  renderLocations();
  renderVehicles();
  renderDisplays();
}

$$('[data-field]').forEach((el) => {
  el.addEventListener('input', () => {
    const d = S.creator.current;
    if (!d) return;
    let v;
    if (el.type === 'checkbox') v = el.checked;
    else if (el.type === 'number') v = el.value === '' ? null : Number(el.value);
    else v = el.value;

    if (el.dataset.field === 'name') {
      v = v.toLowerCase().replace(/[^a-z0-9_-]/g, '');
      el.value = v;
    }
    setPath(d, el.dataset.field, v);

    // Auto-suggest an identifier from the label for new dealerships
    if (el.dataset.field === 'label' && d.id == null && !d._nameTouched) {
      d.name = v.toLowerCase().trim().replace(/\s+/g, '_').replace(/[^a-z0-9_-]/g, '').slice(0, 64);
      $('[data-field="name"]').value = d.name;
    }
    if (el.dataset.field === 'name') d._nameTouched = true;

    markDirty();
    if (el.dataset.field === 'label') renderCreatorList();
  });
});

$('#c-owner').addEventListener('click', async (e) => {
  if (!e.target.closest('#c-revoke')) return;
  const d = S.creator.current;
  const ok = await askConfirm('Revoke ownership?', `${d.business.ownerName} loses ${d.label}, its funds and its staff. They are not refunded.`, 'Revoke', true);
  if (!ok) return;
  const res = await post('creatorResetOwner', { id: d.id });
  if (!res || !res.ok) return toast((res && res.error) || 'Failed.', 'error');
  S.creator.list = arr(res.dealerships).map(normalizeDealership);
  const fresh = S.creator.list.find((x) => x.id === d.id);
  if (fresh) d.business = fresh.business;
  renderCreator();
  toast('Ownership revoked.', 'success');
});

/* ---------- locations ---------- */
function previewModel() {
  const d = S.creator.current;
  return (d && d.vehicles[0] && d.vehicles[0].model) || S.defaults.previewModel;
}

function renderLocations() {
  const d = S.creator.current;
  $('#loc-list').innerHTML = LOCATIONS.map((l) => {
    const c = d[l.key];
    return `<div class="row-card">
      <div class="grow">
        <div class="row-title">${l.title}${l.required ? '<span class="req">required</span>' : ''}</div>
        <div class="muted small">${l.desc}</div>
        <div class="coords ${c ? '' : 'unset'}">${c ? fmtCoords(c) : 'Not placed'}</div>
      </div>
      <div class="row-actions">
        ${c ? `<button class="btn ghost sm" data-tp="${l.key}">Teleport</button>` : ''}
        ${c && !l.required ? `<button class="btn ghost sm danger-text" data-clear="${l.key}">Clear</button>` : ''}
        <button class="btn ${c ? '' : 'primary'}" data-place="${l.key}">${c ? 'Re-place' : 'Place'}</button>
      </div>
    </div>`;
  }).join('');
}

$('#loc-list').addEventListener('click', (e) => {
  const d = S.creator.current;
  const b = e.target.closest('button');
  if (!b || !d) return;
  if (b.dataset.place) {
    post('creatorPlace', { kind: b.dataset.place, model: previewModel() });
  } else if (b.dataset.tp) {
    post('creatorTeleport', { coords: d[b.dataset.tp] });
  } else if (b.dataset.clear) {
    d[b.dataset.clear] = null;
    markDirty();
    renderLocations();
    renderTabs();
  }
});

function onPlacementResult(msg) {
  $('#creator').classList.remove('hidden');
  const d = S.creator.current;
  if (!d || !msg.coords) { pendingDisplayModel = null; return; } // cancelled
  const c = { x: msg.coords.x, y: msg.coords.y, z: msg.coords.z, w: msg.coords.w };

  if (msg.kind === 'display') {
    const model = msg.model || ($('#d-model').value || previewModel());
    if (msg.index != null && d.displays[msg.index]) {
      Object.assign(d.displays[msg.index], c);
    } else {
      d.displays.push(Object.assign(c, { model: pendingDisplayModel || model }));
    }
    pendingDisplayModel = null;
    renderDisplays();
  } else {
    d[msg.kind] = c;
    renderLocations();
  }
  markDirty();
  renderTabs();
}

/* ---------- vehicles ---------- */
function renderVehicles() {
  const d = S.creator.current;
  const owned = d.business.owned;
  $('#v-owned-note').classList.toggle('hidden', !owned);
  const rows = d.vehicles.map((v, i) => `<tr data-idx="${i}">
      <td class="model">${esc(v.model)}</td>
      <td><input class="input sm" data-vf="label" value="${esc(v.label)}" maxlength="100"></td>
      <td><select class="input sm" data-vf="category">${catOptions(v.category)}</select></td>
      <td><input class="input sm" type="number" min="0" data-vf="price" value="${v.price}" ${owned ? 'disabled' : ''}></td>
      <td><input class="input sm" type="number" min="0" data-vf="cost" value="${v.cost ?? ''}" placeholder="auto"></td>
      <td><input class="input sm" type="number" min="-1" data-vf="stock" value="${v.stock}" title="-1 = unlimited" ${owned ? 'disabled' : ''}></td>
      <td><button class="btn ghost sm danger-text" data-vremove="${i}" title="Remove">✕</button></td>
    </tr>`);
  $('#v-body').innerHTML = rows.join('') || '<tr class="empty-row"><td colspan="7">No vehicles yet. Add one above using its spawn name.</td></tr>';
  renderDisplayModelSelect();
}

async function checkModel() {
  const model = $('#v-model').value.trim().toLowerCase();
  if (!model) return null;
  const res = await post('creatorValidate', { model });
  if (!res || !res.valid) {
    toast(`"${model}" is not a valid vehicle model on this server.`, 'error');
    return null;
  }
  if (!$('#v-label').value.trim()) $('#v-label').value = res.label;
  $('#v-cat').value = res.category;
  return res;
}

$('#v-check').addEventListener('click', checkModel);
$('#v-model').addEventListener('keydown', (e) => { if (e.key === 'Enter') { e.preventDefault(); checkModel(); } });

$('#v-add').addEventListener('click', async () => {
  const d = S.creator.current;
  const model = $('#v-model').value.trim().toLowerCase();
  if (!model) return toast('Enter a vehicle spawn name.', 'error');
  if (d.vehicles.some((v) => v.model === model)) return toast(`${model} is already in this dealership.`, 'error');
  if (d.vehicles.length >= S.limits.maxVehicles) return toast(`Maximum of ${S.limits.maxVehicles} vehicles.`, 'error');

  const res = await checkModel();
  if (!res) return;

  const price = Math.max(0, Math.floor(Number($('#v-price').value) || 0));
  const stockRaw = $('#v-stock').value;
  const stock = stockRaw === '' ? -1 : Math.max(-1, Math.floor(Number(stockRaw)));

  const costRaw = $('#v-cost').value;
  const cost = costRaw === '' ? null : Math.max(0, Math.floor(Number(costRaw)));
  d.vehicles.push({ model, label: $('#v-label').value.trim() || res.label, category: $('#v-cat').value, price, cost, stock });
  ['#v-model', '#v-label', '#v-price', '#v-cost', '#v-stock'].forEach((s) => { $(s).value = ''; });
  $('#v-model').focus();
  markDirty();
  renderVehicles();
  renderTabs();
});

$('#v-body').addEventListener('input', (e) => {
  const el = e.target.closest('[data-vf]');
  if (!el) return;
  const v = S.creator.current.vehicles[Number(el.closest('tr').dataset.idx)];
  const field = el.dataset.vf;
  if (field === 'price') v.price = Math.max(0, Math.floor(Number(el.value) || 0));
  else if (field === 'stock') v.stock = el.value === '' ? -1 : Math.max(-1, Math.floor(Number(el.value)));
  else if (field === 'cost') v.cost = el.value === '' ? null : Math.max(0, Math.floor(Number(el.value)));
  else v[field] = el.value;
  markDirty();
});
$('#v-body').addEventListener('change', (e) => { if (e.target.dataset.vf === 'category') { S.creator.current.vehicles[Number(e.target.closest('tr').dataset.idx)].category = e.target.value; markDirty(); } });

$('#v-body').addEventListener('click', async (e) => {
  const b = e.target.closest('[data-vremove]');
  if (!b) return;
  const d = S.creator.current;
  const v = d.vehicles[Number(b.dataset.vremove)];
  const used = d.displays.filter((s) => s.model === v.model).length;
  if (used && !(await askConfirm('Remove vehicle?', `${v.label} is used by ${used} display spot(s). Those spots will stay but show no price.`, 'Remove', true))) return;
  d.vehicles.splice(Number(b.dataset.vremove), 1);
  markDirty();
  renderVehicles();
  renderTabs();
});

/* ---------- showroom ---------- */
let pendingDisplayModel = null;

function renderDisplayModelSelect() {
  const d = S.creator.current;
  const sel = $('#d-model');
  const prev = sel.value;
  sel.innerHTML = d.vehicles.length
    ? d.vehicles.map((v) => `<option value="${esc(v.model)}">${esc(v.label)} (${esc(v.model)})</option>`).join('')
    : '<option value="">Add vehicles first</option>';
  if (d.vehicles.some((v) => v.model === prev)) sel.value = prev;
  $('#d-add').disabled = !d.vehicles.length;
}

function renderDisplays() {
  const d = S.creator.current;
  renderDisplayModelSelect();
  $('#d-count').textContent = `${d.displays.length} / ${S.limits.maxDisplays}`;
  const modelOpts = (selected) => {
    const opts = d.vehicles.map((v) => `<option value="${esc(v.model)}" ${v.model === selected ? 'selected' : ''}>${esc(v.label)}</option>`);
    if (!d.vehicles.some((v) => v.model === selected)) opts.unshift(`<option value="${esc(selected)}" selected>${esc(selected)} (not for sale)</option>`);
    return opts.join('');
  };
  $('#d-list').innerHTML = d.displays.map((s, i) => `<div class="row-card" data-didx="${i}">
      <div class="idx">${i + 1}</div>
      <div class="grow">
        <select class="input sm" data-dmodel style="max-width:280px">${modelOpts(s.model)}</select>
        <div class="coords">${fmtCoords(s)}</div>
      </div>
      <div class="row-actions">
        <button class="btn ghost sm" data-dtp>Teleport</button>
        <button class="btn sm" data-dplace>Re-place</button>
        <button class="btn ghost sm danger-text" data-dremove title="Remove">✕</button>
      </div>
    </div>`).join('') || '<div class="muted pad">No display vehicles placed yet.</div>';
}

$('#d-add').addEventListener('click', () => {
  const d = S.creator.current;
  if (d.displays.length >= S.limits.maxDisplays) return toast(`Maximum of ${S.limits.maxDisplays} display spots.`, 'error');
  const model = $('#d-model').value;
  if (!model) return;
  pendingDisplayModel = model;
  post('creatorPlace', { kind: 'display', model, index: null });
});

$('#d-list').addEventListener('click', (e) => {
  const card = e.target.closest('[data-didx]');
  const b = e.target.closest('button');
  if (!card || !b) return;
  const d = S.creator.current;
  const i = Number(card.dataset.didx);
  const spot = d.displays[i];
  if (b.hasAttribute('data-dtp')) post('creatorTeleport', { coords: spot });
  else if (b.hasAttribute('data-dplace')) post('creatorPlace', { kind: 'display', model: spot.model, index: i });
  else if (b.hasAttribute('data-dremove')) {
    d.displays.splice(i, 1);
    markDirty();
    renderDisplays();
    renderTabs();
  }
});

$('#d-list').addEventListener('change', (e) => {
  if (!e.target.hasAttribute('data-dmodel')) return;
  const i = Number(e.target.closest('[data-didx]').dataset.didx);
  S.creator.current.displays[i].model = e.target.value;
  markDirty();
});

/* ---------- save / delete ---------- */
function validateCurrent() {
  const d = S.creator.current;
  if (!d.label || !d.label.trim()) return ['general', 'A display name is required.'];
  if (!/^[a-z0-9_-]{2,64}$/.test(d.name || '')) return ['general', 'Identifier must be 2–64 characters (a-z, 0-9, - or _).'];
  if (d.job && !/^[A-Za-z0-9_-]+$/.test(d.job)) return ['general', 'Job name contains invalid characters.'];
  if (!d.shop) return ['locations', 'Place the catalogue point first.'];
  if (!d.spawn) return ['locations', 'Place the delivery spawn first.'];
  return null;
}

$('#c-save').addEventListener('click', async () => {
  const d = S.creator.current;
  if (!d) return;
  const problem = validateCurrent();
  if (problem) {
    S.creator.tab = problem[0];
    renderTabs();
    return toast(problem[1], 'error');
  }

  const btn = $('#c-save');
  btn.disabled = true;
  const payload = clone(d);
  delete payload._nameTouched;
  const res = await post('creatorSave', payload);
  btn.disabled = false;

  if (!res || !res.ok) return toast((res && res.error) || 'Save failed.', 'error');

  S.creator.list = arr(res.dealerships).map(normalizeDealership);
  S.creator.current = clone(S.creator.list.find((x) => x.id === res.id)) || null;
  markDirty(false);
  renderCreator();
  toast('Dealership saved.', 'success');
});

$('#c-delete').addEventListener('click', async () => {
  const d = S.creator.current;
  if (!d || d.id == null) return;
  const ok = await askConfirm(`Delete ${d.label}?`, 'This removes the dealership, its vehicle list and showroom. Vehicles players already own are not affected.', 'Delete', true);
  if (!ok) return;
  const res = await post('creatorDelete', { id: d.id });
  if (!res || !res.ok) return toast((res && res.error) || 'Delete failed.', 'error');
  S.creator.list = arr(res.dealerships).map(normalizeDealership);
  S.creator.current = null;
  markDirty(false);
  renderCreator();
  toast('Dealership deleted.', 'success');
});

/* ==========================================================================
   SHOP
   ========================================================================== */
const STATS = {};      // model -> stats | null (loading) | false (unavailable)
const SORTS = {
  featured: null,
  'price-asc': (a, b) => a.price - b.price,
  'price-desc': (a, b) => b.price - a.price,
  name: (a, b) => a.label.localeCompare(b.label),
};

function openShop(data) {
  setCategories(data.categories);
  setCurrency(data.currency);
  const payment = arr(data.payment);
  S.shop = {
    dealership: data.dealership,
    vehicles: arr(data.vehicles),
    balance: data.balance || {},
    payment: payment.length ? payment : ['bank'],
    method: payment[0] || 'bank',
    cat: 'all',
    search: '',
    sort: 'featured',
    selected: null,
    busy: false,
    opts: { color1: null, color2: null, plate: '', finance: false, term: 1, deposit: 0.2 },
  };
  S.features = data.features || {};
  if (S.features.finance) S.shop.opts.deposit = S.features.finance.minDeposit;
  $('#s-trade').classList.toggle('hidden', !S.features.tradeIn);
  const biz = data.dealership.business || {};
  $('#s-title').textContent = data.dealership.label;
  $('#s-eyebrow').textContent = biz.owned ? `Owned by ${biz.ownerName}` : 'Official dealer';
  $('#s-search').value = '';
  $('#s-sort').value = 'featured';
  $$('.window:not(#offer)').forEach((w) => w.classList.add('hidden'));
  $('#shop').classList.remove('hidden');

  // Pre-select the first available vehicle so the details panel is never empty
  const first = S.shop.vehicles.find((v) => v.stock !== 0) || S.shop.vehicles[0];
  if (first) selectVehicle(first.id, false);
  renderShop();
}

function renderShop() {
  renderBalance();
  renderShopCats();
  renderShopGrid();
  renderShopDetails();
}

const methodLabel = (m) => ({ bank: 'Bank', cash: 'Cash' }[m] || m);

function renderBalance() {
  const b = S.shop.balance;
  $('#s-balance').innerHTML = S.shop.payment
    .filter((m) => b[m] != null)
    .map((m) => `<div class="balance"><span>${methodLabel(m)}</span><b>${fmtMoney(b[m])}</b></div>`)
    .join('');
}

function renderShopCats() {
  const counts = {};
  S.shop.vehicles.forEach((v) => { counts[v.category] = (counts[v.category] || 0) + 1; });
  const cats = [{ id: 'all', label: 'All vehicles', n: S.shop.vehicles.length }]
    .concat(S.categories.filter((c) => counts[c.id]).map((c) => ({ id: c.id, label: c.label, n: counts[c.id] })));
  $('#s-cats').innerHTML = cats.map((c) => `<li class="list-item ${S.shop.cat === c.id ? 'active' : ''}" data-cat="${esc(c.id)}"><span>${esc(c.label)}</span><span class="count">${c.n}</span></li>`).join('');
}

function filteredVehicles() {
  const q = S.shop.search.toLowerCase().trim();
  const list = S.shop.vehicles.filter((v) => (S.shop.cat === 'all' || v.category === S.shop.cat)
    && (!q || v.label.toLowerCase().includes(q) || v.model.toLowerCase().includes(q)));
  const sorter = SORTS[S.shop.sort];
  return sorter ? list.slice().sort(sorter) : list;
}

const stockBadge = (v) => (v.used ? `<span class="chip used stock">Pre-owned · ${v.condition}%</span>` : v.stock < 0 ? '' : v.stock === 0
  ? '<span class="chip warn stock">Sold out</span>'
  : `<span class="chip ${v.stock <= 2 ? 'hot' : ''} stock">${v.stock <= 2 ? `Only ${v.stock} left` : `${v.stock} in stock`}</span>`);

function businessBanner() {
  const b = S.shop.dealership.business || {};
  if (b.owned || !(b.price > 0)) return '';
  return `<div class="biz-banner">
    <div class="grow"><div class="row-title">This dealership is for sale</div>
    <div class="muted small">Run it yourself: order stock, set prices, hire staff and haggle with customers.</div></div>
    <div class="big-price">${fmtMoney(b.price)}</div>
    <button class="btn primary" data-buybiz>Buy business</button>
  </div>`;
}

function renderShopGrid() {
  const list = filteredVehicles();
  const catName = S.shop.cat === 'all' ? 'All vehicles' : (S.catLabel[S.shop.cat] || S.shop.cat);
  $('#s-bar').innerHTML = `<span><b>${list.length}</b> ${list.length === 1 ? 'vehicle' : 'vehicles'} · ${esc(catName)}</span>
    <span class="muted small kbd-hint"><kbd>←</kbd><kbd>→</kbd> browse</span>`;
  $('#s-grid').innerHTML = businessBanner() + list.map((v) => `<div class="card ${S.shop.selected === v.id ? 'active' : ''} ${v.stock === 0 ? 'sold-out' : ''}" data-vid="${v.id}">
      <div class="thumb">${thumb(v.model)}<span class="chip cat">${esc(S.catLabel[v.category] || v.category)}</span>${stockBadge(v)}</div>
      <div class="card-body">
        <div class="card-title">${esc(v.label)}</div>
        <div class="card-meta"><span class="price">${fmtMoney(v.price)}</span><span class="muted small mono">${esc(v.model)}</span></div>
      </div>
    </div>`).join('') || `<div class="no-results"><div class="empty-icon">🔍</div>No vehicles match “${esc(S.shop.search)}”.</div>`;
}

async function loadStats(model) {
  if (STATS[model] !== undefined) return;
  STATS[model] = null;
  const res = await post('vehicleStats', { model });
  STATS[model] = res && res.ok ? res : false;
  const sel = S.shop && S.shop.vehicles.find((x) => x.id === S.shop.selected);
  if (sel && sel.model === model) renderShopDetails();
}

function selectVehicle(id, render = true) {
  if (S.shop.selected !== id) Object.assign(S.shop.opts, { color1: null, color2: null, finance: false });
  S.shop.selected = id;
  const v = S.shop.vehicles.find((x) => x.id === id);
  if (v) loadStats(v.model);
  if (render) {
    renderShopGrid();
    renderShopDetails();
    const card = $(`#s-grid [data-vid="${id}"]`);
    if (card) card.scrollIntoView({ block: 'nearest', behavior: 'smooth' });
  }
}

function statBars(model) {
  const st = STATS[model];
  if (st === false) return '';
  if (!st) {
    return `<div class="stats">${['Top speed', 'Acceleration', 'Braking', 'Handling'].map((l) => `
      <div class="stat"><div class="stat-head"><span>${l}</span><span class="skeleton"></span></div><div class="stat-bar"><span class="skeleton"></span></div></div>`).join('')}</div>`;
  }
  const mph = UI.speedUnit === 'mph';
  const speed = Math.round(st.speed * (mph ? 2.236936 : 3.6));
  const rows = [
    ['Top speed', st.speed / 60, `${speed} ${mph ? 'mph' : 'km/h'}`],
    ['Acceleration', st.accel / 0.45],
    ['Braking', st.braking / 1.6],
    ['Handling', st.traction / 3.2],
  ];
  return `<div class="stats">${rows.map(([label, ratio, text]) => {
    const pctv = Math.max(4, Math.min(100, ratio * 100));
    return `<div class="stat"><div class="stat-head"><span>${label}</span><span>${text || `${(pctv / 10).toFixed(1)} / 10`}</span></div>
      <div class="stat-bar"><span style="width:${pctv}%"></span></div></div>`;
  }).join('')}</div>
  ${st.seats ? `<div class="chips"><span class="chip">${st.seats} seat${st.seats === 1 ? '' : 's'}</span></div>` : ''}`;
}

const selectedVehicle = () => S.shop && S.shop.vehicles.find((x) => x.id === S.shop.selected);
const colorInfo = (id) => arr(S.features.colors).find((c) => c.id === id) || { label: '?', hex: '#888' };
const swatch = (id) => `<i class="dot-swatch" style="background:${esc(colorInfo(id).hex)}"></i>`;
const canFinance = (v) => !!(S.features.finance && v.price >= S.features.finance.minPrice);

function planFor(v) {
  const f = S.features.finance;
  if (!S.shop.opts.finance || !f || !canFinance(v)) return null;
  const terms = arr(f.terms);
  const term = terms[S.shop.opts.term - 1] || terms[0];
  const ratio = Math.max(f.minDeposit, Math.min(0.9, S.shop.opts.deposit));
  const deposit = Math.ceil(v.price * ratio);
  const total = Math.floor((v.price - deposit) * (1 + term.interest));
  return { deposit, total, payments: term.payments, payment: Math.ceil(total / term.payments), interest: term.interest };
}
function plateFee() {
  const cp = S.features.customPlate;
  return cp && cp.enabled && S.shop.opts.plate.trim() ? cp.price : 0;
}
function upfrontFor(v) {
  const plan = planFor(v);
  return (plan ? plan.deposit : v.price) + plateFee();
}

function renderShopDetails() {
  const el = $('#s-details');
  const v = selectedVehicle();
  if (!v) {
    el.innerHTML = '<div class="empty"><div class="empty-icon">🔑</div><p>Select a vehicle to see details.</p></div>';
    return;
  }
  const b = S.shop.balance;
  const o = S.shop.opts;
  const f = S.features;
  const soldOut = v.stock === 0;
  const selfService = S.shop.dealership.selfService;
  const plan = planFor(v);
  if (plan) S.shop.method = 'bank';
  const methods = plan ? [] : S.shop.payment;
  const terms = arr(f.finance && f.finance.terms);

  el.innerHTML = `
    <div class="stage">${thumb(v.model)}${f.preview ? '<button class="stage-btn" data-act="preview">⟳ 3D view &amp; paint</button>' : ''}</div>
    <div>
      <div class="chips"><span class="chip">${esc(S.catLabel[v.category] || v.category)}</span>${stockBadge(v).replace(' stock', '') || '<span class="chip good">In stock</span>'}</div>
      <h2>${esc(v.label)}</h2>
      <div class="muted small mono">${esc(v.model)}</div>
    </div>
    <div class="big-price">${fmtMoney(v.price)}</div>
    ${statBars(v.model)}
    ${selfService && !soldOut ? `
    <div class="opt-group">
      ${o.color1 != null ? `<div class="opt-row"><span>Paint</span><span class="paint">${swatch(o.color1)}${esc(colorInfo(o.color1).label)}${o.color2 != null && o.color2 !== o.color1 ? ` / ${swatch(o.color2)}${esc(colorInfo(o.color2).label)}` : ''}</span></div>` : ''}
      ${canFinance(v) ? `<div class="seg"><button class="btn ${!o.finance ? 'active' : ''}" data-pay="full">Pay in full</button><button class="btn ${o.finance ? 'active' : ''}" data-pay="finance">Finance</button></div>` : ''}
      ${plan ? `<div class="finance-box">
          <label class="field"><span>Term</span><select class="input" data-term>${terms.map((t, i) => `<option value="${i + 1}" ${o.term === i + 1 ? 'selected' : ''}>${t.payments} payments · ${Math.round(t.interest * 100)}% interest</option>`).join('')}</select></label>
          <label class="field"><span>Deposit <em id="s-dep">${Math.round(Math.max(f.finance.minDeposit, o.deposit) * 100)}%</em></span>
            <input type="range" class="range" min="${Math.round(f.finance.minDeposit * 100)}" max="90" step="5" value="${Math.round(Math.max(f.finance.minDeposit, o.deposit) * 100)}" data-deposit></label>
          <div class="kv"><span>Deposit today</span><span id="s-plan-dep"></span></div>
          <div class="kv"><span>Instalments</span><span id="s-plan-inst"></span></div>
          <div class="kv"><span>Total cost</span><span id="s-plan-total"></span></div>
          <div class="muted small">Instalments are taken from your bank while you're online. Missing ${f.finance.maxMissed || 3} in a row means the car is repossessed. Check them with /financing.</div>
        </div>` : ''}
      ${f.customPlate && f.customPlate.enabled ? `<label class="field"><span>Custom plate <em>+${fmtMoney(f.customPlate.price)} · optional</em></span>
        <input class="input mono plate-input" maxlength="8" placeholder="RANDOM" value="${esc(o.plate)}" data-plate></label>` : ''}
    </div>` : ''}
    ${selfService && methods.length > 1 && !soldOut ? `<div class="seg">${methods.map((m) => `
      <button class="btn ${S.shop.method === m ? 'active' : ''}" data-method="${esc(m)}">${methodLabel(m)}${b[m] != null ? `<small>${fmtMoney(b[m])}</small>` : ''}</button>`).join('')}</div>` : ''}
    ${selfService && !soldOut ? '<div class="after hidden" id="s-after"></div>' : ''}
    <div class="actions">
      ${S.shop.dealership.testDrive ? `<button class="btn" data-act="test" ${S.shop.busy ? 'disabled' : ''}>
        <svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="9"/><circle cx="12" cy="12" r="2"/><path d="M12 3v7M4.5 15.5l5.8-2.5M19.5 15.5l-5.8-2.5"/></svg>
        Test drive · ${S.shop.dealership.testDriveDuration}s</button>` : ''}
      ${selfService ? '<button class="btn primary" data-act="buy" id="s-buy"></button>' : '<div class="hint center">Purchases here go through a salesperson.</div>'}
    </div>`;
  refreshTotals();
}

/** Updates the money figures without re-rendering (keeps input focus). */
function refreshTotals() {
  const v = selectedVehicle();
  if (!v) return;
  const bal = S.shop.balance[S.shop.method];
  const up = upfrontFor(v);
  const affordable = bal == null || bal >= up;
  const soldOut = v.stock === 0;

  const after = $('#s-after');
  if (after) {
    after.classList.toggle('hidden', bal == null);
    after.classList.toggle('neg', !affordable);
    after.innerHTML = `<span>Balance after purchase</span><b>${fmtMoney((bal || 0) - up)}</b>`;
  }
  const plan = planFor(v);
  if (plan && $('#s-plan-dep')) {
    $('#s-plan-dep').textContent = fmtMoney(plan.deposit);
    $('#s-plan-inst').textContent = `${plan.payments} × ${fmtMoney(plan.payment)}`;
    $('#s-plan-total').textContent = fmtMoney(plan.deposit + plan.total);
  }
  const buy = $('#s-buy');
  if (buy) {
    buy.disabled = soldOut || !affordable || S.shop.busy;
    if (soldOut) buy.textContent = 'Sold out';
    else if (!affordable) buy.textContent = S.shop.method === 'cash' ? 'Not enough cash' : 'Not enough money in the bank';
    else buy.textContent = plan ? `Pay deposit ${fmtMoney(up)}` : `Buy for ${fmtMoney(up)}`;
  }
}

$('#s-cats').addEventListener('click', (e) => {
  const li = e.target.closest('[data-cat]');
  if (!li) return;
  S.shop.cat = li.dataset.cat;
  renderShopCats();
  renderShopGrid();
});

$('#s-search').addEventListener('input', (e) => { S.shop.search = e.target.value; renderShopGrid(); });
$('#s-sort').addEventListener('change', (e) => { S.shop.sort = e.target.value; renderShopGrid(); });

$('#s-grid').addEventListener('click', async (e) => {
  if (e.target.closest('[data-buybiz]')) {
    const b = S.shop.dealership.business;
    const ok = await askConfirm(`Buy ${S.shop.dealership.label}?`, `${fmtMoney(b.price)} will be paid by ${methodLabel(S.shop.method).toLowerCase()}. Stock starts empty, so you'll need to order vehicles.`, 'Buy business');
    if (!ok || !S.shop) return;
    const res = await post('shopBuyBusiness', { method: S.shop.method });
    if (!res || !res.ok) toast((res && res.error) || 'Purchase failed.', 'error');
    return;
  }
  const card = e.target.closest('[data-vid]');
  if (card) selectVehicle(Number(card.dataset.vid));
});

// Arrow keys browse the grid while the shop is open (not while typing)
document.addEventListener('keydown', (e) => {
  if (!S.shop || $('#shop').classList.contains('hidden') || !$('#modal').classList.contains('hidden')) return;
  if (['INPUT', 'SELECT', 'TEXTAREA'].includes(document.activeElement && document.activeElement.tagName)) return;
  const list = filteredVehicles();
  if (!list.length) return;
  const idx = list.findIndex((v) => v.id === S.shop.selected);
  let next = null;
  if (e.key === 'ArrowRight' || e.key === 'ArrowDown') next = list[Math.min(list.length - 1, idx + 1)];
  else if (e.key === 'ArrowLeft' || e.key === 'ArrowUp') next = list[Math.max(0, idx - 1)];
  if (next) { e.preventDefault(); selectVehicle(next.id); }
});

function purchaseSummary(v) {
  const o = S.shop.opts;
  const plan = planFor(v);
  const bal = S.shop.balance[S.shop.method];
  const up = upfrontFor(v);
  return `<div class="confirm-car"><div class="thumb mini">${thumb(v.model)}</div>
      <div><div class="row-title">${esc(v.label)}</div><div class="muted small">${esc(S.catLabel[v.category] || v.category)}${v.used ? ` · ${v.condition}% condition` : ''}</div></div></div>
    <div class="kv"><span>Price</span><span>${fmtMoney(v.price)}</span></div>
    ${o.color1 != null ? `<div class="kv"><span>Paint</span><span>${esc(colorInfo(o.color1).label)}${o.color2 != null && o.color2 !== o.color1 ? ` / ${esc(colorInfo(o.color2).label)}` : ''}</span></div>` : ''}
    ${plateFee() ? `<div class="kv"><span>Custom plate</span><span>${esc(o.plate.trim().toUpperCase())} · ${fmtMoney(plateFee())}</span></div>` : ''}
    ${plan ? `<div class="kv"><span>Financing</span><span>${plan.payments} × ${fmtMoney(plan.payment)}</span></div>` : ''}
    <div class="kv"><span>${plan ? 'Due today' : 'Total'}</span><span>${fmtMoney(up)} · ${methodLabel(S.shop.method)}</span></div>
    ${bal != null ? `<div class="kv"><span>Balance after</span><span>${fmtMoney(bal - up)}</span></div>` : ''}
    <div class="kv"><span>Delivery</span><span>Delivery bay · keys included</span></div>`;
}

async function doBuy() {
  const v = selectedVehicle();
  if (!v || S.shop.busy) return;
  const o = S.shop.opts;
  const ok = await askConfirm('Confirm purchase', '', `Pay ${fmtMoney(upfrontFor(v))}`, false, purchaseSummary(v));
  if (!ok || !S.shop) return;
  S.shop.busy = true; refreshTotals();
  const res = await post('shopBuy', {
    vehicleId: v.id,
    method: S.shop.method,
    options: {
      color1: o.color1, color2: o.color2 != null ? o.color2 : o.color1,
      plate: o.plate.trim(),
      finance: planFor(v) ? { term: o.term, deposit: o.deposit } : null,
    },
  });
  if (!S.shop) return;
  S.shop.busy = false; refreshTotals();
  if (!res || !res.ok) toast((res && res.error) || 'Purchase failed.', 'error');
}

async function doTestDrive() {
  const v = selectedVehicle();
  if (!v || S.shop.busy) return;
  S.shop.busy = true; renderShopDetails();
  const res = await post('shopTestDrive', { vehicleId: v.id });
  if (!S.shop) return;
  S.shop.busy = false; renderShopDetails();
  if (!res || !res.ok) toast((res && res.error) || 'Test drive unavailable.', 'error');
}

$('#s-details').addEventListener('click', async (e) => {
  const b = e.target.closest('button');
  if (!b || !S.shop) return;
  if (b.dataset.method) {
    S.shop.method = b.dataset.method;
    return renderShopDetails();
  }
  if (b.dataset.pay) {
    S.shop.opts.finance = b.dataset.pay === 'finance';
    if (!S.shop.opts.finance) S.shop.method = S.shop.payment[0];
    return renderShopDetails();
  }
  if (b.dataset.act === 'buy') doBuy();
  else if (b.dataset.act === 'test') doTestDrive();
  else if (b.dataset.act === 'preview' && typeof enterPreview === 'function') enterPreview();
});

$('#s-details').addEventListener('change', (e) => {
  if (e.target.matches('[data-term]')) { S.shop.opts.term = Number(e.target.value); refreshTotals(); }
});

$('#s-details').addEventListener('input', (e) => {
  if (e.target.matches('[data-deposit]')) {
    S.shop.opts.deposit = Number(e.target.value) / 100;
    $('#s-dep').textContent = `${e.target.value}%`;
    refreshTotals();
  } else if (e.target.matches('[data-plate]')) {
    const clean = e.target.value.toUpperCase().replace(/[^A-Z0-9 ]/g, '').slice(0, 8);
    if (clean !== e.target.value) e.target.value = clean;
    S.shop.opts.plate = clean;
    refreshTotals();
  }
});

// Trade-in: quote the car the player arrived in
$('#s-trade').addEventListener('click', async () => {
  if (!S.shop) return;
  const q = await post('tradeQuote');
  if (!q || !q.ok) return toast((q && q.error) || 'No vehicle to trade in.', 'error');
  const html = `<div class="confirm-car"><div class="thumb mini">${thumb(q.model)}</div>
      <div><div class="row-title">${esc(q.label)}</div><div class="muted small mono">${esc(q.plate)}</div></div></div>
    <div class="kv"><span>Condition</span><span>${q.condition}%</span></div>
    <div class="kv"><span>Our offer</span><span class="pos">${fmtMoney(q.value)}</span></div>
    <div class="muted small">Paid to your bank. The car leaves your garage and goes on our pre-owned lot. Offer valid for 60 seconds.</div>`;
  const ok = await askConfirm('Trade-in offer', '', `Sell for ${fmtMoney(q.value)}`, false, html);
  if (!ok) return;
  const res = await post('tradeAccept');
  if (!res || !res.ok) return toast((res && res.error) || 'Trade-in failed.', 'error');
  toast(res.message, 'success');
  if (S.shop && res.balance) { S.shop.balance = res.balance; renderBalance(); refreshTotals(); }
});

/* ==========================================================================
   Messages from Lua
   ========================================================================== */
window.addEventListener('message', (e) => {
  const msg = e.data || {};
  switch (msg.action) {
    case 'openCreator': openCreator(msg); break;
    case 'openShop': openShop(msg); break;
    case 'shopUpdate':
      if (S.shop) {
        S.shop.vehicles = arr(msg.vehicles);
        if (msg.categories) setCategories(msg.categories);
        if (!S.shop.vehicles.some((v) => v.id === S.shop.selected)) S.shop.selected = null;
        renderShopCats(); renderShopGrid(); renderShopDetails();
      }
      break;
    case 'hide': $('#creator').classList.add('hidden'); break;
    case 'placementResult': onPlacementResult(msg); break;
    case 'close': closeAll(); break;
    default: break;
  }
});

document.addEventListener('keydown', (e) => {
  if (e.key !== 'Escape') return;
  if (!$('#modal').classList.contains('hidden')) return closeModal(false);
  if (!$('#offer').classList.contains('hidden')) return; // business.js declines the offer
  if (!$('#preview').classList.contains('hidden')) return exitPreview();
  if (anyWindowOpen()) requestClose();
});
