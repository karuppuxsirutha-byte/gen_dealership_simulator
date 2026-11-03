'use strict';
/* Dealership simulator UI: management panel, customer negotiation, incoming offers.
   Relies on helpers from app.js ($, $$, post, esc, toast, askConfirm, fmtMoney, ...). */

const RANKS = { sales: 1, manager: 2, owner: 3 };
const ROLE_NAMES = { owner: 'Owner', manager: 'Manager', sales: 'Salesperson' };
const TX_LABEL = {
  sale: 'Sale', npc_sale: 'Walk-in sale', order: 'Stock order', commission: 'Commission', deposit: 'Deposit',
  withdraw: 'Withdrawal', upkeep: 'Upkeep', refund: 'Refund', delivery: 'Delivery', staff: 'Staff', price: 'Pricing', ownership: 'Ownership',
  freight: 'Freight', tradein: 'Trade-in', finance: 'Finance',
  wage: 'Wages', bonus: 'Bonus', advert: 'Advertising', shift: 'Shift',
};

const B = { data: null, tab: 'overview', nearby: [], receivedAt: 0 };

const canB = (min) => !!(B.data && RANKS[B.data.role] >= RANKS[min]);
const pct = (n) => `${Math.round(n)}%`;
function fmtDuration(sec) {
  sec = Math.max(0, Math.round(sec));
  const h = Math.floor(sec / 3600);
  const m = Math.floor((sec % 3600) / 60);
  const s = sec % 60;
  if (h) return `${h}h ${String(m).padStart(2, '0')}m`;
  return m ? `${m}m ${String(s).padStart(2, '0')}s` : `${s}s`;
}
function timeAgo(t) {
  const diff = Math.max(0, (B.data ? B.data.now : Date.now() / 1000) - t);
  if (diff < 60) return 'just now';
  if (diff < 3600) return `${Math.floor(diff / 60)}m ago`;
  if (diff < 86400) return `${Math.floor(diff / 3600)}h ago`;
  return `${Math.floor(diff / 86400)}d ago`;
}

async function bizAction(action, payload = {}) {
  const res = await post('bizAction', { action, payload });
  if (!res || !res.ok) {
    toast((res && res.error) || 'Action failed.', 'error');
    return null;
  }
  if (res.data) setManageData(res.data);
  if (res.message) toast(res.message, 'success');
  return res;
}

function setManageData(data) {
  B.data = data;
  B.data.vehicles = arr(data.vehicles);
  B.data.employees = arr(data.employees);
  B.data.orders = arr(data.orders);
  B.data.transactions = arr(data.transactions);
  B.data.used = arr(data.used);
  B.data.shifts = arr(data.shifts);
  B.data.leaderboard = arr(data.leaderboard);
  B.data.campaigns = arr(data.campaigns);
  B.data.stats.daily = arr(data.stats.daily);
  B.receivedAt = Date.now();
  renderManage();
}

/* ==========================================================================
   Management panel
   ========================================================================== */
const B_TABS = [
  { id: 'overview', label: 'Overview', min: 'sales' },
  { id: 'inventory', label: 'Inventory', min: 'sales' },
  { id: 'desk', label: 'Sales desk', min: 'sales' },
  { id: 'staff', label: 'Staff', min: 'sales' },
  { id: 'marketing', label: 'Marketing', min: 'manager' },
  { id: 'finance', label: 'Finance', min: 'manager' },
];

function openManage(msg) {
  setCategories(msg.categories);
  setCurrency(msg.currency);
  B.tab = 'overview';
  B.nearby = [];
  $$('.window:not(#offer)').forEach((w) => w.classList.add('hidden'));
  $('#manage').classList.remove('hidden');
  setManageData(msg.data);
}

function renderManage() {
  const d = B.data;
  if (!d) return;
  $('#b-title').textContent = d.label;
  $('#b-role').textContent = d.roleLabel || ROLE_NAMES[d.role] || '';
  const bal = $('#b-balance');
  bal.textContent = fmtMoney(d.balance);
  bal.style.color = d.balance < 0 ? 'var(--bad)' : '';

  $('#b-tabs').innerHTML = B_TABS.filter((t) => canB(t.min))
    .map((t) => `<button data-btab="${t.id}" class="${B.tab === t.id ? 'active' : ''}">${t.label}${t.id === 'desk' && d.customers ? ` <span class="badge warn">${d.customers}</span>` : ''}</button>`)
    .join('');

  const panes = { overview: paneOverview, inventory: paneInventory, desk: paneDesk, staff: paneStaff, marketing: paneMarketing, finance: paneFinance };
  $('#b-pane').innerHTML = (panes[B.tab] || paneOverview)(d);
}

$('#b-tabs').addEventListener('click', (e) => {
  const b = e.target.closest('[data-btab]');
  if (!b) return;
  B.tab = b.dataset.btab;
  renderManage();
});

