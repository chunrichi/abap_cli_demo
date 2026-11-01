/**
 * pages/request-detail.js — 请求详情：头部 + 动作条 + 概览 / 审批 / 变更文档 / 任务 / 备注 / 历史。
 */

import { api, describeError } from '../api.js';
import * as store from '../store.js';
import * as ui from '../ui.js';
import { actionBar, bindActionBar, runMutation } from '../components/action-bar.js';
import { timeline } from '../components/timeline.js';

const EDIT_FIELDS = [
  { name: 'title', label: '标题', type: 'text', required: true, maxlength: 120, span: 'all' },
  { name: 'description', label: '描述', type: 'textarea', rows: 4, span: 'all' },
  {
    name: 'priority',
    label: '优先级',
    type: 'select',
    options: [
      { value: '', label: '未定' },
      { value: '1', label: '紧急' },
      { value: '2', label: '高' },
      { value: '3', label: '中' },
      { value: '4', label: '低' }
    ]
  },
  { name: 'component', label: '组件', type: 'text', required: true, placeholder: '如 MM-PUR' },
  { name: 'cycleId', label: '周期', type: 'select', options: [] },
  { name: 'owner', label: '负责人', type: 'text', placeholder: 'SAP 用户名' },
  { name: 'plannedStart', label: '计划开始', type: 'date', required: true },
  { name: 'plannedEnd', label: '计划结束', type: 'date', required: true },
  { name: 'dueDate', label: '截止日', type: 'date' }
];

