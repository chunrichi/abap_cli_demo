/**
 * router.js — hash 路由。
 *
 * 支持：
 *  - `#/requests/0000000123` 深链
 *  - `#/requests?status=NEW&page=2` 查询串（筛选条件写入 URL）
 *  - 浏览器前进 / 后退
 *  - 动态 import 页面模块；页面模块导出 mount(root, ctx)
 */

import * as ui from './ui.js';

const ROUTES = [
  { name: 'dashboard', segs: ['dashboard'], title: '工作台首页', load: () => import('./pages/dashboard.js') },
  { name: 'my-work', segs: ['my-work'], title: '我的工作', load: () => import('./pages/my-work.js') },
  { name: 'notifications', segs: ['notifications'], title: '通知中心', load: () => import('./pages/notifications.js') },
  { name: 'request-new', segs: ['requests', 'new'], title: '新建请求', load: () => import('./pages/request-new.js') },
  { name: 'requests', segs: ['requests'], title: '请求 CR', load: () => import('./pages/requests.js') },
  { name: 'request-detail', segs: ['requests', ':id'], title: '请求详情', load: () => import('./pages/request-detail.js') },
  { name: 'change-documents', segs: ['change-documents'], title: '变更文档 CD', load: () => import('./pages/change-documents.js') },
  {
    name: 'change-document-detail',
    segs: ['change-documents', ':id'],
    title: '变更文档详情',
    load: () => import('./pages/change-document-detail.js')
  },
  { name: 'tasks', segs: ['tasks'], title: '任务', load: () => import('./pages/tasks.js') },
  { name: 'approvals', segs: ['approvals'], title: '审批中心', load: () => import('./pages/approvals.js') },
  { name: 'transport-detail', segs: ['transports', ':trkorr'], title: '传输详情', load: () => import('./pages/transport-detail.js') },
  { name: 'transports', segs: ['transports'], title: '传输工作台', load: () => import('./pages/transports.js') },
  { name: 'schedule', segs: ['schedule'], title: '导入计划', load: () => import('./pages/schedule.js') },
  { name: 'reports', segs: ['reports'], title: '报表', load: () => import('./pages/reports.js') },
  { name: 'admin', segs: ['admin'], title: '配置', prefix: true, load: () => import('./pages/admin.js') },
  { name: 'about', segs: ['about'], title: '帮助 / 关于', load: () => import('./pages/about.js') }
];

const DEFAULT_PATH = '/dashboard';

const state = {
  host: null,
  route: null,
  unmount: null,
  onRouteChange: null,
  seq: 0
};

/* ------------------------------ 解析 / 构造 ------------------------------ */

