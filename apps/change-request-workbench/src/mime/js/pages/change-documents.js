/**
 * pages/change-documents.js — 变更文档 CD 列表：服务端筛选 / 排序 / 分页。
 */

import { api, describeError } from '../api.js';
import * as ui from '../ui.js';
import { filterBar, bindFilterBar, queryValues } from '../components/form.js';
import { table, bindSort, bindRowLinks, pager, bindPager } from '../components/table.js';

const STATUS_OPTIONS = [
  { value: '', label: '全部状态' },
  { value: 'NEW', label: '新建' },
  { value: 'IN_DEV', label: '开发中' },
  { value: 'IN_TEST', label: '测试中' },
  { value: 'READY_TO_IMPORT', label: '待导入' },
  { value: 'IMPORT_SCHEDULED', label: '已计划导入' },
  { value: 'IMPORTED', label: '已导入' },
  { value: 'CLOSED', label: '已关闭' },
  { value: 'CANCELLED', label: '已取消' }
];

const TARGET_OPTIONS = [
  { value: '', label: '全部目标系统' },
  { value: 'QAS', label: 'QAS' },
  { value: 'PRD', label: 'PRD' },
  { value: 'DEV', label: 'DEV' }
];

function buildFilters(cycles) {
  return [
    { name: 'q', label: '关键词', type: 'text', placeholder: '标题模糊搜索' },
    { name: 'status', label: '状态', type: 'select', options: STATUS_OPTIONS },
    {
      name: 'cycleId',
      label: '周期',
      type: 'select',
      options: [{ value: '', label: '全部周期' }].concat(
        cycles.map((cycle) => ({ value: cycle.id, label: cycle.id + (cycle.description ? ' · ' + cycle.description : '') }))
      )
    },
    { name: 'targetSystem', label: '目标系统', type: 'select', options: TARGET_OPTIONS },
    { name: 'owner', label: '负责人', type: 'text', placeholder: 'SAP 用户名' },
    { name: 'reqId', label: '所属请求', type: 'text', placeholder: '请求编号，如 0000000123' }
  ];
}

function columns() {
  return [
    {
      key: 'displayId',
      label: '编号',
      sortable: true,
      width: '112px',
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
        `<a class="row-title" href="#/change-documents/${encodeURIComponent(row.id)}" title="${ui.esc(
          row.title || ''
        )}">${ui.esc(ui.truncate(row.title, 64))}</a>`
    },
    {
      key: 'reqId',
      label: '所属请求',
      width: '120px',
      render: (row) => {
        const label = row.reqDisplayId || row.reqId;
        return row.reqId
          ? `<a class="mono" href="#/requests/${encodeURIComponent(row.reqId)}">${ui.esc(label || '—')}</a>`
          : '—';
      }
    },
    { key: 'status', label: '状态', sortable: true, width: '130px', render: (row) => ui.statusBadge(row.status) },
    { key: 'cycleId', label: '周期', width: '88px', render: (row) => ui.safe(row.cycleId) },
    { key: 'targetSystem', label: '目标系统', width: '90px', render: (row) => ui.safe(row.targetSystem) },
    { key: 'owner', label: '负责人', width: '116px', render: (row) => ui.safe(row.owner) },
    {
      key: 'plannedImportAt',
      label: '计划导入',
      width: '150px',
      render: (row) => {
        const overdue = row.plannedImportAt && ui.isOverdue(row.plannedImportAt);
        return `<span class="nowrap"${overdue ? ' style="color:var(--danger)"' : ''}>${ui.fmtDateTime(row.plannedImportAt)}</span>`;
      }
    },
    {
      key: 'changedAt',
      label: '更新时间',
      sortable: true,
      width: '146px',
      render: (row) => `<span class="nowrap">${ui.fmtDateTime(row.changedAt)}</span>`
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
    cycles = ui.listOf(await api.get('/config/cycles'));
  } catch (err) {
    cycles = [];
  }
  const fields = buildFilters(cycles);
  const values = queryValues(fields, query);

  root.innerHTML = `<div class="page">
    ${ui.pageHeader({
      title: '变更文档 CD',
      subtitle: '变更文档是开发 / 测试 / 导入与传输关联的载体',
      breadcrumb: [{ label: '工作台', href: '#/dashboard' }, { label: '变更文档 CD' }],
      actions: `<button type="button" class="btn btn-sm" data-action="refresh">${ui.icon('refresh', 15)}刷新</button>
        <a class="btn btn-sm btn-primary" href="#/requests?status=APPROVED">${ui.icon('plus', 15)}从请求创建</a>`
    })}
    <div class="panel">
      ${filterBar(fields, values)}
      <div data-list-body>${ui.loadingPanel('正在加载变更文档…')}</div>
      <div data-pager></div>
    </div>
  </div>`;

  const body = root.querySelector('[data-list-body]');
  const pagerEl = root.querySelector('[data-pager]');

  bindFilterBar(root, ctx, fields);
  bindSort(root, ctx, { sortKey: sort, sortOrder: order });
  bindRowLinks(root, ctx);
  bindPager(root, ctx);
  ui.bindOnce(root, 'change-documents', () => [
    ui.delegate(root, '[data-action="goto-approved"]', 'click', () => ctx.navigate('#/requests?status=APPROVED')),
    ui.delegate(root, '[data-action="retry"]', 'click', () => load()),
    ui.delegate(root, '[data-action="refresh"]', 'click', () => load())
  ]);

  async function load() {
    if (!body) return;
    body.innerHTML = ui.skeletonTable(8, 6);
    if (pagerEl) pagerEl.innerHTML = '';
    try {
      const data = await api.get('/change-documents', {
        page,
        size,
        sort,
        order,
        status: query.status,
        cycleId: query.cycleId,
        targetSystem: query.targetSystem,
        owner: query.owner,
        reqId: query.reqId,
        q: query.q
      });
      const rows = ui.listOf(data);
      const pageData = {
        page: (data && data.page) || page,
        pageSize: (data && data.pageSize) || size,
        total: data && data.total !== undefined ? Number(data.total) : rows.length
      };
      body.innerHTML = table({
        columns: columns(),
        rows,
        sortKey: sort,
        sortOrder: order,
        rowHref: (row) => '#/change-documents/' + encodeURIComponent(row.id),
        emptyOptions: {
          icon: 'cd',
          title: '还没有符合条件的变更文档',
          hint: '变更文档在请求批准后创建；先到请求列表找到已批准的请求。',
          actionLabel: '查看已批准请求',
          action: 'goto-approved'
        }
      });
      if (pagerEl) pagerEl.innerHTML = pager(root, ctx, pageData);
      bindSort(root, ctx, { sortKey: sort, sortOrder: order });
      bindRowLinks(root, ctx);
      bindPager(root, ctx);
    } catch (err) {
      const info = describeError(err);
      body.innerHTML = ui.errorPanel({ title: info.title, message: info.message, correlationId: info.correlationId });
    }
  }

  await load();
  return () => ui.releaseOnce(root, 'change-documents');
}
