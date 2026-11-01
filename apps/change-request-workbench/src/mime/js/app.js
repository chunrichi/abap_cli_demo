/**
 * app.js — 应用启动与外壳（顶栏 + 侧栏 + 内容区）。
 * 零依赖原生 ES modules；启动时先取 /me（身份与角色），再启动 hash 路由。
 */

import {
  api,
  describeError,
  onUnauthorized,
  listNotifications,
  unreadNotificationCount,
  refreshNotifications,
  markNotificationRead,
  markAllNotificationsRead
} from './api.js';
import * as store from './store.js';
import * as ui from './ui.js';
import { start as startRouter } from './router.js';

const NAV = [
  {
    group: '工作台',
    items: [
      { name: 'dashboard', hash: '#/dashboard', icon: 'dashboard', label: '工作台首页', match: ['dashboard'] },
      { name: 'my-work', hash: '#/my-work', icon: 'work', label: '我的工作', match: ['my-work'] },
      { name: 'notifications', hash: '#/notifications', icon: 'inbox', label: '通知', match: ['notifications'], badge: 'notifications' }
    ]
  },
  {
    group: '变更流程',
    items: [
      {
        name: 'requests',
        hash: '#/requests',
        icon: 'request',
        label: '请求 CR',
        match: ['requests', 'request-new', 'request-detail']
      },
      {
        name: 'change-documents',
        hash: '#/change-documents',
        icon: 'cd',
        label: '变更文档 CD',
        match: ['change-documents', 'change-document-detail']
      },
      { name: 'tasks', hash: '#/tasks', icon: 'task', label: '任务', match: ['tasks'] },
      { name: 'approvals', hash: '#/approvals', icon: 'approval', label: '审批', match: ['approvals'], badge: 'approvals' }
    ]
  },
  {
    group: '发布与监控',
    items: [
      {
        name: 'transports',
        hash: '#/transports',
        icon: 'transport',
        label: '传输',
        match: ['transports', 'transport-detail']
      },
      { name: 'schedule', hash: '#/schedule', icon: 'schedule', label: '导入计划', match: ['schedule'] },
      { name: 'reports', hash: '#/reports', icon: 'report', label: '报表', match: ['reports'] }
    ]
  },
  {
    group: '系统',
    items: [
      { name: 'admin', hash: '#/admin', icon: 'config', label: '配置', match: ['admin'], adminOnly: true },
      { name: 'about', hash: '#/about', icon: 'help', label: '帮助 / 关于', match: ['about'] }
    ]
  }
];

const LOGO_SVG =
  '<svg class="brand-mark" viewBox="0 0 32 32" aria-hidden="true"><rect width="32" height="32" rx="7" fill="#1d4ed8"/>' +
  '<path d="M9 10h9l5 5v7H9z" fill="none" stroke="#fff" stroke-width="2"/>' +
  '<path d="M13 15h6M13 18h6" stroke="#fff" stroke-width="2"/></svg>';

const state = {
  booted: false,
  badgeTimer: 0,
  badgeLoadedAt: 0,
  notifyLoadedAt: 0,
  notifyTimer: 0,
  notifyItems: [],
  notifyBusy: false,
  notifyWarned: false,
  sessionWarned: false,
  bootTimer: null
};

function appRoot() {
  if (typeof document === 'undefined') return null;
  return document.getElementById('app');
}

function renderBoot() {
  const app = appRoot();
  if (!app) return;
  app.setAttribute('aria-busy', 'true');
  app.innerHTML = `<div class="boot">
    <div class="boot-mark" aria-hidden="true">${LOGO_SVG}</div>
    <p class="boot-text">正在加载变更请求工作台…</p>
  </div>`;
}

