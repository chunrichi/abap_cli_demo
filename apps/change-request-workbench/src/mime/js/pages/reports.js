/**
 * pages/reports.js — 报表：变更分布 / 审批与关闭时长 / 逾期清单 / ToC 漏斗 / CSV 导出。
 * 全部只读；导出走 GET /reports/export.csv?type=...
 */

import { api, describeError, downloadCsv } from '../api.js';
import * as ui from '../ui.js';

const TABS = [
  { key: 'changes', label: '变更分布' },
  { key: 'duration', label: '时长' },
  { key: 'overdue', label: '逾期清单' },
  { key: 'to-c', label: 'ToC / 导入漏斗' }
];

const STATUS_COLOR = {
  NEW: '#94a3b8',
  PENDING_APPROVAL: '#d97706',
  REJECTED: '#b91c1c',
  APPROVED: '#15803d',
  IN_PROGRESS: '#1d4ed8',
  CLOSED: '#475569',
  CANCELLED: '#71717a'
};

function labelFor(kind, key) {
  if (kind === 'status') return ui.STATUS[key] ? ui.STATUS[key].zh : key;
  if (kind === 'type') return ui.REQUEST_TYPE[key] ? ui.REQUEST_TYPE[key].zh : key;
  if (kind === 'priority') return ui.PRIORITY[String(key)] ? ui.PRIORITY[String(key)].zh : key;
  if (kind === 'stage') {
    const stageMap = {
      CREATED: '已创建',
      RELEASED: '已释放',
      IMPORT_SCHEDULED: '已计划导入',
      IMPORTED: '已导入',
      READY_TO_IMPORT: '待导入',
      IMPORT_SCHEDULED_TOC: 'ToC 已计划',
      RETROFIT_PENDING: '待补做'
    };
    return stageMap[key] || key;
  }
  return key;
}

function barList(items, kind, toneColor) {
  const rows = Array.isArray(items) ? items : [];
  if (rows.length === 0) return ui.emptyPanel({ title: '暂无数据', icon: 'report' });
  const max = Math.max(1, ...rows.map((row) => Number(row.count) || 0));
  return `<div class="bar-list">${rows
    .map((row) => {
      const count = Number(row.count) || 0;
      const width = Math.max(1, Math.round((count / max) * 100));
      const color = kind === 'status' && STATUS_COLOR[row.key] ? STATUS_COLOR[row.key] : toneColor || 'var(--primary)';
      return `<div class="bar-row">
        <span class="nowrap">${ui.esc(labelFor(kind, row.key))}</span>
        <span class="bar-track"><span class="bar-fill" style="width:${width}%;background:${color}"></span></span>
        <span class="bar-count">${ui.fmtNum(count)}</span>
      </div>`;
    })
    .join('')}</div>`;
}

