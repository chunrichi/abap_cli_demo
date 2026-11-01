/**
 * pages/admin.js — 配置与系统状态（P1 只读）：周期 / 角色 / 审批矩阵 / 号段 / 健康检查。
 * 仅 ADMIN 可访问；非管理员展示无权限提示（服务端同样鉴权）。
 */

import { api, describeError } from '../api.js';
import * as store from '../store.js';
import * as ui from '../ui.js';

const SECTIONS = [
  { key: 'cycles', label: '周期', endpoint: '/config/cycles' },
  { key: 'roles', label: '角色分配', endpoint: '/config/roles' },
  { key: 'approval-matrix', label: '审批矩阵', endpoint: '/config/approval-matrix' },
  { key: 'number-ranges', label: '号段', endpoint: '/config/number-ranges' },
  { key: 'health', label: '系统状态', endpoint: '/health' }
];

function componentTone(value) {
  if (value === 'ok') return 'ok';
  if (value === 'degraded') return 'warn';
  if (value === 'down') return 'danger';
  return 'neutral';
}

function healthView(health) {
  const data = health || {};
  const components = data.components || {};
  const rows = Object.keys(components)
    .map(
      (key) => `<tr>
      <td class="mono">${ui.esc(key)}</td>
      <td>${ui.badge(String(components[key]), componentTone(components[key]))}</td>
    </tr>`
    )
    .join('');
  return `<div class="panel"><div class="panel-head"><span class="panel-title">健康检查</span>
      <span class="right">${ui.badge(data.status === 'ok' ? '正常' : data.status === 'degraded' ? '降级' : data.status === 'down' ? '不可用' : '未知', componentTone(data.status))}</span></div>
    <div class="panel-body">
      ${ui.kvList([
        { label: '版本', value: data.version || store.version() },
        { label: '总体状态', value: data.status },
        { label: '环境', value: store.environment() }
      ])}
    </div>
    <div class="table-wrap"><table class="data">
      <thead><tr><th style="width:200px">组件</th><th>状态</th></tr></thead>
      <tbody>${rows || '<tr><td colspan="2" class="muted">无组件状态数据</td></tr>'}</tbody></table></div></div>`;
}

function configColumns(section) {
  if (section === 'cycles') {
    return [
      { key: 'id', label: '周期' },
      { key: 'description', label: '描述' },
      { key: 'startDate', label: '开始日期' },
      { key: 'endDate', label: '结束日期' },
      { key: 'freezeDate', label: '冻结日期' },
      { key: 'status', label: '状态' },
      { key: 'targetSystem', label: '目标系统' }
    ];
  }
  if (section === 'roles') {
    return [
      { key: 'userId', label: '用户' },
      { key: 'role', label: '角色', render: (row) => ui.roleBadge(row.role) },
      { key: 'scopeType', label: '范围类型', render: (row) => ui.esc(ui.SCOPE_TYPE[row.scopeType] || row.scopeType || '—') },
      { key: 'scopeId', label: '范围值' },
      { key: 'validFrom', label: '生效日' },
      { key: 'validTo', label: '失效日' }
    ];
  }
  if (section === 'approval-matrix') {
    return [
      { key: 'profileId', label: '配置组' },
      { key: 'stepNo', label: '步骤' },
      { key: 'objectType', label: '对象类型', render: (row) => ui.esc(ui.OBJECT_TYPE[row.objectType] ? ui.OBJECT_TYPE[row.objectType].zh : row.objectType) },
      { key: 'approverRole', label: '审批角色', render: (row) => (row.approverRole ? ui.roleBadge(row.approverRole) : '—') },
      { key: 'approverUser', label: '审批人' },
      { key: 'reqType', label: '请求类型', render: (row) => ui.esc(row.reqType || '通配') },
      { key: 'priority', label: '优先级', render: (row) => (row.priority ? ui.priorityBadge(row.priority) : '通配') },
      { key: 'mandatory', label: '强制', render: (row) => ui.esc(row.mandatory === 'X' ? '是' : '否') }
    ];
  }
  return null;
}

