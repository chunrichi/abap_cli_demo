/**
 * pages/requests.js — 请求 CR 列表：服务端筛选 / 排序 / 分页，筛选写入 URL。
 */

import { api, describeError, downloadCsv } from '../api.js';
import * as ui from '../ui.js';
import { filterBar, bindFilterBar, queryValues } from '../components/form.js';
import { table, bindSort, bindRowLinks, pager, bindPager } from '../components/table.js';

const STATUS_OPTIONS = [
  { value: '', label: '全部状态' },
  { value: 'NEW', label: '新建' },
  { value: 'PENDING_APPROVAL', label: '待审批' },
  { value: 'REJECTED', label: '已拒绝' },
  { value: 'APPROVED', label: '已批准' },
  { value: 'IN_PROGRESS', label: '进行中' },
  { value: 'CLOSED', label: '已关闭' },
  { value: 'CANCELLED', label: '已取消' }
];

const TYPE_OPTIONS = [
  { value: '', label: '全部类型' },
  { value: 'STD', label: '标准变更' },
  { value: 'URG', label: '紧急变更' },
  { value: 'ADM', label: '管理变更' }
];

const PRIORITY_OPTIONS = [
  { value: '', label: '全部优先级' },
  { value: '1', label: '紧急' },
  { value: '2', label: '高' },
  { value: '3', label: '中' },
  { value: '4', label: '低' }
];

function buildFilters(cycles) {
  const cycleOptions = [{ value: '', label: '全部周期' }].concat(
    cycles.map((cycle) => ({ value: cycle.id, label: cycle.id + (cycle.description ? ' · ' + cycle.description : '') }))
  );
  return [
    { name: 'q', label: '关键词', type: 'text', placeholder: '标题模糊搜索' },
    { name: 'status', label: '状态', type: 'select', options: STATUS_OPTIONS },
    { name: 'requestType', label: '类型', type: 'select', options: TYPE_OPTIONS },
    { name: 'priority', label: '优先级', type: 'select', options: PRIORITY_OPTIONS },
    { name: 'component', label: '组件', type: 'text', placeholder: '如 MM-PUR' },
    { name: 'cycleId', label: '周期', type: 'select', options: cycleOptions },
    { name: 'owner', label: '负责人', type: 'text', placeholder: 'SAP 用户名' },
    { name: 'requester', label: '请求人', type: 'text', placeholder: 'SAP 用户名' }
  ];
}

function columns() {
  return [
    {
      key: 'displayId',
      label: '编号',
      sortable: true,
      width: '116px',
      render: (row) => `<span class="mono">${ui.esc(row.displayId || row.id)}</span>`
    },
    {
      key: 'title',
      label: '标题',
      sortable: true,
      flex: true,
      minWidth: 220,
      ellipsis: true,
      render: (row) =>
        `<a class="row-title" href="#/requests/${encodeURIComponent(row.id)}" title="${ui.esc(row.title || '')}">${ui.esc(
          ui.truncate(row.title, 70)
        )}</a>`
    },
    { key: 'requestType', label: '类型', width: '110px', render: (row) => ui.requestTypeBadge(row.requestType) },
    { key: 'status', label: '状态', sortable: true, width: '130px', render: (row) => ui.statusBadge(row.status) },
    { key: 'priority', label: '优先级', sortable: true, width: '110px', render: (row) => ui.priorityBadge(row.priority) },
    { key: 'component', label: '组件', width: '104px', render: (row) => ui.safe(row.component) },
    { key: 'owner', label: '负责人', width: '118px', render: (row) => ui.safe(row.owner) },
    {
      key: 'dueDate',
      label: '截止日',
      sortable: true,
      width: '110px',
      render: (row) => {
        const overdue = ui.isOverdue(row.dueDate) && row.status !== 'CLOSED' && row.status !== 'CANCELLED';
        return `<span class="nowrap"${overdue ? ' style="color:var(--danger);font-weight:600"' : ''}>${ui.fmtDate(
          row.dueDate
        )}</span>`;
      }
    },
    {
      key: 'changedAt',
      label: '更新时间',
      sortable: true,
      width: '150px',
      render: (row) => `<span class="nowrap" title="${ui.esc(ui.fmtDateTime(row.changedAt))}">${ui.fmtDateTime(row.changedAt)}</span>`
    }
  ];
}

