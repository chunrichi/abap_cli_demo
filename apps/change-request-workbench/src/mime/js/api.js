/**
 * api.js — `/api/v1` 客户端。
 *
 * - 相对路径：页面位于 `/sap/bc/zcrw/`，API 为其下的 `api/v1`（同源）。
 * - 写请求（POST/PATCH/PUT/DELETE）自动带 `X-CRW-Request: 1`。
 * - 成功信封 `{status:"success",data}`；错误信封 `{status:"error",code,message,details,correlationId}`。
 * - 401/403/404/409/502 统一转成中文提示，并保留 correlationId 供页面展示。
 */

const WRITE_METHODS = ['POST', 'PATCH', 'PUT', 'DELETE'];
const DEFAULT_TIMEOUT_MS = 20000;

export class ApiError extends Error {
  constructor(options = {}) {
    super(options.message || '请求失败');
    this.name = 'ApiError';
    this.status = options.status || 0;
    this.code = options.code || 'INTERNAL_ERROR';
    this.details = options.details || {};
    this.correlationId = options.correlationId || '';
    this.httpStatus = options.httpStatus || options.status || 0;
  }
}

let unauthorizedHandler = null;

/** 注册 401 处理（app.js 用来展示会话失效提示）。 */
export function onUnauthorized(handler) {
  unauthorizedHandler = handler;
}

/** 页面同源下的 API 根路径，例如 `/sap/bc/zcrw/api/v1`；mock 环境为 `/api/v1`。 */
export function apiBasePath() {
  const path = (typeof window !== 'undefined' && window.location && window.location.pathname) || '/';
  const dir = path.endsWith('/') ? path : path.replace(/[^/]*$/, '') || '/';
  return dir.replace(/\/$/, '') + '/api/v1';
}

function buildUrl(path, params) {
  const clean = String(path || '').replace(/^\/+/, '');
  let url = apiBasePath() + '/' + clean;
  const query = [];
  Object.keys(params || {}).forEach((key) => {
    const value = params[key];
    if (value === undefined || value === null || value === '') return;
    query.push(encodeURIComponent(key) + '=' + encodeURIComponent(String(value)));
  });
  if (query.length > 0) url += (url.indexOf('?') >= 0 ? '&' : '?') + query.join('&');
  return url;
}

const HTTP_CODE_MAP = {
  400: 'VALIDATION_ERROR',
  401: 'UNAUTHORIZED',
  403: 'FORBIDDEN',
  404: 'NOT_FOUND',
  405: 'VALIDATION_ERROR',
  409: 'CONFLICT',
  500: 'INTERNAL_ERROR',
  502: 'CTS_READ_ERROR',
  503: 'INTERNAL_ERROR',
  504: 'TIMEOUT'
};

function fromHttpStatus(httpStatus, body) {
  const code = HTTP_CODE_MAP[httpStatus] || 'INTERNAL_ERROR';
  const fallback = {
    400: '请求参数校验失败。',
    401: '会话已失效或未登录。',
    403: '没有权限执行该操作。',
    404: '对象不存在，或已被删除。',
    405: '该操作不被允许。',
    409: '数据冲突，请刷新后重试。',
    500: '服务器内部错误，请稍后重试。',
    502: '上游系统读取失败，请稍后重试。',
    503: '服务暂不可用，请稍后重试。',
    504: '请求超时，请稍后重试。'
  };
  return new ApiError({
    status: httpStatus,
    code,
    message: (body && (body.message || body.detail)) || fallback[httpStatus] || '请求失败（HTTP ' + httpStatus + '）。',
    details: (body && body.details) || {},
    correlationId: (body && body.correlationId) || ''
  });
}

/**
 * 发起请求并解包成功信封；失败抛 ApiError。
 * @param {string} method
 * @param {string} path  例如 '/requests/0000000001'
 * @param {{params?:object, body?:object, timeoutMs?:number, raw?:boolean}} options
 */