function trendChart(trend) {
  const rows = Array.isArray(trend) ? trend : [];
  if (rows.length === 0) return ui.emptyPanel({ title: '暂无趋势数据', icon: 'report' });
  const width = 760;
  const height = 190;
  const pad = { top: 12, right: 12, bottom: 26, left: 40 };
  const innerW = width - pad.left - pad.right;
  const innerH = height - pad.top - pad.bottom;
  const max = Math.max(1, ...rows.map((row) => Math.max(Number(row.created) || 0, Number(row.closed) || 0)));
  const niceMax = Math.ceil(max / 4) * 4 || 4;
  const ticks = 4;
  const groupW = innerW / rows.length;
  const barW = Math.max(2, Math.min(10, (groupW * 0.7) / 2));
  let svg = `<svg viewBox="0 0 ${width} ${height}" width="100%" height="${height}" role="img" aria-label="变更创建与关闭趋势">`;
  for (let t = 0; t <= ticks; t++) {
    const value = (niceMax / ticks) * t;
    const y = pad.top + innerH - (value / niceMax) * innerH;
    svg += `<line x1="${pad.left}" y1="${y}" x2="${width - pad.right}" y2="${y}" stroke="#e2e8f0" stroke-width="1"/>`;
    svg += `<text x="${pad.left - 6}" y="${y + 4}" text-anchor="end" font-size="10" fill="#6b7a90">${value}</text>`;
  }
  const labelEvery = Math.max(1, Math.ceil(rows.length / 8));
  rows.forEach((row, index) => {
    const created = Number(row.created) || 0;
    const closed = Number(row.closed) || 0;
    const x = pad.left + groupW * index + (groupW - barW * 2 - 2) / 2;
    const hCreated = created === 0 ? 0 : Math.max(1, (created / niceMax) * innerH);
    const hClosed = closed === 0 ? 0 : Math.max(1, (closed / niceMax) * innerH);
    if (hCreated > 0) {
      svg += `<rect x="${x.toFixed(1)}" y="${(pad.top + innerH - hCreated).toFixed(1)}" width="${barW}" height="${hCreated.toFixed(
        1
      )}" rx="1.5" fill="#1d4ed8" opacity="0.85"><title>${ui.esc(row.date)} 创建 ${created}</title></rect>`;
    }
    if (hClosed > 0) {
      svg += `<rect x="${(x + barW + 2).toFixed(1)}" y="${(pad.top + innerH - hClosed).toFixed(1)}" width="${barW}" height="${hClosed.toFixed(
        1
      )}" rx="1.5" fill="#15803d" opacity="0.7"><title>${ui.esc(row.date)} 关闭 ${closed}</title></rect>`;
    }
    if (index % labelEvery === 0 || index === rows.length - 1) {
      svg += `<text x="${(pad.left + groupW * index + groupW / 2).toFixed(1)}" y="${height - 8}" text-anchor="middle" font-size="10" fill="#6b7a90">${ui.esc(
        String(row.date || '').slice(5)
      )}</text>`;
    }
  });
  svg += '</svg>';
  return `${svg}<div class="legend-inline" style="margin-top:8px">
      <span class="legend-item"><span class="legend-dot"></span>新建</span>
      <span class="legend-item"><span class="legend-dot ok"></span>关闭</span>
    </div>`;
}

function durationCards(label, data) {
  const d = data || {};
  return `<div class="panel">
    <div class="panel-head"><span class="panel-title">${ui.esc(label)}</span>
      <span class="right muted small">样本 ${ui.fmtNum(d.count || 0)} 条</span></div>
    <div class="panel-body"><div class="kpi-grid" style="margin:0">
      <div class="kpi"><span class="kpi-label">平均</span><strong class="kpi-value">${ui.fmtHours(d.avgHours)}</strong></div>
      <div class="kpi"><span class="kpi-label">最短</span><strong class="kpi-value">${ui.fmtHours(d.minHours)}</strong></div>
      <div class="kpi"><span class="kpi-label">最长</span><strong class="kpi-value">${ui.fmtHours(d.maxHours)}</strong></div>
    </div></div>
  </div>`;
}

function changesView(data) {
  const d = data || {};
  return `<div class="grid-2">
      <div class="panel"><div class="panel-head"><span class="panel-title">按状态</span></div>
        <div class="panel-body">${barList(d.byStatus, 'status')}</div></div>
      <div class="panel"><div class="panel-head"><span class="panel-title">按类型 / 优先级</span></div>
        <div class="panel-body">
          <div class="form-section-title" style="margin-top:0">请求类型</div>${barList(d.byType, 'type', '#6d28d9')}
          <div class="form-section-title">优先级</div>${barList(d.byPriority, 'priority', '#b45309')}
        </div></div>
    </div>
    <div class="panel"><div class="panel-head"><span class="panel-title">创建 / 关闭趋势</span>
      <span class="right muted small">按日期</span></div>
      <div class="panel-body">${trendChart(d.trend)}</div></div>`;
}

