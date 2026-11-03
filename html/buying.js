'use strict';
/* 3D preview overlay (camera drag + paint picker) and the /financing window. */

/* ==========================================================================
   3D preview
   ========================================================================== */
const PV = { slot: 1, dragging: false, acc: { dx: 0, dy: 0, zoom: 0 }, timer: null };

async function enterPreview() {
  const v = selectedVehicle();
  if (!v) return;
  const o = S.shop.opts;
  const res = await post('previewStart', { model: v.model, color1: o.color1, color2: o.color2, condition: v.used ? v.condition : 100 });
  if (!res || !res.ok) return toast((res && res.error) || 'Preview unavailable.', 'error');
  PV.slot = 1;
  $('#shop').classList.add('hidden');
  $('#preview').classList.remove('hidden');
  renderPreview();
}

function exitPreview() {
  post('previewStop');
  $('#preview').classList.add('hidden');
  if (S.shop) {
    $('#shop').classList.remove('hidden');
    renderShopDetails();
  }
}

function renderPreview() {
  const v = selectedVehicle();
  if (!v) return exitPreview();
  const o = S.shop.opts;
  $('#pv-cat').textContent = (S.catLabel[v.category] || v.category) + (v.used ? ` · ${v.condition}% condition` : '');
  $('#pv-name').textContent = v.label;
  $('#pv-price').textContent = fmtMoney(v.price);
  $$('#pv-slots [data-slot]').forEach((b) => b.classList.toggle('active', Number(b.dataset.slot) === PV.slot));

  const current = PV.slot === 1 ? o.color1 : (o.color2 != null ? o.color2 : o.color1);
  $('#pv-swatches').innerHTML = arr(S.features.colors).map((c) => `
    <button class="swatch ${current === c.id ? 'active' : ''}" data-color="${c.id}" title="${esc(c.label)}" style="--sw:${esc(c.hex)}"></button>`).join('');
  $('#pv-colorname').textContent = current != null ? `${PV.slot === 1 ? 'Primary' : 'Secondary'}: ${colorInfo(current).label}` : 'Pick a paint colour';

  const soldOut = v.stock === 0;
  const buy = $('#pv-buy');
  buy.disabled = soldOut || !S.shop.dealership.selfService;
  buy.textContent = soldOut ? 'Sold out' : planFor(v) ? `Pay deposit ${fmtMoney(upfrontFor(v))}` : `Buy for ${fmtMoney(upfrontFor(v))}`;
  $('#pv-test').classList.toggle('hidden', !S.shop.dealership.testDrive);
}

$('#pv-slots').addEventListener('click', (e) => {
  const b = e.target.closest('[data-slot]');
  if (!b) return;
  PV.slot = Number(b.dataset.slot);
  renderPreview();
});

$('#pv-swatches').addEventListener('click', (e) => {
  const b = e.target.closest('[data-color]');
  if (!b || !S.shop) return;
  const o = S.shop.opts;
  const id = Number(b.dataset.color);
  if (PV.slot === 1) {
    if (o.color2 == null || o.color2 === o.color1) o.color2 = id;
    o.color1 = id;
  } else {
    if (o.color1 == null) o.color1 = id;
    o.color2 = id;
  }
  post('previewColor', { color1: o.color1, color2: o.color2 });
  renderPreview();
});

$('#pv-back').addEventListener('click', exitPreview);
$('#pv-buy').addEventListener('click', () => doBuy());
$('#pv-test').addEventListener('click', () => doTestDrive());

// Camera: drag to orbit, wheel to zoom (batched to ~25 updates/sec)
function flushCam() {
  PV.timer = null;
  const a = PV.acc;
  if (!a.dx && !a.dy && !a.zoom) return;
  post('previewCam', { dx: a.dx, dy: a.dy, zoom: a.zoom });
  PV.acc = { dx: 0, dy: 0, zoom: 0 };
}
function queueCam() { if (!PV.timer) PV.timer = setTimeout(flushCam, 40); }