function genericTable(rows) {
  if (rows.length === 0) return ui.emptyPanel({ title: '暂无配置数据', icon: 'config' });
  const keys = Array.from(
    rows.reduce((set, row) => {
      Object.keys(row || {}).forEach((key) => set.add(key));
      return set;
    }, new Set())
  ).slice(0, 8);
  const head = keys.map((key) => `<th>${ui.esc(key)}</th>`).join('');
  const body = rows
    .map((row) => `<tr>${keys.map((key) => `<td class="mono">${ui.esc(row[key])}</td>`).join('')}</tr>`)
    .join('');
  return `<div class="table-wrap"><table class="data"><thead><tr>${head}</tr></thead><tbody>${body}</tbody></table></div>`;
}

function configTable(rows, section) {
  if (rows.length === 0) return ui.emptyPanel({ title: '暂无配置数据', icon: 'config' });
  const columns = configColumns(section);
  if (!columns) return genericTable(rows);
  const head = columns
    .map((col) => `<th${col.width ? ` style="width:${col.width}"` : ''}>${ui.esc(col.label)}</th>`)
    .join('');
  const body = rows
    .map(
      (row) =>
        `<tr>${columns
          .map((col) => `<td>${typeof col.render === 'function' ? col.render(row) : ui.safe(row[col.key])}</td>`)
          .join('')}</tr>`
    )
    .join('');
  return `<div class="table-wrap"><table class="data"><thead><tr>${head}</tr></thead><tbody>${body}</tbody></table></div>`;
}

export async function mount(root, ctx) {
  const section = SECTIONS.some((item) => item.key === ctx.params.section) ? ctx.params.section : 'cycles';
  if (!store.isAdmin()) {
    root.innerHTML = `<div class="page">
      ${ui.pageHeader({
        title: '配置',
        breadcrumb: [{ label: '工作台', href: '#/dashboard' }, { label: '配置' }]
      })}
      <div class="panel"><div class="panel-body">
        ${ui.emptyPanel({
          icon: 'alert',
          title: '需要管理员权限',
          hint: '当前用户没有 ADMIN 角色。配置页只对管理员开放；如需调整审批矩阵 / 角色 / 号段，请联系管理员。',
          actionLabel: '返回工作台',
          action: 'go-dashboard'
        })}
      </div></div>
    </div>`;
    ui.delegate(root, '[data-action="go-dashboard"]', 'click', () => ctx.navigate('#/dashboard'));
    return () => {};
  }

  const current = SECTIONS.find((item) => item.key === section);
  root.innerHTML = `<div class="page">
    ${ui.pageHeader({
      title: '配置',
      subtitle: 'P1 只读：周期、角色分配、审批矩阵、号段与系统健康',
      breadcrumb: [{ label: '工作台', href: '#/dashboard' }, { label: '配置' }],
      actions: `<button type="button" class="btn btn-sm" data-action="refresh">${ui.icon('refresh', 15)}刷新</button>`
    })}
    <div class="panel">
      ${ui.tabs({ items: SECTIONS, active: section })}
      <div data-admin-body>${ui.loadingPanel('正在加载配置…')}</div>
    </div>
  </div>`;

  const body = root.querySelector('[data-admin-body]');

  ui.bindOnce(root, 'admin', () => [
    ui.delegate(root, '[data-action="retry"]', 'click', () => load()),
    ui.delegate(root, '[data-action="refresh"]', 'click', () => load())
  ]);
  ui.bindTabs(root, (key) => ctx.navigate('#/admin/' + key));

  async function load() {
    if (!body) return;
    body.innerHTML = ui.skeletonTable(6, 6);
    try {
      const data = await api.get(current.endpoint);
      if (section === 'health') {
        body.innerHTML = healthView(data);
        return;
      }
      const rows = ui.listOf(data);
      body.innerHTML =
        `<div class="panel-head" style="border-top:0"><span class="panel-title">${ui.esc(current.label)}</span>
          <span class="chip">${ui.fmtNum(rows.length)} 行</span>
          <span class="right muted small">${ui.icon('info', 13)} 配置修改当前走 bootstrap / runbook，页面只读</span></div>` +
        configTable(rows, section);
    } catch (err) {
      const info = describeError(err);
      body.innerHTML = ui.errorPanel({ title: info.title, message: info.message, correlationId: info.correlationId });
    }
  }

  await load();
  return () => ui.releaseOnce(root, 'admin');
}