export function parseHash(hash) {
  const raw = String(hash === undefined || hash === null ? '' : hash).replace(/^#/, '');
  const question = raw.indexOf('?');
  const pathPart = question >= 0 ? raw.slice(0, question) : raw;
  const queryPart = question >= 0 ? raw.slice(question + 1) : '';
  let path = pathPart || DEFAULT_PATH;
  if (path.charAt(0) !== '/') path = '/' + path;
  path = path.replace(/\/+$/, '') || '/';
  const query = {};
  if (queryPart) {
    try {
      const params = new URLSearchParams(queryPart);
      params.forEach((value, key) => {
        query[key] = value;
      });
    } catch (err) {
      /* 非法查询串：忽略 */
    }
  }
  return { path, query };
}

export function buildHash(path, query) {
  const normalized = path && path.charAt(0) === '/' ? path : '/' + (path || DEFAULT_PATH).replace(/^#?\/?/, '');
  const search = ui.qs(query);
  return '#' + normalized + (search ? '?' + search : '');
}

function matchRoute(path) {
  const parts = path.split('/').filter(Boolean);
  for (const route of ROUTES) {
    if (route.prefix) {
      if (parts[0] !== route.segs[0]) continue;
    } else if (route.segs.length !== parts.length) {
      continue;
    }
    const params = {};
    let ok = true;
    for (let i = 0; i < route.segs.length; i++) {
      const seg = route.segs[i];
      const value = parts[i];
      if (seg.charAt(0) === ':') {
        if (!value) {
          ok = false;
          break;
        }
        params[seg.slice(1)] = decodeURIComponent(value);
      } else if (seg !== value) {
        ok = false;
        break;
      }
    }
    if (!ok) continue;
    if (route.prefix) {
      params.section = parts.length > 1 ? parts[1] : '';
      params.rest = parts.slice(1).join('/');
    }
    return { route, params };
  }
  return null;
}

/* ------------------------------ 导航 API ------------------------------ */

function normalizeTarget(target) {
  if (typeof target === 'object' && target !== null) {
    return buildHash(target.path || DEFAULT_PATH, target.query || {});
  }
  const str = String(target || '');
  const withHash = str.charAt(0) === '#' ? str : '#' + (str.charAt(0) === '/' ? str : '/' + str);
  return withHash;
}

/** 跳转：target 可为 '#/requests/1'、'/requests/1' 或 {path, query}。 */
export function navigate(target, options = {}) {
  const hash = normalizeTarget(target);
  if (typeof window === 'undefined') return;
  if (options.replace && window.location && typeof window.location.replace === 'function') {
    window.location.replace(hash);
  } else {
    window.location.hash = hash;
  }
  if (options.reload && parseHash(hash).path === currentPath()) {
    render({ force: true });
  }
}

/** 合并当前 URL 查询串；空字符串 / null 表示删除该键。 */
export function setQuery(patch, options = {}) {
  const current = parseHash(typeof window !== 'undefined' ? window.location.hash : '');
  const query = Object.assign({}, current.query);
  let touchPage = false;
  Object.keys(patch || {}).forEach((key) => {
    const value = patch[key];
    if (key === 'page') touchPage = true;
    if (value === undefined || value === null || value === '') {
      delete query[key];
    } else {
      query[key] = String(value);
    }
  });
  if (!touchPage && options.resetPage !== false) {
    delete query.page;
  }
  const target = buildHash(current.path, query);
  const currentHash = typeof window !== 'undefined' ? window.location.hash || '' : '';
  if (target === currentHash) {
    render({ force: true });
    return;
  }
  navigate(target, { replace: options.replace !== false });
}

export function currentPath() {
  const parsed = parseHash(typeof window !== 'undefined' ? window.location.hash : '');
  return parsed.path;
}

export function currentRoute() {
  return state.route;
}

/** 重新渲染当前路由（动作成功后调用）。 */
export function reload() {
  render({ force: true });
}

export function defaultHash() {
  return '#' + DEFAULT_PATH;
}

/* ------------------------------ 渲染 ------------------------------ */

function contextFor(route) {
  return {
    name: route.route.name,
    path: route.path,
    params: route.params,
    query: route.query,
    navigate: (target, options) => navigate(target, options),
    setQuery: (patch, options) => setQuery(patch, options),
    reload: () => reload(),
    back: () => {
      if (typeof history !== 'undefined' && typeof history.back === 'function') history.back();
    },
    clearQuery: () => {
      const parsed = parseHash(typeof window !== 'undefined' ? window.location.hash : '');
      navigate(buildHash(parsed.path, {}), { replace: true });
    }
  };
}

function cleanup() {
  if (typeof state.unmount === 'function') {
    try {
      state.unmount();
    } catch (err) {
      console.error('[router] 页面清理失败', err);
    }
  }
  state.unmount = null;
  ui.closeDrawer();
}

function renderNotFound(host, route, ctx) {
  host.innerHTML =
    `<div class="page">` +
    `<div class="page-header"><div><div class="breadcrumb"><a href="#/dashboard">工作台</a><span class="sep">/</span><span>页面不存在</span></div>` +
    `<h1 class="page-title">页面不存在</h1>` +
    `<div class="page-subtitle">地址 <code>#${ui.esc(route.path)}</code> 没有对应的页面。</div></div></div>` +
    `<div class="panel"><div class="panel-body">` +
    ui.emptyPanel({
      icon: 'search',
      title: '找不到这个页面',
      hint: '请检查链接是否正确，或从下方入口返回工作台。',
      actionLabel: '返回工作台',
      action: 'go-dashboard'
    }) +
    `</div></div></div>`;
  ui.bind(host, '[data-action="go-dashboard"]', 'click', () => navigate('#/dashboard'));
  if (ctx) ctx.path = route.path;
}

async function render(options = {}) {
  const host = state.host;
  if (!host) return;
  const seq = ++state.seq;
  const parsed = parseHash(typeof window !== 'undefined' ? window.location.hash : '');
  if (!parsed.path || parsed.path === '/') {
    navigate(DEFAULT_PATH, { replace: true });
    return;
  }
  const matched = matchRoute(parsed.path);
  cleanup();

  if (!matched) {
    state.route = { path: parsed.path, query: parsed.query, route: { name: 'not-found', title: '页面不存在' }, params: {} };
    renderNotFound(host, { path: parsed.path }, null);
    if (state.onRouteChange) state.onRouteChange(state.route);
    ui.setPageTitle('页面不存在');
    return;
  }

  const route = {
    path: parsed.path,
    query: parsed.query,
    route: matched.route,
    params: matched.params
  };
  state.route = route;
  if (state.onRouteChange) state.onRouteChange(route);
  ui.setPageTitle(matched.route.title);
  ui.scrollToTop();

  try {
    const module = await matched.route.load();
    if (seq !== state.seq) return;
    if (!module || typeof module.mount !== 'function') {
      throw new Error('页面模块缺少 mount 导出：' + matched.route.name);
    }
    const ctx = contextFor(route);
    const result = await module.mount(host, ctx);
    if (seq !== state.seq) {
      if (typeof result === 'function') result();
      return;
    }
    state.unmount = typeof result === 'function' ? result : null;
  } catch (err) {
    if (seq !== state.seq) return;
    console.error('[router] 页面渲染失败', err);
    host.innerHTML =
      `<div class="page">` +
      `<div class="page-header"><div><h1 class="page-title">页面加载失败</h1></div></div>` +
      `<div class="panel"><div class="panel-body">` +
      ui.errorPanel({
        title: '页面渲染出错',
        message: (err && err.message) || '未知错误',
        retry: true
      }) +
      `</div></div></div>`;
    ui.bind(host, '[data-action="retry"]', 'click', () => render({ force: true }));
  }
}

/** 启动路由：绑定 hashchange 并渲染首屏。 */
export function start(host, options = {}) {
  state.host = host;
  state.onRouteChange = options.onRouteChange || null;
  if (typeof window !== 'undefined' && typeof window.addEventListener === 'function') {
    window.addEventListener('hashchange', () => render());
  }
  if (typeof window !== 'undefined' && window.location) {
    if (!window.location.hash || window.location.hash === '#' || window.location.hash === '#/') {
      if (window.history && typeof window.history.replaceState === 'function') {
        window.history.replaceState(null, '', defaultHash());
      } else {
        window.location.hash = defaultHash();
      }
    }
  }
  render();
}