const drag = $('#pv-drag');
drag.addEventListener('mousedown', () => { PV.dragging = true; drag.classList.add('grabbing'); });
window.addEventListener('mouseup', () => { PV.dragging = false; drag.classList.remove('grabbing'); });
window.addEventListener('mousemove', (e) => {
  if (!PV.dragging || $('#preview').classList.contains('hidden')) return;
  PV.acc.dx += e.movementX;
  PV.acc.dy += e.movementY;
  queueCam();
});
drag.addEventListener('wheel', (e) => {
  PV.acc.zoom += e.deltaY;
  queueCam();
}, { passive: true });

/* ==========================================================================
   /financing
   ========================================================================== */
const FW = { data: null, busy: false };

function openFinance(msg) {
  setCurrency(msg.currency);
  FW.data = msg.data;
  FW.data.contracts = arr(msg.data.contracts);
  $$('.window:not(#offer)').forEach((w) => w.classList.add('hidden'));
  $('#finwin').classList.remove('hidden');
  renderFinance();
}

function renderFinance() {
  const d = FW.data;
  $('#f-balance').textContent = d.balance != null ? `Bank: ${fmtMoney(d.balance)}` : '';
  $('#f-body').innerHTML = d.contracts.length ? d.contracts.map((c) => {
    const paid = c.total - c.remaining;
    const pctPaid = Math.round((paid / Math.max(1, c.total)) * 100);
    return `<div class="card-box contract">
      <div class="contract-head">
        <div class="thumb mini">${thumb(c.model)}</div>
        <div class="grow">
          <div class="row-title">${esc(c.label)} <span class="tag mono">${esc(c.plate)}</span></div>
          <div class="muted small">${esc(c.dealership)} · ${c.paymentsLeft} payment${c.paymentsLeft === 1 ? '' : 's'} left</div>
        </div>
        <div class="right"><div class="price">${fmtMoney(c.remaining)}</div><div class="muted small">remaining</div></div>
      </div>
      <div class="meter"><span style="width:${pctPaid}%;background:var(--good)"></span></div>
      <div class="contract-foot">
        <span class="small ${c.missed ? 'neg' : 'muted'}">${c.missed
          ? `⚠ ${c.missed} missed payment${c.missed === 1 ? '' : 's'} (${d.maxMissed} means repossession)`
          : `Next payment ${fmtMoney(c.payment)} ${c.dueIn > 0 ? `in ${fmtDuration(c.dueIn)}` : 'due now'}`}</span>
        <span class="inline">
          <button class="btn sm" data-fpay="${c.id}" ${FW.busy ? 'disabled' : ''}>Pay ${fmtMoney(c.payment)} now</button>
          <button class="btn sm primary" data-fpayoff="${c.id}" ${FW.busy ? 'disabled' : ''}>Pay off ${fmtMoney(c.remaining)}</button>
        </span>
      </div>
    </div>`;
  }).join('') : '<div class="empty-state muted">No active finance contracts. 🎉</div>';
}

$('#f-body').addEventListener('click', async (e) => {
  const one = e.target.closest('[data-fpay]');
  const all = e.target.closest('[data-fpayoff]');
  if ((!one && !all) || FW.busy) return;
  const id = Number((one || all).dataset.fpay || (one || all).dataset.fpayoff);
  if (all) {
    const c = FW.data.contracts.find((x) => x.id === id);
    if (!(await askConfirm('Pay off contract?', `${fmtMoney(c.remaining)} will be taken from your bank and the ${c.label} is fully yours.`, 'Pay off'))) return;
  }
  FW.busy = true; renderFinance();
  const res = await post('financePay', { id, full: !!all });
  FW.busy = false;
  if (!res || !res.ok) { renderFinance(); return toast((res && res.error) || 'Payment failed.', 'error'); }
  toast(res.message, 'success');
  FW.data.contracts = arr(res.contracts);
  FW.data.balance = res.balance;
  renderFinance();
});

window.addEventListener('message', (e) => {
  if ((e.data || {}).action === 'openFinance') openFinance(e.data);
});

document.addEventListener('ui:closed', () => { FW.data = null; PV.dragging = false; });
