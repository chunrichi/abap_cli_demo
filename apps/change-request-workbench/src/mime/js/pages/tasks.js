/**
 * pages/tasks.js — 任务列表：按指派人 / 状态 / 类型 / 截止日筛选；子任务行内展开。
 */

import { api, describeError } from '../api.js';
import * as store from '../store.js';
import * as ui from '../ui.js';
import { filterBar, bindFilterBar, queryValues } from '../components/form.js';
import { table, bindSort, bindRowLinks, pager, bindPager } from '../components/table.js';
import { runMutation } from '../components/action-bar.js';

const STATUS_OPTIONS = [
  { value: '', label: '全部状态' },
  { value: 'OPEN', label: '待开始' },
  { value: 'IN_PROGRESS', label: '进行中' },
  { value: 'DONE', label: '已完成' },
  { value: 'CANCELLED', label: '已取消' }
];

const TYPE_OPTIONS = [
  { value: '', label: '全部类型' },
  { value: 'DEV', label: '开发' },
  { value: 'TEST', label: '测试' },
  { value: 'IMPORT', label: '导入确认' },
  { value: 'RETROFIT', label: '补做' }
];

function buildFilters() {
  return [
    { name: 'assignee', label: '指派人', type: 'text', placeholder: 'SAP 用户名' },
    { name: 'status', label: '状态', type: 'select', options: STATUS_OPTIONS },
    { name: 'taskType', label: '任务类型', type: 'select', options: TYPE_OPTIONS },
    { name: 'dueDateFrom', label: '截止日从', type: 'date' },
    { name: 'dueDateTo', label: '截止日到', type: 'date' },
    { name: 'cdId', label: '变更文档', type: 'text', placeholder: 'CD 编号' },
    { name: 'q', label: '关键词', type: 'text', placeholder: '任务标题' }
  ];
}

function taskColumns() {
  return [
    {
      key: 'displayId',
      label: '编号',
      sortable: true,
      width: '118px',
      render: (row) => `<span class="mono">${ui.esc(row.displayId || row.id)}</span>`
    },
    {
      key: 'title',
      label: '任务',
      sortable: true,
      flex: true,
      minWidth: 220,
      ellipsis: true,
      render: (row) => `${ui.esc(ui.truncate(row.title, 60))}${row.parentTaskId ? ' <span class="chip">子任务</span>' : ''}`
    },
    { key: 'taskType', label: '类型', width: '84px', render: (row) => ui.taskTypeBadge(row.taskType) },
    { key: 'assignee', label: '指派人', width: '124px', render: (row) => ui.safe(row.assignee) },
    { key: 'status', label: '状态', sortable: true, width: '110px', render: (row) => ui.statusBadge(row.status) },
    {
      key: 'dueDate',
      label: '截止日',
      sortable: true,
      width: '112px',
      render: (row) => {
        const overdue = ui.isOverdue(row.dueDate) && row.status !== 'DONE' && row.status !== 'CANCELLED';
        return `<span class="nowrap"${overdue ? ' style="color:var(--danger);font-weight:600"' : ''}>${ui.fmtDate(
          row.dueDate
        )}</span>`;
      }
    },
    {
      key: 'cdId',
      label: 'CD',
      width: '110px',
      render: (row) =>
        row.cdId ? `<a class="mono" href="#/change-documents/${encodeURIComponent(row.cdId)}">${ui.esc(row.cdId)}</a>` : '—'
    },
    { key: 'estHours', label: '预估', align: 'right', width: '76px', render: (row) => (row.estHours ? ui.fmtNum(row.estHours) : '—') },
    {
      key: 'actions',
      label: '操作',
      className: 'actions',
      width: '190px',
      render: (row) => taskActions(row)
    }
  ];
}

function taskActions(task) {
  const buttons = [];
  if (task.status === 'OPEN') {
    buttons.push(`<button type="button" class="btn btn-sm" data-task-action="START" data-task-id="${ui.esc(task.id)}">开始</button>`);
  }
  if (task.status === 'IN_PROGRESS') {
    buttons.push(
      `<button type="button" class="btn btn-sm btn-primary" data-task-action="DONE" data-task-id="${ui.esc(task.id)}">完成</button>`
    );
  }
  if (task.status !== 'DONE' && task.status !== 'CANCELLED') {
    buttons.push(
      `<button type="button" class="btn btn-sm btn-danger" data-task-action="CANCEL" data-task-id="${ui.esc(task.id)}">取消</button>`
    );
  }
  buttons.push(`<button type="button" class="btn btn-sm btn-ghost" data-task-edit="${ui.esc(task.id)}">编辑</button>`);
  return `<div class="cell-actions">${buttons.join('')}</div>`;
}

