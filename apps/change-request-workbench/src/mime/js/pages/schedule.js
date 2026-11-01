/**
 * pages/schedule.js — 导入计划：按日 / 目标系统 / 状态查看计划，改期 / 取消 / 确认完成。
 */

import { api, describeError } from '../api.js';
import * as ui from '../ui.js';
import { filterBar, bindFilterBar, queryValues } from '../components/form.js';
import { runMutation } from '../components/action-bar.js';

const STATUS_OPTIONS = [
  { value: '', label: '全部状态' },
  { value: 'PLANNED', label: '已计划' },
  { value: 'DONE', label: '已完成' },
  { value: 'MISSED', label: '已逾期' },
  { value: 'CANCELLED', label: '已取消' }
];

const TARGET_OPTIONS = [
  { value: '', label: '全部目标系统' },
  { value: 'QAS', label: 'QAS' },
  { value: 'PRD', label: 'PRD' }
];

function buildFilters() {
  return [
    { name: 'from', label: '计划日期从', type: 'date' },
    { name: 'to', label: '计划日期到', type: 'date' },
    { name: 'targetSystem', label: '目标系统', type: 'select', options: TARGET_OPTIONS },
    { name: 'status', label: '状态', type: 'select', options: STATUS_OPTIONS },
    { name: 'overdue', label: '只看逾期', type: 'checkbox' }
  ];
}

function scheduleActions(schedule) {
  const buttons = [];
  if (schedule.status === 'PLANNED' || schedule.status === 'MISSED') {
    buttons.push(`<button type="button" class="btn btn-sm" data-sched-action="RESCHEDULE" data-sched-id="${ui.esc(schedule.id)}">改期</button>`);
    buttons.push(`<button type="button" class="btn btn-sm btn-primary" data-sched-action="CONFIRM" data-sched-id="${ui.esc(schedule.id)}">确认完成</button>`);
    buttons.push(`<button type="button" class="btn btn-sm btn-danger" data-sched-action="CANCEL" data-sched-id="${ui.esc(schedule.id)}">取消计划</button>`);
  }
  return `<div class="cell-actions">${buttons.join('') || '<span class="muted small">—</span>'}</div>`;
}

function objectLink(schedule) {
  if (schedule.objectType === 'CD') {
    return `<a class="mono" href="#/change-documents/${encodeURIComponent(schedule.objectId)}">${ui.esc(
      schedule.objectDisplayId || schedule.objectId
    )}</a>`;
  }
  if (schedule.objectType === 'TOC') {
    return `<a class="mono" href="#/transports/${encodeURIComponent(schedule.objectId)}">${ui.esc(schedule.objectId)}</a>`;
  }
  return `<span class="mono">${ui.esc(schedule.objectId)}</span>`;
}

function groupByDay(schedules) {
  const groups = new Map();
  schedules.forEach((schedule) => {
    const key = ui.fmtDate(schedule.scheduledAt);
    if (!groups.has(key)) groups.set(key, []);
    groups.get(key).push(schedule);
  });
  return Array.from(groups.entries()).sort((a, b) => (a[0] < b[0] ? -1 : 1));
}

function renderDayGroups(schedules) {
  const groups = groupByDay(schedules);
  return groups
    .map(([day, rows]) => {
      const body = rows
        .map(
          (schedule) => `<tr>
          <td>${objectLink(schedule)}</td>
          <td>${ui.objectTypeBadge(schedule.objectType)}</td>
          <td>${ui.esc(schedule.targetSystem || '—')}</td>
          <td class="nowrap">${ui.fmtDateTime(schedule.scheduledAt)}</td>
          <td>${ui.scheduleStatusBadge(schedule.status)}${
            schedule.overdue && schedule.status !== 'MISSED' ? ' ' + ui.badge('逾期', 'danger') : ''
          }</td>
          <td><div class="cell-clip small muted">${ui.esc(ui.truncate(schedule.note || '—', 50))}</div></td>
          <td class="num">${schedule.taskCount !== undefined ? ui.fmtNum(schedule.taskCount) : '—'}</td>
          <td class="actions">${scheduleActions(schedule)}</td>
        </tr>`
        )
        .join('');
      const overdue = rows.some((row) => row.overdue);
      return `<div class="panel">
        <div class="panel-head">
          <span class="panel-title">${ui.fmtDayLabel(day)}</span>
          <span class="chip">${rows.length} 条</span>
          ${overdue ? ui.badge('含逾期计划', 'danger') : ''}
          <span class="right muted small">计划只做提醒与状态跟踪，不执行 TMS 导入</span>
        </div>
        <div class="table-wrap"><table class="data fixed" style="min-width:1120px">
          <colgroup><col style="width:130px"><col style="width:84px"><col style="width:90px">
            <col style="width:150px"><col style="width:150px"><col><col style="width:70px"><col style="width:230px"></colgroup>
          <thead><tr><th>对象</th><th>类型</th><th>目标系统</th>
            <th>计划时间</th><th>状态</th><th>备注</th><th class="num">任务</th>
            <th class="actions">操作</th></tr></thead>
          <tbody>${body}</tbody></table></div>
      </div>`;
    })
    .join('');
}

