/**
 * ui.js — 渲染与交互工具：转义、中文映射、徽标、表单、表格、分页、
 * toast / modal / drawer、空态 / 加载态 / 错误态、日期格式化。
 *
 * 约定：
 *  - 所有用户数据进入 HTML 前必须走 esc()。
 *  - 本模块不改全局状态；页面通过返回值自行绑定事件。
 *  - 所有 DOM 访问都在函数内部完成，方便在 node 下做渲染冒烟测试。
 */

/* ============================ 文本安全 ============================ */

const ESC_MAP = {
  '&': '&amp;',
  '<': '&lt;',
  '>': '&gt;',
  '"': '&quot;',
  "'": '&#39;'
};

/** HTML 转义（文本与属性通用）。所有用户可控文本必须经过这里。 */
export function esc(value) {
  if (value === null || value === undefined) return '';
  return String(value).replace(/[&<>"']/g, (ch) => ESC_MAP[ch]);
}

/** 转义并给空值占位符。 */
export function safe(value, placeholder = '—') {
  if (value === null || value === undefined || value === '') return esc(placeholder);
  return esc(value);
}

/* ============================ 时间格式化 ============================ */

function pad2(n) {
  return n < 10 ? '0' + n : String(n);
}

/** 解析后端时间：yyyy-MM-ddTHH:mm:ss / yyyyMMddHHmmss / ISO 带偏移 / yyyy-MM-dd。 */
export function parseTimestamp(value) {
  if (!value) return null;
  const raw = String(value).trim();
  if (/^\d{14}$/.test(raw)) {
    return {
      y: +raw.slice(0, 4),
      m: +raw.slice(4, 6),
      d: +raw.slice(6, 8),
      hh: +raw.slice(8, 10),
      mm: +raw.slice(10, 12),
      ss: +raw.slice(12, 14),
      naive: true
    };
  }
  const m = raw.match(/^(\d{4})-(\d{2})-(\d{2})(?:[T ](\d{2}):(\d{2})(?::(\d{2}))?)?/);
  if (!m) return null;
  const hasOffset = /(?:Z|[+-]\d{2}:?\d{2})$/.test(raw) && /T/.test(raw);
  if (hasOffset) {
    const dt = new Date(raw);
    if (!Number.isNaN(dt.getTime())) {
      return {
        y: dt.getFullYear(),
        m: dt.getMonth() + 1,
        d: dt.getDate(),
        hh: dt.getHours(),
        mm: dt.getMinutes(),
        ss: dt.getSeconds(),
        naive: false
      };
    }
  }
  return {
    y: +m[1],
    m: +m[2],
    d: +m[3],
    hh: m[4] === undefined ? 0 : +m[4],
    mm: m[5] === undefined ? 0 : +m[5],
    ss: m[6] === undefined ? 0 : +m[6],
    naive: true
  };
}

/** yyyy-MM-dd HH:mm（SAP 系统本地时间，不做时区换算）。 */
export function fmtDateTime(value, placeholder = '—') {
  const p = parseTimestamp(value);
  if (!p) return esc(placeholder);
  const hasTime = /[T ]\d{2}:\d{2}/.test(String(value)) || /^\d{14}$/.test(String(value).trim());
  if (!hasTime) return `${p.y}-${pad2(p.m)}-${pad2(p.d)}`;
  return `${p.y}-${pad2(p.m)}-${pad2(p.d)} ${pad2(p.hh)}:${pad2(p.mm)}`;
}

/** yyyy-MM-dd。 */
export function fmtDate(value, placeholder = '—') {
  const p = parseTimestamp(value);
  if (!p) return esc(placeholder);
  return `${p.y}-${pad2(p.m)}-${pad2(p.d)}`;
}

/** yyyy-MM-ddTHH:mm（用于 <input type="datetime-local">）。 */
export function toDateTimeInput(value) {
  const p = parseTimestamp(value);
  if (!p) return '';
  return `${p.y}-${pad2(p.m)}-${pad2(p.d)}T${pad2(p.hh)}:${pad2(p.mm)}`;
}

/** 表单 datetime-local 值 → API 需要的 yyyy-MM-ddTHH:mm:ss。 */
export function fromDateTimeInput(value) {
  if (!value) return '';
  const raw = String(value).trim();
  if (/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/.test(raw)) return raw + ':00';
  return raw;
}

/** 表单 date 值 → yyyy-MM-dd（截断时间部分）。 */
export function fromDateInput(value) {
  if (!value) return '';
  return String(value).slice(0, 10);
}

export function toDateInput(value) {
  const p = parseTimestamp(value);
  if (!p) return '';
  return `${p.y}-${pad2(p.m)}-${pad2(p.d)}`;
}

/** 相对时间：刚刚 / N 分钟前 / N 小时前 / N 天前 / 绝对时间。 */
export function fmtRelative(value, placeholder = '—') {
  const p = parseTimestamp(value);
  if (!p) return esc(placeholder);
  if (!p.naive) {
    const ts = new Date(String(value)).getTime();
    if (!Number.isNaN(ts)) return relativeFromMs(ts);
  }
  const ts = new Date(p.y, p.m - 1, p.d, p.hh, p.mm, p.ss).getTime();
  return relativeFromMs(ts);
}

function relativeFromMs(ts) {
  const diff = Date.now() - ts;
  if (Number.isNaN(diff)) return '—';
  if (diff < 0) {
    const ahead = Math.abs(diff);
    if (ahead < 3600000) return Math.round(ahead / 60000) + ' 分钟后';
    if (ahead < 86400000) return Math.round(ahead / 3600000) + ' 小时后';
    return Math.round(ahead / 86400000) + ' 天后';
  }
  if (diff < 60000) return '刚刚';
  if (diff < 3600000) return Math.max(1, Math.round(diff / 60000)) + ' 分钟前';
  if (diff < 86400000) return Math.round(diff / 3600000) + ' 小时前';
  if (diff < 86400000 * 30) return Math.round(diff / 86400000) + ' 天前';
  return fmtDate(new Date(ts).toISOString());
}

/** 是否已过期（仅按日期/时间字面比较，不做时区换算）。 */
export function isOverdue(value) {
  const p = parseTimestamp(value);
  if (!p) return false;
  const hasTime = /[T ]\d{2}:\d{2}/.test(String(value)) || /^\d{14}$/.test(String(value).trim());
  const target = new Date(p.y, p.m - 1, p.d, hasTime ? p.hh : 23, hasTime ? p.mm : 59, 0, 0).getTime();
  return target < Date.now();
}

/** 今天 yyyy-MM-dd（本地）。 */
export function today() {
  const now = new Date();
  return `${now.getFullYear()}-${pad2(now.getMonth() + 1)}-${pad2(now.getDate())}`;
}

export function addDays(dateStr, days) {
  const p = parseTimestamp(dateStr);
  if (!p) return dateStr;
  const dt = new Date(p.y, p.m - 1, p.d);
  dt.setDate(dt.getDate() + days);
  return `${dt.getFullYear()}-${pad2(dt.getMonth() + 1)}-${pad2(dt.getDate())}`;
}

const WEEKDAYS = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'];

/** 计划分组用：2026-11-27（周五）。 */
export function fmtDayLabel(dateStr) {
  const p = parseTimestamp(dateStr);
  if (!p) return esc(dateStr || '—');
  const dt = new Date(p.y, p.m - 1, p.d);
  return `${p.y}-${pad2(p.m)}-${pad2(p.d)}（${WEEKDAYS[dt.getDay()]}）`;
}

export function fmtNum(value) {
  const n = Number(value);
  if (!Number.isFinite(n)) return esc(value === undefined || value === null ? '—' : value);
  return new Intl.NumberFormat('zh-CN').format(n);
}

export function fmtHours(value) {
  const n = Number(value);
  if (!Number.isFinite(n)) return '—';
  if (n < 1) return Math.round(n * 60) + ' 分钟';
  if (n < 48) return (Math.round(n * 10) / 10) + ' 小时';
  return (Math.round((n / 24) * 10) / 10) + ' 天';
}

/* ============================ 中文映射 ============================ */

/** 对象状态（CR / CD / Task / 计划共用，按编码取值）。 */
export const STATUS = {
  NEW: { zh: '新建', tone: 'neutral' },
  PENDING_APPROVAL: { zh: '待审批', tone: 'warn' },
  REJECTED: { zh: '已拒绝', tone: 'danger' },
  APPROVED: { zh: '已批准', tone: 'ok' },
  IN_PROGRESS: { zh: '进行中', tone: 'info' },
  CLOSED: { zh: '已关闭', tone: 'neutral' },
  CANCELLED: { zh: '已取消', tone: 'neutral' },
  IN_DEV: { zh: '开发中', tone: 'cyan' },
  IN_TEST: { zh: '测试中', tone: 'violet' },
  READY_TO_IMPORT: { zh: '待导入', tone: 'teal' },
  IMPORT_SCHEDULED: { zh: '已计划导入', tone: 'indigo' },
  IMPORTED: { zh: '已导入', tone: 'ok' },
  OPEN: { zh: '待开始', tone: 'neutral' },
  DONE: { zh: '已完成', tone: 'ok' },
  PLANNED: { zh: '已计划', tone: 'indigo' },
  MISSED: { zh: '已逾期', tone: 'danger' }
};

export const PRIORITY = {
  1: { zh: '紧急', tone: 'danger' },
  2: { zh: '高', tone: 'warn' },
  3: { zh: '中', tone: 'info' },
  4: { zh: '低', tone: 'neutral' },
  '': { zh: '未定', tone: 'neutral' }
};

export const REQUEST_TYPE = {
  STD: { zh: '标准变更', tone: 'info' },
  URG: { zh: '紧急变更', tone: 'danger' },
  ADM: { zh: '管理变更', tone: 'neutral' }
};

export const TASK_TYPE = {
  DEV: { zh: '开发', tone: 'cyan' },
  TEST: { zh: '测试', tone: 'violet' },
  IMPORT: { zh: '导入确认', tone: 'teal' },
  RETROFIT: { zh: '补做', tone: 'warn' }
};

export const TASK_LEVEL = {
  T: { zh: '任务', tone: 'neutral' },
  S: { zh: '子任务', tone: 'neutral' }
};

export const APPROVAL_STATE = {
  NONE: { zh: '无审批', tone: 'neutral' },
  PENDING: { zh: '审批中', tone: 'warn' },
  APPROVED: { zh: '已批准', tone: 'ok' },
  REJECTED: { zh: '已驳回', tone: 'danger' },
  SKIPPED: { zh: '已跳过', tone: 'neutral' }
};

export const ROLE = {
  REQUESTER: { zh: '请求人', tone: 'neutral' },
  CHANGE_MANAGER: { zh: '变更经理', tone: 'info' },
  DEVELOPER: { zh: '开发', tone: 'cyan' },
  TESTER: { zh: '测试', tone: 'violet' },
  RELEASE_MANAGER: { zh: '发布管理员', tone: 'indigo' },
  ADMIN: { zh: '管理员', tone: 'warn' },
  VIEWER: { zh: '观察者', tone: 'neutral' }
};

export const SCOPE_TYPE = {
  GLOBAL: '全局',
  COMPONENT: '组件',
  CYCLE: '周期'
};

export const OBJECT_TYPE = {
  REQ: { zh: '请求', tone: 'info' },
  CD: { zh: '变更文档', tone: 'violet' },
  TASK: { zh: '任务', tone: 'neutral' },
  TR: { zh: '传输', tone: 'teal' },
  SCHED: { zh: '导入计划', tone: 'indigo' },
  CONFIG: { zh: '配置', tone: 'neutral' },
  NOTE: { zh: '备注', tone: 'neutral' }
};

export const TR_KIND = {
  DEV: { zh: '开发传输', tone: 'info' },
  TOC: { zh: 'ToC 传输', tone: 'violet' }
};

export const TR_STATUS = {
  D: { zh: '可修改', tone: 'info' },
  R: { zh: '已释放', tone: 'ok' },
  N: { zh: '未释放', tone: 'warn' }
};

export const SYNC_STATE = {
  OK: { zh: '已同步', tone: 'ok' },
  ERROR: { zh: '同步失败', tone: 'danger' },
  DETACHED: { zh: '已标记不再关联', tone: 'warn' },
  UNKNOWN: { zh: '未知', tone: 'neutral' }
};

export const RETROFIT_STATE = {
  NA: { zh: '不适用', tone: 'neutral' },
  PENDING: { zh: '待补做', tone: 'warn' },
  DONE: { zh: '已补做', tone: 'ok' }
};

export const SCHEDULE_STATUS = {
  PLANNED: { zh: '已计划', tone: 'indigo' },
  DONE: { zh: '已完成', tone: 'ok' },
  MISSED: { zh: '已逾期', tone: 'danger' },
  CANCELLED: { zh: '已取消', tone: 'neutral' }
};

/** In-app notification type (notifyType). */
export const NOTIFY_TYPE = {
  APPROVAL_PENDING: { zh: '待审批', tone: 'warn' },
  APPROVAL_REJECTED: { zh: '审批驳回', tone: 'danger' },
  TASK_OVERDUE: { zh: '任务逾期', tone: 'danger' },
  SCHED_OVERDUE: { zh: '计划逾期', tone: 'danger' },
  INFO: { zh: '一般通知', tone: 'info' }
};

/** In-app notification severity. */
export const NOTIFY_SEVERITY = {
  INFO: { zh: '提示', tone: 'neutral' },
  WARN: { zh: '警告', tone: 'warn' },
  CRITICAL: { zh: '严重', tone: 'danger' }
};

/** In-app notification read state (status). */
export const NOTIFY_STATE = {
  UNREAD: { zh: '未读', tone: 'info' },
  READ: { zh: '已读', tone: 'neutral' },
  DISMISSED: { zh: '已忽略', tone: 'neutral' }
};

export const ACTION_LABEL = {
  SUBMIT: '提交审批',
  WITHDRAW: '撤回',
  APPROVE_STEP: '通过审批',
  REJECT: '驳回',
  SKIP_STEP: '跳过步骤',
  REVISE: '修改后重提',
  START_PROGRESS: '开始进行',
  CLOSE: '关闭',
  CANCEL: '取消',
  START_DEV: '开始开发',
  SUBMIT_TEST: '提交测试',
  PASS_TEST: '测试通过',
  SUBMIT_APPROVAL: '提交导入审批',
  MARK_READY: '标记待导入',
  SCHEDULE_IMPORT: '计划导入',
  CONFIRM_IMPORT: '确认导入',
  START: '开始',
  DONE: '完成',
  RESCHEDULE: '改期',
  CONFIRM: '确认完成',
  CREATE_REQ: '创建请求',
  CREATE_CD: '创建变更文档',
  CREATE_TASK: '创建任务',
  CREATE_SUBTASK: '创建子任务',
  UPDATE_REQ: '编辑请求',
  UPDATE_CD: '编辑变更文档',
  UPDATE_TASK: '编辑任务',
  LINK_TR: '关联传输',
  UNLINK_TR: '解绑传输',
  MARK_DETACHED: '标记不再关联',
  SYNC_TR: '同步传输',
  ADD_NOTE: '添加备注',
  DECISION_APPROVED: '审批通过',
  DECISION_REJECTED: '审批驳回'
};

export function actionLabel(action) {
  if (!action) return '—';
  return ACTION_LABEL[action] || String(action);
}

function dictEntry(dict, key, fallbackZh) {
  if (key === null || key === undefined) key = '';
  return dict[key] || { zh: fallbackZh || String(key) || '未知', tone: 'neutral' };
}

/* ============================ 徽标 ============================ */

export function badge(text, tone = 'neutral', extraClass = '') {
  const cls = ['badge', 'tone-' + tone, extraClass].filter(Boolean).join(' ');
  return `<span class="${cls}">${esc(text)}</span>`;
}

export function statusBadge(status, extra = '') {
  const entry = dictEntry(STATUS, status, status || '未知');
  return badge(extra ? entry.zh + ' · ' + extra : entry.zh, entry.tone);
}

/** 审批步骤状态（APPR_STATE）与对象审批状态共用。 */
export function apprStateBadge(state) {
  const entry = dictEntry(APPROVAL_STATE, state, state || '未知');
  return badge(entry.zh, entry.tone);
}

export function approvalStateBadge(state) {
  return apprStateBadge(state);
}

export function priorityBadge(priority) {
  const key = priority === null || priority === undefined ? '' : String(priority);
  const entry = dictEntry(PRIORITY, key, key || '未定');
  return badge(entry.zh, entry.tone);
}

export function requestTypeBadge(type) {
  const entry = dictEntry(REQUEST_TYPE, type, type || '未知');
  return badge(entry.zh, entry.tone);
}

export function taskTypeBadge(type) {
  const entry = dictEntry(TASK_TYPE, type, type || '未知');
  return badge(entry.zh, entry.tone);
}

export function taskLevelBadge(level) {
  const entry = dictEntry(TASK_LEVEL, level, level || '未知');
  return badge(entry.zh, entry.tone);
}

export function trKindBadge(kind) {
  const entry = dictEntry(TR_KIND, kind, kind || '未知');
  return badge(entry.zh, entry.tone);
}

export function syncStateBadge(state) {
  const entry = dictEntry(SYNC_STATE, state, state || '未知');
  return badge(entry.zh, entry.tone);
}

export function trStatusBadge(transport) {
  const t = transport || {};
  const entry = dictEntry(TR_STATUS, t.trStatus, t.trStatusText || t.trStatus || '未知');
  // 服务端 trStatusText 与本地中文映射相同则只显示一次，避免「可修改 · 可修改」
  const text = t.trStatusText && t.trStatusText !== entry.zh ? entry.zh + ' · ' + t.trStatusText : entry.zh;
  return badge(text, entry.tone);
}

export function retrofitBadge(state) {
  const entry = dictEntry(RETROFIT_STATE, state, state || '未知');
  return badge(entry.zh, entry.tone);
}

export function scheduleStatusBadge(status) {
  const entry = dictEntry(SCHEDULE_STATUS, status, status || '未知');
  return badge(entry.zh, entry.tone);
}

export function notifyTypeBadge(type) {
  const entry = dictEntry(NOTIFY_TYPE, type, type || '通知');
  return badge(entry.zh, entry.tone);
}

export function notifySeverityBadge(severity) {
  const entry = dictEntry(NOTIFY_SEVERITY, severity, severity || '提示');
  return badge(entry.zh, entry.tone);
}

export function notifyStatusBadge(status) {
  const entry = dictEntry(NOTIFY_STATE, status, status || '未知');
  return badge(entry.zh, entry.tone);
}

export function roleBadge(role) {
  const entry = dictEntry(ROLE, role, role || '未知');
  return badge(entry.zh, entry.tone);
}

export function objectTypeBadge(type) {
  const entry = dictEntry(OBJECT_TYPE, type, type || '未知');
  return badge(entry.zh, entry.tone);
}

export function objectTypeLabel(type) {
  return dictEntry(OBJECT_TYPE, type, type || '未知').zh;
}

export function roleLabel(role) {
  return dictEntry(ROLE, role, role || '未知').zh;
}

export function statusLabel(status) {
  return dictEntry(STATUS, status, status || '未知').zh;
}

/* ============================ 内联 SVG 图标 ============================ */

const ICONS = {
  dashboard: '<rect x="3" y="3" width="7" height="9" rx="1"/><rect x="14" y="3" width="7" height="5" rx="1"/><rect x="14" y="12" width="7" height="9" rx="1"/><rect x="3" y="16" width="7" height="5" rx="1"/>',
  work: '<path d="M9 11l3 3L22 4"/><path d="M21 12v7a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h11"/>',
  request: '<path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><path d="M14 2v6h6"/><path d="M9 13h6M9 17h6"/>',
  cd: '<path d="M4 4a2 2 0 0 1 2-2h8l6 6v12a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2z"/><path d="M14 2v6h6"/><path d="M8 13h4M8 17h8"/>',
  task: '<path d="M9 11l3 3 8-8"/><path d="M20 12v6a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2h9"/>',
  approval: '<path d="M9 12l2 2 4-4"/><path d="M12 22c5.5 0 10-4.5 10-10S17.5 2 12 2 2 6.5 2 12s4.5 10 10 10z"/>',
  transport: '<path d="M21 8a2 2 0 0 0-1-1.73l-7-4a2 2 0 0 0-2 0l-7 4A2 2 0 0 0 3 8v8a2 2 0 0 0 1 1.73l7 4a2 2 0 0 0 2 0l7-4A2 2 0 0 0 21 16z"/><path d="M3.3 7l8.7 5 8.7-5"/><path d="M12 22V12"/>',
  schedule: '<rect x="3" y="4" width="18" height="18" rx="2"/><path d="M16 2v4M8 2v4M3 10h18"/>',
  report: '<path d="M3 3v18h18"/><rect x="7" y="12" width="3" height="6" rx="1"/><rect x="12" y="8" width="3" height="10" rx="1"/><rect x="17" y="5" width="3" height="13" rx="1"/>',
  config: '<path d="M4 21v-7M4 10V3M12 21v-9M12 8V3M20 21v-5M20 12V3"/><path d="M1 14h6M9 8h6M17 16h6"/>',
  help: '<circle cx="12" cy="12" r="10"/><path d="M9.1 9a3 3 0 0 1 5.8 1c0 2-3 3-3 3"/><path d="M12 17h.01"/>',
  search: '<circle cx="11" cy="11" r="7"/><path d="M21 21l-4.3-4.3"/>',
  close: '<path d="M18 6L6 18M6 6l12 12"/>',
  plus: '<path d="M12 5v14M5 12h14"/>',
  chevronRight: '<path d="M9 18l6-6-6-6"/>',
  chevronLeft: '<path d="M15 18l-6-6 6-6"/>',
  chevronDown: '<path d="M6 9l6 6 6-6"/>',
  refresh: '<path d="M21 12a9 9 0 1 1-2.6-6.4"/><path d="M21 3v6h-6"/>',
  alert: '<path d="M10.3 3.9L1.8 18a2 2 0 0 0 1.7 3h17a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0z"/><path d="M12 9v4M12 17h.01"/>',
  info: '<circle cx="12" cy="12" r="10"/><path d="M12 16v-4M12 8h.01"/>',
  check: '<path d="M20 6L9 17l-5-5"/>',
  x: '<path d="M18 6L6 18M6 6l12 12"/>',
  link: '<path d="M10 13a5 5 0 0 0 7.5.5l3-3a5 5 0 0 0-7-7l-1.7 1.7"/><path d="M14 11a5 5 0 0 0-7.5-.5l-3 3a5 5 0 0 0 7 7l1.7-1.7"/>',
  unlink: '<path d="M18.8 5.2a5 5 0 0 1 0 7l-1.7 1.7"/><path d="M5.2 18.8a5 5 0 0 1 0-7l1.7-1.7"/><path d="M8 2v4M2 8h4M16 22v-4M22 16h-4"/>',
  clock: '<circle cx="12" cy="12" r="10"/><path d="M12 6v6l4 2"/>',
  user: '<path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2"/><circle cx="12" cy="7" r="4"/>',
  download: '<path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><path d="M7 10l5 5 5-5"/><path d="M12 15V3"/>',
  filter: '<path d="M22 3H2l8 9.5V19l4 2v-8.5z"/>',
  sync: '<path d="M23 4v6h-6"/><path d="M1 20v-6h6"/><path d="M3.5 9a9 9 0 0 1 14.9-3.4L23 10"/><path d="M20.5 15a9 9 0 0 1-14.9 3.4L1 14"/>',
  history: '<path d="M3 3v6h6"/><path d="M3.5 9a9 9 0 1 1 2.1 9.4"/>',
  inbox: '<path d="M22 12h-6l-2 3h-4l-2-3H2"/><path d="M5.4 5.1L2 12v6a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2v-6l-3.4-6.9A2 2 0 0 0 16.8 4H7.2a2 2 0 0 0-1.8 1.1z"/>',
  external: '<path d="M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6"/><path d="M15 3h6v6"/><path d="M10 14L21 3"/>',
  edit: '<path d="M11 4H4a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7"/><path d="M18.5 2.5a2.1 2.1 0 0 1 3 3L12 15l-4 1 1-4z"/>',
  folder: '<path d="M22 19a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h5l2 3h9a2 2 0 0 1 2 2z"/>'
};

export function icon(name, size = 16, cls = '') {
  const path = ICONS[name];
  if (!path) return '';
  return (
    `<svg ${cls ? 'class="' + esc(cls) + '" ' : ''}width="${size}" height="${size}" viewBox="0 0 24 24" ` +
    'fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" ' +
    `aria-hidden="true">${path}</svg>`
  );
}

/* ============================ 通用 HTML 片段 ============================ */

export function banner(text, kind = 'info', iconName = 'info') {
  return `<div class="banner banner-${esc(kind)}">${icon(iconName, 16)}<div>${esc(text)}</div></div>`;
}

/**
 * 页头：面包屑 + 标题 + 副标题 + 右侧动作。
 * @param {{title:string, subtitle?:string, breadcrumb?:Array<{label:string,href?:string}>, actions?:string, meta?:string}} opts
 */
export function pageHeader(opts = {}) {
  const crumbs = (opts.breadcrumb || [])
    .map((item, index) => {
      const label = esc(item.label);
      const link = item.href ? `<a href="${esc(item.href)}">${label}</a>` : `<span>${label}</span>`;
      return (index > 0 ? '<span class="sep">/</span>' : '') + link;
    })
    .join('');
  return `<div class="page-header">
    <div>
      ${crumbs ? `<div class="breadcrumb">${crumbs}</div>` : ''}
      <h1 class="page-title">${esc(opts.title || '')}${opts.titleExtra || ''}</h1>
      ${opts.subtitle ? `<div class="page-subtitle">${opts.subtitle}</div>` : ''}
      ${opts.meta ? `<div class="page-meta">${opts.meta}</div>` : ''}
    </div>
    ${opts.actions ? `<div class="page-head-actions">${opts.actions}</div>` : '<div></div>'}
  </div>`;
}

export function kvList(items) {
  const rows = items
    .map((item) => {
      const value = item.html !== undefined ? item.html : safe(item.value);
      return `<div class="kv"><dt>${esc(item.label)}</dt><dd>${value}</dd></div>`;
    })
    .join('');
  return `<dl class="kv-grid">${rows}</dl>`;
}

export function field(def, value, extraClass = '') {
  const id = 'f-' + String(def.name).replace(/[^a-zA-Z0-9_-]/g, '');
  const val = value === undefined || value === null ? def.value : value;
  const classes = ['field', def.span === 2 ? 'span-2' : '', def.span === 'all' ? 'span-all' : '', extraClass]
    .filter(Boolean)
    .join(' ');
  const required = def.required ? '<span class="req" title="必填">*</span>' : '';
  let control = '';
  const disabled = def.disabled ? ' disabled' : '';
  const placeholder = def.placeholder ? ` placeholder="${esc(def.placeholder)}"` : '';
  if (def.type === 'select') {
    const options = (def.options || [])
      .map((opt) => {
        const selected = String(opt.value) === String(val === undefined || val === null ? '' : val) ? ' selected' : '';
        return `<option value="${esc(opt.value)}"${selected}>${esc(opt.label)}</option>`;
      })
      .join('');
    control = `<select class="select" id="${id}" name="${esc(def.name)}"${disabled}${def.required ? ' required' : ''}>${options}</select>`;
  } else if (def.type === 'textarea') {
    control = `<textarea class="textarea" id="${id}" name="${esc(def.name)}" rows="${def.rows || 4}"${placeholder}${disabled}${def.required ? ' required' : ''}>${esc(val)}</textarea>`;
  } else if (def.type === 'checkbox') {
    return `<div class="${classes}"><label class="checkbox"><input type="checkbox" id="${id}" name="${esc(def.name)}"${val ? ' checked' : ''}${disabled}> <span>${esc(def.label)}</span></label>${
      def.hint ? `<div class="field-hint">${esc(def.hint)}</div>` : ''
    }<div class="field-error" data-error-for="${esc(def.name)}"></div></div>`;
  } else {
    const type = def.type || 'text';
    const attrs = [
      def.min !== undefined ? `min="${esc(def.min)}"` : '',
      def.max !== undefined ? `max="${esc(def.max)}"` : '',
      def.step !== undefined ? `step="${esc(def.step)}"` : '',
      def.maxlength !== undefined ? `maxlength="${esc(def.maxlength)}"` : '',
      def.pattern ? `pattern="${esc(def.pattern)}"` : ''
    ]
      .filter(Boolean)
      .join(' ');
    control = `<input class="input" type="${esc(type)}" id="${id}" name="${esc(def.name)}" value="${esc(val)}"${placeholder}${disabled} ${attrs}${def.required ? ' required' : ''}>`;
  }
  return `<div class="${classes}" data-field="${esc(def.name)}">
    <label class="field-label" for="${id}">${esc(def.label)}${required}</label>
    ${control}
    ${def.hint ? `<div class="field-hint">${esc(def.hint)}</div>` : ''}
    <div class="field-error" data-error-for="${esc(def.name)}"></div>
  </div>`;
}

/** 多字段渲染为 .form-grid。 */
export function renderFields(fields, values = {}) {
  const html = fields
    .map((def) => field(def, Object.prototype.hasOwnProperty.call(values, def.name) ? values[def.name] : undefined))
    .join('');
  return `<div class="form-grid">${html}</div>`;
}

/** 读取表单值：input / select / textarea（按 name），checkbox 返回 boolean。 */
export function readFormValues(root) {
  const values = {};
  if (!root || typeof root.querySelectorAll !== 'function') return values;
  const nodes = root.querySelectorAll('[name]');
  for (let i = 0; i < nodes.length; i++) {
    const el = nodes[i];
    const name = el.name;
    if (!name) continue;
    if (el.type === 'checkbox') {
      values[name] = Boolean(el.checked);
    } else if (el.type === 'number') {
      values[name] = el.value === '' ? '' : Number(el.value);
    } else {
      values[name] = typeof el.value === 'string' ? el.value.trim() : el.value;
    }
  }
  return values;
}

/** 纯函数校验：返回 { field: message }。 */
export function validateValues(values, fields) {
  const errors = {};
  (fields || []).forEach((def) => {
    if (!def.required) return;
    const value = values ? values[def.name] : undefined;
    if (def.type === 'checkbox') {
      if (!value) errors[def.name] = def.requiredMessage || '此项必选';
      return;
    }
    if (value === undefined || value === null || String(value).trim() === '') {
      errors[def.name] = def.requiredMessage || '此项必填';
    }
  });
  return errors;
}

/** 把校验结果写到内联提示；返回第一个出错元素。 */
export function showFieldErrors(root, errors) {
  let first = null;
  if (!root || typeof root.querySelectorAll !== 'function') return first;
  const nodes = root.querySelectorAll('[data-field]');
  for (let i = 0; i < nodes.length; i++) {
    const wrap = nodes[i];
    const name = wrap.getAttribute('data-field');
    const msg = errors && errors[name];
    wrap.classList.toggle('invalid', Boolean(msg));
    const errEl = wrap.querySelector('[data-error-for]');
    if (errEl) errEl.textContent = msg || '';
    if (msg && !first) first = wrap.querySelector('input, select, textarea');
  }
  const loose = root.querySelectorAll('[data-error-for]');
  for (let i = 0; i < loose.length; i++) {
    const el = loose[i];
    const name = el.getAttribute('data-error-for');
    if (name && errors && errors[name]) el.textContent = errors[name];
  }
  if (first && typeof first.focus === 'function') first.focus();
  return first;
}

export function clearFieldErrors(root) {
  showFieldErrors(root, {});
}

/* ============================ 空 / 加载 / 错误态 ============================ */

export function loadingPanel(text = '正在加载…') {
  return `<div class="loading-box"><div class="spinner" aria-hidden="true"></div><div>${esc(text)}</div></div>`;
}

export function skeletonTable(cols = 5, rows = 6) {
  let html = '<div class="skeleton">';
  for (let r = 0; r < rows; r++) {
    html +=
      '<div class="skeleton-row ' +
      (r % 3 === 0 ? 'w-70' : r % 3 === 1 ? 'w-40' : '') +
      '"></div>';
  }
  html += '</div>';
  return html;
}

export function emptyPanel(options = {}) {
  const opts = typeof options === 'string' ? { title: options } : options;
  const action = opts.action
    ? `<button type="button" class="btn btn-sm" data-action="${esc(opts.action)}">${esc(opts.actionLabel || '下一步')}</button>`
    : '';
  return `<div class="empty">
    <div class="empty-icon">${icon(opts.icon || 'inbox', 20)}</div>
    <div class="empty-title">${esc(opts.title || '暂无数据')}</div>
    ${opts.hint ? `<div class="empty-hint">${esc(opts.hint)}</div>` : ''}
    ${action}
  </div>`;
}

export function errorPanel(options = {}) {
  const opts = typeof options === 'string' ? { message: options } : options;
  const correlation = opts.correlationId
    ? `<div class="error-detail">追踪号 <span class="correlation">${esc(opts.correlationId)}</span></div>`
    : '';
  const retry =
    opts.retry === false
      ? ''
      : `<button type="button" class="btn btn-sm" data-action="retry">${esc(opts.retryLabel || '重试')}</button>`;
  return `<div class="error-box">
    <div class="error-icon">${icon('alert', 20)}</div>
    <div class="error-title">${esc(opts.title || '加载失败')}</div>
    ${opts.message ? `<div class="error-detail">${esc(opts.message)}</div>` : ''}
    ${correlation}
    ${retry}
  </div>`;
}

/* ============================ 分页 ============================ */

function pageWindow(page, pages) {
  if (pages <= 7) {
    const list = [];
    for (let i = 1; i <= pages; i++) list.push(i);
    return list;
  }
  const set = new Set([1, pages, page - 1, page, page + 1]);
  const sorted = Array.from(set)
    .filter((p) => p >= 1 && p <= pages)
    .sort((a, b) => a - b);
  const out = [];
  let prev = 0;
  sorted.forEach((p) => {
    if (prev && p - prev > 1) out.push('…');
    out.push(p);
    prev = p;
  });
  return out;
}

export function pagination(state = {}) {
  const page = Math.max(1, Number(state.page) || 1);
  const pageSize = Number(state.pageSize) || 50;
  const total = Number(state.total) || 0;
  const pages = Math.max(1, Math.ceil(total / pageSize));
  const from = total === 0 ? 0 : (page - 1) * pageSize + 1;
  const to = Math.min(page * pageSize, total);
  const buttons = pageWindow(page, pages)
    .map((p) => {
      if (p === '…') return '<span class="pager-ellipsis">…</span>';
      const current = p === page ? ' current' : '';
      return `<button type="button" class="pager-btn${current}" data-page="${p}"${
        p === page ? ' aria-current="page"' : ''
      }>${p}</button>`;
    })
    .join('');
  const sizes = [20, 50, 100, 200]
    .map((s) => `<option value="${s}"${s === pageSize ? ' selected' : ''}>${s} 条/页</option>`)
    .join('');
  return `<div class="pager">
    <div class="pager-info">
      <span>第 ${from}–${to} 条，共 ${fmtNum(total)} 条</span>
      <select class="pager-size" data-page-size aria-label="每页条数">${sizes}</select>
    </div>
    <div class="pager-btns">
      <button type="button" class="pager-btn" data-page="${page - 1}"${page <= 1 ? ' disabled' : ''} aria-label="上一页">上一页</button>
      ${buttons}
      <button type="button" class="pager-btn" data-page="${page + 1}"${page >= pages ? ' disabled' : ''} aria-label="下一页">下一页</button>
    </div>
  </div>`;
}

/** 绑定分页：onChange({page, pageSize})。 */
export function bindPager(root, onChange) {
  bindAll(root, '[data-page]', 'click', (event, el) => {
    const page = Number(el.getAttribute('data-page'));
    if (!Number.isFinite(page) || page < 1 || el.disabled) return;
    onChange({ page });
  });
  bindAll(root, '[data-page-size]', 'change', (event, el) => {
    const pageSize = Number(el.value);
    if (!Number.isFinite(pageSize) || pageSize < 1) return;
    onChange({ page: 1, pageSize });
  });
}

/* ============================ 事件绑定 ============================ */

/** 安全绑定单个元素；节点缺失时静默返回 null（便于无 DOM 冒烟测试）。 */
export function bind(root, selector, event, handler) {
  if (!root || typeof root.querySelector !== 'function') return null;
  const el = root.querySelector(selector);
  if (!el || typeof el.addEventListener !== 'function') return null;
  el.addEventListener(event, handler);
  return el;
}

/** 安全批量绑定。 */
export function bindAll(root, selector, event, handler) {
  if (!root || typeof root.querySelectorAll !== 'function') return [];
  const nodes = root.querySelectorAll(selector);
  const out = [];
  for (let i = 0; i < nodes.length; i++) {
    const el = nodes[i];
    if (el && typeof el.addEventListener === 'function') {
      el.addEventListener(event, (ev) => handler(ev, el));
      out.push(el);
    }
  }
  return out;
}

/** 事件委托：节点在后续渲染中出现也能命中。 */
export function delegate(root, selector, event, handler) {
  if (!root || typeof root.addEventListener !== 'function') return () => {};
  const listener = (ev) => {
    const target = ev.target;
    if (!target || typeof target.closest !== 'function') return;
    const el = target.closest(selector);
    if (el && root.contains && root.contains(el)) handler(ev, el);
  };
  root.addEventListener(event, listener);
  return () => {
    if (typeof root.removeEventListener === 'function') root.removeEventListener(event, listener);
  };
}

/**
 * 每个页面实例只绑定一次根级事件委托：页面重渲染后仍有效，离开页面时释放。
 * binder 返回 ui.delegate() 的解除函数数组（或单个函数）。
 */
export function bindOnce(root, key, binder) {
  if (!root || typeof root !== 'object') return false;
  const flag = '__once_' + key;
  if (root[flag]) return false;
  const result = binder();
  root[flag] = Array.isArray(result) ? result : typeof result === 'function' ? [result] : [];
  return true;
}

export function releaseOnce(root, key) {
  if (!root || typeof root !== 'object') return;
  const offs = root['__once_' + key];
  if (Array.isArray(offs)) {
    offs.forEach((off) => {
      try {
        off();
      } catch (err) {
        /* 忽略 */
      }
    });
  }
  delete root['__once_' + key];
}

export function debounce(fn, wait = 300) {
  let timer = null;
  return function debounced(...args) {
    if (timer) clearTimeout(timer);
    timer = setTimeout(() => {
      timer = null;
      fn.apply(this, args);
    }, wait);
  };
}

/* ============================ 查询串 ============================ */

/** 把对象拼成 query string；跳过空字符串 / null / undefined。 */
export function qs(params) {
  const parts = [];
  Object.keys(params || {}).forEach((key) => {
    const value = params[key];
    if (value === undefined || value === null || value === '') return;
    parts.push(encodeURIComponent(key) + '=' + encodeURIComponent(String(value)));
  });
  return parts.join('&');
}

/* ============================ Toast ============================ */

function rootEl(id) {
  if (typeof document === 'undefined') return null;
  if (typeof document.getElementById === 'function') {
    const found = document.getElementById(id);
    if (found) return found;
  }
  return document.body || null;
}

/**
 * toast(message, {title, type, correlationId, duration})
 * type: info | success | warn | error
 */
export function toast(message, options = {}) {
  const opts = typeof options === 'string' ? { type: options } : options || {};
  const host = rootEl('toast-root');
  if (!host || typeof document === 'undefined' || typeof document.createElement !== 'function') {
    if (typeof console !== 'undefined') console.log('[toast]', opts.type || 'info', message);
    return;
  }
  const type = opts.type || 'info';
  const el = document.createElement('div');
  el.className = 'toast toast-' + type;
  el.setAttribute('role', type === 'error' ? 'alert' : 'status');
  const iconName = type === 'error' ? 'alert' : type === 'success' ? 'check' : type === 'warn' ? 'alert' : 'info';
  el.innerHTML =
    icon(iconName, 17) +
    '<div class="toast-body">' +
    (opts.title ? `<div class="toast-title">${esc(opts.title)}</div>` : '') +
    `<div class="toast-text">${esc(message)}</div>` +
    (opts.correlationId ? `<div class="toast-correlation">追踪号 ${esc(opts.correlationId)}</div>` : '') +
    '</div>' +
    '<button type="button" class="toast-close" aria-label="关闭提示">×</button>';
  const close = () => {
    if (el.parentNode) el.parentNode.removeChild(el);
  };
  const closeBtn = typeof el.querySelector === 'function' ? el.querySelector('.toast-close') : null;
  if (closeBtn && typeof closeBtn.addEventListener === 'function') closeBtn.addEventListener('click', close);
  if (typeof host.appendChild === 'function') host.appendChild(el);
  const duration = opts.duration === undefined ? (type === 'error' ? 8000 : 4500) : opts.duration;
  if (duration > 0) setTimeout(close, duration);
  return close;
}

/* ============================ Modal / 确认框 ============================ */

function overlayHost() {
  if (typeof document === 'undefined') return null;
  return rootEl('overlay-root');
}

function keydownOnce(handler) {
  if (typeof document === 'undefined' || typeof document.addEventListener !== 'function') return () => {};
  const fn = (event) => {
    if (event.key === 'Escape') handler(event);
  };
  document.addEventListener('keydown', fn);
  return () => document.removeEventListener('keydown', fn);
}

/**
 * 危险动作 / 需要补充字段的确认框。
 * fields 为空时是纯确认；否则渲染表单并校验必填。
 * 返回 Promise<values | null>（取消为 null）。
 */
export function confirmDialog(options = {}) {
  const opts = {
    title: options.title || '确认操作',
    message: options.message || '',
    confirmText: options.confirmText || '确定',
    cancelText: options.cancelText || '取消',
    danger: Boolean(options.danger),
    fields: options.fields || null,
    values: options.values || {},
    html: options.html || ''
  };
  const host = overlayHost();
  if (!host || typeof document === 'undefined' || typeof document.createElement !== 'function') {
    return Promise.resolve(null);
  }
  return new Promise((resolve) => {
    const overlay = document.createElement('div');
    overlay.className = 'modal-overlay';
    overlay.innerHTML =
      '<div class="modal" role="dialog" aria-modal="true" aria-labelledby="modal-title">' +
      '<div class="modal-head"><div class="modal-title" id="modal-title">' +
      esc(opts.title) +
      '</div></div>' +
      '<div class="modal-body">' +
      (opts.message ? `<p>${esc(opts.message)}</p>` : '') +
      opts.html +
      (opts.fields ? `<div class="modal-fields" data-modal-fields>${renderFields(opts.fields, opts.values)}</div>` : '') +
      '</div>' +
      '<div class="modal-foot">' +
      `<button type="button" class="btn" data-modal="cancel">${esc(opts.cancelText)}</button>` +
      `<button type="button" class="btn ${opts.danger ? 'btn-danger-solid' : 'btn-primary'}" data-modal="ok">${esc(
        opts.confirmText
      )}</button>` +
      '</div></div>';
    if (typeof host.appendChild === 'function') host.appendChild(overlay);

    let done = false;
    const finish = (result) => {
      if (done) return;
      done = true;
      removeKey();
      if (overlay.parentNode) overlay.parentNode.removeChild(overlay);
      resolve(result);
    };
    const removeKey = keydownOnce(() => finish(null));
    const okBtn = overlay.querySelector('[data-modal="ok"]');
    const cancelBtn = overlay.querySelector('[data-modal="cancel"]');
    const fieldsWrap = overlay.querySelector('[data-modal-fields]');
    if (okBtn) {
      okBtn.addEventListener('click', () => {
        if (fieldsWrap && opts.fields) {
          const values = readFormValues(fieldsWrap);
          const errors = validateValues(values, opts.fields);
          showFieldErrors(fieldsWrap, errors);
          if (Object.keys(errors).length > 0) return;
          finish(values);
          return;
        }
        finish({});
      });
    }
    if (cancelBtn) cancelBtn.addEventListener('click', () => finish(null));
    overlay.addEventListener('click', (event) => {
      if (event.target === overlay) finish(null);
    });
    if (opts.fields && fieldsWrap) {
      const firstInput = fieldsWrap.querySelector('input, select, textarea');
      if (firstInput && typeof firstInput.focus === 'function') firstInput.focus();
    } else if (okBtn && typeof okBtn.focus === 'function') {
      okBtn.focus();
    }
  });
}

/** 只读信息弹窗。 */
export function infoDialog(options = {}) {
  return confirmDialog({
    title: options.title,
    message: options.message,
    html: options.html,
    confirmText: options.confirmText || '关闭',
    cancelText: options.cancelText || '',
    fields: null
  });
}

/* ============================ Drawer ============================ */

let activeDrawer = null;

/**
 * 右侧抽屉。返回 { el, body, foot, close }。
 */
export function openDrawer(options = {}) {
  closeDrawer();
  const host = overlayHost();
  if (!host || typeof document === 'undefined' || typeof document.createElement !== 'function') return null;
  const overlay = document.createElement('div');
  overlay.className = 'overlay';
  overlay.innerHTML =
    '<aside class="drawer" role="dialog" aria-modal="true" aria-label="' +
    esc(options.title || '详情') +
    '">' +
    '<div class="drawer-head">' +
    '<div><div class="drawer-title">' +
    esc(options.title || '详情') +
    '</div>' +
    (options.subtitle ? `<div class="drawer-sub">${esc(options.subtitle)}</div>` : '') +
    '</div>' +
    '<button type="button" class="icon-btn close" data-drawer="close" aria-label="关闭">' +
    icon('close', 16) +
    '</button></div>' +
    `<div class="drawer-body" data-drawer-body>${options.body || ''}</div>` +
    (options.footer ? `<div class="drawer-foot" data-drawer-foot>${options.footer}</div>` : '') +
    '</aside>';
  if (typeof host.appendChild === 'function') host.appendChild(overlay);

  const removeKey = keydownOnce(() => closeDrawer());
  const close = () => {
    removeKey();
    activeDrawer = null;
    if (overlay.parentNode) overlay.parentNode.removeChild(overlay);
  };
  const closeBtn = overlay.querySelector('[data-drawer="close"]');
  if (closeBtn) closeBtn.addEventListener('click', close);
  overlay.addEventListener('click', (event) => {
    if (event.target === overlay) close();
  });
  activeDrawer = { overlay, close };
  return {
    el: overlay,
    body: overlay.querySelector('[data-drawer-body]'),
    foot: overlay.querySelector('[data-drawer-foot]'),
    close
  };
}

export function closeDrawer() {
  if (activeDrawer) {
    const close = activeDrawer.close;
    activeDrawer = null;
    try {
      close();
    } catch (err) {
      /* ignore */
    }
  }
}

export function setBusy(button, busy, busyText = '处理中…') {
  if (!button || typeof button.setAttribute !== 'function') return;
  if (busy) {
    if (!button.getAttribute('data-original-html')) {
      button.setAttribute('data-original-html', button.innerHTML || '');
    }
    button.setAttribute('disabled', 'disabled');
    button.innerHTML = `<span class="spinner" style="width:13px;height:13px;border-width:2px"></span>${esc(busyText)}`;
  } else {
    button.removeAttribute('disabled');
    const original = button.getAttribute('data-original-html');
    if (original) button.innerHTML = original;
    button.removeAttribute('data-original-html');
  }
}

/* ============================ Tabs ============================ */

/**
 * tabs({items:[{key,label,count?}], active, dataAttr})
 * 使用事件委托，页面绑定 [data-tab]。
 */
export function tabs(options = {}) {
  const items = options.items || [];
  const active = options.active;
  const attr = options.attr || 'data-tab';
  return `<div class="tabs" role="tablist">${items
    .map((item) => {
      const isActive = item.key === active;
      const count =
        item.count === undefined || item.count === null
          ? ''
          : `<span class="tab-count">${fmtNum(item.count)}</span>`;
      return `<button type="button" class="tab${isActive ? ' active' : ''}" ${attr}="${esc(item.key)}" role="tab" aria-selected="${
        isActive ? 'true' : 'false'
      }">${esc(item.label)}${count}</button>`;
    })
    .join('')}</div>`;
}

export function bindTabs(root, onChange, attr = 'data-tab') {
  bindAll(root, `[${attr}]`, 'click', (event, el) => {
    const key = el.getAttribute(attr);
    if (key) onChange(key);
  });
}

/* ============================ 其他小工具 ============================ */

export function setPageTitle(title) {
  if (typeof document !== 'undefined') {
    document.title = title ? title + ' · 变更请求工作台' : '变更请求工作台';
  }
}

export function scrollToTop() {
  const main = typeof document !== 'undefined' && document.querySelector ? document.querySelector('.main') : null;
  if (main && typeof main.scrollTo === 'function') main.scrollTo({ top: 0 });
}

export function truncate(text, max = 60) {
  const str = String(text === null || text === undefined ? '' : text);
  return str.length > max ? str.slice(0, max - 1) + '…' : str;
}

export function emptyIf(value, placeholder = '—') {
  return value === null || value === undefined || value === '' ? placeholder : value;
}

/** 容错取列表：数组 / {items:[...]} / null → 数组。 */
export function listOf(data) {
  if (Array.isArray(data)) return data;
  if (data && Array.isArray(data.items)) return data.items;
  if (data && Array.isArray(data.data)) return data.data;
  return [];
}

