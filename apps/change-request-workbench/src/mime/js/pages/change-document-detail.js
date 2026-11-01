/**
 * pages/change-document-detail.js — 变更文档详情：头部 + 动作条 +
 * 概览 / 任务（含子任务） / 传输 / 导入计划 / 审批。
 */

import { api, describeError } from '../api.js';
import * as store from '../store.js';
import * as ui from '../ui.js';
import { actionBar, bindActionBar, runMutation } from '../components/action-bar.js';
import { formBody } from '../components/form.js';

const TABS = ['overview', 'tasks', 'transports', 'schedule', 'approvals'];

function editFields(cycles) {
  return [
    { name: 'title', label: '标题', type: 'text', required: true, maxlength: 120, span: 'all' },
    {
      name: 'targetSystem',
      label: '目标系统',
      type: 'select',
      required: true,
      options: [
        { value: 'QAS', label: 'QAS 质量系统' },
        { value: 'PRD', label: 'PRD 生产系统' },
        { value: 'DEV', label: 'DEV 开发系统' }
      ]
    },
    {
      name: 'cycleId',
      label: '周期',
      type: 'select',
      options: [{ value: '', label: '不指定周期' }].concat(
        cycles.map((cycle) => ({ value: cycle.id, label: cycle.id + (cycle.description ? ' · ' + cycle.description : '') }))
      )
    },
    { name: 'owner', label: '负责人', type: 'text', placeholder: 'SAP 用户名' },
    { name: 'devLead', label: '开发负责人', type: 'text', placeholder: 'SAP 用户名' },
    { name: 'testLead', label: '测试负责人', type: 'text', placeholder: 'SAP 用户名' },
    { name: 'plannedImportAt', label: '计划导入时间', type: 'datetime-local' }
  ];
}

function taskFields() {
  return [
    { name: 'title', label: '任务标题', type: 'text', required: true, maxlength: 120, span: 'all' },
    {
      name: 'taskType',
      label: '任务类型',
      type: 'select',
      required: true,
      options: [
        { value: 'DEV', label: '开发' },
        { value: 'TEST', label: '测试' },
        { value: 'IMPORT', label: '导入确认' },
        { value: 'RETROFIT', label: '补做' }
      ]
    },
    { name: 'assignee', label: '指派人', type: 'text', required: true, placeholder: 'SAP 用户名' },
    { name: 'dueDate', label: '截止日', type: 'date' },
    { name: 'estHours', label: '预估工时（小时）', type: 'number', min: 0, step: 1 }
  ];
}

function transportLinkFields() {
  return [
    { name: 'trkorr', label: '传输号', type: 'text', required: true, maxlength: 10, placeholder: '如 QASK900123', span: 'all' },
    {
      name: 'trKind',
      label: '传输类型',
      type: 'select',
      required: true,
      options: [
        { value: 'DEV', label: 'DEV 开发传输' },
        { value: 'TOC', label: 'ToC 传输' }
      ]
    },
    { name: 'taskId', label: '关联任务编号（可选）', type: 'text', placeholder: '如 0000000042' }
  ];
}

function header(cd) {
  const badges = [ui.statusBadge(cd.status), cd.approvalState ? ui.apprStateBadge(cd.approvalState) : '']
    .filter(Boolean)
    .join(' ');
  return ui.pageHeader({
    title: (cd.displayId || cd.id) + ' · ' + (cd.title || ''),
    breadcrumb: [
      { label: '工作台', href: '#/dashboard' },
      { label: '变更文档 CD', href: '#/change-documents' },
      { label: cd.displayId || cd.id }
    ],
    meta: [
      cd.reqId
        ? `<span>所属请求 <a href="#/requests/${encodeURIComponent(cd.reqId)}" class="mono">${ui.esc(
            cd.reqDisplayId || cd.reqId
          )}</a></span>`
        : '',
      `<span>周期 <b>${ui.esc(cd.cycleId || '—')}</b></span>`,
      `<span>目标系统 <b>${ui.esc(cd.targetSystem || '—')}</b></span>`,
      `<span>负责人 <b>${ui.esc(cd.owner || '—')}</b></span>`,
      `<span>版本 <b>v${ui.esc(cd.version === undefined ? '—' : cd.version)}</b></span>`,
      `<span>更新 ${ui.fmtDateTime(cd.changedAt)} · ${ui.esc(cd.changedBy || '—')}</span>`,
      `<span>时区 <b>SAP_SYSTEM</b></span>`
    ].join(''),
    actions: `<a class="btn btn-sm" href="#/change-documents">${ui.icon('chevronLeft', 15)}返回列表</a>
      <button type="button" class="btn btn-sm" data-action="refresh">${ui.icon('refresh', 15)}刷新</button>`
  }).replace('</h1>', '</h1><div class="page-meta" style="margin-top:2px">' + badges + '</div>');
}