/* ---------- overview ---------- */
function paneOverview(d) {
  const st = d.stats;
  const maxRev = Math.max(1, ...st.daily.map((x) => x.revenue));
  const repColor = d.reputation >= 66 ? 'var(--good)' : d.reputation >= 33 ? 'var(--warn)' : 'var(--bad)';
  const inStock = d.vehicles.reduce((n, v) => n + Math.max(0, v.stock), 0);
  const incoming = d.orders.reduce((n, o) => n + o.quantity, 0);

  const tile = (label, value, sub = '') => `<div class="tile"><div class="tile-label">${label}</div><div class="tile-value">${value}</div>${sub ? `<div class="tile-sub">${sub}</div>` : ''}</div>`;

  return `
    ${statusStrip(d)}
    ${marketBanner(d)}
    <div class="tiles">
      ${tile('Sales today', st.day.count, fmtMoney(st.day.revenue))}
      ${tile('Sales · 7 days', st.week.count, fmtMoney(st.week.revenue))}
      ${tile('Vehicles in stock', inStock, incoming ? `${incoming} on the way` : 'No pending orders')}
      ${tile('Staff on duty', d.onDuty, `${d.employees.length} on payroll`)}
      ${tile('Customers waiting', d.customers, d.settings.customersEnabled ? 'Walk up and press E' : 'AI customers disabled')}
      <div class="tile">
        <div class="tile-label">Reputation</div>
        <div class="tile-value">${d.reputation}<span class="muted small"> / 100</span></div>
        <div class="meter"><span style="width:${d.reputation}%;background:${repColor}"></span></div>
      </div>
    </div>

    <div class="split">
      <div class="card-box">
        <h3 class="section-title flush">Revenue · last 7 days</h3>
        <div class="bars">
          ${st.daily.map((x) => `<div class="bar-col" title="${x.count} sale(s) · ${fmtMoney(x.revenue)}">
            <div class="bar-val">${x.revenue ? fmtMoney(x.revenue) : ''}</div>
            <div class="bar" style="height:${Math.max(2, (x.revenue / maxRev) * 100)}%"></div>
            <div class="bar-label">${esc(x.label)}</div>
          </div>`).join('')}
        </div>
      </div>
      <div class="card-box">
        <h3 class="section-title flush">Recent activity</h3>
        ${txList(d.transactions.slice(0, 7))}
      </div>
    </div>
    <div class="split">
      <div class="card-box">
        <h3 class="section-title flush">Top sellers · this week</h3>
        ${leaderboard(d)}
      </div>
      <div class="card-box">
        <h3 class="section-title flush">Dealership ranking</h3>
        <div class="big-stat">${d.rank && d.rank.rank ? `#${d.rank.rank}<span class="muted small"> of ${d.rank.of}</span>` : '<span class="muted small">No sales this week yet</span>'}</div>
        ${d.target.count > 0 ? `<div class="stat-head"><span>Your weekly target</span><span>${d.target.mine} / ${d.target.count} sales</span></div>
          <div class="stat-bar"><span style="width:${Math.min(100, (d.target.mine / d.target.count) * 100)}%"></span></div>
          <p class="hint">Hit it to earn a ${fmtMoney(d.target.bonus)} bonus (staff only, once a week).</p>` : '<p class="hint">No weekly sales target set.</p>'}
      </div>
    </div>
    <p class="hint">Staff within ${Math.round(d.settings.dutyRadius)} m of the catalogue point count as on duty. Walk-in customers only show up while someone is on duty, and more often the better your reputation. Fair prices raise reputation; ignored or insulted customers lower it.</p>`;
}

function statusStrip(d) {
  const needClock = d.settings.requireClockIn;
  const shiftFor = d.clockedIn && d.shiftStarted ? fmtDuration(d.now - d.shiftStarted) : '';
  return `<div class="status-strip ${d.clockedIn ? 'on' : ''}">
    <span class="dot ${d.clockedIn ? 'on' : ''}"></span>
    <div class="grow">
      <div class="row-title">${d.clockedIn ? `Clocked in · ${shiftFor}` : d.clockedElsewhere ? 'Clocked in at another dealership' : 'Clocked out'}</div>
      <div class="muted small">${needClock ? 'Clock in to count as on duty, serve walk-in customers' : 'Being at the dealership counts as on duty'}${d.myWage ? ` and earn ${fmtMoney(d.myWage)}/h` : ''}.</div>
    </div>
    <button class="btn ${d.clockedIn ? '' : 'primary'}" data-clock ${d.clockedElsewhere ? 'disabled' : ''}>${d.clockedIn ? 'Clock out' : 'Clock in'}</button>
  </div>`;
}

function marketBanner(d) {
  const parts = [];
  if (d.market) {
    parts.push(`<div class="banner market"><b>📈 ${esc(d.market.label)}</b> <span class="muted">· ends in ${fmtDuration(d.market.endsIn)}</span>
      <div class="small">${esc(d.market.description)}</div>
      <div class="chips">${arr(d.market.effects).map((e) => `<span class="chip">${esc(e)}</span>`).join('')}</div></div>`);
  }
  if (d.ad) {
    parts.push(`<div class="banner ad"><b>📣 ${esc(d.ad.label)} running</b> <span class="muted">· +${d.ad.boost}% customer traffic · ${fmtDuration(d.ad.endsIn)} left</span></div>`);
  }
  return parts.join('');
}

function leaderboard(d) {
  if (!d.leaderboard.length) return '<div class="muted pad">No staff sales yet this week.</div>';
  const max = Math.max(...d.leaderboard.map((r) => r.revenue), 1);
  return `<div class="leader">${d.leaderboard.map((r, i) => `
    <div class="leader-row ${r.me ? 'me' : ''}">
      <span class="pos-n">${['🥇', '🥈', '🥉'][i] || `#${i + 1}`}</span>
      <div class="grow"><div class="leader-head"><span>${esc(r.name)}${r.me ? ' <span class="tag">you</span>' : ''}</span><span>${fmtMoney(r.revenue)} · ${r.count}</span></div>
      <div class="stat-bar"><span style="width:${(r.revenue / max) * 100}%"></span></div></div>
    </div>`).join('')}</div>`;
}

/* ---------- marketing ---------- */
function paneMarketing(d) {
  return `
    ${marketBanner(d) || '<div class="banner"><b>Market is calm</b> <span class="muted">· no special event right now</span></div>'}
    <h3 class="section-title">Advertising campaigns</h3>
    <p class="hint">Campaigns bring more walk-in customers while staff are on duty. Radio and billboard campaigns also broadcast your message to every player.</p>
    <label class="field"><span>Announcement message <em>radio / billboard · optional</em></span>
      <input class="input" id="ad-msg" maxlength="90" placeholder="Big deals today at ${esc(d.label)}! Come take a look."></label>
    <div class="campaigns">${d.campaigns.map((c) => `
      <div class="card-box campaign">
        <div class="row-title">${esc(c.label)}</div>
        <div class="big-price">${fmtMoney(c.cost)}</div>
        <div class="muted small">+${c.boost}% customer traffic · ${fmtDuration(c.duration)}${c.announce ? ' · server-wide announcement' : ''}</div>
        <button class="btn primary" data-advert="${esc(c.id)}" ${d.ad || d.balance < c.cost ? 'disabled' : ''}>${d.ad ? 'Campaign running' : d.balance < c.cost ? 'Not enough funds' : 'Launch'}</button>
      </div>`).join('')}</div>`;
}

function txList(list) {
  if (!list.length) return '<div class="muted pad">No activity yet.</div>';
  return `<div class="tx-list">${list.map((t) => `<div class="tx">
      <div class="grow"><div>${esc(t.description || TX_LABEL[t.type] || t.type)}</div>
      <div class="muted small">${esc(TX_LABEL[t.type] || t.type)}${t.actor ? ` · ${esc(t.actor)}` : ''} · ${timeAgo(t.t)}</div></div>
      ${t.amount ? `<div class="amount ${t.amount > 0 ? 'pos' : 'neg'}">${t.amount > 0 ? '+' : ''}${fmtMoney(t.amount)}</div>` : ''}
    </div>`).join('')}</div>`;
}

/* ---------- inventory ---------- */
function freightStatus(f) {
  const parts = [];
  if (f.transit) parts.push(`<span class="pos">${f.transit} on the road</span>${arr(f.drivers).length ? ` <span class="muted">(${arr(f.drivers).map(esc).join(', ')})</span>` : ''}`);
  if (f.waiting) parts.push(`${f.waiting} waiting at the depot${f.autoIn != null ? ` · NPC freight in <span data-eta="${f.autoIn}" data-eta-prefix="">${fmtDuration(f.autoIn)}</span>` : ''}`);
  return `<div class="small right">${parts.join('<br>')}</div>`;
}

function paneInventory(d) {
  const mgr = canB('manager');
  const rows = d.vehicles.map((v) => {
    const margin = v.cost > 0 ? ((v.price - v.cost) / v.cost) * 100 : 0;
    return `<tr data-vid="${v.id}">
      <td><div class="row-title">${esc(v.label)}</div><div class="muted small mono">${esc(v.model)}</div></td>
      <td><span class="stock-pill ${v.stock > 0 ? 'ok' : 'empty'}">${Math.max(0, v.stock)}</span>${v.incoming ? ` <span class="muted small">+${v.incoming}</span>` : ''}</td>
      <td>${fmtMoney(v.cost)}</td>
      <td>${mgr
        ? `<input class="input sm" type="number" data-price min="${v.minPrice}" max="${v.maxPrice}" value="${v.price}" title="${fmtMoney(v.minPrice)} – ${fmtMoney(v.maxPrice)}">`
        : fmtMoney(v.price)}</td>
      <td class="${margin >= 0 ? 'pos' : 'neg'}">${pct(margin)}</td>
      ${mgr ? `<td class="nowrap"><input class="input sm qty" type="number" data-qty min="1" max="${d.settings.maxOrderQty}" value="1">
        <button class="btn sm" data-order title="Order at ${fmtMoney(v.cost)} each">Order</button></td>` : ''}
    </tr>`;
  }).join('');

  const orders = d.orders.length
    ? d.orders.map((o) => `<div class="tx"><div class="grow">${o.remaining < o.quantity ? `${o.remaining} of ${o.quantity}` : o.quantity}× ${esc(o.label)}<div class="muted small">${fmtMoney(o.cost)}</div></div>
        ${o.freight ? freightStatus(o.freight) : `<div class="muted small" data-eta="${o.eta}">arrives in ${fmtDuration(o.eta)}</div>`}</div>`).join('')
    : '<div class="muted pad">No pending orders.</div>';

  return `
    ${mgr ? `<p class="hint">Restock by ordering at wholesale cost from business funds. ${d.settings.logistics
        ? `Each vehicle waits at <b>${esc(d.settings.depotLabel)}</b> until a logistics driver (or your own staff) hauls it here, for a ${fmtMoney(d.settings.freightFee)} freight fee per vehicle.${d.settings.autoDeliverAfter ? ` Unclaimed shipments arrive by NPC freight after ${fmtDuration(d.settings.autoDeliverAfter)}.` : ''}`
        : `Deliveries arrive after ${fmtDuration(d.settings.deliveryTime)}.`} Prices can be set between ${Math.round(d.settings.minMarkup * 100)}% and ${Math.round(d.settings.maxMarkup * 100)}% of cost.</p>` : ''}
    <div class="table-wrap">
      <table class="table">
        <thead><tr><th>Vehicle</th><th>Stock</th><th>Cost</th><th>Price</th><th>Margin</th>${mgr ? '<th>Restock</th>' : ''}</tr></thead>
        <tbody id="inv-body">${rows || `<tr class="empty-row"><td colspan="6">This dealership has no vehicles in its catalogue.</td></tr>`}</tbody>
      </table>
    </div>
    <h3 class="section-title">Incoming deliveries</h3>
    <div class="card-box">${orders}</div>
    ${usedTable(d, mgr)}`;
}

function usedTable(d, mgr) {
  const used = arr(d.used);
  if (!used.length) return '';
  return `<h3 class="section-title">Pre-owned lot</h3>
    <div class="table-wrap"><table class="table">
      <thead><tr><th>Vehicle</th><th>Condition</th><th>Source</th><th>Paid</th><th>Price</th></tr></thead>
      <tbody>${used.map((u) => `<tr data-uid="${u.id}">
        <td><div class="row-title">${esc(u.label)}</div><div class="muted small mono">${esc(u.model)}</div></td>
        <td>${u.condition}%</td>
        <td><span class="chip">${u.source === 'repo' ? 'Repossession' : 'Trade-in'}</span></td>
        <td>${fmtMoney(u.value)}</td>
        <td>${mgr ? `<input class="input sm" type="number" data-uprice min="100" value="${u.price}">` : fmtMoney(u.price)}</td>
      </tr>`).join('')}</tbody>
    </table></div>`;
}

$('#b-pane').addEventListener('change', (e) => {
  const usedInput = e.target.closest('[data-uprice]');
  if (usedInput) {
    bizAction('setUsedPrice', { id: Number(usedInput.closest('[data-uid]').dataset.uid), price: Number(usedInput.value) });
    return;
  }
  const priceInput = e.target.closest('[data-price]');
  if (priceInput) {
    const vid = Number(priceInput.closest('[data-vid]').dataset.vid);
    bizAction('setPrice', { vehicleId: vid, price: Number(priceInput.value) });
  }
});

/* ---------- sales desk ---------- */
function paneDesk(d) {
  const inStock = d.vehicles.filter((v) => v.stock > 0);
  const players = B.nearby.map((p) => `<option value="${p.id}">${esc(p.name)} (#${p.id})</option>`).join('');
  const first = inStock[0];
  return `
    <div class="split">
      <div class="card-box">
        <h3 class="section-title flush">Sell to a player</h3>
        ${inStock.length ? `
        <div class="stack">
          <label class="field"><span>Vehicle</span>
            <select class="input" id="desk-vehicle">${inStock.map((v) => `<option value="${v.id}">${esc(v.label)} · ${v.stock} in stock</option>`).join('')}</select>
          </label>
          <label class="field"><span>Price <em id="desk-range">${first ? `${fmtMoney(first.minPrice)} – ${fmtMoney(first.maxPrice)}` : ''}</em></span>
            <input class="input" type="number" id="desk-price" value="${first ? first.price : ''}">
          </label>
          <label class="field"><span>Customer <em>players within 10 m</em></span>
            <div class="inline">
              <select class="input" id="desk-target">${players || '<option value="">Nobody nearby (press refresh)</option>'}</select>
              <button class="btn" data-refresh-nearby>Refresh</button>
            </div>
          </label>
          <div class="inline">
            <span class="muted small grow">${d.myCommission ? `Your commission: ${d.myCommission}%` : d.role === 'owner' ? 'Revenue goes to the business account.' : ''}</span>
            <button class="btn primary" data-send-offer>Send offer</button>
          </div>
        </div>` : '<div class="muted pad">Nothing in stock. A manager needs to order vehicles first.</div>'}
      </div>
      <div class="card-box">
        <h3 class="section-title flush">Walk-in customers</h3>
        <div class="big-stat">${d.customers}</div>
        <p class="muted">${d.customers === 1 ? 'customer is' : 'customers are'} browsing the lot right now.</p>
        <p class="hint">Find them near the display cars and press <b>E</b> to start haggling. Each customer has a hidden budget: ask too much and they'll walk away, and an insulting price costs you reputation. You get ${d.myCommission || 0}% commission on every deal you close.</p>
      </div>
    </div>`;
}

$('#b-pane').addEventListener('input', (e) => {
  if (e.target.id === 'desk-vehicle') {
    const v = B.data.vehicles.find((x) => x.id === Number(e.target.value));
    if (v) {
      $('#desk-price').value = v.price;
      $('#desk-range').textContent = `${fmtMoney(v.minPrice)} – ${fmtMoney(v.maxPrice)}`;
    }
  }
});

async function refreshNearby() {
  const res = await bizAction('nearby');
  if (!res) return;
  B.nearby = arr(res.players);
  renderManage();
  if (!B.nearby.length) toast('No players within 10 m.', 'info');
}

/* ---------- staff ---------- */
function paneStaff(d) {
  const owner = d.role === 'owner';
  const mgr = canB('manager');
  const rows = d.employees.map((e) => {
    const editable = owner && e.role !== 'owner';
    const canFire = e.role !== 'owner' && (owner || (mgr && e.role === 'sales'));
    const status = e.onDuty ? '<span class="dot on"></span>On duty' : e.clockedIn ? '<span class="dot idle"></span>Clocked in (away)' : e.online ? '<span class="dot idle"></span>Online' : '<span class="dot"></span>Offline';
    return `<tr data-ident="${esc(e.identifier)}">
      <td><div class="row-title">${esc(e.name)}${e.me ? ' <span class="tag">you</span>' : ''}</div></td>
      <td>${editable ? `<select class="input sm" data-erole>
          <option value="sales" ${e.role === 'sales' ? 'selected' : ''}>Salesperson</option>
          <option value="manager" ${e.role === 'manager' ? 'selected' : ''}>Manager</option></select>` : esc(e.roleLabel)}</td>
      <td>${e.role === 'owner' ? '—' : editable
        ? `<input class="input sm qty" type="number" min="0" max="${d.settings.maxCommission}" data-ecomm value="${e.commission}"> %`
        : `${e.commission}%`}</td>
      <td>${e.role === 'owner' ? '—' : editable
        ? `<input class="input sm qty wide" type="number" min="0" max="${d.settings.maxWage}" data-ewage value="${e.wage}"> /h`
        : `${fmtMoney(e.wage)}/h`}</td>
      <td class="nowrap small">${status}</td>
      <td>${canFire ? '<button class="btn ghost sm danger-text" data-fire>Let go</button>' : ''}</td>
    </tr>`;
  }).join('');

  const players = B.nearby.map((p) => `<option value="${p.id}">${esc(p.name)} (#${p.id})</option>`).join('');
  return `
    <div class="table-wrap">
      <table class="table">
        <thead><tr><th>Name</th><th>Role</th><th>Commission</th><th>Wage</th><th>Status</th><th></th></tr></thead>
        <tbody>${rows}</tbody>
      </table>
    </div>
    ${mgr ? `
    <h3 class="section-title">Hire</h3>
    <div class="add-row">
      <select class="input" id="hire-target">${players || '<option value="">Nobody nearby (press refresh)</option>'}</select>
      <button class="btn" data-refresh-nearby>Refresh</button>
      <select class="input" id="hire-role" style="flex:0 0 160px">
        <option value="sales">Salesperson</option>
        ${owner ? '<option value="manager">Manager</option>' : ''}
      </select>
      <button class="btn primary" data-hire>Hire</button>
    </div>
    <p class="hint">Stand next to the player you want to hire (within 10 m). Up to ${d.settings.maxEmployees} employees. Managers can restock, set prices and hire salespeople. Commission is paid from business funds on every sale the employee closes; wages are paid while they're clocked in at the dealership.</p>` : ''}
    ${owner ? `<h3 class="section-title">Weekly sales target</h3>
    <div class="add-row">
      <label class="field grow"><span>Sales per week</span><input class="input" type="number" min="0" id="tgt-count" value="${d.target.count}"></label>
      <label class="field grow"><span>Bonus</span><input class="input" type="number" min="0" id="tgt-bonus" value="${d.target.bonus}"></label>
      <button class="btn primary" data-target style="align-self:flex-end">Save target</button>
    </div>
    <p class="hint">Every employee who closes this many sales in a week (Monday to Sunday) gets the bonus once, paid from business funds. Set 0 to disable.</p>` : ''}
    <h3 class="section-title">Recent shifts</h3>
    <div class="card-box">${d.shifts.length ? `<div class="tx-list">${d.shifts.map((sh) => `<div class="tx">
        <div class="grow"><div>${esc(sh.name)}${sh.active ? ' <span class="chip good">on shift</span>' : ''}</div>
        <div class="muted small">${timeAgo(sh.started)} · ${fmtDuration(sh.duration)}</div></div>
        <div class="amount pos">${sh.earned ? fmtMoney(sh.earned) : ''}</div></div>`).join('')}</div>` : '<div class="muted pad">No shifts yet.</div>'}</div>`;
}

/* ---------- finance ---------- */
function paneFinance(d) {
  const owner = d.role === 'owner';
  return `
    <div class="split">
      <div class="card-box">
        <h3 class="section-title flush">Business account</h3>
        <div class="big-stat ${d.balance < 0 ? 'neg' : ''}">${fmtMoney(d.balance)}</div>
        <div class="stack">
          <div class="inline"><input class="input" type="number" min="1" id="fin-dep" placeholder="Amount"><button class="btn" data-deposit>Deposit from bank</button></div>
          ${owner ? '<div class="inline"><input class="input" type="number" min="1" id="fin-wd" placeholder="Amount"><button class="btn" data-withdraw>Withdraw to bank</button></div>' : ''}
        </div>
        ${d.settings.upkeep > 0 ? `<p class="hint">Upkeep: ${fmtMoney(d.settings.upkeep)} every ${fmtDuration(d.settings.upkeepInterval)}.</p>` : ''}
        ${owner ? `<h3 class="section-title">Sell business</h3>
          <p class="hint">Sell ${esc(d.label)} back for <b>${fmtMoney(d.settings.sellBack)}</b>, plus whatever is left in the account. All staff are let go.</p>
          <button class="btn danger" data-sell>Sell business</button>` : ''}
      </div>
      <div class="card-box">
        <h3 class="section-title flush">Transactions</h3>
        <div class="scroll-list">${txList(d.transactions)}</div>
      </div>
    </div>`;
}

/* ---------- panel actions ---------- */
$('#b-pane').addEventListener('click', async (e) => {
  const t = e.target;
  const d = B.data;
  if (!d) return;

  if (t.closest('[data-clock]')) {
    bizAction('clock');
  } else if (t.closest('[data-target]')) {
    bizAction('setTarget', { count: Number($('#tgt-count').value), bonus: Number($('#tgt-bonus').value) });
  } else if (t.closest('[data-advert]')) {
    const id = t.closest('[data-advert]').dataset.advert;
    const c = d.campaigns.find((x) => x.id === id);
    if (await askConfirm(`Launch ${c.label}?`, `${fmtMoney(c.cost)} from business funds for ${fmtDuration(c.duration)} of extra customer traffic.`, 'Launch')) {
      bizAction('advertise', { id, message: $('#ad-msg').value });
    }
  } else if (t.closest('[data-order]')) {
    const row = t.closest('[data-vid]');
    const v = d.vehicles.find((x) => x.id === Number(row.dataset.vid));
    const qty = Math.max(1, Math.floor(Number(row.querySelector('[data-qty]').value) || 1));
    const fee = d.settings.logistics ? d.settings.freightFee * qty : 0;
    const ok = await askConfirm(`Order ${qty}× ${v.label}?`, `${fmtMoney(v.cost * qty + fee)} will be taken from business funds${fee ? ` (${fmtMoney(v.cost * qty)} stock + ${fmtMoney(fee)} freight)` : ''}.`, 'Order');
    if (ok) bizAction('order', { vehicleId: v.id, quantity: qty });
  } else if (t.closest('[data-refresh-nearby]')) {
    refreshNearby();
  } else if (t.closest('[data-send-offer]')) {
    const target = Number($('#desk-target').value);
    if (!target) return toast('Choose a customer first (press Refresh).', 'error');
    bizAction('offer', { vehicleId: Number($('#desk-vehicle').value), price: Number($('#desk-price').value), target });
  } else if (t.closest('[data-hire]')) {
    const target = Number($('#hire-target').value);
    if (!target) return toast('Choose a player first (press Refresh).', 'error');
    bizAction('hire', { target, role: $('#hire-role').value });
  } else if (t.closest('[data-fire]')) {
    const ident = t.closest('[data-ident]').dataset.ident;
    const emp = d.employees.find((x) => x.identifier === ident);
    if (await askConfirm(`Let ${emp.name} go?`, 'They lose access to this dealership immediately.', 'Let go', true)) {
      bizAction('fire', { identifier: ident });
    }
  } else if (t.closest('[data-deposit]')) {
    bizAction('deposit', { amount: Number($('#fin-dep').value) });
  } else if (t.closest('[data-withdraw]')) {
    bizAction('withdraw', { amount: Number($('#fin-wd').value) });
  } else if (t.closest('[data-sell]')) {
    const ok = await askConfirm(`Sell ${d.label}?`, `You receive ${fmtMoney(d.settings.sellBack + Math.max(0, d.balance))}. This can't be undone.`, 'Sell business', true);
    if (ok) {
      const res = await post('bizAction', { action: 'sellBusiness', payload: {} });
      if (!res || !res.ok) toast((res && res.error) || 'Failed.', 'error');
    }
  }
});