function renderBootError(err) {
  const app = appRoot();
  if (!app) return;
  app.setAttribute('aria-busy', 'false');
  const info = describeError(err);
  const isAuth = err && (err.status === 401 || err.code === 'UNAUTHORIZED');
  app.innerHTML = `<div class="boot">
    <div class="boot-mark" aria-hidden="true">${LOGO_SVG}</div>
    <h1 style="font-size:17px">${ui.esc(info.title)}</h1>
    <p class="boot-text" style="max-width:520px;text-align:center">${ui.esc(
      isAuth ? '未登录或会话已过期。请完成 SAP 登录后刷新本页。' : info.message
    )}</p>
    ${info.correlationId ? `<p class="boot-text muted small">追踪号 ${ui.esc(info.correlationId)}</p>` : ''}
    <div style="display:flex;gap:8px;margin-top:8px">
      <button type="button" class="btn btn-primary" data-boot="retry">重新加载</button>
      <a class="btn" href="#/about">关于本页</a>
    </div>
    <p class="boot-text muted small" style="max-width:560px;text-align:center;margin-top:10px">
      页面同源调用 <code>./api/v1</code>；若错误持续，请确认 ICF 节点 <code>ZCRW_APP</code> 与 MIME 资源已部署。
    </p>
  </div>`;
  const retry = app.querySelector('[data-boot="retry"]');
  if (retry) {
    retry.addEventListener('click', () => {
      if (typeof window !== 'undefined' && window.location) window.location.reload();
    });
  }
}

function navHtml() {
  const admin = store.isAdmin();
  return NAV.map((section) => {
    const items = section.items
      .filter((item) => !item.adminOnly || admin)
      .map((item) => {
        const badge = item.badge ? `<span class="nav-badge" data-nav-badge="${item.badge}"></span>` : '';
        return `<a class="nav-link" href="${item.hash}" data-nav="${item.name}" title="${ui.esc(item.label)}">
          <span class="nav-icon">${ui.icon(item.icon, 17)}</span>
          <span class="nav-label">${ui.esc(item.label)}</span>${badge}
        </a>`;
      })
      .join('');
    if (!items) return '';
    return `<div class="nav-group"><div class="nav-group-title">${ui.esc(section.group)}</div>${items}</div>`;
  }).join('');
}

