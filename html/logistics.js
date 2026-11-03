'use strict';
/* Logistics board: single & carrier jobs, cargo insurance, logistics company. */

const LG = { data: null, busy: false, tab: 'jobs', insured: true, nearby: [] };

function openLogistics(msg) {
  setCurrency(msg.currency);
  LG.tab = 'jobs';
  LG.nearby = [];
  setLogisticsData(msg.data);
  $$('.window:not(#offer)').forEach((w) => w.classList.add('hidden'));
  $('#logi').classList.remove('hidden');
}

function setLogisticsData(data) {
  LG.data = data;
  LG.data.shipments = arr(data.shipments);
  LG.data.carriers = arr(data.carriers);
  LG.busy = false;
  renderLogistics();
}

const pctTxt = (n) => `${Math.round(n * 100)}%`;

function renderLogistics() {
  const d = LG.data;
  const co = d.company;
  $('#l-title').textContent = `${d.depot} · Logistics`;
  const tabs = co ? `<nav class="tabs inline-tabs">
      <button data-ltab="jobs" class="${LG.tab === 'jobs' ? 'active' : ''}">Jobs</button>
      <button data-ltab="company" class="${LG.tab === 'company' ? 'active' : ''}">${esc(co.label)}${co.owned ? '' : ' <span class="badge warn">for sale</span>'}</button>
    </nav>` : '';
  $('#l-body').innerHTML = tabs + (LG.tab === 'company' && co ? companyPane(d, co) : jobsPane(d));
}

function jobsPane(d) {
  const ins = d.insurance || {};
  const active = d.active ? `
    <div class="card-box haul">
      <div class="grow">
        <div class="tile-label">Current delivery${d.active.kind === 'carrier' ? ' · carrier' : ''}${d.active.insured ? ' · insured' : ''}</div>
        <div class="row-title">${esc(d.active.label)} → ${esc(d.active.dealership)}</div>
        <div class="muted small">${fmtDuration(d.active.timeLeft)} left · follow the yellow route and park on the drop-off marker</div>
      </div>
      <button class="btn danger" data-lcancel ${LG.busy ? 'disabled' : ''}>Cancel delivery</button>
    </div>` : '';

  if (!d.canTake) {
    return `${active}<div class="empty-state muted">Only <b>${esc(d.job || 'logistics')}</b> workers${d.company ? ` and ${esc(d.company.label)} drivers` : ''} can take freight jobs here.</div>`;
  }

  const disabled = LG.busy || !!d.active;
  const insurance = `<label class="ins-toggle">
      <input type="checkbox" id="l-ins" ${LG.insured ? 'checked' : ''}>
      <span><b>Insure my cargo</b> <span class="muted small">−${pctTxt(ins.premium || 0)} of pay on delivery · if the cargo is lost you get ${pctTxt(ins.payout || 0)} instead of paying a ${pctTxt(ins.uninsuredPenalty || 0)} penalty</span></span>
    </label>`;

  const carriers = d.carriers.map((c) => `
    <div class="row-card carrier">
      <div class="truck-ico">🚛</div>
      <div class="grow">
        <div class="row-title">Car carrier · ${c.count} vehicles ${c.highValue ? '<span class="chip hot">High value</span>' : ''}</div>
        <div class="muted small">To <b>${esc(c.dealership)}</b> · ${(c.distance / 1000).toFixed(1)} km · ${arr(c.labels).map(esc).join(', ')}</div>
      </div>
      <div class="right"><div class="price">${fmtMoney(c.payout)}</div><div class="muted small">truck + trailer</div></div>
      <button class="btn primary" data-lcarrier="${c.dealershipId}" ${disabled ? 'disabled' : ''}>Take job</button>
    </div>`).join('');

  const singles = d.shipments.map((s) => `
    <div class="row-card">
      <div class="thumb mini">${thumb(s.model)}</div>
      <div class="grow">
        <div class="row-title">${esc(s.label)} ${s.highValue ? '<span class="chip hot">High value</span>' : ''}</div>
        <div class="muted small">To <b>${esc(s.dealership)}</b> · ${(s.distance / 1000).toFixed(1)} km</div>
      </div>
      <div class="right"><div class="price">${fmtMoney(s.payout)}</div><div class="muted small">at full condition</div></div>
      <button class="btn primary" data-laccept="${s.id}" ${disabled ? 'disabled' : ''}>Take job</button>
    </div>`).join('');

  return `
    ${active}
    ${insurance}
    <p class="hint">Drive the cargo to the dealership and park on the drop-off marker. Pay drops with damage. High-value and carrier loads attract hijackers, but surviving an ambush earns hazard pay.</p>
    ${carriers ? `<h3 class="section-title">Carrier jobs</h3><div class="stack">${carriers}</div>` : ''}
    <h3 class="section-title">Single deliveries</h3>
    <div class="stack">${singles || '<div class="empty-state muted">No shipments waiting right now. Dealerships order stock from their management panel.</div>'}</div>`;
}

