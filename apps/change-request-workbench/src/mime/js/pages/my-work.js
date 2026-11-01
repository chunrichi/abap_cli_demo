/**
 * pages/my-work.js — 我的工作：待我审批 / 我的请求 / 我的变更文档 / 我的任务 / 我的传输。
 */

import { api, describeError } from '../api.js';
import * as store from '../store.js';
import * as ui from '../ui.js';
import { openApprovalDrawer } from '../components/approval-drawer.js';

function sectionPanel(title, subtitle, linkHref, linkLabel, content, count) {
  return `<div class="panel">
    <div class="panel-head">
      <span class="panel-title">${ui.esc(title)}</span>
      ${subtitle ? `<span class="panel-sub">${ui.esc(subtitle)}</span>` : ''}
      ${count !== undefined ? `<span class="chip">${ui.fmtNum(count)} 条</span>` : ''}
      <span class="right"><a href="${ui.esc(linkHref)}" class="small">${ui.esc(linkLabel || '查看全部')} →</a></span>
    </div>
    <div class="panel-body flush">${content}</div>
  </div>`;
}

function simpleEmpty(text) {
  return `<div class="empty" style="padding:26px 16px"><div class="empty-title" style="font-size:13px">${ui.esc(text)}</div></div>`;
}

function approvalsTable(rows, ctx) {
  if (!rows.length) return simpleEmpty('没有待你审批的步骤。');
  return `<div class="table-wrap"><table class="data">
    <thead><tr><th style="width:80px">类型</th><th style="width:110px">对象</th><th>标题</th><th style="width:60px">步骤</th><th style="width:140px">创建时间</th><th class="actions">操作</th></tr></thead>
    <tbody>${rows
      .map(
        (row) => `<tr>
        <td>${ui.objectTypeBadge(row.objectType)}</td>
        <td><span class="mono">${ui.esc(row.objectDisplayId || row.objectId)}</span></td>
        <td>${ui.esc(row.objectTitle || '—')}</td>
        <td>${ui.esc(row.stepNo)}</td>
        <td class="nowrap">${ui.fmtDateTime(row.createdAt)}</td>
        <td class="actions"><button type="button" class="btn btn-sm btn-primary" data-approval-open="${ui.esc(
          row.id
        )}">处理</button></td>
      </tr>`
      )
      .join('')}</tbody></table></div>`;
}

function requestsTable(rows) {
  if (!rows.length) return simpleEmpty('还没有创建过请求。');
  return `<div class="table-wrap"><table class="data">
    <thead><tr><th style="width:110px">编号</th><th>标题</th><th style="width:120px">状态</th><th style="width:70px">优先级</th><th style="width:140px">变更时间</th></tr></thead>
    <tbody>${rows
      .map(
        (row) => `<tr>
        <td><span class="mono">${ui.esc(row.displayId || row.id)}</span></td>
        <td><a class="row-title" href="#/requests/${encodeURIComponent(row.id)}">${ui.esc(row.title || '—')}</a></td>
        <td>${ui.statusBadge(row.status)}</td>
        <td>${ui.priorityBadge(row.priority)}</td>
        <td class="nowrap">${ui.fmtRelative(row.changedAt)}</td>
      </tr>`
      )
      .join('')}</tbody></table></div>`;
}

function cdsTable(rows) {
  if (!rows.length) return simpleEmpty('没有你负责的变更文档。');
  return `<div class="table-wrap"><table class="data">
    <thead><tr><th style="width:110px">编号</th><th>标题</th><th style="width:130px">状态</th><th style="width:76px">目标系统</th><th style="width:150px">计划导入</th></tr></thead>
    <tbody>${rows
      .map(
        (row) => `<tr>
        <td><span class="mono">${ui.esc(row.displayId || row.id)}</span></td>
        <td><a class="row-title" href="#/change-documents/${encodeURIComponent(row.id)}">${ui.esc(row.title || '—')}</a></td>
        <td>${ui.statusBadge(row.status)}</td>
        <td>${ui.esc(row.targetSystem || '—')}</td>
        <td class="nowrap">${ui.fmtDateTime(row.plannedImportAt)}</td>
      </tr>`
      )
      .join('')}</tbody></table></div>`;
}

function tasksTable(rows) {
  if (!rows.length) return simpleEmpty('没有指派给你的待办任务。');
  return `<div class="table-wrap"><table class="data">
    <thead><tr><th style="width:80px">编号</th><th>任务</th><th style="width:80px">类型</th><th style="width:110px">状态</th><th style="width:110px">截止日</th></tr></thead>
    <tbody>${rows
      .map(
        (row) => `<tr>
        <td><span class="mono">${ui.esc(row.displayId || row.id)}</span></td>
        <td>${ui.esc(row.title || '—')}${
          row.parentTaskId ? ' <span class="chip">子任务</span>' : ''
        }</td>
        <td>${ui.taskTypeBadge(row.taskType)}</td>
        <td>${ui.statusBadge(row.status)}</td>
        <td class="nowrap${ui.isOverdue(row.dueDate) && row.status !== 'DONE' ? '' : ''}" style="${
          ui.isOverdue(row.dueDate) && row.status !== 'DONE' ? 'color:var(--danger)' : ''
        }">${ui.fmtDate(row.dueDate)}</td>
      </tr>`
      )
      .join('')}</tbody></table></div>`;
}