function overviewTab(cd, tasks, transports, schedule) {
  const openTasks = tasks.filter((task) => task.status !== 'DONE' && task.status !== 'CANCELLED').length;
  const devTrs = transports.filter((tr) => tr.trKind === 'DEV');
  const released = devTrs.filter((tr) => tr.trStatus === 'R').length;
  return `<div class="panel"><div class="panel-head"><span class="panel-title">基本信息</span></div>
    <div class="panel-body">
      ${ui.kvList([
        { label: '显示编号', value: cd.displayId || cd.id },
        { label: '状态', html: ui.statusBadge(cd.status) },
        { label: '导入审批', html: cd.approvalState ? ui.apprStateBadge(cd.approvalState) : '—' },
        { label: '所属请求', html: cd.reqId ? `<a href="#/requests/${encodeURIComponent(cd.reqId)}">${ui.esc(cd.reqDisplayId || cd.reqId)}</a>` : '—' },
        { label: '周期', value: cd.cycleId },
        { label: '目标系统', value: cd.targetSystem },
        { label: '负责人', value: cd.owner },
        { label: '开发负责人', value: cd.devLead },
        { label: '测试负责人', value: cd.testLead },
        { label: '计划导入时间', value: ui.fmtDateTime(cd.plannedImportAt) },
        { label: '当前导入计划', value: schedule ? ui.SCHEDULE_STATUS[schedule.status] ? ui.SCHEDULE_STATUS[schedule.status].zh : schedule.status : '—' },
        { label: '任务', value: tasks.length + ' 个（未完成 ' + openTasks + '）' },
        { label: 'DEV 传输', value: devTrs.length + ' 条（已释放 ' + released + '）' },
        { label: '创建', value: ui.fmtDateTime(cd.createdAt) + ' · ' + (cd.createdBy || '—') },
        { label: '最后更新', value: ui.fmtDateTime(cd.changedAt) + ' · ' + (cd.changedBy || '—') },
        { label: '关闭时间', value: ui.fmtDateTime(cd.closedAt) }
      ])}
    </div></div>`;
}

function tasksTab(cd, tasks) {
  const parents = tasks.filter((task) => task.taskLevel === 'T' || !task.parentTaskId);
  const childrenOf = (parentId) => tasks.filter((task) => task.parentTaskId === parentId);
  const rowActions = (task) => {
    const buttons = [];
    if (task.status === 'OPEN') buttons.push(`<button type="button" class="btn btn-sm" data-task-action="START" data-task-id="${ui.esc(task.id)}">开始</button>`);
    if (task.status === 'IN_PROGRESS') buttons.push(`<button type="button" class="btn btn-sm btn-primary" data-task-action="DONE" data-task-id="${ui.esc(task.id)}">完成</button>`);
    if (task.status !== 'DONE' && task.status !== 'CANCELLED')
      buttons.push(`<button type="button" class="btn btn-sm btn-danger" data-task-action="CANCEL" data-task-id="${ui.esc(task.id)}">取消</button>`);
    buttons.push(`<button type="button" class="btn btn-sm btn-ghost" data-task-edit="${ui.esc(task.id)}">编辑</button>`);
    return `<div class="cell-actions">${buttons.join('')}</div>`;
  };
  const taskRow = (task, isSub) => `<tr data-task-row="${ui.esc(task.id)}">
    <td>${isSub ? '<span class="role-label" style="margin-left:16px">子任务</span>' : `<span class="mono">${ui.esc(task.displayId || task.id)}</span>`}</td>
    <td><div class="cell-clip">${ui.esc(task.title || '—')}</div></td>
    <td>${ui.taskTypeBadge(task.taskType)}</td>
    <td>${ui.esc(task.assignee || '—')}</td>
    <td>${ui.statusBadge(task.status)}</td>
    <td class="nowrap"${ui.isOverdue(task.dueDate) && task.status !== 'DONE' ? ' style="color:var(--danger)"' : ''}>${ui.fmtDate(task.dueDate)}</td>
    <td class="num">${task.estHours ? ui.fmtNum(task.estHours) : '—'}</td>
    <td class="actions">${rowActions(task)}</td>
  </tr>`;
  const body = parents
    .map((parent) => {
      const children = childrenOf(parent.id);
      const expander = children.length
        ? `<button type="button" class="expander" data-toggle-sub="${ui.esc(parent.id)}" aria-label="展开子任务" title="展开子任务">${ui.icon('chevronRight', 12)}</button>`
        : '';
      const rows = [taskRow(parent, false).replace('<td>', '<td>' + expander)];
      if (children.length) {
        const childHtml = children.map((child) => taskRow(child, true)).join('');
        rows.push(`<tr class="sub-row hidden" data-sub-row="${ui.esc(parent.id)}"><td colspan="8"><div class="subtasks">${childHtml}</div></td></tr>`);
      }
      return rows.join('');
    })
    .join('');
  const orphanChildren = tasks.filter((task) => task.parentTaskId && !parents.some((parent) => parent.id === task.parentTaskId));
  const orphanHtml = orphanChildren.map((task) => taskRow(task, true)).join('');
  const content = tasks.length
    ? `<div class="table-wrap"><table class="data fixed" style="min-width:1080px">
        <colgroup><col style="width:140px"><col><col style="width:80px"><col style="width:120px"><col style="width:110px"><col style="width:110px"><col class="num" style="width:90px"><col style="width:180px"></colgroup>
        <thead><tr><th>编号</th><th>任务</th><th>类型</th><th>指派人</th><th>状态</th><th>截止日</th><th class="num">预估</th><th class="actions">操作</th></tr></thead>
        <tbody>${body}${orphanHtml}</tbody></table></div>`
    : ui.emptyPanel({ icon: 'task', title: '还没有任务', hint: '为变更文档创建开发 / 测试 / 导入确认任务。', actionLabel: '新建任务', action: 'new-task' });
  return `<div class="panel-head"><span class="panel-title">任务</span><span class="panel-sub">父任务下的子任务可展开</span>
      <span class="right"><button type="button" class="btn btn-sm btn-primary" data-action="new-task">${ui.icon('plus', 14)}新建任务</button></span></div>
    <div class="panel-body flush">${content}</div>
    <div class="panel-body tight muted small">任务状态：待开始 → 进行中 → 已完成；取消需填写原因。子任务关闭不会自动关闭父任务。</div>`;
}

