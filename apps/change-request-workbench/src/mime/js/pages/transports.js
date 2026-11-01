/**
 * pages/transports.js — 传输工作台：DEV / ToC 只读展示 + 手工关联 / 同步 / 解绑 / 标记。
 */

import { api, describeError } from '../api.js';
import * as ui from '../ui.js';
import { filterBar, bindFilterBar, queryValues } from '../components/form.js';
import { runMutation } from '../components/action-bar.js';

const KIND_OPTIONS = [
  { value: '', label: '全部类型' },
  { value: 'DEV', label: '开发传输' },
  { value: 'TOC', label: 'ToC 传输' }
];

const TARGET_OPTIONS = [
  { value: '', label: '全部目标系统' },
  { value: 'QAS', label: 'QAS' },
  { value: 'PRD', label: 'PRD' },
  { value: 'DEV', label: 'DEV' }
];

const SYNC_OPTIONS = [
  { value: '', label: '全部同步状态' },
  { value: 'OK', label: '已同步' },
  { value: 'ERROR', label: '同步失败' },
  { value: 'DETACHED', label: '已标记不再关联' },
  { value: 'UNKNOWN', label: '未知' }
];

function buildFilters() {
  return [
    { name: 'q', label: '关键词', type: 'text', placeholder: '传输号 / 描述' },
    { name: 'trKind', label: '类型', type: 'select', options: KIND_OPTIONS },
    { name: 'targetSystem', label: '目标系统', type: 'select', options: TARGET_OPTIONS },
    { name: 'syncState', label: '同步状态', type: 'select', options: SYNC_OPTIONS },
    { name: 'cdId', label: '关联 CD', type: 'text', placeholder: 'CD 编号' }
  ];
}

function transportLinkFields() {
  return [
    { name: 'cdId', label: '关联变更文档', type: 'text', required: true, placeholder: 'CD 编号，如 0000000045', span: 'all' },
    { name: 'trkorr', label: '传输号', type: 'text', required: true, maxlength: 10, placeholder: '如 QASK900123' },
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
    { name: 'taskId', label: '关联任务编号（可选）', type: 'text', placeholder: '任务编号' }
  ];
}

function tableRows(rows) {
  if (rows.length === 0) {
    return ui.emptyPanel({
      icon: 'transport',
      title: '没有符合条件的传输',
      hint: '传输在 SE01 / abap-cli 创建后，通过「关联传输」写入本应用；应用不创建、不释放、不导入传输。'
    });
  }
  const body = rows
    .map((tr) => {
      const cdCell = tr.cdId
        ? `<a class="mono" href="#/change-documents/${encodeURIComponent(tr.cdId)}">${ui.esc(tr.cdId)}</a>`
        : '<span class="muted">未关联</span>';
      // syncState 徽标已表达「同步失败 / 不再关联」，这里只补 retrofit 状态，避免重复与溢出
      const flags = tr.retrofitState === 'PENDING' ? [ui.retrofitBadge('PENDING')] : [];
      const actions = [`<button type="button" class="btn btn-sm" data-tr-action="sync" data-trkorr="${ui.esc(tr.trkorr)}">同步</button>`];
      if (tr.trStatus === 'D' && tr.linked) {
        actions.push(`<button type="button" class="btn btn-sm btn-danger" data-tr-action="unlink" data-trkorr="${ui.esc(tr.trkorr)}">解绑</button>`);
      } else if (tr.linked) {
        actions.push(
          `<button type="button" class="btn btn-sm btn-danger" data-tr-action="detach" data-trkorr="${ui.esc(tr.trkorr)}">不再关联</button>`
        );
      }
      return `<tr>
        <td><a class="mono" href="#/transports/${encodeURIComponent(tr.trkorr)}">${ui.esc(tr.trkorr)}</a></td>
        <td>${cdCell}</td>
        <td>${ui.trKindBadge(tr.trKind)}</td>
        <td>${ui.esc(tr.targetSystem || '—')}</td>
        <td>${ui.trStatusBadge(tr)}</td>
        <td>${ui.syncStateBadge(tr.syncState)} ${flags.join(' ')}</td>
        <td title="${ui.esc(ui.fmtDateTime(tr.releasedAt))}">${ui.fmtDate(tr.releasedAt)}</td>
        <td title="${ui.esc(ui.fmtDateTime(tr.importedAt))}">${ui.fmtDate(tr.importedAt)}</td>
        <td><div class="cell-clip small muted">${ui.esc(ui.truncate(tr.description || '—', 40))}</div></td>
        <td class="actions"><div class="cell-actions">${actions.join('')}</div></td>
      </tr>`;
    })
    .join('');
  return `<div class="table-wrap"><table class="data fixed" style="min-width:1170px">
    <colgroup><col style="width:106px"><col style="width:98px"><col style="width:86px"><col style="width:78px">
      <col style="width:124px"><col style="width:164px"><col style="width:110px"><col style="width:110px">
      <col><col style="width:160px"></colgroup>
    <thead><tr><th>传输号</th><th>关联 CD</th><th>类型</th><th>目标系统</th>
      <th>CTS 状态</th><th>同步</th><th>释放日</th><th>导入日</th>
      <th>描述</th><th class="actions">操作</th></tr></thead>
    <tbody>${body}</tbody></table></div>`;
}