$('#b-pane').addEventListener('change', (e) => {
  const row = e.target.closest('[data-ident]');
  if (!row) return;
  if (!(e.target.matches('[data-erole]') || e.target.matches('[data-ecomm]') || e.target.matches('[data-ewage]'))) return;
  bizAction('updateEmployee', {
    identifier: row.dataset.ident,
    role: row.querySelector('[data-erole]').value,
    commission: Number(row.querySelector('[data-ecomm]').value),
    wage: Number(row.querySelector('[data-ewage]').value),
  });
});

// live countdown for deliveries
setInterval(() => {
  if (!B.data || $('#manage').classList.contains('hidden')) return;
  const elapsed = (Date.now() - B.receivedAt) / 1000;
  $$('[data-eta]').forEach((el) => {
    const left = Number(el.dataset.eta) - elapsed;
    const prefix = el.dataset.etaPrefix ?? 'arrives in ';
    el.textContent = left > 0 ? `${prefix}${fmtDuration(left)}` : 'arriving…';
  });
}, 1000);

/* ==========================================================================
   Negotiation with an AI customer
   ========================================================================== */
const N = { data: null, busy: false };

function openNegotiation(msg) {
  setCurrency(msg.currency);
  N.data = msg.data;
  N.busy = false;
  $$('.window:not(#offer)').forEach((w) => w.classList.add('hidden'));
  $('#nego').classList.remove('hidden');
  renderNego();
}