export async function mount(root, ctx) {
  const query = ctx.query || {};
  const page = Math.max(1, Number(query.page) || 1);
  const size = Math.max(1, Number(query.size) || 50);
  const sort = query.sort || 'dueDate';
  const order = query.order === 'desc' ? 'desc' : 'asc';
  const fields = buildFilters();
  const values = queryValues(fields, query);
  let tasksById = new Map();

  root.innerHTML = `<div class="page">
    ${ui.pageHeader({
      title: '任务',
      subtitle: '开发 / 测试 / 导入确认任务；父任务可展开子任务',
      breadcrumb: [{ label: '工作台', href: '#/dashboard' }, { label: '任务' }],
      actions: `<button type="button" class="btn btn-sm" data-action="mine">只看我的</button>
        <button type="button" class="btn btn-sm" data-action="refresh">${ui.icon('refresh', 15)}刷新</button>`
    })}
    <div class="panel">
      ${filterBar(fields, values)}
      <div data-list-body>${ui.loadingPanel('正在加载任务…')}</div>
      <div data-pager></div>
    </div>
  </div>`;

  const body = root.querySelector('[data-list-body]');
  const pagerEl = root.querySelector('[data-pager]');
  bindFilterBar(root, ctx, fields);
  bindSort(root, ctx, { sortKey: sort, sortOrder: order });
  bindPager(root, ctx);

  ui.bindOnce(root, 'tasks', () => [
    ui.delegate(root, '[data-action="retry"]', 'click', () => load()),
    ui.delegate(root, '[data-action="refresh"]', 'click', () => load()),
    ui.delegate(root, '[data-action="mine"]', 'click', () => ctx.setQuery({ assignee: store.userName() })),
    ui.delegate(root, '[data-action="mine-only"]', 'click', () => ctx.setQuery({ assignee: store.userName() })),
    ui.delegate(root, '[data-toggle-sub]', 'click', async (event, el) => {
      const taskId = el.getAttribute('data-toggle-sub');
      const row = root.querySelector(`[data-sub-row="${taskId}"]`);
      if (row && row.getAttribute('data-loaded') === '1') {
        const willShow = row.classList.toggle('hidden') === false;
        el.innerHTML = ui.icon(willShow ? 'chevronDown' : 'chevronRight', 12);
        return;
      }
      el.innerHTML = '<span class="spinner" style="width:11px;height:11px;border-width:2px"></span>';
      try {
        const raw = await api.get('/tasks/' + encodeURIComponent(taskId) + '/subtasks');
        const children = ui.listOf(raw);
        const html = subtaskRowHtml(taskId, children);
        const existing = root.querySelector(`[data-sub-row="${taskId}"]`);
        if (existing) {
          existing.outerHTML = html;
        } else if (el.closest('tr') && el.closest('tr').parentNode) {
          el.closest('tr').insertAdjacentHTML('afterend', html);
        }
        el.innerHTML = ui.icon('chevronDown', 12);
      } catch (err) {
        el.innerHTML = ui.icon('chevronRight', 12);
        const info = describeError(err);
        ui.toast(info.message, { title: info.title, type: 'error', correlationId: info.correlationId });
      }
    }),
    ui.delegate(root, '[data-task-edit]', 'click', (event, el) => openEdit(el.getAttribute('data-task-edit'))),
    ui.delegate(root, '[data-task-action]', 'click', async (event, el) => {
      const action = el.getAttribute('data-task-action');
      const task = tasksById.get(el.getAttribute('data-task-id'));
      if (!task) return;
      const payload = { action, version: Number(task.version) };
      if (action === 'CANCEL') {
        const values = await ui.confirmDialog({
          title: '取消任务',
          message: '取消为终态操作，原因必填。',
          confirmText: '确认取消',
          danger: true,
          fields: [{ name: 'comment', label: '取消原因', type: 'textarea', required: true, rows: 3 }]
        });
        if (!values) return;
        payload.comment = values.comment;
      }
      await runMutation(
        async () => {
          await api.post('/tasks/' + encodeURIComponent(task.id) + '/actions', payload);
          return { message: ui.actionLabel(action) + '成功。' };
        },
        { ctx, button: el, successMessage: ui.actionLabel(action) + '成功。' }
      );
    })
  ]);

  async function openEdit(taskId) {
    const task = tasksById.get(taskId);
    if (!task) return;
    const values = await ui.confirmDialog({
      title: '编辑任务',
      message: '修改指派人与计划信息。',
      confirmText: '保存',
      fields: [
        { name: 'title', label: '任务标题', type: 'text', required: true, maxlength: 120, span: 'all' },
        { name: 'assignee', label: '指派人', type: 'text', required: true },
        { name: 'dueDate', label: '截止日', type: 'date' },
        { name: 'estHours', label: '预估工时（小时）', type: 'number', min: 0 }
      ],
      values: { title: task.title || '', assignee: task.assignee || '', dueDate: ui.toDateInput(task.dueDate), estHours: task.estHours || '' }
    });
    if (!values) return;
    await runMutation(
      async () => {
        await api.patch('/tasks/' + encodeURIComponent(task.id), Object.assign({}, values, { version: Number(task.version) }));
        return { message: '任务已更新。' };
      },
      { ctx, successMessage: '任务已更新。' }
    );
  }

  function subtaskRowHtml(parentId, children) {
    const inner = children.length
      ? children
          .map(
            (task) => `<div class="subtask">
              <span class="mono">${ui.esc(task.displayId || task.id)}</span>
              <span>${ui.esc(task.title || '')}</span>
              ${ui.taskTypeBadge(task.taskType)}
              ${ui.statusBadge(task.status)}
              <span class="muted">${ui.esc(task.assignee || '—')}</span>
              <span class="muted">${ui.fmtDate(task.dueDate)}</span>
              <span style="margin-left:auto"></span>
              ${taskActions(task)}
            </div>`
          )
          .join('')
      : '<div class="muted small">没有子任务</div>';
    return `<tr class="sub-row" data-sub-row="${ui.esc(parentId)}" data-loaded="1"><td colspan="10"><div class="subtasks">${inner}</div></td></tr>`;
  }

  async function load() {
    if (!body) return;
    body.innerHTML = ui.skeletonTable(8, 6);
    if (pagerEl) pagerEl.innerHTML = '';
    try {
      const data = await api.get('/tasks', {
        page,
        size,
        sort,
        order,
        assignee: query.assignee,
        status: query.status,
        taskType: query.taskType,
        dueDateFrom: query.dueDateFrom,
        dueDateTo: query.dueDateTo,
        cdId: query.cdId,
        q: query.q
      });
      const rows = ui.listOf(data);
      tasksById = new Map(rows.map((row) => [row.id, row]));
      const pageData = {
        page: (data && data.page) || page,
        pageSize: (data && data.pageSize) || size,
        total: data && data.total !== undefined ? Number(data.total) : rows.length
      };
      const columns = taskColumns();
      body.innerHTML = table({
        columns,
        rows,
        sortKey: sort,
        sortOrder: order,
        emptyOptions: {
          icon: 'task',
          title: '没有符合条件的任务',
          hint: '调整筛选条件；任务在变更文档详情中创建。',
          actionLabel: '查看我的任务',
          action: 'mine-only'
        }
      });
      // 父任务行注入子任务展开控件
      const trs = body.querySelectorAll('tbody tr');
      rows.forEach((row, index) => {
        if (row.parentTaskId) return;
        const tr = trs[index];
        const firstTd = tr && tr.querySelector('td');
        if (!firstTd) return;
        const btn = `<button type="button" class="expander" data-toggle-sub="${ui.esc(row.id)}" aria-label="展开子任务" title="展开子任务">${ui.icon(
          'chevronRight',
          12
        )}</button>`;
        firstTd.innerHTML = btn + firstTd.innerHTML;
      });
      if (pagerEl) pagerEl.innerHTML = pager(root, ctx, pageData);
      bindSort(root, ctx, { sortKey: sort, sortOrder: order });
      bindPager(root, ctx);
    } catch (err) {
      const info = describeError(err);
      body.innerHTML = ui.errorPanel({ title: info.title, message: info.message, correlationId: info.correlationId });
    }
  }

  await load();
  return () => ui.releaseOnce(root, 'tasks');
}