function shellHtml() {
  const me = store.getMe() || {};
  return `<header class="topbar">
    <button type="button" class="sidebar-toggle" data-shell="toggle-sidebar" aria-label="收起或展开侧栏" title="收起或展开侧栏">${ui.icon(
      'chevronLeft',
      16
    )}</button>
    <a class="brand" href="#/dashboard" aria-label="变更请求工作台首页">
      ${LOGO_SVG}
      <span class="brand-name">变更请求工作台</span>
      <span class="brand-ver">v${ui.esc(store.version())}</span>
    </a>
    <form class="topbar-search" data-shell="search" role="search">
      ${ui.icon('search', 15)}
      <input type="search" name="q" placeholder="搜索请求 / 变更文档标题" aria-label="全局搜索">
    </form>
    <div class="topbar-actions">
      <span class="chip" title="当前 SAP 环境">${ui.esc(store.environment())}</span>
      <button type="button" class="icon-btn" data-shell="new-request" title="新建请求">
        ${ui.icon('plus', 15)}<span class="topbar-new-label">新建请求</span>
      </button>
      <a class="icon-btn" href="#/approvals" title="我的待审批" aria-label="我的待审批">
        ${ui.icon('approval', 16)}<span class="count hidden" data-shell-count="approvals"></span>
      </a>
      <div class="notify-menu">
        <button type="button" class="icon-btn notify-btn" data-shell="notify-toggle" title="通知中心" aria-label="通知中心" aria-haspopup="true" aria-expanded="false">
          ${ui.icon('inbox', 16)}<span class="count hidden" data-shell-count="notifications"></span>
        </button>
        <div class="dropdown notify-dropdown" data-shell="notify-dropdown" hidden>
          <div class="dropdown-head">
            <div class="dropdown-title">通知</div>
            <div class="dropdown-sub" data-notify-summary>正在加载…</div>
          </div>
          <div class="notify-list" data-notify-list></div>
          <div class="notify-foot">
            <button type="button" class="dropdown-item notify-foot-btn" data-shell="notify-read-all">
              ${ui.icon('check', 15)}全部已读
            </button>
            <a class="dropdown-item notify-foot-btn" href="#/notifications" data-shell="notify-more">
              ${ui.icon('chevronRight', 15)}查看全部通知
            </a>
          </div>
        </div>
      </div>
      <div class="user-menu">
        <button type="button" class="user-btn" data-shell="user-toggle" aria-haspopup="true" aria-expanded="false">
          <span class="avatar">${ui.esc(String(store.displayName()).slice(0, 1))}</span>
          <span class="user-name">${ui.esc(store.displayName())}</span>
          ${ui.icon('chevronDown', 14)}
        </button>
        <div class="dropdown" data-shell="user-dropdown" hidden>
          <div class="dropdown-head">
            <div class="dropdown-title">${ui.esc(store.displayName())}</div>
            <div class="dropdown-sub">${ui.esc(me.user || '')} · ${ui.esc(store.environment())}</div>
            <div class="role-list" style="margin-top:8px">
              ${(store.roleRows().length ? store.roleRows() : [{ role: '—', scopeType: '', scopeId: '' }])
                .map((row) => ui.roleBadge(row.role))
                .join('')}
            </div>
          </div>
          <a class="dropdown-item" href="#/my-work">${ui.icon('work', 15)}我的工作</a>
          <a class="dropdown-item" href="#/approvals">${ui.icon('approval', 15)}我的待审批</a>
          <a class="dropdown-item" href="#/about">${ui.icon('help', 15)}帮助 / 关于</a>
          ${
            store.isAdmin()
              ? `<a class="dropdown-item" href="#/admin/health">${ui.icon('config', 15)}系统状态</a>`
              : ''
          }
          <div class="dropdown-sep"></div>
          <button type="button" class="dropdown-item" data-shell="refresh">${ui.icon('refresh', 15)}刷新数据</button>
        </div>
      </div>
    </div>
  </header>
  <div class="shell">
    <nav class="sidebar" aria-label="主导航">${navHtml()}</nav>
    <main class="main" id="page" tabindex="-1"></main>
  </div>`;
}

function updateNav(route) {
  const page = typeof document !== 'undefined' ? document.getElementById('page') : null;
  const links = typeof document !== 'undefined' && document.querySelectorAll ? document.querySelectorAll('[data-nav]') : [];
  for (let i = 0; i < links.length; i++) {
    const name = links[i].getAttribute('data-nav');
    const item = findNavItem(name);
    const active = Boolean(item && item.match.indexOf(route.route.name) >= 0);
    links[i].classList.toggle('active', active);
    if (active) links[i].setAttribute('aria-current', 'page');
    else links[i].removeAttribute('aria-current');
  }
  if (page) page.setAttribute('data-page-name', route.route.name);
}

function findNavItem(name) {
  for (const section of NAV) {
    for (const item of section.items) {
      if (item.name === name) return item;
    }
  }
  return null;
}

function toggleSidebar(force) {
  const app = appRoot();
  if (!app) return;
  const collapsed = force === undefined ? !app.classList.contains('collapsed') : Boolean(force);
  app.classList.toggle('collapsed', collapsed);
  const toggle = app.querySelector('[data-shell="toggle-sidebar"]');
  if (toggle) toggle.innerHTML = ui.icon(collapsed ? 'chevronRight' : 'chevronLeft', 16);
  try {
    if (typeof localStorage !== 'undefined') localStorage.setItem('crw.sidebar', collapsed ? 'collapsed' : 'open');
  } catch (err) {
    /* 隐私模式忽略 */
  }
}

