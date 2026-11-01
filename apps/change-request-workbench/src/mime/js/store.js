/**
 * store.js — 当前用户 / 角色 / 环境 / 版本等轻量状态。
 * 不做全局响应式框架：写操作后由页面主动 reload（hash 路由重渲染）。
 */

const state = {
  me: null,
  health: null,
  conflicts: 0
};

const listeners = new Set();

export function setMe(me) {
  state.me = me || null;
  emit();
}

export function getMe() {
  return state.me;
}

export function setHealth(health) {
  state.health = health || null;
  emit();
}

export function getHealth() {
  return state.health;
}

export function onChange(fn) {
  listeners.add(fn);
  return () => listeners.delete(fn);
}

function emit() {
  for (const fn of listeners) {
    try {
      fn(state);
    } catch (err) {
      // 监听器错误不影响主流程
      console.error('[store] listener failed', err);
    }
  }
}

/** 角色行结构：{ role, scopeType, scopeId } */
export function roleRows() {
  const me = state.me;
  return me && Array.isArray(me.roles) ? me.roles : [];
}

export function hasRole(role) {
  return roleRows().some((row) => row && row.role === role);
}

export function hasAnyRole(roles) {
  if (!Array.isArray(roles) || roles.length === 0) return true;
  return roles.some((role) => hasRole(role));
}

export function isAdmin() {
  const me = state.me;
  return Boolean(me && (me.admin === true || hasRole('ADMIN')));
}

/** 当前用户是否命中某个数据范围（GLOBAL 始终命中）。 */
export function hasScope(role, scopeType, scopeId) {
  return roleRows().some((row) => {
    if (!row || row.role !== role) return false;
    if (row.scopeType === 'GLOBAL' || row.scopeType === '') return true;
    if (scopeType && row.scopeType !== scopeType) return false;
    return !scopeId || row.scopeId === scopeId;
  });
}

export function userName() {
  return state.me ? state.me.user || '' : '';
}

export function displayName() {
  const me = state.me;
  if (!me) return '未知用户';
  return me.displayName || me.user || '未知用户';
}

export function environment() {
  const me = state.me;
  const env = me ? me.environment || '' : '';
  return env || 'SAP System';
}

export function version() {
  const me = state.me;
  if (me && me.version) return me.version;
  return state.health && state.health.version ? state.health.version : '—';
}

export function healthStatus() {
  return state.health ? state.health.status || 'unknown' : '';
}

/** 标记一次版本冲突（用于顶栏提示历史冲突次数，纯展示）。 */
export function noteConflict() {
  state.conflicts += 1;
}

export function conflictCount() {
  return state.conflicts;
}

/** 当前用户是否具备任一审批角色（用于“审批”导航的弱提示）。 */
export function canApprove() {
  return hasAnyRole(['CHANGE_MANAGER', 'ADMIN']);
}
