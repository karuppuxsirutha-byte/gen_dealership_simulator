'use strict';
/* Admin dashboard: server-wide sales, dealerships, economy, market control. */

const AD = { data: null };
const KIND_LABEL = { shop: 'Self-service', staff: 'Staff offers', npc: 'Walk-in (AI)', used: 'Pre-owned' };

function openAdmin(msg) {
  setCurrency(msg.currency);
  AD.data = msg.data;
  $$('.window:not(#offer)').forEach((w) => w.classList.add('hidden'));
  $('#adminwin').classList.remove('hidden');
  renderAdmin();
}

function renderAdmin() {
  const d = AD.data;
  const e = d.economy;
  const kinds = arr(d.byKind);
  const models = arr(d.topModels);
  const dealers = arr(d.dealers);
  const moves = arr(d.bigMoves);
  const maxModel = Math.max(1, ...models.map((m) => m.c));
  const tile = (label, value, sub = '') => `<div class="tile"><div class="tile-label">${label}</div><div class="tile-value">${value}</div>${sub ? `<div class="tile-sub">${sub}</div>` : ''}</div>`;

  $('#ad-body').innerHTML = `
    <div class="tiles">
      ${tile('Vehicles sold', d.totals.count, fmtMoney(d.totals.revenue))}
      ${tile('Business funds (all owners)', fmtMoney(e.businessBalances), `${dealers.filter((x) => x.owned).length} of ${dealers.length} dealerships player-owned`)}
      ${tile('Finance outstanding', fmtMoney(e.finance.outstanding), `${e.finance.count} active contract${e.finance.count === 1 ? '' : 's'}`)}
      ${tile('Freight', `${e.logistics.waiting} waiting`, `${e.logistics.transit} in transit · ${e.logistics.hauls} active haul${e.logistics.hauls === 1 ? '' : 's'}`)}
      ${tile('Logistics company', e.company ? (e.company.owned ? fmtMoney(e.company.balance) : 'For sale') : 'Disabled', e.company && e.company.owned ? `${esc(e.company.ownerName)} · ${e.company.cut}% cut` : '')}
      <div class="tile">
        <div class="tile-label">Market event</div>
        <div class="tile-value small-value">${d.market ? esc(d.market.label) : 'None'}</div>
        <div class="inline" style="margin-top:8px">
          <select class="input sm" id="ad-event"><option value="random">Random event</option>${arr(d.events).map((ev) => `<option value="${esc(ev.id)}">${esc(ev.label)}</option>`).join('')}</select>
          <button class="btn sm" data-market="start">Start</button>
          ${d.market ? '<button class="btn sm danger" data-market="clear">End</button>' : ''}
        </div>
      </div>
    </div>

    <h3 class="section-title">Dealerships</h3>
    <div class="table-wrap"><table class="table">
      <thead><tr><th>Dealership</th><th>Owner</th><th>Sales</th><th>Revenue</th><th>Funds</th><th>Rep</th><th>Stock</th><th>Staff</th></tr></thead>
      <tbody>${dealers.map((x) => `<tr>
        <td><div class="row-title">${esc(x.label)}</div><div class="muted small mono">${esc(x.name)} · ${x.catalogue} models${x.used ? ` · ${x.used} pre-owned` : ''}</div></td>
        <td>${x.owned ? esc(x.ownerName) : '<span class="muted">State</span>'}</td>
        <td>${x.sales}</td>
        <td>${fmtMoney(x.revenue)}</td>
        <td>${x.balance != null ? `<span class="${x.balance < 0 ? 'neg' : ''}">${fmtMoney(x.balance)}</span>` : '—'}</td>
        <td>${x.reputation != null && x.owned ? x.reputation : '—'}</td>
        <td>${x.owned ? x.stock : '∞'}</td>
        <td>${x.staff}</td>
      </tr>`).join('') || '<tr class="empty-row"><td colspan="8">No dealerships yet.</td></tr>'}</tbody>
    </table></div>

    <div class="split" style="margin-top:14px">
      <div class="card-box">
        <h3 class="section-title flush">Top models</h3>
        ${models.length ? `<div class="leader">${models.map((m) => `<div class="leader-row"><div class="grow">
          <div class="leader-head"><span>${esc(m.label)}</span><span>${m.c} sold · ${fmtMoney(m.r)}</span></div>
          <div class="stat-bar"><span style="width:${(m.c / maxModel) * 100}%"></span></div></div></div>`).join('')}</div>` : '<div class="muted pad">No sales yet.</div>'}
        <h3 class="section-title">Sales channels</h3>
        ${kinds.length ? kinds.map((k) => `<div class="kv"><span>${esc(KIND_LABEL[k.kind] || k.kind)}</span><span>${k.c} · ${fmtMoney(k.r)}</span></div>`).join('') : '<div class="muted pad">No sales yet.</div>'}
      </div>
      <div class="card-box">
        <h3 class="section-title flush">Biggest money moves · 24h</h3>
        ${moves.length ? `<div class="tx-list">${moves.map((t) => `<div class="tx">
          <div class="grow"><div>${esc(t.description || t.type)}</div><div class="muted small">${esc(t.dealership)} · ${esc(t.actor || 'System')}</div></div>
          <div class="amount ${t.amount > 0 ? 'pos' : 'neg'}">${t.amount > 0 ? '+' : ''}${fmtMoney(t.amount)}</div></div>`).join('')}</div>` : '<div class="muted pad">Nothing yet.</div>'}
      </div>
    </div>`;
}

$('#ad-body').addEventListener('click', async (e) => {
  const b = e.target.closest('[data-market]');
  if (!b) return;
  const id = b.dataset.market === 'clear' ? 'clear' : $('#ad-event').value;
  const res = await post('adminMarket', { id });
  if (!res || !res.ok) return toast((res && res.error) || 'Failed.', 'error');
  AD.data = res;
  renderAdmin();
  toast(id === 'clear' ? 'Market event ended.' : 'Market event started.', 'success');
});

$('#ad-refresh').addEventListener('click', async () => {
  const res = await post('adminRefresh');
  if (!res || !res.ok) return toast((res && res.error) || 'Failed.', 'error');
  AD.data = res;
  renderAdmin();
});

$('#ad-creator').addEventListener('click', () => { closeAll(); post('adminCreator'); });

window.addEventListener('message', (e) => {
  if ((e.data || {}).action === 'openAdmin') openAdmin(e.data);
});

document.addEventListener('ui:closed', () => { AD.data = null; });