function closeUserMenu() {
  const dropdown = document.querySelector ? document.querySelector('[data-shell="user-dropdown"]') : null;
  const btn = document.querySelector ? document.querySelector('[data-shell="user-toggle"]') : null;
  if (dropdown) dropdown.hidden = true;
  if (btn) btn.setAttribute('aria-expanded', 'false');
}

function applyBadge(name, count) {
  const el = document.querySelector ? document.querySelector(`[data-nav-badge="${name}"]`) : null;
  if (el) el.textContent = count > 0 ? String(count) : '';
  const top = document.querySelector ? document.querySelector(`[data-shell-count="${name}"]`) : null;
  if (top) {
    top.textContent = count > 0 ? (count > 99 ? '99+' : String(count)) : '';
    top.classList.toggle('hidden', !(count > 0));
  }
}

/** 待办计数（顶栏 / 侧栏徽标），节流 30 秒。 */
async function refreshBadges(force) {
  const now = Date.now();
  if (!force && now - state.badgeLoadedAt < 30000) return;
  state.badgeLoadedAt = now;
  try {
    const data = await api.get('/dashboard');
    const kpis = (data && data.kpis) || {};
    applyBadge('approvals', Number(kpis.myApprovals) || 0);
    applyBadge('tasks', Number(kpis.myTasks) || 0);
  } catch (err) {
    /* 徽标失败不阻断页面 */
  }
}

/* ---------------------------- Notification bell ---------------------------- */

function closeNotifyMenu() {
  const dropdown = document.querySelector ? document.querySelector('[data-shell="notify-dropdown"]') : null;
  const btn = document.querySelector ? document.querySelector('[data-shell="notify-toggle"]') : null;
  if (dropdown) dropdown.hidden = true;
  if (btn) btn.setAttribute('aria-expanded', 'false');
}

/** linkPage only accepts in-app hashes (#/...); invalid or empty falls back to the notifications page. */
function safeNotifyLink(linkPage) {
  const raw = linkPage ? String(linkPage).trim() : '';
  return /^#\/[^\s]*$/.test(raw) ? raw : '#/notifications';
}

function notifyItemHtml(item) {
  const row = item || {};
  const typeEntry = ui.NOTIFY_TYPE[row.notifyType] || { zh: '通知', tone: 'info' };
  const severity = String(row.severity || '').toUpperCase();
  const severityClass = severity === 'CRITICAL' ? ' sev-critical' : severity === 'WARN' ? ' sev-warn' : '';
  const meta = [typeEntry.zh, row.objectDisplayId ? String(row.objectDisplayId) : ''].filter(Boolean).join(' · ');
  return `<button type="button" class="notify-item${severityClass}" data-notify-id="${ui.esc(row.id)}">
    <span class="notify-dot" aria-hidden="true"></span>
    <span class="notify-main">
      <span class="notify-item-head">
        <span class="notify-item-title">${ui.esc(row.title || typeEntry.zh)}</span>
        <span class="notify-item-time">${ui.fmtRelative(row.createdAt)}</span>
      </span>
      <span class="notify-item-msg">${ui.esc(ui.truncate(row.message || '', 72))}</span>
      <span class="notify-item-meta">${ui.esc(meta)}</span>
    </span>
  </button>`;
}

function renderNotifyPanel(items) {
  const listEl = document.querySelector ? document.querySelector('[data-notify-list]') : null;
  const summary = document.querySelector ? document.querySelector('[data-notify-summary]') : null;
  const rows = Array.isArray(items) ? items : [];
  if (summary) summary.textContent = rows.length > 0 ? '最近 ' + rows.length + ' 条未读' : '暂无未读通知';
  if (!listEl) return;
  if (rows.length === 0) {
    listEl.innerHTML = `<div class="notify-empty">${ui.icon('check', 16)}<span>没有未读通知</span></div>`;
    return;
  }
  listEl.innerHTML = rows.map(notifyItemHtml).join('');
}