export async function mount(root, ctx) {
  const query = ctx.query || {};
  const fields = buildFilters();
  const values = queryValues(fields, query);
  let schedules = [];

  root.innerHTML = `<div class="page">
    ${ui.pageHeader({
      title: '导入计划',
      subtitle: '按日查看导入日程；到点未导入会标记为逾期（读取时计算）',
      breadcrumb: [{ label: '工作台', href: '#/dashboard' }, { label: '导入计划' }],
      actions: `<button type="button" class="btn btn-sm" data-action="refresh">${ui.icon('refresh', 15)}刷新</button>`
    })}
    <div class="panel">
      ${filterBar(fields, values)}
      <div data-schedule-body>${ui.loadingPanel('正在加载导入计划…')}</div>
    </div>
  </div>`;

  const body = root.querySelector('[data-schedule-body]');
  bindFilterBar(root, ctx, fields);

  ui.bindOnce(root, 'schedule', () => [
    ui.delegate(root, '[data-action="retry"]', 'click', () => load()),
    ui.delegate(root, '[data-action="refresh"]', 'click', () => load()),
    ui.delegate(root, '[data-sched-action]', 'click', (event, el) =>
      handleAction(el.getAttribute('data-sched-action'), el.getAttribute('data-sched-id'), el)
    )
  ]);

  async function handleAction(action, id, button) {
    const schedule = schedules.find((item) => item.id === id);
    if (!schedule) return;
    let payload = { action };
    if (action === 'RESCHEDULE') {
      const values2 = await ui.confirmDialog({
        title: '改期导入计划',
        message: '改期后状态保持「已计划」（逾期计划改期后回到已计划）。时间冲突会返回 SCHEDULE_CONFLICT。',
        confirmText: '保存新时间',
        danger: true,
        fields: [
          { name: 'scheduledAt', label: '新的计划时间', type: 'datetime-local', required: true },
          { name: 'note', label: '备注（可选）', type: 'textarea', rows: 2 }
        ],
        values: { scheduledAt: ui.toDateTimeInput(schedule.scheduledAt) }
      });
      if (!values2) return;
      payload.scheduledAt = ui.fromDateTimeInput(values2.scheduledAt);
      if (values2.note) payload.note = values2.note;
    } else if (action === 'CANCEL') {
      const values2 = await ui.confirmDialog({
        title: '取消导入计划',
        message: '取消后计划状态为「已取消」，关联 CD 回到「待导入」。',
        confirmText: '确认取消',
        danger: true,
        fields: [{ name: 'note', label: '原因（可选）', type: 'textarea', rows: 2 }]
      });
      if (!values2) return;
      if (values2.note) payload.note = values2.note;
    } else if (action === 'CONFIRM') {
      const ok = await ui.confirmDialog({
        title: '确认计划完成',
        message: '确认后计划状态为「已完成」；实际导入仍以 STMS 为准。',
        confirmText: '确认完成'
      });
      if (!ok) return;
    }
    await runMutation(
      async () => {
        await api.post('/schedules/' + encodeURIComponent(id) + '/actions', payload);
        return { message: ui.actionLabel(action) + '成功。' };
      },
      { ctx, button, successMessage: '计划已更新。' }
    );
  }

  async function load() {
    if (!body) return;
    body.innerHTML = ui.skeletonTable(8, 5);
    try {
      const data = await api.get('/schedules', {
        from: query.from,
        to: query.to,
        targetSystem: query.targetSystem,
        status: query.status,
        overdue: query.overdue === 'true' || query.overdue === '1' ? 'true' : ''
      });
      schedules = ui.listOf(data);
      const planned = schedules.filter((row) => row.status === 'PLANNED').length;
      const missed = schedules.filter((row) => row.status === 'MISSED' || row.overdue).length;
      const done = schedules.filter((row) => row.status === 'DONE').length;
      body.innerHTML =
        (missed > 0 ? ui.banner(missed + ' 条计划已逾期仍未确认导入，请发布管理员处理。', 'warn', 'alert') : '') +
        `<div class="panel-head" style="border-top:0">
          <span class="panel-title">日程</span>
          <span class="chip">已计划 ${ui.fmtNum(planned)}</span>
          <span class="chip">逾期 ${ui.fmtNum(missed)}</span>
          <span class="chip">已完成 ${ui.fmtNum(done)}</span>
          <span class="right muted small">共 ${ui.fmtNum(schedules.length)} 条</span>
        </div>` +
        (schedules.length
          ? renderDayGroups(schedules)
          : ui.emptyPanel({
              icon: 'schedule',
              title: '没有符合条件的导入计划',
              hint: '计划由 CD 的「计划导入」动作创建；调整筛选条件查看其它日期。',
              actionLabel: '查看待导入变更文档',
              action: 'goto-ready'
            }));
    } catch (err) {
      const info = describeError(err);
      body.innerHTML = ui.errorPanel({ title: info.title, message: info.message, correlationId: info.correlationId });
    }
  }

  ui.delegate(root, '[data-action="goto-ready"]', 'click', () => ctx.navigate('#/change-documents?status=READY_TO_IMPORT'));

  await load();
  return () => ui.releaseOnce(root, 'schedule');
}
