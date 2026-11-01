/**
 * pages/transport-detail.js — 传输详情：状态时间线 + 对象清单（E071 快照）+ 关联 CD + 同步 / 解绑。
 */

import { api, describeError } from '../api.js';
import * as ui from '../ui.js';
import { runMutation } from '../components/action-bar.js';

function header(tr) {
  const badges = [
    ui.trKindBadge(tr.trKind),
    ui.trStatusBadge(tr),
    ui.syncStateBadge(tr.syncState),
    tr.degraded ? ui.badge('降级', 'danger') : ''
  ]
    .filter(Boolean)
    .join(' ');
  return ui.pageHeader({
    title: tr.trkorr + (tr.description ? ' · ' + tr.description : ''),
    breadcrumb: [{ label: '工作台', href: '#/dashboard' }, { label: '传输', href: '#/transports' }, { label: tr.trkorr }],
    meta: [
      `<span>目标系统 <b>${ui.esc(tr.targetSystem || '—')}</b></span>`,
      tr.cdId
        ? `<span>关联 CD <a href="#/change-documents/${encodeURIComponent(tr.cdId)}" class="mono">${ui.esc(
            tr.cdId
          )}</a></span>`
        : '<span>关联 CD <b>未关联</b></span>',
      tr.taskId ? `<span>关联任务 <b class="mono">${ui.esc(tr.taskId)}</b></span>` : '',
      `<span>关联人 <b>${ui.esc(tr.linkedBy || '—')}</b></span>`,
      `<span>最后同步 <b>${ui.fmtDateTime(tr.lastSyncAt)}</b></span>`
    ].join(''),
    actions: `<a class="btn btn-sm" href="#/transports">${ui.icon('chevronLeft', 15)}返回列表</a>
      <button type="button" class="btn btn-sm" data-action="sync">${ui.icon('sync', 15)}同步</button>`
  }).replace('</h1>', '</h1><div class="page-meta" style="margin-top:2px">' + badges + '</div>');
}

function timelinePanel(tr) {
  const events = [
    { label: '关联变更文档', at: tr.linkedAt, by: tr.linkedBy },
    { label: '释放传输', at: tr.releasedAt },
    { label: '计划导入', at: tr.importScheduledAt },
    { label: '导入完成', at: tr.importedAt },
    { label: '最后同步', at: tr.lastSyncAt }
  ].filter((event) => event.at);
  if (events.length === 0) {
    return ui.emptyPanel({ icon: 'clock', title: '暂无时间线数据', hint: '同步 CTS 后会写入释放 / 导入时间快照。' });
  }
  const items = events
    .map(
      (event) => `<div class="tl-item"><span class="tl-dot ok"></span>
        <div class="tl-head"><span class="tl-action">${ui.esc(event.label)}</span></div>
        <div class="tl-meta"><span>${ui.fmtDateTime(event.at)}</span>${
          event.by ? `<span>${ui.esc(event.by)}</span>` : ''
        }</div></div>`
    )
    .join('');
  return `<div class="timeline">${items}</div>`;
}

function objectsPanel(objects) {
  if (!objects || objects.length === 0) {
    return ui.emptyPanel({
      icon: 'folder',
      title: '没有对象清单',
      hint: '对象清单实时读取 E071；读取失败时降级为不展示，不影响头部状态。'
    });
  }
  const rows = objects
    .map(
      (obj) => `<tr>
      <td class="mono">${ui.esc(obj.pgmid || '—')}</td>
      <td class="mono">${ui.esc(obj.object || obj.objType || '—')}</td>
      <td class="mono"><div class="cell-clip">${ui.esc(obj.objName || '—')}</div></td>
      <td>${ui.esc(obj.objType || '—')}</td>
      <td><div class="cell-clip">${ui.esc(obj.objNameText || obj.text || '—')}</div></td>
    </tr>`
    )
    .join('');
  return `<div class="table-wrap"><table class="data fixed" style="min-width:720px">
    <colgroup><col style="width:90px"><col style="width:100px"><col><col style="width:90px"><col></colgroup>
    <thead><tr><th>PGMID</th><th>对象类型</th><th>对象名</th><th>子类型</th><th>描述</th></tr></thead>
    <tbody>${rows}</tbody></table></div>`;
}

function actionsPanel(tr) {
  const buttons = [];
  if (tr.linked && tr.trStatus === 'D') {
    buttons.push(`<button type="button" class="btn btn-danger btn-sm" data-action="unlink">解绑传输</button>`);
  } else if (tr.linked) {
    buttons.push(`<button type="button" class="btn btn-danger btn-sm" data-action="detach">标记不再关联</button>`);
  }
  if (tr.syncState === 'DETACHED') {
    buttons.push(`<span class="chip">已标记不再关联</span>`);
  }
  return `<div class="action-bar" style="margin-bottom:0">
    <span class="label">操作</span>
    ${buttons.join('') || '<span class="muted small">当前状态无可用操作（传输只读，操作在 SE01 / STMS 完成）</span>'}
    <span class="spacer"></span>
    <span class="muted small">${ui.icon('info', 13)} 应用不创建 / 不释放 / 不导入传输</span>
  </div>`;
}

