'use strict';
/* Logistics board: pick a shipment at the depot and haul it to a dealership. */

const LG = { data: null, busy: false };

function openLogistics(msg) {
  setCurrency(msg.currency);
  LG.data = msg.data;
  LG.data.shipments = arr(msg.data.shipments);
  LG.busy = false;
  $$('.window:not(#offer)').forEach((w) => w.classList.add('hidden'));
  $('#logi').classList.remove('hidden');
  renderLogistics();
}

function renderLogistics() {
  const d = LG.data;
  $('#l-title').textContent = `${d.depot} · Logistics board`;

  const active = d.active ? `
    <div class="card-box haul">
      <div class="grow">
        <div class="tile-label">Current delivery</div>
        <div class="row-title">${esc(d.active.label)} → ${esc(d.active.dealership)}</div>
        <div class="muted small">${fmtDuration(d.active.timeLeft)} left · follow the yellow route and park on the drop-off marker</div>
      </div>
      <button class="btn danger" data-lcancel ${LG.busy ? 'disabled' : ''}>Cancel delivery</button>
    </div>` : '';

  const rows = d.shipments.map((s) => `
    <div class="row-card">
      <div class="thumb mini">${thumb(s.model)}</div>
      <div class="grow">
        <div class="row-title">${esc(s.label)}</div>
        <div class="muted small">To <b>${esc(s.dealership)}</b> · ${(s.distance / 1000).toFixed(1)} km</div>
      </div>
      <div class="right">
        <div class="price">${fmtMoney(s.payout)}</div>
        <div class="muted small">at full condition</div>
      </div>
      <button class="btn primary" data-laccept="${s.id}" ${LG.busy || d.active ? 'disabled' : ''}>Take job</button>
    </div>`).join('');

  $('#l-body').innerHTML = `
    ${active}
    <p class="hint">Pick a shipment, drive the vehicle to the dealership and park it on the drop-off marker. Your pay drops with any damage to the vehicle, and if it's wrecked or you run out of time the shipment goes back on the board.</p>
    <div class="stack">${rows || '<div class="empty-state muted">No shipments waiting right now. Dealerships order stock from their management panel.</div>'}</div>`;
}

$('#l-body').addEventListener('click', async (e) => {
  const accept = e.target.closest('[data-laccept]');
  if (accept && !LG.busy) {
    LG.busy = true;
    renderLogistics();
    const res = await post('logiAccept', { id: Number(accept.dataset.laccept) });
    LG.busy = false;
    if (!res || !res.ok) {
      toast((res && res.error) || 'Could not take that job.', 'error');
      if (LG.data) renderLogistics();
    }
    return;
  }
  if (e.target.closest('[data-lcancel]')) {
    const ok = await askConfirm('Cancel delivery?', 'The vehicle is removed and the shipment goes back on the board. You are not paid.', 'Cancel delivery', true);
    if (!ok) return;
    const res = await post('logiCancel');
    if (!res || !res.ok) return toast((res && res.error) || 'Failed.', 'error');
    LG.data.active = null;
    renderLogistics();
    toast('Delivery cancelled.', 'info');
  }
});

window.addEventListener('message', (e) => {
  if ((e.data || {}).action === 'openLogistics') openLogistics(e.data);
});

document.addEventListener('ui:closed', () => { LG.data = null; });