export async function mount(root, ctx) {
  const query = ctx.query || {};
  const page = Math.max(1, Number(query.page) || 1);
  const size = Math.max(1, Number(query.size) || 50);
  const sort = query.sort || 'createdAt';
  const order = query.order === 'asc' ? 'asc' : 'desc';

  let cycles = [];
  try {
    const raw = await api.get('/config/cycles');
    cycles = ui.listOf(raw);
  } catch (err) {
    cycles = [];
  }

  const fields = buildFilters(cycles);
  const values = queryValues(fields, query);

  root.innerHTML = `<div class="page">
    ${ui.pageHeader({
      title: '请求 CR',
      subtitle: '变更请求列表，按状态、类型与责任人筛选',
      breadcrumb: [{ label: '工作台', href: '#/dashboard' }, { label: '请求 CR' }],
      actions: `
        <button type="button" class="btn btn-sm" data-action="export">${ui.icon('download', 15)}导出 CSV</button>
        <button type="button" class="btn btn-sm" data-action="refresh" title="刷新列表">${ui.icon('refresh', 15)}刷新</button>
        <a class="btn btn-primary btn-sm" href="#/requests/new">${ui.icon('plus', 15)}新建请求</a>`
    })}
    <div class="panel">
      ${filterBar(fields, values)}
      <div data-list-body>${ui.loadingPanel('正在加载请求…')}</div>
      <div data-pager></div>
    </div>
  </div>`;

  const body = root.querySelector('[data-list-body]');
  const pagerEl = root.querySelector('[data-pager]');

  bindFilterBar(root, ctx, fields);
  bindSort(root, ctx, { sortKey: sort, sortOrder: order });
  bindRowLinks(root, ctx);
  bindPager(root, ctx);
  ui.bindOnce(root, 'requests', () => [
    ui.delegate(root, '[data-action="new-request"]', 'click', () => ctx.navigate('#/requests/new')),
    ui.delegate(root, '[data-action="retry"]', 'click', () => load()),
    ui.delegate(root, '[data-action="refresh"]', 'click', () => load()),
    ui.delegate(root, '[data-action="export"]', 'click', async (event, el) => {
      ui.setBusy(el, true, '导出中…');
      try {
        await downloadCsv('requests', {
          status: query.status,
          requestType: query.requestType,
          priority: query.priority,
          component: query.component,
          cycleId: query.cycleId,
          owner: query.owner,
          requester: query.requester,
          q: query.q
        });
        ui.toast('已开始下载 CSV。', { type: 'success' });
      } catch (err) {
        const info = describeError(err);
        ui.toast(info.message, { title: info.title, type: 'error', correlationId: info.correlationId });
      } finally {
        ui.setBusy(el, false);
      }
    })
  ]);

  async function load() {
    if (!body) return;
    body.innerHTML = ui.skeletonTable(8, 6);
    if (pagerEl) pagerEl.innerHTML = '';
    try {
      const data = await api.get('/requests', {
        page,
        size,
        sort,
        order,
        status: query.status,
        requestType: query.requestType,
        priority: query.priority,
        component: query.component,
        cycleId: query.cycleId,
        owner: query.owner,
        requester: query.requester,
        q: query.q
      });
      const rows = ui.listOf(data);
      const total = data && data.total !== undefined ? Number(data.total) : rows.length;
      const pageData = {
        page: (data && data.page) || page,
        pageSize: (data && data.pageSize) || size,
        total
      };
      body.innerHTML = table({
        columns: columns(),
        rows,
        sortKey: sort,
        sortOrder: order,
        rowHref: (row) => '#/requests/' + encodeURIComponent(row.id),
        emptyOptions: {
          icon: 'request',
          title: '还没有符合条件的请求',
          hint: '调整筛选条件，或创建一个新的变更请求。',
          actionLabel: '新建请求',
          action: 'new-request'
        }
      });
      if (pagerEl) pagerEl.innerHTML = pager(root, ctx, pageData, { hideIfEmpty: false });
      bindSort(root, ctx, { sortKey: sort, sortOrder: order });
      bindRowLinks(root, ctx);
      bindPager(root, ctx);
    } catch (err) {
      const info = describeError(err);
      const isForbidden = err && (err.status === 403 || err.code === 'FORBIDDEN');
      body.innerHTML = ui.errorPanel({
        title: info.title,
        message: isForbidden ? '当前角色没有查看请求列表的权限。' : info.message,
        correlationId: info.correlationId
      });
    }
  }

  await load();
  return () => ui.releaseOnce(root, 'requests');
}
