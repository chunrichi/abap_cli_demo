/**
 * pages/notifications.js — notification center: status / type filters, server-side paging,
 * mark-as-read, mark-all-read and refresh. Only the /notifications endpoints are used;
 * api.js adds the X-CRW-Request header to write requests.
 */

import {
  listNotifications,
  unreadNotificationCount,
  refreshNotifications,
  markNotificationRead,
  markAllNotificationsRead,
  describeError
} from '../api.js';
import * as ui from '../ui.js';
import { filterBar, bindFilterBar, queryValues } from '../components/form.js';
import { table, bindRowLinks, pager, bindPager } from '../components/table.js';

const STATUS_OPTIONS = [
  { value: '', label: '全部通知' },
  { value: 'UNREAD', label: '未读' },
  { value: 'READ', label: '已读' }
];

const TYPE_OPTIONS = [{ value: '', label: '全部类型' }].concat(
  Object.keys(ui.NOTIFY_TYPE).map((key) => ({ value: key, label: ui.NOTIFY_TYPE[key].zh }))
);

/** linkPage only accepts in-app hashes (#/...); anything else is treated as no link. */
function linkOf(row) {
  const raw = row && row.linkPage ? String(row.linkPage).trim() : '';
  return /^#\/[^\s]*$/.test(raw) ? raw : '';
}

function objectCell(row) {
  const display = row.objectDisplayId || row.objectId || '';
  const href = linkOf(row);
  const id = href
    ? `<a class="mono" href="${ui.esc(href)}">${ui.esc(display || '—')}</a>`
    : `<span class="mono">${ui.esc(display || '—')}</span>`;
  return `<span class="notify-object">${ui.objectTypeBadge(row.objectType)}${id}</span>`;
}

function columns() {
  return [
    {
      key: 'createdAt',
      label: '时间',
      width: '158px',
      render: (row) =>
        `<div class="nowrap">${ui.fmtDateTime(row.createdAt)}</div>` +
        `<div class="nowrap small muted">${ui.fmtRelative(row.createdAt)}</div>`
    },
    { key: 'notifyType', label: '类型', width: '116px', render: (row) => ui.notifyTypeBadge(row.notifyType) },
    { key: 'object', label: '对象', width: '182px', render: objectCell },
    {
      key: 'title',
      label: '标题',
      flex: true,
      minWidth: 200,
      ellipsis: true,
      render: (row) => {
        const text = ui.esc(ui.truncate(row.title || '—', 64));
        const href = linkOf(row);
        return href
          ? `<a class="row-title" href="${ui.esc(href)}">${text}</a>`
          : `<span class="row-title">${ui.esc(row.title || '—')}</span>`;
      }
    },
    {
      key: 'message',
      label: '消息',
      flex: true,
      minWidth: 260,
      ellipsis: true,
      render: (row) => {
        const text = `<span class="muted">${ui.esc(ui.truncate(row.message || '—', 90))}</span>`;
        return String(row.severity || '').toUpperCase() === 'CRITICAL'
          ? ui.notifySeverityBadge('CRITICAL') + ' ' + text
          : text;
      }
    },
    {
      key: 'status',
      label: '状态',
      width: '92px',
      render: (row) => `<span data-notify-status>${ui.notifyStatusBadge(row.status)}</span>`
    },
    {
      key: 'actions',
      label: '操作',
      className: 'actions',
      width: '100px',
      render: (row) =>
        row.status === 'UNREAD'
          ? `<button type="button" class="btn btn-sm" data-mark-read="${ui.esc(row.id)}">标记已读</button>`
          : `<span class="muted small">${row.status === 'DISMISSED' ? '已忽略' : '已读'}</span>`
    }
  ];
}

function metaHtml(unread, total) {
  return (
    `<span data-notify-meta>` +
    `<span class="chip">未读 ${ui.fmtNum(unread || 0)}</span>` +
    `<span class="chip">列表 ${ui.fmtNum(total || 0)} 条</span>` +
    `</span>`
  );
}