export async function request(method, path, options = {}) {
  const upper = String(method || 'GET').toUpperCase();
  const isWrite = WRITE_METHODS.indexOf(upper) >= 0;
  const headers = {
    Accept: 'application/json'
  };
  if (isWrite) {
    headers['X-CRW-Request'] = '1';
    if (options.body !== undefined) headers['Content-Type'] = 'application/json; charset=utf-8';
  }

  const controller = typeof AbortController !== 'undefined' ? new AbortController() : null;
  const timeoutMs = options.timeoutMs || DEFAULT_TIMEOUT_MS;
  const timer = controller ? setTimeout(() => controller.abort(), timeoutMs) : null;

  let response;
  try {
    response = await fetch(buildUrl(path, options.params), {
      method: upper,
      headers,
      credentials: 'same-origin',
      cache: 'no-store',
      signal: controller ? controller.signal : undefined,
      body: options.body === undefined ? undefined : JSON.stringify(options.body)
    });
  } catch (err) {
    if (timer) clearTimeout(timer);
    const aborted = err && (err.name === 'AbortError' || err.code === 20);
    throw new ApiError({
      status: aborted ? 504 : 0,
      code: aborted ? 'TIMEOUT' : 'NETWORK_ERROR',
      message: aborted ? '请求超时，请检查网络后重试。' : '无法连接服务（网络错误或服务不可达）。'
    });
  }
  if (timer) clearTimeout(timer);

  let body = null;
  let text = '';
  try {
    text = await response.text();
    if (text) body = JSON.parse(text);
  } catch (err) {
    body = null;
  }

  if (response.status === 401) {
    if (unauthorizedHandler) {
      try {
        unauthorizedHandler();
      } catch (handlerErr) {
        /* 忽略 */
      }
    }
    throw fromHttpStatus(401, body);
  }

  if (!response.ok) {
    if (body && body.status === 'error') {
      throw new ApiError({
        status: response.status,
        code: body.code || HTTP_CODE_MAP[response.status] || 'INTERNAL_ERROR',
        message: body.message || '请求失败。',
        details: body.details || {},
        correlationId: body.correlationId || ''
      });
    }
    throw fromHttpStatus(response.status, body);
  }

  if (body && body.status === 'error') {
    throw new ApiError({
      status: response.status,
      code: body.code || 'INTERNAL_ERROR',
      message: body.message || '请求失败。',
      details: body.details || {},
      correlationId: body.correlationId || ''
    });
  }

  if (text === '') return null;
  if (!body) {
    throw new ApiError({
      status: response.status,
      code: 'INTERNAL_ERROR',
      message: '响应不是合法的 JSON。'
    });
  }
  if (body.status && body.status !== 'success') {
    throw new ApiError({
      status: response.status,
      code: body.code || 'INTERNAL_ERROR',
      message: body.message || '请求失败。',
      details: body.details || {},
      correlationId: body.correlationId || ''
    });
  }
  return Object.prototype.hasOwnProperty.call(body, 'data') ? body.data : body;
}

export const api = {
  get(path, params, options = {}) {
    return request('GET', path, Object.assign({}, options, { params }));
  },
  post(path, body, options = {}) {
    return request('POST', path, Object.assign({}, options, { body: body === undefined ? {} : body }));
  },
  patch(path, body, options = {}) {
    return request('PATCH', path, Object.assign({}, options, { body }));
  },
  del(path, body, options = {}) {
    return request('DELETE', path, Object.assign({}, options, { body }));
  }
};

/** 版本冲突判定（含 SAP 锁占用，二者都要求刷新后重试）。 */
export function isVersionConflict(err) {
  return Boolean(err) && (err.code === 'CONCURRENT_MODIFICATION' || err.code === 'OBJECT_LOCKED');
}

export function isNotFound(err) {
  return Boolean(err) && (err.code === 'NOT_FOUND' || err.status === 404);
}

/**
 * 错误提示文案：{ title, message, correlationId, code }。
 * 优先使用服务端 message，补充前端可执行的下一步提示。
 */