function cdCreateFields(cycles) {
  return [
    { name: 'title', label: '变更文档标题', type: 'text', required: true, maxlength: 120, span: 'all' },
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

function header(req) {
  const badges = [
    ui.statusBadge(req.status),
    req.approvalState ? ui.apprStateBadge(req.approvalState) : '',
    ui.priorityBadge(req.priority),
    ui.requestTypeBadge(req.requestType)
  ]
    .filter(Boolean)
    .join(' ');
  const meta = [
    `<span>请求人 <b>${ui.esc(req.requester || '—')}</b></span>`,
    `<span>负责人 <b>${ui.esc(req.owner || '—')}</b></span>`,
    `<span>组件 <b>${ui.esc(req.component || '—')}</b></span>`,
    `<span>周期 <b>${ui.esc(req.cycleId || '—')}</b></span>`,
    `<span>版本 <b>v${ui.esc(req.version === undefined ? '—' : req.version)}</b></span>`,
    `<span>创建 ${ui.fmtDateTime(req.createdAt)} · ${ui.esc(req.createdBy || '—')}</span>`,
    `<span>更新 ${ui.fmtDateTime(req.changedAt)} · ${ui.esc(req.changedBy || '—')}</span>`,
    `<span>时区 <b>SAP_SYSTEM</b></span>`
  ].join('');
  return ui.pageHeader({
    title: (req.displayId || req.id || '') + ' · ' + (req.title || ''),
    titleExtra: '',
    breadcrumb: [
      { label: '工作台', href: '#/dashboard' },
      { label: '请求 CR', href: '#/requests' },
      { label: req.displayId || req.id }
    ],
    meta: meta,
    actions: `<a class="btn btn-sm" href="#/requests">${ui.icon('chevronLeft', 15)}返回列表</a>
      <button type="button" class="btn btn-sm" data-action="refresh">${ui.icon('refresh', 15)}刷新</button>`
  }).replace('</h1>', '</h1><div class="page-meta" style="margin-top:2px">' + badges + '</div>');
}

function overviewTab(req, steps, cds) {
  const currentStep = steps
    .slice()
    .sort((a, b) => Number(a.stepNo) - Number(b.stepNo))
    .find((step) => step.apprState === 'PENDING');
  return `<div class="panel"><div class="panel-head"><span class="panel-title">基本信息</span></div>
    <div class="panel-body">
      ${ui.kvList([
        { label: '显示编号', value: req.displayId || req.id },
        { label: '请求类型', html: ui.requestTypeBadge(req.requestType) },
        { label: '状态', html: ui.statusBadge(req.status) },
        { label: '审批状态', html: req.approvalState ? ui.apprStateBadge(req.approvalState) : '—' },
        { label: '优先级', html: ui.priorityBadge(req.priority) },
        { label: '组件', value: req.component },
        { label: '周期', value: req.cycleId },
        { label: '请求人', value: req.requester },
        { label: '负责人', value: req.owner },
        { label: '计划开始', value: ui.fmtDate(req.plannedStart) },
        { label: '计划结束', value: ui.fmtDate(req.plannedEnd) },
        { label: '截止日', value: ui.fmtDate(req.dueDate) },
        { label: '创建', value: ui.fmtDateTime(req.createdAt) + ' · ' + (req.createdBy || '—') },
        { label: '最后更新', value: ui.fmtDateTime(req.changedAt) + ' · ' + (req.changedBy || '—') },
        { label: '关闭时间', value: ui.fmtDateTime(req.closedAt) },
        { label: '当前审批步骤', value: currentStep ? `第 ${currentStep.stepNo} 步 · ${currentStep.approver}` : '—' },
        { label: '变更文档', value: String(cds.length) + ' 个' }
      ])}
      ${req.cancelReason ? `<div class="desc-block"><strong>取消原因：</strong>${ui.esc(req.cancelReason)}</div>` : ''}
      <div class="desc-block"><div class="field-label" style="margin-bottom:6px">描述</div>${
        req.description ? ui.esc(req.description) : '<span class="muted">（未填写描述）</span>'
      }</div>
    </div></div>`;
}

function approvalsTab(steps) {
  if (steps.length === 0) {
    return ui.emptyPanel({
      icon: 'approval',
      title: '还没有审批步骤',
      hint: '提交请求（SUBMIT）后按审批矩阵生成审批步骤。'
    });
  }
  const rows = steps
    .map((step) => {
      const current = step.apprState === 'PENDING' ? ' style="background:#f8fafc"' : '';
      return `<tr${current}>
        <td>${ui.esc(step.stepNo)}</td>
        <td>${ui.esc(step.approver || '—')}</td>
        <td>${ui.apprStateBadge(step.apprState)}</td>
        <td class="nowrap">${ui.fmtDateTime(step.decidedAt)}</td>
        <td><div class="cell-clip small">${ui.esc(step.comment || '—')}</div></td>
      </tr>`;
    })
    .join('');
  return `<div class="table-wrap"><table class="data fixed" style="min-width:760px">
    <colgroup><col style="width:64px"><col style="width:160px"><col style="width:110px"><col style="width:160px"><col></colgroup>
    <thead><tr><th>步骤</th><th>审批人</th><th>状态</th><th>决策时间</th><th>意见</th></tr></thead>
    <tbody>${rows}</tbody></table></div>
    <div class="panel-body tight muted small">审批操作也可在「审批中心」处理；驳回意见必填，请求人不能审批自己的请求。</div>`;
}

function cdsTab(cds) {
  if (cds.length === 0) {
    return ui.emptyPanel({
      icon: 'cd',
      title: '还没有变更文档',
      hint: '请求批准后可创建变更文档（CD），再拆分开发 / 测试任务与传输。',
      actionLabel: '新建变更文档',
      action: 'new-cd'
    });
  }
  const rows = cds
    .map(
      (cd) => `<tr>
      <td><span class="mono">${ui.esc(cd.displayId || cd.id)}</span></td>
      <td><div class="cell-clip"><a class="row-title" href="#/change-documents/${encodeURIComponent(cd.id)}" title="${ui.esc(
        cd.title || ''
      )}">${ui.esc(cd.title || '—')}</a></div></td>
      <td>${ui.statusBadge(cd.status)}</td>
      <td>${ui.esc(cd.targetSystem || '—')}</td>
      <td class="nowrap">${ui.fmtDateTime(cd.plannedImportAt)}</td>
      <td>${ui.esc(cd.owner || '—')}</td>
    </tr>`
    )
    .join('');
  return `<div class="table-wrap"><table class="data fixed" style="min-width:900px">
    <colgroup><col style="width:116px"><col><col style="width:130px"><col style="width:80px"><col style="width:160px"><col style="width:120px"></colgroup>
    <thead><tr><th>编号</th><th>标题</th><th>状态</th><th>目标系统</th><th>计划导入</th><th>负责人</th></tr></thead>
    <tbody>${rows}</tbody></table></div>`;
}

function tasksTab(tasks) {
  if (tasks.length === 0) {
    return ui.emptyPanel({ icon: 'task', title: '暂无任务', hint: '任务挂在变更文档下；进入 CD 详情创建开发 / 测试任务。' });
  }
  const rows = tasks
    .map(
      (task) => `<tr>
      <td><span class="mono">${ui.esc(task.displayId || task.id)}</span></td>
      <td><div class="cell-clip">${ui.esc(task.title || '—')}${task.parentTaskId ? ' <span class="chip">子任务</span>' : ''}</div></td>
      <td><span class="mono">${ui.esc(task.cdId || '—')}</span></td>
      <td>${ui.taskTypeBadge(task.taskType)}</td>
      <td>${ui.esc(task.assignee || '—')}</td>
      <td>${ui.statusBadge(task.status)}</td>
      <td class="nowrap"${ui.isOverdue(task.dueDate) && task.status !== 'DONE' ? ' style="color:var(--danger)"' : ''}>${ui.fmtDate(
        task.dueDate
      )}</td>
    </tr>`
    )
    .join('');
  return `<div class="table-wrap"><table class="data fixed" style="min-width:900px">
    <colgroup><col style="width:92px"><col><col style="width:100px"><col style="width:80px"><col style="width:110px"><col style="width:110px"><col style="width:110px"></colgroup>
    <thead><tr><th>编号</th><th>任务</th><th>CD</th><th>类型</th><th>指派人</th><th>状态</th><th>截止日</th></tr></thead>
    <tbody>${rows}</tbody></table></div>`;
}

function notesTab(notes, req) {
  const list = notes
    .map(
      (note) => `<div class="tl-item">
      <span class="tl-dot"></span>
      <div class="tl-head"><span class="tl-action">${ui.esc(note.author || '—')}</span>${
        note.visibility ? `<span class="chip">${ui.esc(note.visibility)}</span>` : ''
      }</div>
      <div class="tl-meta"><span>${ui.fmtDateTime(note.createdAt)}</span><span>${ui.fmtRelative(note.createdAt)}</span></div>
      <div class="tl-comment">${ui.esc(note.text || '')}</div>
    </div>`
    )
    .join('');
  return `<div class="panel" style="margin-bottom:0">
    <div class="panel-head"><span class="panel-title">备注</span><span class="right muted small">${notes.length} 条</span></div>
    <div class="panel-body">${
      notes.length ? `<div class="timeline">${list}</div>` : '<div class="muted">还没有备注。</div>'
    }</div>
    <form class="filters" data-note-form style="border-top:1px solid var(--border);border-bottom:0">
      <div class="field" data-field="text">
        <label class="field-label" for="note-text">新增备注 <span class="req">*</span></label>
        <textarea class="textarea" id="note-text" name="text" rows="3" placeholder="补充说明、决策依据或沟通结论"></textarea>
        <div class="field-error" data-error-for="text"></div>
      </div>
      <div class="filter-foot">
        <span class="muted small">备注可留空？不可以：请填写内容后再提交。</span>
        <span class="spacer" style="margin-left:auto"></span>
        <button type="submit" class="btn btn-primary btn-sm" data-note-submit>添加备注</button>
      </div>
    </form>
  </div>`;
}

function tabPanelContent(tab, data) {
  if (tab === 'approvals') return approvalsTab(data.steps);
  if (tab === 'cds') return cdsTab(data.cds);
  if (tab === 'tasks') return tasksTab(data.tasks);
  if (tab === 'notes') return notesTab(data.notes, data.req);
  if (tab === 'history') {
    return `<div class="panel"><div class="panel-head"><span class="panel-title">历史 / 审计</span></div>
      <div class="panel-body">${timeline(data.history)}</div></div>`;
  }
  return overviewTab(data.req, data.steps, data.cds);
}

function buildActions(req, steps, cds) {
  // 服务端 allowedActions 为权威；客户端规则只用于生成禁用原因（前端隐藏按钮不是安全边界）。
  const allowedActions = Array.isArray(req.allowedActions) ? req.allowedActions : null;
  const gate = (key, clientGuard) => {
    if (allowedActions) {
      return allowedActions.includes(key) ? '' : clientGuard || '当前状态或角色不允许该动作';
    }
    return clientGuard || '';
  };
  const me = store.userName();
  const isCM = store.hasAnyRole(['CHANGE_MANAGER', 'ADMIN']);
  const isDev = store.hasAnyRole(['DEVELOPER', 'ADMIN']);
  const isRequester = req.requester === me;
  const status = req.status;
  const currentStep = steps
    .slice()
    .sort((a, b) => Number(a.stepNo) - Number(b.stepNo))
    .find((step) => step.apprState === 'PENDING');
  const canApprove = Boolean(currentStep && currentStep.approver === me);
  const allCdsClosed = cds.length > 0 && cds.every((cd) => cd.status === 'CLOSED' || cd.status === 'CANCELLED');
  const actions = [];

  const submitGuard = isRequester || isCM ? '' : '只有请求人或变更经理可以提交';
  const cancelRole = status === 'NEW' ? isRequester || isCM : isCM;
  const cancelGuard = cancelRole ? '' : status === 'NEW' ? '只有请求人或变更经理可以取消' : '只有变更经理可以取消';

  const postAction = async (action, values) => {
    const body = Object.assign({ action, version: Number(req.version) }, values || {});
    const result = await api.post('/requests/' + encodeURIComponent(req.id) + '/actions', body);
    return { message: result && result.message ? result.message : ui.actionLabel(action) + '成功。' };
  };

  if (status === 'NEW' || status === 'REJECTED') {
    actions.push({
      key: 'EDIT',
      label: '编辑',
      icon: 'edit',
      disabledReason: isRequester || isCM ? '' : '只有请求人或变更经理可以编辑',
      confirm: {
        title: '编辑请求头部字段',
        message: '仅「新建 / 已拒绝」状态可编辑；保存会更新版本号。',
        confirmText: '保存',
        values: {
          title: req.title || '',
          description: req.description || '',
          priority: req.priority === null || req.priority === undefined ? '' : String(req.priority),
          component: req.component || '',
          cycleId: req.cycleId || '',
          owner: req.owner || '',
          plannedStart: ui.toDateInput(req.plannedStart),
          plannedEnd: ui.toDateInput(req.plannedEnd),
          dueDate: ui.toDateInput(req.dueDate)
        },
        fields: EDIT_FIELDS
      },
      run: async (values) => {
        const body = {};
        EDIT_FIELDS.forEach((def) => {
          if (Object.prototype.hasOwnProperty.call(values, def.name)) body[def.name] = values[def.name];
        });
        await api.patch('/requests/' + encodeURIComponent(req.id), Object.assign(body, { version: Number(req.version) }));
        return { message: '请求已更新。' };
      }
    });
  }
  if (status === 'NEW') {
    actions.push({
      key: 'SUBMIT',
      label: '提交审批',
      icon: 'check',
      tone: 'primary',
      disabledReason: gate('SUBMIT', submitGuard),
      confirm: {
        title: '提交审批',
        message: '提交后按审批矩阵生成审批步骤，审批中不能编辑头部字段。',
        confirmText: '提交'
      },
      run: () => postAction('SUBMIT')
    });
  }
  if (status === 'PENDING_APPROVAL') {
    const approveGuard = canApprove ? '' : currentStep ? `当前审批人：${currentStep.approver}` : '当前没有待审批步骤';
    actions.push({
      key: 'APPROVE_STEP',
      label: '通过当前步骤',
      icon: 'check',
      tone: 'primary',
      disabledReason: gate('APPROVE_STEP', approveGuard),
      confirm: {
        title: '通过当前审批步骤',
        message: '通过末步后请求将变为「已批准」。意见可选。',
        confirmText: '通过',
        fields: [{ name: 'comment', label: '审批意见（可选）', type: 'textarea', rows: 3 }]
      },
      run: (values) => postAction('APPROVE_STEP', { comment: values.comment || '' })
    });
    actions.push({
      key: 'REJECT',
      label: '驳回',
      icon: 'x',
      tone: 'danger',
      disabledReason: gate('REJECT', approveGuard),
      confirm: {
        title: '驳回请求',
        message: '驳回后请求变为「已拒绝」，请求人可修改后重新提交。驳回原因必填。',
        confirmText: '确认驳回',
        danger: true,
        fields: [{ name: 'comment', label: '驳回原因', type: 'textarea', required: true, rows: 3 }]
      },
      run: (values) => postAction('REJECT', { comment: values.comment })
    });
    actions.push({
      key: 'WITHDRAW',
      label: '撤回',
      icon: 'chevronLeft',
      disabledReason: gate('WITHDRAW', submitGuard),
      confirm: { title: '撤回提交', message: '撤回后请求回到「新建」，未决审批步骤标记为跳过。', confirmText: '撤回' },
      run: () => postAction('WITHDRAW')
    });
  }
  if (status === 'REJECTED') {
    actions.push({
      key: 'REVISE',
      label: '修改后重提',
      icon: 'edit',
      tone: 'primary',
      disabledReason: gate('REVISE', submitGuard),
      confirm: { title: '回到新建状态', message: '请求回到「新建」，修改后可重新提交审批。', confirmText: '继续' },
      run: () => postAction('REVISE')
    });
  }
  if (status === 'APPROVED') {
    actions.push({
      key: 'START_PROGRESS',
      label: '开始进行',
      icon: 'work',
      tone: 'primary',
      disabledReason: gate('START_PROGRESS', isCM || isDev ? (cds.length === 0 ? '需要至少 1 个变更文档' : '') : '需要变更经理或开发角色'),
      confirm: { title: '开始进行', message: '建议先创建变更文档（CD）再开始推进。', confirmText: '开始' },
      run: () => postAction('START_PROGRESS')
    });
  }
  if (status === 'IN_PROGRESS') {
    actions.push({
      key: 'CLOSE',
      label: '关闭请求',
      icon: 'check',
      disabledReason: gate('CLOSE', isCM ? (allCdsClosed ? '' : '所有变更文档已关闭或取消') : '只有变更经理可以关闭'),
      confirm: { title: '关闭请求', message: '关闭后请求为终态，只读且不可重开。', confirmText: '关闭', danger: true },
      run: () => postAction('CLOSE')
    });
  }
  if (status !== 'CLOSED' && status !== 'CANCELLED') {
    actions.push({
      key: 'CANCEL',
      label: '取消请求',
      icon: 'x',
      tone: 'danger',
      disabledReason: gate('CANCEL', cancelGuard),
      confirm: {
        title: '取消请求',
        message: '取消为终态操作，必须填写原因；未决审批步骤将终止。',
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
  const tab = ctx.query.tab && ['overview', 'approvals', 'cds', 'tasks', 'notes', 'history'].includes(ctx.query.tab)
    ? ctx.query.tab
    : 'overview';

  root.innerHTML = `<div class="page">${ui.loadingPanel('正在加载请求详情…')}</div>`;
  let cycles = [];
  try {
    cycles = ui.listOf(await api.get('/config/cycles'));
  } catch (err) {
    cycles = [];
  }
  EDIT_FIELDS[4].options = [{ value: '', label: '不指定周期' }].concat(
    cycles.map((cycle) => ({ value: cycle.id, label: cycle.id + (cycle.description ? ' · ' + cycle.description : '') }))
  );
  ui.bindOnce(root, 'request-detail', () => [
    ui.delegate(root, '[data-action="retry"]', 'click', () => mount(root, ctx)),
    ui.delegate(root, '[data-action="refresh"]', 'click', () => ctx.reload()),
    ui.delegate(root, '[data-action="new-cd"]', 'click', () => {
      const bar = root.querySelector('[data-action-bar] [data-action-key="NEW_CD"]');
      if (bar && !bar.disabled) {
        bar.click();
      } else {
        ui.toast('请求批准后才能创建变更文档。', { type: 'warn', title: '当前状态不允许' });
      }
    })
  ]);

  let data = null;
  async function load() {
    try {
      const [req, stepsRaw, historyRaw, notesRaw, tasksRaw] = await Promise.all([
        api.get('/requests/' + encodeURIComponent(id)),
        api.get('/approvals/steps', { objectType: 'REQ', objectId: id }).catch(() => []),
        api.get('/requests/' + encodeURIComponent(id) + '/history').catch(() => []),
        api.get('/requests/' + encodeURIComponent(id) + '/notes').catch(() => []),
        api.get('/tasks', { reqId: id, size: 200 }).catch(() => [])
      ]);
      const steps = ui.listOf(stepsRaw);
      const history = ui.listOf(historyRaw);
      const notes = ui.listOf(notesRaw);
      let cdsRaw = req.changeDocuments;
      if (!Array.isArray(cdsRaw)) {
        cdsRaw = await api.get('/requests/' + encodeURIComponent(id) + '/change-documents').catch(() => null);
      }
      const cds = ui.listOf(cdsRaw);
      const tasks = ui.listOf(tasksRaw);
      data = { req, steps, history, notes, cds, tasks };

      const actions = buildActions(req, steps, cds);
      actions.push({
        key: 'NEW_CD',
        label: '新建变更文档',
        icon: 'plus',
        hidden: !(req.status === 'APPROVED' || req.status === 'IN_PROGRESS'),
        disabledReason: store.hasAnyRole(['CHANGE_MANAGER', 'DEVELOPER', 'ADMIN'])
          ? ''
          : '需要变更经理或开发角色',
        confirm: {
          title: '新建变更文档',
          message: '变更文档挂在当前请求下，可继续拆分任务与关联传输。',
          confirmText: '创建',
          values: { targetSystem: 'QAS' },
          fields: cdCreateFields(cycles)
        },
        run: async (values) => {
          const body = Object.assign({}, values, { version: Number(req.version) });
          const created = await api.post('/requests/' + encodeURIComponent(req.id) + '/change-documents', body);
          return { message: '变更文档已创建' + (created && (created.displayId || created.id) ? '：' + (created.displayId || created.id) : '') + '。' };
        }
      });

      const tabsHtml = ui.tabs({
        items: [
          { key: 'overview', label: '概览' },
          { key: 'approvals', label: '审批', count: steps.length },
          { key: 'cds', label: '变更文档', count: cds.length },
          { key: 'tasks', label: '任务', count: tasks.length },
          { key: 'notes', label: '备注', count: notes.length },
          { key: 'history', label: '历史' }
        ],
        active: tab
      });

      root.innerHTML = `<div class="page">
        ${header(req)}
        ${actionBar(actions)}
        <div class="panel">
          ${tabsHtml}
          <div data-tab-body>${tabPanelContent(tab, data)}</div>
        </div>
      </div>`;

      bindActionBar(root, ctx, actions);
      ui.bindTabs(root, (key) => ctx.setQuery({ tab: key }));

      const noteForm = root.querySelector('[data-note-form]');
      if (noteForm) {
        noteForm.addEventListener('submit', async (event) => {
          event.preventDefault();
          const values = ui.readFormValues(noteForm);
          const errors = ui.validateValues(values, [{ name: 'text', required: true }]);
          ui.showFieldErrors(noteForm, errors);
          if (Object.keys(errors).length > 0) return;
          const button = noteForm.querySelector('[data-note-submit]');
          await runMutation(
            async () => {
              await api.post('/requests/' + encodeURIComponent(req.id) + '/notes', {
                text: values.text,
                version: Number(req.version)
              });
              return { message: '备注已添加。' };
            },
            { ctx, button, successMessage: '备注已添加。' }
          );
        });
      }
    } catch (err) {
      const info = describeError(err);
      const isNotFound = err && (err.status === 404 || err.code === 'NOT_FOUND');
      root.innerHTML = `<div class="page">
        ${ui.pageHeader({
          title: '请求详情',
          breadcrumb: [{ label: '工作台', href: '#/dashboard' }, { label: '请求 CR', href: '#/requests' }, { label: id }]
        })}
        <div class="panel"><div class="panel-body">${ui.errorPanel({
          title: isNotFound ? '请求不存在' : info.title,
          message: isNotFound ? '该请求不存在或已被删除。' : info.message,
          correlationId: info.correlationId
        })}</div>
        <div class="panel-body tight"><a class="btn btn-sm" href="#/requests">返回请求列表</a></div></div>
      </div>`;
    }
  }

  await load();
  return () => {
    ui.releaseOnce(root, 'request-detail');
    void data;
  };
}