function transportsTab(cd, transports) {
  if (transports.length === 0) {
    return `<div class="panel-head"><span class="panel-title">传输</span>
        <span class="right"><button type="button" class="btn btn-sm btn-primary" data-action="link-tr">${ui.icon('link', 14)}关联传输</button></span></div>
      <div class="panel-body">${ui.emptyPanel({
        icon: 'transport',
        title: '还没有关联传输',
        hint: '在 SE01 / abap-cli 创建 DEV 传输或 ToC 后，把传输号关联到本变更文档。应用只读 CTS 状态。'
      })}</div>`;
  }
  const degraded = transports.some((tr) => tr.syncState === 'ERROR' || tr.degraded);
  const rows = transports
    .map((tr) => {
      const actions = [];
      if (!tr.linked && tr.syncState !== 'DETACHED') {
        actions.push(`<button type="button" class="btn btn-sm" data-tr-action="link" data-trkorr="${ui.esc(tr.trkorr)}">关联</button>`);
      }
      actions.push(`<button type="button" class="btn btn-sm" data-tr-action="sync" data-trkorr="${ui.esc(tr.trkorr)}">同步</button>`);
      if (tr.trStatus === 'D' && tr.linked) {
        actions.push(`<button type="button" class="btn btn-sm btn-danger" data-tr-action="unlink" data-trkorr="${ui.esc(tr.trkorr)}">解绑</button>`);
      } else if (tr.linked) {
        actions.push(`<button type="button" class="btn btn-sm btn-danger" data-tr-action="detach" data-trkorr="${ui.esc(tr.trkorr)}">标记不再关联</button>`);
      }
      return `<tr>
        <td><a class="mono" href="#/transports/${encodeURIComponent(tr.trkorr)}">${ui.esc(tr.trkorr)}</a></td>
        <td>${ui.trKindBadge(tr.trKind)}</td>
        <td>${ui.esc(tr.targetSystem || '—')}</td>
        <td>${ui.trStatusBadge(tr)}</td>
        <td>${ui.syncStateBadge(tr.syncState)}</td>
        <td class="nowrap">${ui.fmtDateTime(tr.importedAt)}</td>
        <td><div class="cell-clip small muted">${ui.esc(tr.description || '—')}</div></td>
        <td class="actions"><div class="cell-actions">${actions.join('')}</div></td>
      </tr>`;
    })
    .join('');
  return `<div class="panel-head"><span class="panel-title">传输</span>
      <span class="panel-sub">DEV 与 ToC 只读展示，手工关联</span>
      <span class="right">
        <button type="button" class="btn btn-sm" data-action="sync-all">${ui.icon('sync', 14)}同步全部</button>
        <button type="button" class="btn btn-sm btn-primary" data-action="link-tr">${ui.icon('link', 14)}关联传输</button>
      </span></div>
    ${degraded ? `<div class="panel-body tight">${ui.banner('存在 CTS 读取失败的传输，状态显示为「未知」，请到 STMS 确认后再操作。', 'warn', 'alert')}</div>` : ''}
    <div class="panel-body flush"><div class="table-wrap"><table class="data fixed" style="min-width:1160px">
      <colgroup><col style="width:120px"><col style="width:100px"><col style="width:90px"><col style="width:140px"><col style="width:120px"><col style="width:150px"><col><col style="width:220px"></colgroup>
      <thead><tr><th>传输号</th><th>类型</th><th>目标系统</th><th>状态</th><th>同步</th><th>导入时间</th><th>描述</th><th class="actions">操作</th></tr></thead>
      <tbody>${rows}</tbody></table></div></div>`;
}