function durationView(data) {
  const d = data || {};
  return `<div class="grid-2">
    ${durationCards('审批时长（提交 → 末步通过）', d.approval)}
    ${durationCards('关闭时长（创建 → 关闭）', d.closure)}
  </div>
  <div class="panel"><div class="panel-body muted small">
    时长为按历史记录估算的小时数，样本量较小时仅供参考；时间基准为 SAP 系统本地时间。
  </div></div>`;
}

function overdueView(data) {
  const items = (data && data.items) || [];
  if (items.length === 0) {
    return ui.emptyPanel({ icon: 'clock', title: '没有逾期事项', hint: '任务、导入计划与审批步骤均未逾期。' });
  }
  const kindLabel = { TASK: '任务', SCHEDULE: '导入计划', APPROVAL: '审批' };
  const rows = items
    .map((item) => {
      let href = '';
      if (item.objectType === 'REQ') href = '#/requests/' + encodeURIComponent(item.objectId);
      else if (item.objectType === 'CD') href = '#/change-documents/' + encodeURIComponent(item.objectId);
      else if (item.kind === 'SCHEDULE') href = '#/schedule';
      else if (item.kind === 'TASK') href = '#/tasks';
      else if (item.kind === 'APPROVAL') href = '#/approvals';
      const title = href
        ? `<a class="row-title" href="${href}">${ui.esc(item.title || item.displayId || item.objectId)}</a>`
        : ui.esc(item.title || '—');
      return `<tr>
        <td><span class="chip">${ui.esc(kindLabel[item.kind] || item.kind || '—')}</span></td>
        <td>${ui.objectTypeBadge(item.objectType)}</td>
        <td><span class="mono">${ui.esc(item.displayId || item.objectId)}</span></td>
        <td><div class="cell-clip">${title}</div></td>
        <td class="nowrap">${ui.fmtDateTime(item.dueAt)}</td>
        <td class="num" style="color:var(--danger);font-weight:600">${ui.fmtNum(item.daysOverdue)} 天</td>
      </tr>`;
    })
    .join('');
  return `<div class="panel"><div class="panel-head"><span class="panel-title">逾期清单</span>
      <span class="chip">${ui.fmtNum(items.length)} 项</span></div>
    <div class="table-wrap"><table class="data fixed" style="min-width:900px">
      <colgroup><col style="width:96px"><col style="width:84px"><col style="width:120px"><col><col style="width:160px"><col style="width:100px"></colgroup>
      <thead><tr><th>类型</th><th>对象</th><th>编号</th><th>标题</th>
        <th>应完成时间</th><th class="num">逾期</th></tr></thead>
      <tbody>${rows}</tbody></table></div></div>`;
}

