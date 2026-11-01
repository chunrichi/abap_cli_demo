/**
 * pages/dashboard.js — 工作台首页：KPI、最近动态、快捷入口、系统提示。
 */

import { api, describeError } from '../api.js';
import * as store from '../store.js';
import * as ui from '../ui.js';

const RECENT_LINK = {
  REQ: (row) => '#/requests/' + encodeURIComponent(row.objectId),
  CD: (row) => '#/change-documents/' + encodeURIComponent(row.objectId),
  TASK: (row) => '#/tasks?q=' + encodeURIComponent(row.displayId || row.objectId),
  TR: (row) => '#/transports/' + encodeURIComponent(row.objectId),
  SCHED: () => '#/schedule'
};

function kpiCard(def, value) {
  const alert = def.alert && Number(value) > 0 ? ' alert' : '';
  const warn = def.warn && Number(value) > 0 ? ' warn' : '';
  return `<a class="kpi${alert}${warn}" href="${ui.esc(def.href)}">
    <span class="kpi-label">${ui.icon(def.icon, 14)}${ui.esc(def.label)}</span>
    <strong class="kpi-value">${ui.fmtNum(value)}</strong>
    <span class="kpi-note">${ui.esc(def.note)}</span>
  </a>`;
}

function kpiDefs() {
  const me = encodeURIComponent(store.userName());
  return [
    { key: 'myApprovals', label: '我的待审批', note: '前往审批中心', href: '#/approvals', icon: 'approval' },
    { key: 'myTasks', label: '我的任务', note: '待开始 / 进行中', href: '#/tasks?assignee=' + me, icon: 'task' },
    { key: 'pendingRequests', label: '待处理请求', note: '待审批的请求', href: '#/requests?status=PENDING_APPROVAL', icon: 'request' },
    { key: 'inDev', label: '开发中', note: '变更文档', href: '#/change-documents?status=IN_DEV', icon: 'cd' },
    { key: 'readyToImport', label: '待导入', note: '变更文档', href: '#/change-documents?status=READY_TO_IMPORT', icon: 'transport' },
    { key: 'overdue', label: '逾期事项', note: '任务 / 计划 / 审批', href: '#/reports?tab=overdue', icon: 'clock', alert: true }
  ];
}

function recentPanel(recent) {
  if (!recent || recent.length === 0) {
    return ui.emptyPanel({ icon: 'history', title: '暂无最近动态', hint: '创建请求、推进状态或审批后，这里会显示变更动态。' });
  }
  const rows = recent
    .map((row) => {
      const href = RECENT_LINK[row.objectType] ? RECENT_LINK[row.objectType](row) : '';
      const titleText = row.title || row.displayId || row.objectId || '—';
      const title = href
        ? `<a class="row-title" href="${ui.esc(href)}" title="${ui.esc(titleText)}">${ui.esc(titleText)}</a>`
        : `<span title="${ui.esc(titleText)}">${ui.esc(titleText)}</span>`;
      return `<tr>
        <td>${ui.objectTypeBadge(row.objectType)}</td>
        <td><span class="mono">${ui.esc(row.displayId || row.objectId)}</span></td>
        <td><div class="cell-clip">${title}</div></td>
        <td>${ui.esc(ui.actionLabel(row.action))}</td>
        <td>${ui.fmtRelative(row.changedAt)}</td>
        <td>${ui.esc(row.changedBy || '—')}</td>
      </tr>`;
    })
    .join('');
  return `<div class="table-wrap"><table class="data fixed" style="min-width:860px">
    <colgroup><col style="width:90px"><col style="width:120px"><col><col style="width:110px"><col style="width:100px"><col style="width:110px"></colgroup>
    <thead><tr><th>类型</th><th>编号</th><th>标题</th><th>动作</th><th>时间</th><th>操作人</th></tr></thead>
    <tbody>${rows}</tbody></table></div>`;
}

function quickLinks() {
  const links = [
    { href: '#/requests/new', icon: 'plus', title: '新建请求', desc: '创建标准 / 紧急 / 管理变更' },
    { href: '#/my-work', icon: 'work', title: '我的工作', desc: '待办、我的请求与任务' },
    { href: '#/approvals', icon: 'approval', title: '审批中心', desc: '处理待我审批的步骤' },
    { href: '#/schedule', icon: 'schedule', title: '导入计划', desc: '查看近期导入日程' }
  ];
  return `<div class="kpi-grid" style="margin-bottom:0">${links
    .map(
      (link) => `<a class="kpi" href="${ui.esc(link.href)}" style="padding:12px 14px">
        <span class="kpi-label">${ui.icon(link.icon, 14)}${ui.esc(link.title)}</span>
        <span class="kpi-note">${ui.esc(link.desc)}</span>
      </a>`
    )
    .join('')}</div>`;
}

function healthBanner() {
  const health = store.getHealth();
  if (!health || health.status === 'ok') return '';
  if (health.status === 'degraded') {
    return ui.banner('系统存在降级组件（如 CTS 状态读取失败），部分状态可能显示为「未知」。可到「配置 · 系统状态」查看详情。', 'warn', 'alert');
  }
  if (health.status === 'down') {
    return ui.banner('系统健康检查失败，部分功能可能不可用，请联系管理员。', 'danger', 'alert');
  }
  return '';
}

export async function mount(root, ctx) {
  root.innerHTML = `<div class="page" data-page="dashboard">
    <div data-dashboard-body>${ui.loadingPanel('正在加载工作台…')}</div>
  </div>`;
  const body = root.querySelector('[data-dashboard-body]');
  if (!body) return;

  ui.bindOnce(root, 'dashboard', () => ui.delegate(root, '[data-action="retry"]', 'click', () => load()));

  async function load() {
    body.innerHTML = ui.loadingPanel('正在加载工作台…');
    try {
      const data = await api.get('/dashboard');
      const kpis = (data && data.kpis) || {};
      const recent = (data && data.recent) || [];
      body.innerHTML =
        healthBanner() +
        ui.pageHeader({
          title: '工作台首页',
          subtitle: '我的待办与最近的变更动态',
          breadcrumb: [{ label: '工作台' }],
          meta: `<span>当前用户 <b>${ui.esc(store.displayName())}</b></span><span>环境 <b>${ui.esc(store.environment())}</b></span><span>版本 <b>${ui.esc(store.version())}</b></span>`
        }) +
        `<div class="kpi-grid">${kpiDefs().map((def) => kpiCard(def, kpis[def.key] || 0)).join('')}</div>` +
        `<div class="panel">
          <div class="panel-head"><span class="panel-title">最近动态</span>
            <span class="right muted small">最近 ${recent.length} 条</span></div>
          <div class="panel-body flush">${recentPanel(recent)}</div>
        </div>
        <div class="panel">
          <div class="panel-head"><span class="panel-title">快捷入口</span></div>
          <div class="panel-body">${quickLinks()}</div>
        </div>`;
    } catch (err) {
      const info = describeError(err);
      body.innerHTML =
        ui.pageHeader({ title: '工作台首页', breadcrumb: [{ label: '工作台' }] }) +
        `<div class="panel"><div class="panel-body">${ui.errorPanel({
          title: info.title,
          message: info.message,
          correlationId: info.correlationId
        })}</div></div>`;
    }
  }

  await load();
  return () => ui.releaseOnce(root, 'dashboard');
}