function renderNego() {
  const n = N.data;
  const initials = n.name.split(' ').map((p) => p[0]).join('').slice(0, 2);
  const done = n.state === 'sold' || n.state === 'left';
  const margin = n.cost > 0 ? (((n.price || n.offer) - n.cost) / n.cost) * 100 : 0;

  $('#n-body').innerHTML = `
    <div class="person">
      <div class="avatar">${esc(initials)}</div>
      <div class="grow"><div class="row-title">${esc(n.name)}</div><div class="muted small">Interested in <b>${esc(n.label)}</b></div></div>
      ${!done ? `<div class="rounds">${Array.from({ length: n.maxRounds }, (_, i) => `<span class="${i < n.round ? 'used' : ''}"></span>`).join('')}</div>` : ''}
    </div>
    <div class="speech ${n.state}">“${esc(n.line || '')}”</div>
    <div class="kv"><span>List price</span><span>${fmtMoney(n.listPrice)}</span></div>
    <div class="kv"><span>Dealer cost</span><span>${fmtMoney(n.cost)}</span></div>
    ${n.commission ? `<div class="kv"><span>Your commission</span><span>${n.commission}%</span></div>` : ''}
    ${n.state === 'sold' ? `
      <div class="result good">Sold for <b>${fmtMoney(n.price)}</b>${n.commissionPaid ? ` · you earned ${fmtMoney(n.commissionPaid)}` : ''}<div class="small">${pct(margin)} margin over cost</div></div>
      <button class="btn primary block" data-nclose>Close</button>`
    : n.state === 'left' ? `
      <div class="result bad">The customer walked away.</div>
      <button class="btn block" data-nclose>Close</button>`
    : `
      <div class="offer-line"><span class="muted">Their offer</span><span class="big-price">${fmtMoney(n.offer)}</span></div>
      <div class="inline">
        <input class="input" type="number" id="n-counter" placeholder="Your counter-offer" value="${Math.round(Math.max(n.offer, n.listPrice) / 100) * 100}">
        <button class="btn" data-ncounter ${N.busy ? 'disabled' : ''}>Counter</button>
      </div>
      <div class="inline">
        <button class="btn danger grow" data-ndecline ${N.busy ? 'disabled' : ''}>Decline</button>
        <button class="btn primary grow" data-naccept ${N.busy ? 'disabled' : ''}>Accept ${fmtMoney(n.offer)}</button>
      </div>`}`;
}