export async function mount(root, ctx) {
  const query = ctx.query || {};
  const page = Math.max(1, Number(query.page) || 1);
  const size = Math.max(1, Number(query.size) || 20);
  const fields = [
    { name: 'status', label: '状态', type: 'select', options: STATUS_OPTIONS },
    { name: 'type', label: '类型', type: 'select', options: TYPE_OPTIONS }
  ];
  const values = queryValues(fields, query);

  let unreadCount = 0;

  root.innerHTML = `<div class="page">
    ${ui.pageHeader({
      title: '通知中心',
      subtitle: '审批、任务与导入计划的站内提醒；点击通知可跳转到对应对象',
      breadcrumb: [{ label: '工作台', href: '#/dashboard' }, { label: '通知中心' }],
      meta: metaHtml(0, 0),
      actions: `
        <button type="button" class="btn btn-sm" data-action="read-all">${ui.icon('check', 15)}全部已读</button>
        <button type="button" class="btn btn-sm" data-action="refresh" title="重新扫描并加载通知">${ui.icon('refresh', 15)}刷新</button>`
    })}
    <div class="panel">
      ${filterBar(fields, values)}
      <div data-notify-body>${ui.loadingPanel('正在加载通知…')}</div>
      <div data-pager></div>
    </div>
  </div>`;

  const body = root.querySelector('[data-notify-body]');
  const pagerEl = root.querySelector('[data-pager]');

  function updateMeta(total) {
    const meta = root.querySelector('[data-notify-meta]');
    if (meta) meta.innerHTML = `<span class="chip">未读 ${ui.fmtNum(unreadCount)}</span><span class="chip">列表 ${ui.fmtNum(total || 0)} 条</span>`;
  }

  /** Broadcast the unread count to the shell (bell / nav badge) to avoid duplicate requests. */
  function publishUnread(value) {
    if (value === undefined || value === null) return;
    const count = Number(value);
    if (!Number.isFinite(count)) return;
    unreadCount = Math.max(0, count);
    if (typeof window !== 'undefined' && typeof window.dispatchEvent === 'function' && typeof CustomEvent === 'function') {
      window.dispatchEvent(new CustomEvent('crw:notify-changed', { detail: { unread: unreadCount } }));
    }
  }

  bindFilterBar(root, ctx, fields);
  bindRowLinks(root, ctx);
  bindPager(root, ctx);

  ui.bindOnce(root, 'notifications', () => [
    ui.delegate(root, '[data-action="retry"]', 'click', () => load()),
    ui.delegate(root, '[data-action="refresh"]', 'click', async (event, el) => {
      ui.setBusy(el, true, '刷新中…');
      try {
        const result = await refreshNotifications();
        const created = result && result.created !== undefined ? Number(result.created) || 0 : 0;
        const unread = result ? result.unread : undefined;
        publishUnread(unread);
        ui.toast(created > 0 ? '已刷新，新增 ' + created + ' 条通知。' : '已刷新，暂无新通知。', { type: 'success' });
      } catch (err) {
        const info = describeError(err);
        ui.toast(info.message, { title: '刷新通知失败', type: 'error', correlationId: info.correlationId });
      } finally {
        ui.setBusy(el, false);
      }
      await load();
    }),
    ui.delegate(root, '[data-action="read-all"]', 'click', async (event, el) => {
      ui.setBusy(el, true, '处理中…');
      try {
        const result = await markAllNotificationsRead();
        const updated = result && result.updated !== undefined ? Number(result.updated) || 0 : 0;
        publishUnread(result ? result.unread : 0);
        ui.toast(updated > 0 ? '已标记 ' + updated + ' 条通知为已读。' : '没有未读通知。', { type: 'success' });
        await load();
      } catch (err) {
        const info = describeError(err);
        ui.toast(info.message, { title: '操作失败', type: 'error', correlationId: info.correlationId });
      } finally {
        ui.setBusy(el, false);
      }
    }),
    ui.delegate(root, '[data-mark-read]', 'click', async (event, el) => {
      const id = el.getAttribute('data-mark-read');
      if (!id) return;
      ui.setBusy(el, true, '处理中…');
      try {
        const result = await markNotificationRead(id);
        publishUnread(result && result.unread !== undefined ? result.unread : Math.max(0, unreadCount - 1));
        markRowRead(el);
        ui.toast('已标记为已读。', { type: 'success' });
      } catch (err) {
        ui.setBusy(el, false);
        const info = describeError(err);
        ui.toast(info.message, { title: info.title, type: 'error', correlationId: info.correlationId });
      }
    })
  ]);

  /** After mark-as-read, update the row in place so the table does not re-render / lose scroll. */
  function markRowRead(button) {
    const tr = button && typeof button.closest === 'function' ? button.closest('tr') : null;
    if (!tr) return;
    tr.classList.remove('notify-unread');
    const statusEl = tr.querySelector('[data-notify-status]');
    if (statusEl) statusEl.innerHTML = ui.notifyStatusBadge('READ');
    const actionCell = button.parentNode;
    if (actionCell) actionCell.innerHTML = '<span class="muted small">已读</span>';
  }

  async function load() {
    if (!body) return;
    body.innerHTML = ui.skeletonTable(7, 6);
    if (pagerEl) pagerEl.innerHTML = '';
    let listError = null;
    const [listData, countData] = await Promise.all([
      listNotifications({ status: query.status || '', type: query.type || '', page, size }).catch((err) => {
        listError = err;
        return null;
      }),
      unreadNotificationCount().catch(() => null)
    ]);
    try {
      if (listError) throw listError;
      const rows = ui.listOf(listData);
      const total = listData && listData.total !== undefined && listData.total !== null ? Number(listData.total) || 0 : rows.length;
      const pageData = {
        page: (listData && Number(listData.page)) || page,
        pageSize: (listData && Number(listData.pageSize)) || size,
        total
      };
      if (countData && countData.count !== undefined) publishUnread(countData.count);
      updateMeta(total);
      body.innerHTML = table({
        columns: columns(),
        rows,
        rowHref: linkOf,
        rowClass: (row) => (row.status === 'UNREAD' ? 'notify-unread' : ''),
        emptyOptions: {
          icon: 'inbox',
          title: query.status === 'UNREAD' ? '没有未读通知' : '暂无通知',
          hint:
            query.status === 'UNREAD'
              ? '所有通知都已读；切换筛选查看历史通知。'
              : '审批、任务与导入计划产生提醒后会出现在这里。'
        }
      });
      if (pagerEl) pagerEl.innerHTML = pager(root, ctx, pageData, { hideIfEmpty: false });
      bindRowLinks(root, ctx);
      bindPager(root, ctx);
    } catch (err) {
      const info = describeError(err);
      body.innerHTML = ui.errorPanel({
        title: info.title,
        message: info.message,
        correlationId: info.correlationId
      });
      ui.toast(info.message, { title: '通知加载失败', type: 'error', correlationId: info.correlationId });
    }
  }

  await load();
  return () => ui.releaseOnce(root, 'notifications');
}