/** Show the refresh failure toast once (startup and panel loading may both fail). */
function notifyWarnOnce(err) {
  if (state.notifyWarned) return;
  state.notifyWarned = true;
  const info = describeError(err);
  ui.toast(info.message, { title: '通知刷新失败', type: 'warn', correlationId: info.correlationId });
}

/** Open the panel: trigger a refresh scan first, then load the latest 5 unread items. */
async function loadNotifyPanel() {
  if (state.notifyBusy) return;
  state.notifyBusy = true;
  const listEl = document.querySelector ? document.querySelector('[data-notify-list]') : null;
  const summary = document.querySelector ? document.querySelector('[data-notify-summary]') : null;
  if (listEl) listEl.innerHTML = '<div class="notify-empty"><span>正在加载…</span></div>';
  if (summary) summary.textContent = '正在加载…';
  try {
    let refreshed = null;
    try {
      refreshed = await refreshNotifications();
    } catch (err) {
      notifyWarnOnce(err);
    }
    const data = await listNotifications({ status: 'UNREAD', size: 5 });
    const items = ui
      .listOf(data)
      .filter((item) => item && item.status !== 'DISMISSED')
      .slice(0, 5);
    state.notifyItems = items;
    const serverUnread = refreshed && refreshed.unread !== undefined ? Number(refreshed.unread) : NaN;
    const totalUnread = Number.isFinite(serverUnread) ? serverUnread : Number(data && data.total);
    applyBadge('notifications', Number.isFinite(totalUnread) ? Math.max(0, totalUnread) : items.length);
    state.notifyLoadedAt = Date.now();
    renderNotifyPanel(items);
  } catch (err) {
    const info = describeError(err);
    if (summary) summary.textContent = '加载失败';
    if (listEl) {
      listEl.innerHTML =
        `<div class="notify-empty notify-empty-error">` +
        `<span>${ui.esc(info.message)}</span>` +
        `<button type="button" class="btn btn-sm" data-shell="notify-retry">重试</button>` +
        `</div>`;
    }
  } finally {
    state.notifyBusy = false;
  }
}

/** Unread badge: refreshed on route change / page actions, plus 60s polling (read-only). */
async function refreshNotifyBadge(force) {
  const now = Date.now();
  if (!force && now - state.notifyLoadedAt < 15000) return;
  state.notifyLoadedAt = now;
  try {
    const data = await unreadNotificationCount();
    if (!data || data.count === undefined || data.count === null) return;
    const count = Number(data.count);
    if (Number.isFinite(count)) applyBadge('notifications', Math.max(0, count));
  } catch (err) {
    /* unread badge failures must not block the app */
  }
}