function transportsTable(rows) {
  if (!rows.length) return simpleEmpty('我的变更文档还没有关联传输。');
  return `<div class="table-wrap"><table class="data">
    <thead><tr><th style="width:110px">传输号</th><th style="width:110px">关联 CD</th><th style="width:96px">类型</th><th style="width:110px">状态</th><th style="width:96px">目标系统</th><th style="width:140px">导入时间</th></tr></thead>
    <tbody>${rows
      .map(
        (row) => `<tr>
        <td><a class="mono" href="#/transports/${encodeURIComponent(row.trkorr)}">${ui.esc(row.trkorr)}</a></td>
        <td><span class="mono">${ui.esc(row.cdId || '—')}</span></td>
        <td>${ui.trKindBadge(row.trKind)}</td>
        <td>${ui.trStatusBadge(row)}</td>
        <td>${ui.esc(row.targetSystem || '—')}</td>
        <td class="nowrap">${ui.fmtDateTime(row.importedAt)}</td>
      </tr>`
      )
      .join('')}</tbody></table></div>`;
}

function summaryStrip(data) {
  const items = [
    { label: '待我审批', value: data.approvals.length, href: '#/approvals' },
    { label: '我的待办任务', value: data.tasks.length, href: '#/tasks?assignee=' + encodeURIComponent(store.userName()) },
    { label: '我的请求', value: data.requests.length, href: '#/requests?requester=' + encodeURIComponent(store.userName()) },
    { label: '我的变更文档', value: data.cds.length, href: '#/change-documents?owner=' + encodeURIComponent(store.userName()) }
  ];
  return `<div class="kpi-grid">${items
    .map(
      (item) => `<a class="kpi" href="${ui.esc(item.href)}">
        <span class="kpi-label">${ui.esc(item.label)}</span>
        <strong class="kpi-value">${ui.fmtNum(item.value)}</strong>
        <span class="kpi-note">查看列表 →</span>
      </a>`
    )
    .join('')}</div>`;
}

export async function mount(root, ctx) {
  root.innerHTML = `<div class="page"><div data-mywork-body>${ui.loadingPanel('正在加载我的工作…')}</div></div>`;
  const body = root.querySelector('[data-mywork-body]');
  if (!body) return;
  let approvals = [];

  ui.bindOnce(root, 'my-work', () => [
    ui.delegate(root, '[data-action="retry"]', 'click', () => load()),
    ui.delegate(root, '[data-approval-open]', 'click', (event, el) => {
      const id = el.getAttribute('data-approval-open');
      const row = approvals.find((item) => item.id === id);
      if (row) openApprovalDrawer(row, ctx);
    })
  ]);

  async function load() {
    body.innerHTML = ui.loadingPanel('正在加载我的工作…');
    const me = encodeURIComponent(store.userName());
    try {
      const [approvalsRaw, requestsData, cdsData, tasksData, transportsData] = await Promise.all([
        api.get('/approvals', { scope: 'mine' }).catch(() => ({ items: [] })),
        api.get('/requests', { requester: store.userName(), size: 10, sort: 'changedAt', order: 'desc' }),
        api.get('/change-documents', { owner: store.userName(), size: 10, sort: 'changedAt', order: 'desc' }),
        api.get('/tasks', { assignee: store.userName(), size: 50, sort: 'dueDate', order: 'asc' }),
        api.get('/transports', { size: 200 }).catch(() => ({ items: [] }))
      ]);
      approvals = ui.listOf(approvalsRaw);
      const requests = ui.listOf(requestsData);
      const cds = ui.listOf(cdsData);
      const allTasks = ui.listOf(tasksData);
      const tasks = allTasks.filter((task) => task.status === 'OPEN' || task.status === 'IN_PROGRESS');
      const myCdIds = new Set(cds.map((cd) => cd.id));
      const myTransports = ui.listOf(transportsData)
        .filter((tr) => tr.cdId && myCdIds.has(tr.cdId))
        .slice(0, 10);

      body.innerHTML =
        ui.pageHeader({
          title: '我的工作',
          subtitle: '与当前用户相关的待办与对象',
          breadcrumb: [{ label: '工作台' }, { label: '我的工作' }],
          actions: `<button type="button" class="btn" data-refresh>${ui.icon('refresh', 15)}刷新</button>`
        }) +
        summaryStrip({ approvals, tasks, requests, cds }) +
        sectionPanel('待我审批', '当前步骤审批人为你', '#/approvals', '审批中心', approvalsTable(approvals, ctx), approvals.length) +
        sectionPanel('我的请求', '我提交的变更请求', '#/requests?requester=' + me, '请求 CR', requestsTable(requests), requests.length) +
        sectionPanel('我的变更文档', '我作为负责人 / 开发 / 测试的 CD', '#/change-documents?owner=' + me, '变更文档', cdsTable(cds), cds.length) +
        sectionPanel('我的任务', '未完成的任务（含进行中）', '#/tasks?assignee=' + me, '任务', tasksTable(tasks), tasks.length) +
        sectionPanel('我的传输', '与我的变更文档关联的传输', '#/transports', '传输工作台', transportsTable(myTransports), myTransports.length);

      ui.bind(body, '[data-refresh]', 'click', () => load());
    } catch (err) {
      const info = describeError(err);
      body.innerHTML = ui.errorPanel({ title: info.title, message: info.message, correlationId: info.correlationId });
    }
  }

  await load();
  return () => ui.releaseOnce(root, 'my-work');
}