function toCView(data) {
  const d = data || {};
  const funnel = Array.isArray(d.funnel) ? d.funnel : [];
  const items = Array.isArray(d.items) ? d.items : [];
  const max = Math.max(1, ...funnel.map((row) => Number(row.count) || 0));
  const funnelHtml = funnel.length
    ? `<div class="funnel">${funnel
        .map(
          (row) => `<div class="funnel-row">
            <span>${ui.esc(labelFor('stage', row.stage))}</span>
            <span class="funnel-track"><span class="funnel-fill" style="width:${Math.max(3, Math.round(
              ((Number(row.count) || 0) / max) * 100
            ))}%">${ui.fmtNum(row.count)}</span></span>
            <span class="bar-count">${ui.fmtNum(row.count)}</span>
          </div>`
        )
        .join('')}</div>`
    : ui.emptyPanel({ title: '暂无漏斗数据', icon: 'report' });
  const rows = items
    .map(
      (item) => `<tr>
      <td><a class="mono" href="#/transports/${encodeURIComponent(item.trkorr)}">${ui.esc(item.trkorr)}</a></td>
      <td>${item.cdId ? `<a class="mono" href="#/change-documents/${encodeURIComponent(item.cdId)}">${ui.esc(item.cdId)}</a>` : '—'}</td>
      <td>${ui.esc(item.targetSystem || '—')}</td>
      <td>${ui.trStatusBadge({ trStatus: item.trStatus })}</td>
      <td class="nowrap">${ui.fmtDateTime(item.importedAt)}</td>
      <td>${ui.retrofitBadge(item.retrofitState)}</td>
    </tr>`
    )
    .join('');
  return `<div class="panel"><div class="panel-head"><span class="panel-title">ToC / 导入漏斗</span></div>
      <div class="panel-body">${funnelHtml}</div></div>
    <div class="panel"><div class="panel-head"><span class="panel-title">ToC 传输</span>
      <span class="chip">${ui.fmtNum(items.length)} 条</span></div>
      <div class="panel-body flush">${
        items.length
          ? `<div class="table-wrap"><table class="data fixed" style="min-width:820px">
              <colgroup><col style="width:120px"><col style="width:118px"><col style="width:90px"><col style="width:140px"><col style="width:150px"><col style="width:100px"></colgroup>
              <thead><tr><th>传输号</th><th>关联 CD</th><th>目标系统</th>
                <th>CTS 状态</th><th>导入时间</th><th>retrofit</th></tr></thead>
              <tbody>${rows}</tbody></table></div>`
          : ui.emptyPanel({ icon: 'transport', title: '暂无 ToC 传输', hint: '关联 ToC 传输后在此展示导入漏斗与补做状态。' })
      }</div></div>`;
}

export async function mount(root, ctx) {
  const tab = TABS.some((item) => item.key === ctx.query.tab) ? ctx.query.tab : 'changes';

  root.innerHTML = `<div class="page">
    ${ui.pageHeader({
      title: '报表',
      subtitle: '变更分布、审批与关闭时长、逾期清单、ToC 导入漏斗（只读）',
      breadcrumb: [{ label: '工作台', href: '#/dashboard' }, { label: '报表' }],
      actions: `<button type="button" class="btn btn-sm" data-action="export">${ui.icon('download', 15)}导出 CSV</button>
        <button type="button" class="btn btn-sm" data-action="refresh">${ui.icon('refresh', 15)}刷新</button>`
    })}
    <div class="panel">
      ${ui.tabs({ items: TABS, active: tab })}
      <div data-report-body>${ui.loadingPanel('正在加载报表…')}</div>
    </div>
  </div>`;

  const body = root.querySelector('[data-report-body]');

  ui.bindOnce(root, 'reports', () => [
    ui.delegate(root, '[data-action="retry"]', 'click', () => load()),
    ui.delegate(root, '[data-action="refresh"]', 'click', () => load()),
    ui.delegate(root, '[data-action="export"]', 'click', async (event, el) => {
      ui.setBusy(el, true, '导出中…');
      try {
        await downloadCsv(tab);
        ui.toast('已开始下载 CSV。', { type: 'success' });
      } catch (err) {
        const info = describeError(err);
        ui.toast(info.message, { title: info.title, type: 'error', correlationId: info.correlationId });
      } finally {
        ui.setBusy(el, false);
      }
    })
  ]);
  ui.bindTabs(root, (key) => ctx.setQuery({ tab: key === 'changes' ? '' : key }));

  async function load() {
    if (!body) return;
    body.innerHTML = ui.skeletonTable(6, 6);
    try {
      let html = '';
      if (tab === 'changes') {
        html = changesView(await api.get('/reports/changes'));
      } else if (tab === 'duration') {
        html = durationView(await api.get('/reports/duration'));
      } else if (tab === 'overdue') {
        html = overdueView(await api.get('/reports/overdue'));
      } else {
        html = toCView(await api.get('/reports/to-c'));
      }
      body.innerHTML = html;
    } catch (err) {
      const info = describeError(err);
      body.innerHTML = ui.errorPanel({ title: info.title, message: info.message, correlationId: info.correlationId });
    }
  }

  await load();
  return () => ui.releaseOnce(root, 'reports');
}