function bindNotifyEvents(app) {
  if (!app) return;
  const toggle = app.querySelector('[data-shell="notify-toggle"]');
  const dropdown = app.querySelector('[data-shell="notify-dropdown"]');
  if (toggle && dropdown) {
    toggle.addEventListener('click', (event) => {
      event.stopPropagation();
      if (!dropdown.hidden) {
        closeNotifyMenu();
        return;
      }
      closeUserMenu();
      dropdown.hidden = false;
      toggle.setAttribute('aria-expanded', 'true');
      loadNotifyPanel();
    });
  }

  ui.delegate(app, '[data-notify-id]', 'click', async (event, el) => {
    const id = el.getAttribute('data-notify-id');
    const row = state.notifyItems.find((item) => String(item.id) === String(id)) || null;
    const target = safeNotifyLink(row ? row.linkPage : '');
    if (id) {
      try {
        const result = await markNotificationRead(id);
        if (result && result.unread !== undefined) {
          const unread = Number(result.unread);
          if (Number.isFinite(unread)) {
            applyBadge('notifications', Math.max(0, unread));
            state.notifyLoadedAt = Date.now();
          }
        }
      } catch (err) {
        const info = describeError(err);
        ui.toast(info.message, { title: '标记已读失败', type: 'warn', correlationId: info.correlationId });
      }
    }
    state.notifyItems = state.notifyItems.filter((item) => String(item.id) !== String(id));
    closeNotifyMenu();
    if (typeof window !== 'undefined' && window.location) window.location.hash = target;
  });

  ui.delegate(app, '[data-shell="notify-retry"]', 'click', () => loadNotifyPanel());

  ui.delegate(app, '[data-shell="notify-read-all"]', 'click', async (event, el) => {
    event.stopPropagation();
    ui.setBusy(el, true, '处理中…');
    try {
      const result = await markAllNotificationsRead();
      const updated = result && result.updated !== undefined ? Number(result.updated) || 0 : 0;
      const unread = result && result.unread !== undefined ? Math.max(0, Number(result.unread) || 0) : 0;
      applyBadge('notifications', unread);
      state.notifyLoadedAt = Date.now();
      state.notifyItems = [];
      ui.toast(updated > 0 ? '已全部标记为已读（' + updated + ' 条）。' : '没有未读通知。', { type: 'success' });
      await loadNotifyPanel();
    } catch (err) {
      const info = describeError(err);
      ui.toast(info.message, { title: '操作失败', type: 'error', correlationId: info.correlationId });
    } finally {
      ui.setBusy(el, false);
    }
  });

  ui.delegate(app, '[data-shell="notify-more"]', 'click', () => closeNotifyMenu());

  if (typeof document !== 'undefined' && document.addEventListener) {
    document.addEventListener('click', (event) => {
      if (!dropdown || dropdown.hidden) return;
      const target = event.target;
      if (target && typeof target.closest === 'function' && target.closest('.notify-menu')) return;
      closeNotifyMenu();
    });
    document.addEventListener('keydown', (event) => {
      if (!event || event.key !== 'Escape') return;
      closeNotifyMenu();
      closeUserMenu();
    });
  }
}

/** Start 60s unread polling and listen for unread changes broadcast by pages. */
function startNotifyPolling() {
  if (typeof window === 'undefined') return;
  refreshNotifyBadge(true);
  if (state.notifyTimer) clearInterval(state.notifyTimer);
  state.notifyTimer = setInterval(() => {
    refreshNotifyBadge(false);
  }, 60000);
  window.addEventListener('crw:notify-changed', (event) => {
    const detail = event && event.detail ? event.detail : {};
    const unread = detail.unread;
    if (unread === undefined || unread === null) return;
    const count = Number(unread);
    if (!Number.isFinite(count)) return;
    applyBadge('notifications', Math.max(0, count));
    state.notifyLoadedAt = Date.now();
    state.notifyItems = [];
  });
}

/** Run one refresh scan on startup; failure shows one toast and never blocks boot. */
function bootNotifyRefresh() {
  refreshNotifications()
    .then((data) => {
      const unread = data && data.unread !== undefined ? Number(data.unread) : NaN;
      if (Number.isFinite(unread)) applyBadge('notifications', Math.max(0, unread));
    })
    .catch((err) => notifyWarnOnce(err));
}

function showSessionWarning() {
  if (state.sessionWarned) return;
  state.sessionWarned = true;
  ui.toast('未登录或会话已过期，请重新登录 SAP 后刷新页面。', { type: 'warn', title: '会话失效', duration: 12000 });
}