function scheduleTab(cd, schedule) {
  const actionButtons = schedule
    ? `<button type="button" class="btn btn-sm" data-sched-action="RESCHEDULE">改期</button>
       <button type="button" class="btn btn-sm btn-primary" data-sched-action="CONFIRM">确认完成</button>
       ${
         schedule.status === 'PLANNED' || schedule.status === 'MISSED'
           ? '<button type="button" class="btn btn-sm btn-danger" data-sched-action="CANCEL">取消计划</button>'
           : ''
       }`
    : '';
  const content = schedule
    ? `<div class="panel-body">
        ${ui.kvList([
          { label: '计划编号', value: schedule.id },
          { label: '对象', value: ui.objectTypeLabel(schedule.objectType) + ' ' + (schedule.objectDisplayId || schedule.objectId) },
          { label: '目标系统', value: schedule.targetSystem },
          { label: '计划时间', value: ui.fmtDateTime(schedule.scheduledAt) },
          { label: '状态', html: ui.scheduleStatusBadge(schedule.status) },
          { label: '逾期', html: schedule.overdue ? ui.badge('已逾期', 'danger') : ui.badge('未逾期', 'ok') },
          { label: '备注', value: schedule.note }
        ])}
      </div>`
    : `<div class="panel-body">${ui.emptyPanel({
        icon: 'schedule',
        title: '还没有导入计划',
        hint: '变更文档进入「待导入」后可以安排导入时间；应用只做计划与提醒，不执行 TMS 导入。',
        actionLabel: '计划导入',
        action: 'new-schedule'
      })}</div>`;
  return `<div class="panel-head"><span class="panel-title">导入计划</span>
      <span class="panel-sub">计划 + 提醒 + 状态跟踪，不执行 TMS 导入</span>
      <span class="right">${actionButtons}</span></div>${content}`;
}

function approvalsTab(steps) {
  if (steps.length === 0) {
    return ui.emptyPanel({ icon: 'approval', title: '暂无 CD 审批步骤', hint: '「提交导入审批」后按审批矩阵生成步骤；也可配置为不需要 CD 审批。' });
  }
  const rows = steps
    .map(
      (step) => `<tr>
      <td>${ui.esc(step.stepNo)}</td>
      <td>${ui.esc(step.approver || '—')}</td>
      <td>${ui.apprStateBadge(step.apprState)}</td>
      <td class="nowrap">${ui.fmtDateTime(step.decidedAt)}</td>
      <td><div class="cell-clip small">${ui.esc(step.comment || '—')}</div></td>
    </tr>`
    )
    .join('');
  return `<div class="table-wrap"><table class="data fixed" style="min-width:760px">
    <colgroup><col style="width:64px"><col style="width:160px"><col style="width:110px"><col style="width:160px"><col></colgroup>
    <thead><tr><th>步骤</th><th>审批人</th><th>状态</th><th>决策时间</th><th>意见</th></tr></thead>
    <tbody>${rows}</tbody></table></div>
    <div class="panel-body tight muted small">审批决策在「审批中心」处理；导入审批通过后才能标记待导入（可配置关闭该级审批）。</div>`;
}