export async function mount(root, ctx) {
  const query = ctx.query || {};
  const fields = buildFilters();
  const values = queryValues(fields, query);
  let transports = [];

  root.innerHTML = `<div class="page">
    ${ui.pageHeader({
      title: '传输工作台',
      subtitle: 'CTS 只读：关联、同步快照与降级提示；不创建 / 不释放 / 不导入',
      breadcrumb: [{ label: '工作台', href: '#/dashboard' }, { label: '传输' }],
      actions: `<button type="button" class="btn btn-sm" data-action="sync-all">${ui.icon('sync', 15)}同步全部</button>
        <button type="button" class="btn btn-sm btn-primary" data-action="link-tr">${ui.icon('link', 15)}关联传输</button>
        <button type="button" class="btn btn-sm" data-action="refresh">${ui.icon('refresh', 15)}刷新</button>`
    })}
    <div class="panel">
      ${filterBar(fields, values)}
      <div data-transports-body>${ui.loadingPanel('正在加载传输…')}</div>
    </div>
  </div>`;

  const body = root.querySelector('[data-transports-body]');
  bindFilterBar(root, ctx, fields);

  ui.bindOnce(root, 'transports', () => [
    ui.delegate(root, '[data-action="retry"]', 'click', () => load()),
    ui.delegate(root, '[data-action="refresh"]', 'click', () => load()),
    ui.delegate(root, '[data-action="sync-all"]', 'click', async (event, el) => {
      await runMutation(
        async () => {
          await api.post('/transports/sync', {});
          return { message: '已触发传输状态同步。' };
        },
        { ctx, button: el, successMessage: '已触发同步。' }
      );
    }),
    ui.delegate(root, '[data-action="link-tr"]', 'click', async () => {
      const values2 = await ui.confirmDialog({
        title: '关联传输',
        message: '传输必须已存在于 E070；已关联其它 CD 的传输会返回 DUPLICATE_LINK。',
        confirmText: '关联',
        fields: transportLinkFields(),
        values: { trKind: 'DEV' }
      });
      if (!values2) return;
      const payload = { cdId: values2.cdId, trkorr: values2.trkorr, trKind: values2.trKind };
      if (values2.taskId) payload.taskId = values2.taskId;
      await runMutation(
        async () => {
          await api.post('/transports/link', payload);
          return { message: '传输已关联。' };
        },
        { ctx, successMessage: '传输已关联。' }
      );
    }),
    ui.delegate(root, '[data-tr-action]', 'click', async (event, el) => {
      const action = el.getAttribute('data-tr-action');
      const trkorr = el.getAttribute('data-trkorr');
      if (!trkorr) return;
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
        const values2 = await ui.confirmDialog({
          title: '解绑传输',
          message: '解绑仅对可修改（D）传输可用；已释放的传输只能标记「不再关联」。',
          confirmText: '确认解绑',
          danger: true,
          fields: [{ name: 'comment', label: '原因（可选）', type: 'textarea', rows: 2 }]
        });
        if (!values2) return;
        await runMutation(
          async () => {
            await api.post('/transports/' + encodeURIComponent(trkorr) + '/unlink', { comment: values2.comment || '' });
            return { message: '传输已解绑。' };
          },
          { ctx, button: el, successMessage: '传输已解绑。' }
        );
        return;
      }
      if (action === 'detach') {
        const values2 = await ui.confirmDialog({
          title: '标记不再关联',
          message: '适用于已释放 / 已导入的传输；原因必填并写入审计。',
          confirmText: '确认标记',
          danger: true,
          fields: [{ name: 'reason', label: '原因', type: 'textarea', required: true, rows: 3 }]
        });
        if (!values2) return;
        await runMutation(
          async () => {
            await api.post('/transports/' + encodeURIComponent(trkorr) + '/mark-detached', { reason: values2.reason });
            return { message: '已标记不再关联。' };
          },
          { ctx, button: el, successMessage: '已标记不再关联。' }
        );
      }
    })
  ]);

  async function load() {
    if (!body) return;
    body.innerHTML = ui.skeletonTable(8, 6);
    try {
      const data = await api.get('/transports', {
        trKind: query.trKind,
        targetSystem: query.targetSystem,
        syncState: query.syncState,
        cdId: query.cdId,
        q: query.q
      });
      transports = ui.listOf(data);
      const degraded = transports.filter((tr) => tr.degraded || tr.syncState === 'ERROR').length;
      const unlinked = transports.filter((tr) => !tr.linked).length;
      body.innerHTML =
        (degraded > 0
          ? ui.banner(degraded + ' 条传输的 CTS 状态读取失败（降级显示为未知），请到 STMS 确认。', 'warn', 'alert')
          : '') +
        (unlinked > 0 ? ui.banner(unlinked + ' 条传输尚未关联变更文档，可在 CD 详情或此处关联。', 'info', 'info') : '') +
        `<div class="panel-head" style="border-top:0">
          <span class="panel-title">传输列表</span><span class="chip">${ui.fmtNum(transports.length)} 条</span>
          <span class="right muted small">只读 CTS 快照 · 同步写 ZCRW_TR</span>
        </div>` +
        tableRows(transports);
    } catch (err) {
      const info = describeError(err);
      body.innerHTML = ui.errorPanel({ title: info.title, message: info.message, correlationId: info.correlationId });
    }
  }

  await load();
  return () => ui.releaseOnce(root, 'transports');
}