function companyPane(d, co) {
  if (!co.owned) {
    return `<div class="card-box company-sale">
        <div class="truck-ico big">🏢</div>
        <div class="grow">
          <div class="row-title">${esc(co.label)} is for sale</div>
          <div class="muted small">Own the depot's freight operation: take a ${co.cut}% cut of every haul, hire your own drivers (no job needed), withdraw the profits.</div>
        </div>
        <div class="big-price">${fmtMoney(co.price)}</div>
        <button class="btn primary" data-cbuy>Buy company</button>
      </div>`;
  }
  if (!co.isOwner) {
    return `<div class="card-box"><div class="row-title">${esc(co.label)}</div>
      <div class="muted">Owned by ${esc(co.ownerName)} · takes a ${co.cut}% cut of each haul.${co.isDriver ? ' You drive for this company.' : ''}</div></div>`;
  }
  const a = co.admin;
  const players = LG.nearby.map((p) => `<option value="${p.id}">${esc(p.name)} (#${p.id})</option>`).join('');
  return `
    <div class="split">
      <div class="card-box">
        <div class="tile-label">Company balance</div>
        <div class="big-stat">${fmtMoney(a.balance)}</div>
        <div class="inline"><input class="input" type="number" min="1" id="c-wd" placeholder="Amount"><button class="btn" data-cwithdraw>Withdraw</button></div>
      </div>
      <div class="card-box">
        <div class="tile-label">Cut of every haul</div>
        <div class="big-stat">${co.cut}%</div>
        <div class="inline"><input class="input" type="number" min="0" max="${a.maxCut}" id="c-cut" value="${co.cut}"><button class="btn" data-ccut>Save</button></div>
      </div>
    </div>
    <h3 class="section-title">Drivers (${a.drivers.length}/${a.maxDrivers})</h3>
    <div class="card-box">${a.drivers.length ? `<div class="tx-list">${a.drivers.map((dr) => `<div class="tx" data-cident="${esc(dr.identifier)}">
        <span class="dot ${dr.online ? 'on' : ''}"></span><div class="grow">${esc(dr.name)}</div>
        <button class="btn ghost sm danger-text" data-cfire>Let go</button></div>`).join('')}</div>` : '<div class="muted pad">No drivers yet. Hired drivers can haul without the logistics job.</div>'}</div>
    <div class="add-row" style="margin-top:12px">
      <select class="input" id="c-target">${players || '<option value="">Nobody nearby (press refresh)</option>'}</select>
      <button class="btn" data-cnearby>Refresh</button>
      <button class="btn primary" data-chire>Hire driver</button>
    </div>
    <h3 class="section-title">Sell company</h3>
    <p class="hint">Sell back for <b>${fmtMoney(a.sellBack)}</b> plus the balance. All drivers are let go.</p>
    <button class="btn danger" data-csell>Sell company</button>`;
}

async function companyAction(action, payload = {}) {
  const res = await post('logiCompany', { action, payload });
  if (!res || !res.ok) { toast((res && res.error) || 'Action failed.', 'error'); return null; }
  if (res.message) toast(res.message, 'success');
  if (res.board) setLogisticsData(res.board);
  return res;
}

$('#l-body').addEventListener('change', (e) => {
  if (e.target.id === 'l-ins') LG.insured = e.target.checked;
});

$('#l-body').addEventListener('click', async (e) => {
  const t = e.target;
  const tab = t.closest('[data-ltab]');
  if (tab) { LG.tab = tab.dataset.ltab; return renderLogistics(); }

  const single = t.closest('[data-laccept]');
  const carrier = t.closest('[data-lcarrier]');
  if ((single || carrier) && !LG.busy) {
    LG.busy = true;
    renderLogistics();
    const res = await post('logiAccept', single
      ? { kind: 'single', id: Number(single.dataset.laccept), insured: LG.insured }
      : { kind: 'carrier', dealershipId: Number(carrier.dataset.lcarrier), insured: LG.insured });
    LG.busy = false;
    if (!res || !res.ok) {
      toast((res && res.error) || 'Could not take that job.', 'error');
      if (LG.data) renderLogistics();
    }
    return;
  }
  if (t.closest('[data-lcancel]')) {
    const ok = await askConfirm('Cancel delivery?', 'The vehicle is removed and the shipment goes back on the board. You are not paid.', 'Cancel delivery', true);
    if (!ok) return;
    const res = await post('logiCancel');
    if (!res || !res.ok) return toast((res && res.error) || 'Failed.', 'error');
    LG.data.active = null;
    renderLogistics();
    toast('Delivery cancelled.', 'info');
    return;
  }

  const co = LG.data && LG.data.company;
  if (t.closest('[data-cbuy]')) {
    if (await askConfirm(`Buy ${co.label}?`, `${fmtMoney(co.price)} will be taken from your bank.`, 'Buy company')) companyAction('buy');
  } else if (t.closest('[data-cwithdraw]')) {
    companyAction('withdraw', { amount: Number($('#c-wd').value) });
  } else if (t.closest('[data-ccut]')) {
    companyAction('setCut', { cut: Number($('#c-cut').value) });
  } else if (t.closest('[data-cnearby]')) {
    const res = await companyAction('nearby');
    if (res) { LG.nearby = arr(res.players); renderLogistics(); if (!LG.nearby.length) toast('No players within 10 m.', 'info'); }
  } else if (t.closest('[data-chire]')) {
    const target = Number($('#c-target').value);
    if (!target) return toast('Choose a player first (press Refresh).', 'error');
    companyAction('hire', { target });
  } else if (t.closest('[data-cfire]')) {
    companyAction('fire', { identifier: t.closest('[data-cident]').dataset.cident });
  } else if (t.closest('[data-csell]')) {
    if (await askConfirm(`Sell ${co.label}?`, `You receive ${fmtMoney(co.admin.sellBack + co.admin.balance)}. This can't be undone.`, 'Sell', true)) companyAction('sell');
  }
});

window.addEventListener('message', (e) => {
  if ((e.data || {}).action === 'openLogistics') openLogistics(e.data);
});

document.addEventListener('ui:closed', () => { LG.data = null; });