function buildActions(cd, tasks, transports, steps, cycles) {
  // 服务端 allowedActions 权威；客户端规则只用于禁用原因与守卫提示。
  const allowedActions = Array.isArray(cd.allowedActions) ? cd.allowedActions : null;
  const gate = (key, clientGuard) => {
    if (allowedActions) {
      return allowedActions.includes(key) ? '' : clientGuard || '当前状态或角色不允许该动作';
    }
    return clientGuard || '';
  };
  const isCM = store.hasAnyRole(['CHANGE_MANAGER', 'ADMIN']);
  const isDev = store.hasAnyRole(['DEVELOPER', 'ADMIN']);
  const isTester = store.hasAnyRole(['TESTER', 'ADMIN']);
  const isRM = store.hasAnyRole(['RELEASE_MANAGER', 'ADMIN']);
  const status = cd.status;
  const devTasks = tasks.filter((task) => task.taskType === 'DEV');
  const devTasksOpen = devTasks.filter((task) => task.status !== 'DONE' && task.status !== 'CANCELLED');
  const devTrs = transports.filter((tr) => tr.trKind === 'DEV');
  const devTrsReleased = devTrs.length > 0 && devTrs.every((tr) => tr.trStatus === 'R');
  const allTasksClosed = tasks.every((task) => task.status === 'DONE' || task.status === 'CANCELLED');
  const approvalOk = cd.approvalState === 'APPROVED';

  const postAction = async (action, values) => {
    const body = Object.assign({ action, version: Number(cd.version) }, values || {});
    const result = await api.post('/change-documents/' + encodeURIComponent(cd.id) + '/actions', body);
    return { message: result && result.message ? result.message : ui.actionLabel(action) + '成功。' };
  };
  const actions = [];

  actions.push({
    key: 'EDIT',
    label: '编辑',
    icon: 'edit',
    hidden: status === 'CLOSED' || status === 'CANCELLED',
    disabledReason: isCM || isDev ? '' : '需要变更经理或开发角色',
    confirm: {
      title: '编辑变更文档',
      message: '保存后版本号 +1。',
      confirmText: '保存',
      values: {
        title: cd.title || '',
        targetSystem: cd.targetSystem || 'QAS',
        cycleId: cd.cycleId || '',
        owner: cd.owner || '',
        devLead: cd.devLead || '',
        testLead: cd.testLead || '',
        plannedImportAt: ui.toDateTimeInput(cd.plannedImportAt)
      },
      fields: editFields(cycles)
    },
    run: async (values) => {
      await api.patch('/change-documents/' + encodeURIComponent(cd.id), Object.assign({}, values, { version: Number(cd.version) }));
      return { message: '变更文档已更新。' };
    }
  });

  if (status === 'NEW') {
    actions.push({
      key: 'START_DEV',
      label: '开始开发',
      icon: 'work',
      tone: 'primary',
      disabledReason: gate('START_DEV', !isDev && !isCM ? '需要开发或变更经理角色' : cd.owner ? '' : '需要先指定负责人'),
      confirm: { title: '开始开发', message: '状态将变为「开发中」。', confirmText: '开始开发' },
      run: () => postAction('START_DEV')
    });
  }
  if (status === 'IN_DEV') {
    const guard = !isDev && !isTester && !isCM
      ? '需要开发 / 测试 / 变更经理角色'
      : devTasksOpen.length > 0
        ? '开发任务尚未全部完成（' + devTasksOpen.length + ' 个未完成）'
        : devTrs.length === 0
          ? '需要至少 1 条 DEV 传输'
          : '';
    actions.push({
      key: 'SUBMIT_TEST',
      label: '提交测试',
      icon: 'task',
      tone: 'primary',
      disabledReason: gate('SUBMIT_TEST', guard),
      confirm: { title: '提交测试', message: '提交后进入「测试中」，测试负责人执行测试结论。', confirmText: '提交测试' },
      run: () => postAction('SUBMIT_TEST')
    });
  }
  if (status === 'IN_TEST') {
    actions.push({
      key: 'PASS_TEST',
      label: '测试通过',
      icon: 'check',
      disabledReason: gate('PASS_TEST', isTester || isCM ? '' : '需要测试或变更经理角色'),
      confirm: {
        title: '记录测试结论',
        message: '测试通过只记录结论；进入「待导入」还需通过导入审批并释放全部 DEV 传输。',
        confirmText: '确认通过',
        fields: [{ name: 'comment', label: '测试结论（可选）', type: 'textarea', rows: 3 }]
      },
      run: (values) => postAction('PASS_TEST', { comment: values.comment || '' })
    });
    actions.push({
      key: 'SUBMIT_APPROVAL',
      label: '提交导入审批',
      icon: 'approval',
      disabledReason: gate('SUBMIT_APPROVAL', isCM ? '' : '需要变更经理角色'),
      confirm: { title: '提交导入审批', message: '按审批矩阵生成 CD 导入审批步骤。', confirmText: '提交' },
      run: () => postAction('SUBMIT_APPROVAL')
    });
    actions.push({
      key: 'MARK_READY',
      label: '标记待导入',
      icon: 'transport',
      tone: 'primary',
      disabledReason: gate('MARK_READY', !isRM && !isCM
        ? '需要发布管理员或变更经理角色'
        : cd.approvalState === 'PENDING'
          ? '导入审批尚未通过'
          : devTrs.length > 0 && !devTrsReleased
            ? 'DEV 传输未全部释放'
            : ''),
      confirm: { title: '标记待导入', message: '确认测试通过、审批完成、DEV 传输全部释放后继续。', confirmText: '标记待导入' },
      run: () => postAction('MARK_READY')
    });
  }
  if (status === 'READY_TO_IMPORT' || status === 'IMPORT_SCHEDULED') {
    actions.push({
      key: 'SCHEDULE_IMPORT',
      label: status === 'IMPORT_SCHEDULED' ? '调整导入计划' : '计划导入',
      icon: 'schedule',
      tone: 'primary',
      disabledReason: gate('SCHEDULE_IMPORT', isRM ? '' : '需要发布管理员角色'),
      confirm: {
        title: status === 'IMPORT_SCHEDULED' ? '调整导入计划（改期）' : '安排导入计划',
        message: '计划导入时间写入导入计划与 CD；冲突会返回 SCHEDULE_CONFLICT。',
        confirmText: '保存计划',
        fields: [{ name: 'plannedImportAt', label: '计划导入时间', type: 'datetime-local', required: true }]
      },
      run: (values) =>
        postAction('SCHEDULE_IMPORT', { plannedImportAt: ui.fromDateTimeInput(values.plannedImportAt) })
    });
    if (status === 'IMPORT_SCHEDULED') {
      actions.push({
        key: 'CANCEL_SCHEDULE',
        label: '取消计划',
        icon: 'x',
        disabledReason: gate('SCHEDULE_IMPORT', isRM ? '' : '需要发布管理员角色'),
        confirm: {
          title: '取消导入计划',
          message: '取消后 CD 回到「待导入」，计划状态置为已取消。',
          confirmText: '取消计划',
          danger: true,
          fields: [{ name: 'comment', label: '原因（可选）', type: 'textarea', rows: 2 }]
        },
        run: (values) => postAction('SCHEDULE_IMPORT', { cancelSchedule: true, comment: values.comment || '' })
      });
    }
    actions.push({
      key: 'CONFIRM_IMPORT',
      label: '确认导入',
      icon: 'check',
      tone: 'primary',
      disabledReason: gate('CONFIRM_IMPORT', isRM ? '' : '需要发布管理员角色'),
      confirm: {
        title: '确认导入完成',
        message: '确认后 CD 变为「已导入」，关联导入计划置为完成。',
        confirmText: '确认导入',
        fields: [{ name: 'importedAt', label: '导入时间（留空取当前时间）', type: 'datetime-local' }]
      },
      run: (values) => {
        const body = {};
        if (values.importedAt) body.importedAt = ui.fromDateTimeInput(values.importedAt);
        return postAction('CONFIRM_IMPORT', body);
      }
    });
  }
  if (status === 'IMPORTED') {
    actions.push({
      key: 'CLOSE',
      label: '关闭变更文档',
      icon: 'check',
      tone: 'primary',
      disabledReason: gate('CLOSE', isCM ? (allTasksClosed ? '' : '所有任务需已关闭或取消') : '需要变更经理角色'),
      confirm: { title: '关闭变更文档', message: '关闭后为终态，只读。', confirmText: '关闭', danger: true },
      run: () => postAction('CLOSE')
    });
  }
  if (status !== 'CLOSED' && status !== 'CANCELLED') {
    actions.push({
      key: 'CANCEL',
      label: '取消变更文档',
      icon: 'x',
      tone: 'danger',
      disabledReason: gate('CANCEL', isCM ? '' : '需要变更经理角色'),
      confirm: {
        title: '取消变更文档',
        message: '取消为终态，原因必填；已释放传输不回滚。',
        confirmText: '确认取消',
        danger: true,
        fields: [{ name: 'comment', label: '取消原因', type: 'textarea', required: true, rows: 3 }]
      },
      run: (values) => postAction('CANCEL', { comment: values.comment })
    });
  }
  return actions;
}