function bindShell() {
  const app = appRoot();
  if (!app) return;
  const toggle = app.querySelector('[data-shell="toggle-sidebar"]');
  if (toggle) toggle.addEventListener('click', () => toggleSidebar());
  const newRequest = app.querySelector('[data-shell="new-request"]');
  if (newRequest) newRequest.addEventListener('click', () => { window.location.hash = '#/requests/new'; });
  const searchForm = app.querySelector('[data-shell="search"]');
  if (searchForm) {
    searchForm.addEventListener('submit', (event) => {
      event.preventDefault();
      const input = searchForm.querySelector('input[name="q"]');
      const q = input && input.value ? input.value.trim() : '';
      window.location.hash = q ? '#/requests?q=' + encodeURIComponent(q) : '#/requests';
      if (input) input.value = '';
    });
  }
  const userBtn = app.querySelector('[data-shell="user-toggle"]');
  const dropdown = app.querySelector('[data-shell="user-dropdown"]');
  if (userBtn && dropdown) {
    userBtn.addEventListener('click', (event) => {
      event.stopPropagation();
      const willOpen = dropdown.hidden;
      if (willOpen) closeNotifyMenu();
      dropdown.hidden = !willOpen;
      userBtn.setAttribute('aria-expanded', willOpen ? 'true' : 'false');
    });
  }
  if (typeof document !== 'undefined' && document.addEventListener) {
    document.addEventListener('click', (event) => {
      if (!dropdown || dropdown.hidden) return;
      const target = event.target;
      if (target && typeof target.closest === 'function' && target.closest('.user-menu')) return;
      closeUserMenu();
    });
  }
  ui.bindAll(app, '.dropdown-item[href]', 'click', () => closeUserMenu());
  const refreshBtn = app.querySelector('[data-shell="refresh"]');
  if (refreshBtn) {
    refreshBtn.addEventListener('click', () => {
      closeUserMenu();
      refreshBadges(true);
      refreshNotifyBadge(true);
      ui.toast('已刷新待办计数与通知未读数；页面数据可重新进入当前页加载。', { type: 'success' });
    });
  }
  bindNotifyEvents(app);
  // 恢复侧栏折叠状态
  try {
    if (typeof localStorage !== 'undefined' && localStorage.getItem('crw.sidebar') === 'collapsed') {
      toggleSidebar(true);
    }
  } catch (err) {
    /* 忽略 */
  }
}

function bindGlobalErrors() {
  if (typeof window === 'undefined' || !window.addEventListener) return;
  window.addEventListener('error', (event) => {
    if (!event || !event.message) return;
    ui.toast('页面脚本异常：' + event.message, { type: 'error', title: '前端异常' });
  });
  window.addEventListener('unhandledrejection', (event) => {
    const reason = event && event.reason;
    if (reason && reason.name === 'ApiError') return; // 已由页面提示
    const message = reason && reason.message ? reason.message : '未处理的异步错误';
    ui.toast(message, { type: 'error', title: '前端异常' });
  });
}

async function boot() {
  state.bootTimer = setTimeout(() => {
    if (!state.booted) {
      renderBootError({ status: 0, code: 'TIMEOUT', message: '加载超时，请检查网络或 ICF 服务。' });
    }
  }, 25000);
  renderBoot();
  try {
    const me = await api.get('/me');
    store.setMe(me);
  } catch (err) {
    if (state.bootTimer) clearTimeout(state.bootTimer);
    renderBootError(err);
    return;
  }
  // 健康信息不阻塞主流程
  api
    .get('/health')
    .then((health) => store.setHealth(health))
    .catch(() => {
      /* 健康检查失败不影响使用 */
    });
  if (state.bootTimer) clearTimeout(state.bootTimer);
  state.booted = true;
  const app = appRoot();
  if (!app) return;
  app.setAttribute('aria-busy', 'false');
  app.innerHTML = shellHtml();
  bindShell();
  startNotifyPolling();
  startRouter(document.getElementById('page'), {
    onRouteChange: (route) => {
      updateNav(route);
      closeNotifyMenu();
      refreshBadges(false);
      refreshNotifyBadge(false);
    }
  });
  bootNotifyRefresh();
}

onUnauthorized(showSessionWarning);
bindGlobalErrors();

if (typeof window !== 'undefined' && typeof document !== 'undefined') {
  if (document.readyState === 'loading' && document.addEventListener) {
    document.addEventListener('DOMContentLoaded', boot);
  } else {
    boot();
  }
}