export async function mount(root, ctx) {
  const trkorr = ctx.params.trkorr;
  root.innerHTML = `<div class="page">${ui.loadingPanel('正在加载传输详情…')}</div>`;
  let tr = null;

  ui.bindOnce(root, 'transport-detail', () => [
    ui.delegate(root, '[data-action="retry"]', 'click', () => load(true)),
    ui.delegate(root, '[data-action="sync"]', 'click', async (event, el) => {
      await runMutation(
        async () => {
          await api.post('/transports/sync', { trkorr });
          return { message: '已同步传输 ' + trkorr + '。' };
        },
        { ctx, button: el, successMessage: '已同步。' }
      );
    }),
    ui.delegate(root, '[data-action="unlink"]', 'click', async () => {
      const values = await ui.confirmDialog({
        title: '解绑传输',
        message: '解绑后传输与当前变更文档解除关联，保留审计记录。',
        confirmText: '确认解绑',
        danger: true,
        fields: [{ name: 'comment', label: '原因（可选）', type: 'textarea', rows: 2 }]
      });
      if (!values) return;
      await runMutation(
        async () => {
          await api.post('/transports/' + encodeURIComponent(trkorr) + '/unlink', { comment: values.comment || '' });
          return { message: '传输已解绑。' };
        },
        { ctx, successMessage: '传输已解绑。' }
      );
    }),
    ui.delegate(root, '[data-action="detach"]', 'click', async () => {
      const values = await ui.confirmDialog({
        title: '标记不再关联',
        message: '已释放 / 已导入的传输只能标记「不再关联」，原因必填并写入审计。',
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
        { ctx, successMessage: '已标记不再关联。' }
      );
    })
  ]);

  async function load(isRetry) {
    try {
      tr = await api.get('/transports/' + encodeURIComponent(trkorr));
      root.innerHTML = `<div class="page">
        ${header(tr)}
        ${actionsPanel(tr)}
        <div class="grid-2">
          <div class="panel">
            <div class="panel-head"><span class="panel-title">状态时间线</span></div>
            <div class="panel-body">${timelinePanel(tr)}</div>
          </div>
          <div class="panel">
            <div class="panel-head"><span class="panel-title">基本信息</span></div>
            <div class="panel-body">
              ${ui.kvList([
                { label: '传输号', value: tr.trkorr },
                { label: '类型', html: ui.trKindBadge(tr.trKind) },
                { label: '目标系统', value: tr.targetSystem },
                { label: 'CTS 状态', html: ui.trStatusBadge(tr) },
                { label: '同步状态', html: ui.syncStateBadge(tr.syncState) },
                { label: '关联 CD', html: tr.cdId ? `<a href="#/change-documents/${encodeURIComponent(tr.cdId)}" class="mono">${ui.esc(tr.cdId)}</a>` : '未关联' },
                { label: '关联任务', value: tr.taskId },
                { label: 'retrofit', html: ui.retrofitBadge(tr.retrofitState) },
                { label: '关联时间', value: ui.fmtDateTime(tr.linkedAt) },
                { label: '释放时间', value: ui.fmtDateTime(tr.releasedAt) },
                { label: '计划导入', value: ui.fmtDateTime(tr.importScheduledAt) },
                { label: '导入时间', value: ui.fmtDateTime(tr.importedAt) },
                { label: '最后同步', value: ui.fmtDateTime(tr.lastSyncAt) },
                { label: '描述', value: tr.description }
              ])}
            </div>
          </div>
        </div>
        <div class="panel">
          <div class="panel-head"><span class="panel-title">对象清单（E071 快照）</span>
            <span class="right muted small">${(tr.objects || []).length} 个对象</span></div>
          <div class="panel-body flush">${objectsPanel(tr.objects)}</div>
        </div>
      </div>`;
    } catch (err) {
      const info = describeError(err);
      const isNotFound = err && (err.status === 404 || err.code === 'NOT_FOUND');
      root.innerHTML = `<div class="page">
        ${ui.pageHeader({
          title: '传输详情',
          breadcrumb: [{ label: '工作台', href: '#/dashboard' }, { label: '传输', href: '#/transports' }, { label: trkorr }]
        })}
        <div class="panel"><div class="panel-body">${ui.errorPanel({
          title: isNotFound ? '传输不存在' : info.title,
          message: isNotFound
            ? '该传输在 E070 中不存在，或尚未同步到本应用。'
            : info.message,
          correlationId: info.correlationId,
          retry: !isNotFound
        })}</div>
        <div class="panel-body tight"><a class="btn btn-sm" href="#/transports">返回传输列表</a></div></div>
      </div>`;
    }
    void isRetry;
  }

  await load(false);
  return () => ui.releaseOnce(root, 'transport-detail');
}