export function describeError(err) {
  if (!err) return { title: '请求失败', message: '未知错误。', correlationId: '', code: '' };
  const code = err.code || '';
  const correlationId = err.correlationId || '';
  const serverMsg = err.message || '';
  const details = err.details || {};
  const missing = Array.isArray(details.missing) && details.missing.length > 0 ? details.missing : null;

  let title = '请求失败';
  let message = serverMsg || '请求失败，请稍后重试。';

  if (err.status === 401 || code === 'UNAUTHORIZED') {
    title = '会话失效';
    message = '未登录或会话已过期，请重新登录 SAP 后刷新页面。';
  } else if (err.status === 403 || code === 'FORBIDDEN') {
    title = '无权限';
    message = serverMsg || '当前角色没有执行该操作的权限。';
  } else if (code === 'APPROVER_MISMATCH') {
    title = '非当前审批人';
    message = serverMsg || '你不是当前审批步骤的审批人，无法通过或驳回。';
  } else if (code === 'SELF_APPROVAL') {
    title = '不能自审';
    message = serverMsg || '请求人不能审批自己提交的请求。';
  } else if (code === 'NOT_FOUND' || err.status === 404) {
    title = '对象不存在';
    message = serverMsg || '对象不存在，或已被删除。';
  } else if (code === 'CONCURRENT_MODIFICATION') {
    title = '版本冲突';
    message = '记录已被其他人修改，正在刷新最新数据，请确认后重试。';
  } else if (code === 'OBJECT_LOCKED') {
    title = '记录被占用';
    message = 'SAP 锁占用导致本次操作失败，请稍后重试。';
  } else if (code === 'INVALID_TRANSITION') {
    title = '当前状态不允许';
    message = serverMsg || '当前状态不允许执行该动作，请刷新后查看最新状态。';
  } else if (code === 'GUARD_FAILED') {
    title = '前置条件不满足';
    message = serverMsg || '前置条件不满足，暂时无法执行该动作。';
    if (missing) message += '（未满足：' + missing.join('、') + '）';
  } else if (code === 'DUPLICATE_LINK') {
    title = '传输已被关联';
    message = serverMsg || '该传输已关联到其他变更文档，不能重复关联。';
  } else if (code === 'SCHEDULE_CONFLICT') {
    title = '计划冲突';
    message = serverMsg || '已存在生效中的导入计划，请先改期或取消后再操作。';
  } else if (code === 'CTS_READ_ERROR' || err.status === 502) {
    title = 'CTS 读取失败';
    message = '传输状态读取失败，已降级显示为未知状态；请稍后重试或到 STMS 确认。';
  } else if (code === 'VALIDATION_ERROR' || err.status === 400) {
    title = '校验失败';
    message = serverMsg || '请求参数校验失败，请检查后重试。';
  } else if (code === 'TIMEOUT') {
    title = '请求超时';
    message = '请求超时，请检查网络后重试。';
  } else if (code === 'NETWORK_ERROR') {
    title = '网络错误';
    message = '无法连接服务，请检查网络或稍后重试。';
  } else if (err.status >= 500) {
    title = '服务异常';
    message = serverMsg || '服务器内部错误，请稍后重试。';
  }

  return { title, message, correlationId, code };
}

const EXPORT_TYPES = ['changes', 'duration', 'overdue', 'to-c', 'requests', 'audit'];

function sanitizeExportType(type) {
  return EXPORT_TYPES.indexOf(String(type)) >= 0 ? String(type) : 'changes';
}

/**
 * 下载报表 CSV：GET /reports/export.csv?type=...
 * 文件名只用白名单 type + 日期，不拼接用户输入。
 */
export async function downloadCsv(type, params = {}) {
  const safeType = sanitizeExportType(type);
  const url = buildUrl('/reports/export.csv', Object.assign({}, params, { type: safeType }));
  let response;
  try {
    response = await fetch(url, {
      method: 'GET',
      headers: { Accept: 'text/csv', 'X-CRW-Request': '1' },
      credentials: 'same-origin',
      cache: 'no-store'
    });
  } catch (err) {
    throw new ApiError({ status: 0, code: 'NETWORK_ERROR', message: '无法连接服务，导出失败。' });
  }
  if (!response.ok) {
    let body = null;
    try {
      body = await response.json();
    } catch (err) {
      body = null;
    }
    if (body && body.code) {
      throw new ApiError({
        status: response.status,
        code: body.code,
        message: body.message || '导出失败。',
        details: body.details || {},
        correlationId: body.correlationId || ''
      });
    }
    throw fromHttpStatus(response.status, body);
  }
  const blob = await response.blob();
  const stamp = new Date().toISOString().slice(0, 10).replace(/-/g, '');
  const filename = 'crw-' + safeType + '-' + stamp + '.csv';
  if (typeof document === 'undefined' || typeof document.createElement !== 'function') return filename;
  const href = URL.createObjectURL(blob);
  const link = document.createElement('a');
  link.href = href;
  link.download = filename;
  link.style.display = 'none';
  document.body.appendChild(link);
  link.click();
  setTimeout(() => {
    URL.revokeObjectURL(href);
    if (link.parentNode) link.parentNode.removeChild(link);
  }, 0);
  return filename;
}
