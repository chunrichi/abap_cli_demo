/**
 * pages/approvals.js — 审批中心：待我审批 / 我审批过的 / 全部待办；抽屉内决策。
 */

import { api, describeError } from '../api.js';
import * as ui from '../ui.js';
import { openApprovalDrawer } from '../components/approval-drawer.js';

const SCOPES = [
  { key: 'mine', label: '待我审批' },
  { key: 'decided', label: '我审批过的' },
  { key: 'all', label: '全部待办' }
];

function colgroup(scope) {
  return `<colgroup>${columns(scope)
    .map((col) => {
      if (col.key === 'objectTitle') return '<col>';
      const width = typeof col.width === 'number' ? col.width + 'px' : col.width || '150px';
      return `<col style="width:${ui.esc(width)}">`;
    })
    .join('')}</colgroup>`;
}

function columns(scope) {
  const cols = [
    { key: 'objectType', label: '类型', width: '84px', render: (row) => ui.objectTypeBadge(row.objectType) },
    {
      key: 'objectDisplayId',
      label: '对象',
      width: '120px',
      render: (row) => {
        const href =
          row.objectType === 'REQ'
            ? '#/requests/' + encodeURIComponent(row.objectId)
            : '#/change-documents/' + encodeURIComponent(row.objectId);
        return `<a class="mono" href="${href}">${ui.esc(row.objectDisplayId || row.objectId)}</a>`;
      }
    },
    {
      key: 'objectTitle',
      label: '标题',
      render: (row) => `<div class="cell-clip">${ui.esc(ui.truncate(row.objectTitle, 60))}</div>`
    },
    { key: 'stepNo', label: '步骤', width: '64px', render: (row) => ui.esc(row.stepNo) },
    { key: 'approver', label: '审批人', width: '130px', render: (row) => ui.esc(row.approver || '—') },
    { key: 'apprState', label: '状态', width: '110px', render: (row) => ui.apprStateBadge(row.apprState) },
    {
      key: 'decidedAt',
      label: '决策时间',
      width: '150px',
      render: (row) => `<span class="nowrap">${ui.fmtDateTime(row.decidedAt)}</span>`
    },
    {
      key: 'comment',
      label: '意见',
      render: (row) => `<div class="cell-clip"><span class="small muted">${ui.esc(ui.truncate(row.comment || '—', 42))}</span></div>`
    }
  ];
  if (scope !== 'decided') {
    cols.push({
      key: 'actions',
      label: '操作',
      className: 'actions',
      width: '90px',
      render: (row) =>
        `<button type="button" class="btn btn-sm ${row.apprState === 'PENDING' ? 'btn-primary' : ''}" data-approval-open="${ui.esc(
          row.id
        )}">${row.apprState === 'PENDING' ? '处理' : '查看'}</button>`
    });
  }
  return cols;
}

export async function mount(root, ctx) {
  const scope = SCOPES.some((item) => item.key === ctx.query.scope) ? ctx.query.scope : 'mine';
  let approvals = [];

  root.innerHTML = `<div class="page">
    ${ui.pageHeader({
      title: '审批中心',
      subtitle: '按审批矩阵生成的步骤；驳回意见必填，请求人不能审批自己',
      breadcrumb: [{ label: '工作台', href: '#/dashboard' }, { label: '审批' }],
      actions: `<button type="button" class="btn btn-sm" data-action="refresh">${ui.icon('refresh', 15)}刷新</button>`
    })}
    <div class="panel">
      ${ui.tabs({ items: SCOPES, active: scope })}
      <div data-approval-body>${ui.loadingPanel('正在加载审批待办…')}</div>
    </div>
  </div>`;

  const body = root.querySelector('[data-approval-body]');

  ui.bindOnce(root, 'approvals', () => [
    ui.delegate(root, '[data-action="retry"]', 'click', () => load()),
    ui.delegate(root, '[data-action="refresh"]', 'click', () => load()),
    ui.delegate(root, '[data-approval-open]', 'click', (event, el) => {
      const row = approvals.find((item) => item.id === el.getAttribute('data-approval-open'));
      if (row) openApprovalDrawer(row, ctx);
    })
  ]);
  ui.bindTabs(root, (key) => ctx.setQuery({ scope: key === 'mine' ? '' : key }));

  async function load() {
    if (!body) return;
    body.innerHTML = ui.skeletonTable(7, 6);
    try {
      const raw = await api.get('/approvals', { scope });
      approvals = ui.listOf(raw);
      const pending = approvals.filter((row) => row.apprState === 'PENDING').length;
      body.innerHTML =
        (scope === 'all'
          ? ui.banner('「全部待办」按角色聚合显示，可能包含当前步骤审批人不是你、仅可查看的步骤。', 'info', 'info')
          : '') +
        `<div class="panel-body flush"><div class="panel-head" style="border-top:0">
          <span class="panel-title">${ui.esc((SCOPES.find((s) => s.key === scope) || {}).label || '')}</span>
          <span class="chip">${ui.fmtNum(approvals.length)} 条</span>
          ${pending ? `<span class="chip">待处理 ${pending}</span>` : ''}
        </div>
        ${
          approvals.length === 0
            ? ui.emptyPanel({
                icon: 'approval',
                title: scope === 'mine' ? '没有待你审批的步骤' : '暂无记录',
                hint:
                  scope === 'mine'
                    ? '提交审批后，当前步骤审批人为你的步骤会出现在这里。'
                    : '切换上方范围查看其它审批记录。'
              })
            : `<div class="table-wrap"><table class="data fixed" style="min-width:1080px">
                ${colgroup(scope)}
                <thead><tr>${columns(scope)
                  .map(
                    (col) =>
                      `<th${col.width ? ` style="width:${col.width}"` : ''}${
                        col.className ? ` class="${col.className}"` : ''
                      }>${ui.esc(col.label)}</th>`
                  )
                  .join('')}</tr></thead>
                <tbody>${approvals
                  .map(
                    (row) =>
                      `<tr>${columns(scope)
                        .map((col) => `<td class="${col.className || ''}">${col.render(row)}</td>`)
                        .join('')}</tr>`
                  )
                  .join('')}</tbody></table></div>`
        }</div>`;
    } catch (err) {
      const info = describeError(err);
      body.innerHTML = ui.errorPanel({ title: info.title, message: info.message, correlationId: info.correlationId });
    }
  }

  await load();
  return () => ui.releaseOnce(root, 'approvals');
}