async function negotiate(action, amount) {
  if (N.busy || !N.data) return;
  N.busy = true;
  renderNego();
  const res = await post('negRespond', { id: N.data.id, action, amount });
  N.busy = false;
  if (!N.data) return;
  if (!res || !res.ok) {
    toast((res && res.error) || 'The customer left.', 'error');
    N.data.state = 'left';
    N.data.line = (res && res.error) || '';
  } else {
    N.data = Object.assign(N.data, res);
  }
  renderNego();
}

$('#n-body').addEventListener('click', (e) => {
  if (e.target.closest('[data-naccept]')) negotiate('accept');
  else if (e.target.closest('[data-ndecline]')) negotiate('decline');
  else if (e.target.closest('[data-ncounter]')) negotiate('counter', Number($('#n-counter').value));
  else if (e.target.closest('[data-nclose]')) { closeAll(); post('close'); }
});
$('#n-body').addEventListener('keydown', (e) => {
  if (e.key === 'Enter' && e.target.id === 'n-counter') negotiate('counter', Number(e.target.value));
});

/* ==========================================================================
   Incoming offer from a salesperson
   ========================================================================== */
const O = { offer: null, method: 'bank', deadline: 0, timer: null, busy: false };

function openOffer(msg) {
  setCurrency(msg.currency);
  O.offer = msg.offer;
  const methods = arr(msg.offer.payment);
  O.method = methods[0] || 'bank';
  O.deadline = Date.now() + (msg.offer.timeout || 60) * 1000;
  O.busy = false;
  $('#offer').classList.remove('hidden');
  renderOffer();
  clearInterval(O.timer);
  O.timer = setInterval(tickOffer, 500);
  tickOffer();
}