export async function mount(root, ctx) {
  const id = ctx.params.id;
  const tab = TABS.includes(ctx.query.tab) ? ctx.query.tab : 'overview';
  root.innerHTML = `<div class="page">${ui.loadingPanel('正在加载变更文档详情…')}</div>`;

  let cycles = [];
  try {
    cycles = ui.listOf(await api.get('/config/cycles'));
  } catch (err) {
    cycles = [];
  }

  let data = null;

  async function openTaskDialog(parentTask) {
    const values = await ui.confirmDialog({
      title: parentTask ? '新建子任务' : '新建任务',
      message: parentTask ? '子任务挂在任务「' + parentTask.title + '」下。' : '任务挂在当前变更文档下，可分派给开发 / 测试人员。',
      confirmText: '创建',
      fields: taskFields(),
      values: { taskType: 'DEV' }
    });
    if (!values) return;
    const body = Object.assign({}, values, { version: Number(data.cd.version) });
    if (values.estHours === '') delete body.estHours;
    if (values.dueDate === '') delete body.dueDate;
    const path = parentTask
      ? '/tasks/' + encodeURIComponent(parentTask.id) + '/subtasks'
      : '/change-documents/' + encodeURIComponent(id) + '/tasks';
    await runMutation(
      async () => {
        await api.post(path, body);
        return { message: parentTask ? '子任务已创建。' : '任务已创建。' };
      },
      { ctx, successMessage: '任务已创建。' }
    );
  }

  async function openTaskEdit(task) {
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
      values: {
        title: task.title || '',
        assignee: task.assignee || '',
        dueDate: ui.toDateInput(task.dueDate),
        estHours: task.estHours || ''
      }
    });
    if (!values) return;
    const body = Object.assign({}, values, { version: Number(task.version) });
    await runMutation(
      async () => {
        await api.patch('/tasks/' + encodeURIComponent(task.id), body);
        return { message: '任务已更新。' };
      },
      { ctx, successMessage: '任务已更新。' }
    );
  }

  async function linkTransport() {
    const values = await ui.confirmDialog({
      title: '关联传输',
      message: '传输在 SE01 或 abap-cli 创建；应用只写关联与状态快照。',
      confirmText: '关联',
      fields: transportLinkFields(),
      values: { trKind: 'DEV' }
    });
    if (!values) return;
    const body = {
      cdId: id,
      trkorr: values.trkorr,
      trKind: values.trKind,
      version: Number(data.cd.version)
    };
    if (values.taskId) body.taskId = values.taskId;
    await runMutation(
      async () => {
        await api.post('/transports/link', body);
        return { message: '传输已关联。' };
      },
      { ctx, successMessage: '传输已关联。' }
    );
  }

  async function scheduleAction(action) {
    const schedule = data.schedule;
    if (!schedule) return;
    let payload = { action, version: data.cd.version };
    if (action === 'RESCHEDULE') {
      const values = await ui.confirmDialog({
        title: '改期导入计划',
        message: '改期后状态回到「已计划」；与其它计划冲突会返回 SCHEDULE_CONFLICT。',
        confirmText: '保存新时间',
        danger: true,
        fields: [{ name: 'scheduledAt', label: '新的计划导入时间', type: 'datetime-local', required: true }],
        values: { scheduledAt: ui.toDateTimeInput(schedule.scheduledAt) }
      });
      if (!values) return;
      payload = { action, version: data.cd.version, scheduledAt: ui.fromDateTimeInput(values.scheduledAt) };
    } else if (action === 'CANCEL') {
      const values = await ui.confirmDialog({
        title: '取消导入计划',
        message: '取消后计划状态为「已取消」，CD 回到「待导入」。',
        confirmText: '确认取消',
        danger: true,
        fields: [{ name: 'note', label: '原因（可选）', type: 'textarea', rows: 2 }]
      });
      if (!values) return;
      payload = { action, version: data.cd.version, note: values.note || '' };
    } else if (action === 'CONFIRM') {
      const ok = await ui.confirmDialog({
        title: '确认计划完成',
        message: '确认后计划状态为「已完成」。',
        confirmText: '确认完成'
      });
      if (!ok) return;
    }
    await runMutation(
      async () => {
        await api.post('/schedules/' + encodeURIComponent(schedule.id) + '/actions', payload);
        return { message: ui.actionLabel(action) + '成功。' };
      },
      { ctx, successMessage: '计划已更新。' }
    );
  }

  function bindDynamic(rootEl) {
  const offs = [];
  const on = (selector, event, handler) => offs.push(ui.delegate(rootEl, selector, event, handler));
    on('[data-action="retry"]', 'click', () => render());
    on('[data-action="refresh"]', 'click', () => render());
    on('[data-toggle-sub]', 'click', (event, el) => {
      const parentId = el.getAttribute('data-toggle-sub');
      const row = rootEl.querySelector(`[data-sub-row="${parentId}"]`);
      if (!row) return;
      const willShow = row.classList.toggle('hidden') === false;
      el.innerHTML = ui.icon(willShow ? 'chevronDown' : 'chevronRight', 12);
    });
    on('[data-action="new-task"]', 'click', () => openTaskDialog(null));
    on('[data-action="new-subtask"]', 'click', () => openTaskDialog(null));
    on('[data-task-edit]', 'click', (event, el) => {
      const task = data.tasks.find((item) => item.id === el.getAttribute('data-task-edit'));
      if (task) openTaskEdit(task);
    });
    on('[data-task-action]', 'click', async (event, el) => {
      const action = el.getAttribute('data-task-action');
      const task = data.tasks.find((item) => item.id === el.getAttribute('data-task-id'));
      if (!task) return;
      let payload = { action, version: Number(task.version) };
      if (action === 'CANCEL') {
        const values = await ui.confirmDialog({
          title: '取消任务',
          message: '取消任务为终态，原因必填。',
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
    });
    on('[data-action="link-tr"]', 'click', () => linkTransport());
    on('[data-action="sync-all"]', 'click', async (event, el) => {
      await runMutation(
        async () => {
          await api.post('/transports/sync', { cdId: id });
          return { message: '已触发传输状态同步。' };
        },
        { ctx, button: el, successMessage: '已触发传输状态同步。' }
      );
    });
    on('[data-tr-action]', 'click', async (event, el) => {
      const action = el.getAttribute('data-tr-action');
      const trkorr = el.getAttribute('data-trkorr');
      const tr = data.transports.find((item) => item.trkorr === trkorr);
      if (!tr) return;
      if (action === 'sync') {
        await runMutation(
          async () => {
            await api.post('/transports/sync', { trkorr });
            return { message: '已同步传输 ' + trkorr + '。' };
          },
          { ctx, button: el, successMessage: '已同步。' }
        );
        return;
      }
      if (action === 'unlink') {
        const values = await ui.confirmDialog({
          title: '解绑传输',
          message: '解绑仅对可修改（D）传输可用；历史保留审计记录。',
          confirmText: '确认解绑',
          danger: true,
          fields: [{ name: 'comment', label: '原因（可选）', type: 'textarea', rows: 2 }]
        });
        if (!values) return;
        await runMutation(
          async () => {
            await api.post('/transports/' + encodeURIComponent(trkorr) + '/unlink', {
              version: Number(data.cd.version),
              comment: values.comment || ''
            });
            return { message: '传输已解绑。' };
          },
          { ctx, button: el, successMessage: '传输已解绑。' }
        );
        return;
      }
      if (action === 'detach') {
        const values = await ui.confirmDialog({
          title: '标记不再关联',
          message: '已释放 / 已导入的传输不能解绑，只能标记「不再关联」并保留审计。原因必填。',
          confirmText: '确认标记',
          danger: true,
          fields: [{ name: 'reason', label: '原因', type: 'textarea', required: true, rows: 3 }]
        });
        if (!values) return;
        await runMutation(
          async () => {
            await api.post('/transports/' + encodeURIComponent(trkorr) + '/mark-detached', { reason: values.reason });
            return { message: '已标记不再关联。' };
          },
          { ctx, button: el, successMessage: '已标记不再关联。' }
        );
      }
    });
    on('[data-sched-action]', 'click', (event, el) => scheduleAction(el.getAttribute('data-sched-action')));
    on('[data-action="new-schedule"]', 'click', () => {
      const bar = rootEl.querySelector('[data-action-bar] [data-action-key="SCHEDULE_IMPORT"]');
      if (bar && !bar.disabled) bar.click();
      else ui.toast('需要先将变更文档标记为「待导入」。', { type: 'warn' });
    });
  return offs;
}

async function render() {
    try {
      const cd = await api.get('/change-documents/' + encodeURIComponent(id));
      // 真实 API：详情扁平返回 tasks / transports / schedule / approvalSteps；缺失时回退到子端点。
      const [tasksRaw, trsRaw, stepsRaw, schedRaw] = await Promise.all([
        Array.isArray(cd.tasks)
          ? Promise.resolve(cd.tasks)
          : api.get('/change-documents/' + encodeURIComponent(id) + '/tasks').catch(() => []),
        Array.isArray(cd.transports)
          ? Promise.resolve(cd.transports)
          : api.get('/change-documents/' + encodeURIComponent(id) + '/transports').catch(() => []),
        Array.isArray(cd.approvalSteps)
          ? Promise.resolve(cd.approvalSteps)
          : api.get('/approvals/steps', { objectType: 'CD', objectId: id }).catch(() => []),
        Object.prototype.hasOwnProperty.call(cd, 'schedule')
          ? Promise.resolve(cd.schedule)
          : api.get('/change-documents/' + encodeURIComponent(id) + '/schedule').catch(() => null)
      ]);
      const tasks = ui.listOf(tasksRaw);
      const transports = ui.listOf(trsRaw);
      const steps = ui.listOf(stepsRaw);
      const schedule = schedRaw
        ? Array.isArray(schedRaw)
          ? schedRaw[0] || null
          : schedRaw.schedule || schedRaw
        : null;
      data = { cd, tasks, transports, steps, schedule };

      const actions = buildActions(cd, tasks, transports, steps, cycles);
      const tabsHtml = ui.tabs({
        items: [
          { key: 'overview', label: '概览' },
          { key: 'tasks', label: '任务', count: tasks.length },
          { key: 'transports', label: '传输', count: transports.length },
          { key: 'schedule', label: '导入计划' },
          { key: 'approvals', label: '审批', count: steps.length }
        ],
        active: tab
      });
      let tabBody = overviewTab(cd, tasks, transports, schedule);
      if (tab === 'tasks') tabBody = tasksTab(cd, tasks);
      else if (tab === 'transports') tabBody = transportsTab(cd, transports);
      else if (tab === 'schedule') tabBody = scheduleTab(cd, schedule);
      else if (tab === 'approvals') tabBody = approvalsTab(steps);

      root.innerHTML = `<div class="page">
        ${header(cd)}
        ${actionBar(actions)}
        <div class="panel">
          ${tabsHtml}
          ${tabBody}
        </div>
      </div>`;

      bindActionBar(root, ctx, actions);
      ui.bindOnce(root, 'cd-detail', () => bindDynamic(root));
      ui.bindTabs(root, (key) => ctx.setQuery({ tab: key }));
    } catch (err) {
      const info = describeError(err);
      const isNotFound = err && (err.status === 404 || err.code === 'NOT_FOUND');
      root.innerHTML = `<div class="page">
        ${ui.pageHeader({
          title: '变更文档详情',
          breadcrumb: [
            { label: '工作台', href: '#/dashboard' },
            { label: '变更文档 CD', href: '#/change-documents' },
            { label: id }
          ]
        })}
        <div class="panel"><div class="panel-body">${ui.errorPanel({
          title: isNotFound ? '变更文档不存在' : info.title,
          message: isNotFound ? '该变更文档不存在或已被删除。' : info.message,
          correlationId: info.correlationId
        })}</div><div class="panel-body tight"><a class="btn btn-sm" href="#/change-documents">返回变更文档列表</a></div></div>
      </div>`;
    }
  }

  await render();
  return () => {
    ui.releaseOnce(root, 'cd-detail');
    void formBody;
  };
}