function tickOffer() {
  if (!O.offer) return;
  const left = Math.ceil((O.deadline - Date.now()) / 1000);
  $('#o-timer').textContent = `${Math.max(0, left)}s`;
  if (left <= 0) respondOffer(false);
}

function renderOffer() {
  const o = O.offer;
  const methods = arr(o.payment);
  $('#o-body').innerHTML = `
    <div class="thumb">${thumb(o.model)}</div>
    <div><h2 class="flush">${esc(o.label)}</h2><div class="muted small">${esc(o.sellerName)} at ${esc(o.dealership)} is offering you this vehicle.</div></div>
    <div class="big-price">${fmtMoney(o.price)}</div>
    ${methods.length > 1 ? `<div class="seg">${methods.map((m) => `<button class="btn ${O.method === m ? 'active' : ''}" data-omethod="${esc(m)}">${m === 'cash' ? 'Cash' : 'Bank'}</button>`).join('')}</div>` : ''}
    <div class="inline">
      <button class="btn danger grow" data-odecline ${O.busy ? 'disabled' : ''}>Decline</button>
      <button class="btn primary grow" data-oaccept ${O.busy ? 'disabled' : ''}>Accept & pay</button>
    </div>`;
}

async function respondOffer(accept) {
  if (!O.offer || O.busy) return;
  O.busy = true;
  renderOffer();
  const id = O.offer.id;
  clearInterval(O.timer);
  const res = await post('offerRespond', { id, accept, method: O.method });
  O.offer = null;
  $('#offer').classList.add('hidden');
  if (accept && (!res || !res.ok)) toast((res && res.error) || 'Purchase failed.', 'error');
  else if (!accept) toast('Offer declined.', 'info');
}

$('#o-body').addEventListener('click', (e) => {
  const m = e.target.closest('[data-omethod]');
  if (m) { O.method = m.dataset.omethod; return renderOffer(); }
  if (e.target.closest('[data-oaccept]')) respondOffer(true);
  else if (e.target.closest('[data-odecline]')) respondOffer(false);
});

document.addEventListener('keydown', (e) => {
  if (e.key === 'Escape' && O.offer && $('#modal').classList.contains('hidden')) respondOffer(false);
});

/* ==========================================================================
   Messages & lifecycle
   ========================================================================== */
window.addEventListener('message', (e) => {
  const msg = e.data || {};
  switch (msg.action) {
    case 'openManage': openManage(msg); break;
    case 'openNegotiation': openNegotiation(msg); break;
    case 'openOffer': openOffer(msg); break;
    default: break;
  }
});

document.addEventListener('ui:closed', () => {
  B.data = null;
  N.data = null;
  if (O.offer) { clearInterval(O.timer); O.offer = null; }
});
