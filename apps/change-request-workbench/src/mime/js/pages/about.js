/**
 * pages/about.js — 帮助 / 关于：版本、环境、我的角色、状态与错误码说明、快捷键与接口信息。
 */

import { api } from '../api.js';
import * as store from '../store.js';
import * as ui from '../ui.js';

const STATUS_GROUPS = [
  {
    title: '请求 CR',
    items: ['NEW', 'PENDING_APPROVAL', 'APPROVED', 'REJECTED', 'IN_PROGRESS', 'CLOSED', 'CANCELLED']
  },
  {
    title: '变更文档 CD',
    items: ['NEW', 'IN_DEV', 'IN_TEST', 'READY_TO_IMPORT', 'IMPORT_SCHEDULED', 'IMPORTED', 'CLOSED', 'CANCELLED']
  },
  {
    title: '任务 / 计划',
    items: ['OPEN', 'IN_PROGRESS', 'DONE', 'CANCELLED', 'PLANNED', 'MISSED']
  }
];

const ERROR_HINTS = [
  ['VALIDATION_ERROR (400)', '参数 / 必填校验失败：按字段内联提示修正后重试。'],
  ['UNAUTHORIZED (401)', '未登录或会话过期：重新登录 SAP 后刷新页面。'],
  ['FORBIDDEN (403)', '角色或数据范围不允许；动作条会按角色隐藏 / 禁用。'],
  ['APPROVER_MISMATCH (403)', '非当前步骤审批人，无法通过 / 驳回。'],
  ['SELF_APPROVAL (403)', '请求人不能审批自己提交的请求。'],
  ['NOT_FOUND (404)', '对象不存在或已删除，返回列表重新选择。'],
  ['INVALID_TRANSITION (409)', '当前状态不允许该动作，刷新后查看最新状态。'],
  ['GUARD_FAILED (409)', '前置条件不满足（审批未完成 / 传输未释放 / 任务未关闭等）。'],
  ['CONCURRENT_MODIFICATION (409)', '版本冲突：页面会提示并刷新最新数据，确认后再操作。'],
  ['DUPLICATE_LINK (409)', '传输已关联其他变更文档，不能重复关联。'],
  ['SCHEDULE_CONFLICT (409)', '已存在生效中的导入计划，请先改期或取消。'],
  ['CTS_READ_ERROR (502)', 'CTS 读取失败，状态降级为「未知」，请到 STMS 确认。']
];

function section(title, bodyHtml, sub) {
  return `<div class="panel"><div class="panel-head"><span class="panel-title">${ui.esc(title)}</span>
    ${sub ? `<span class="panel-sub">${ui.esc(sub)}</span>` : ''}</div>
    <div class="panel-body">${bodyHtml}</div></div>`;
}

function healthBadge() {
  const health = store.getHealth();
  if (!health) return ui.badge('未获取', 'neutral');
  const map = { ok: { zh: '正常', tone: 'ok' }, degraded: { zh: '降级', tone: 'warn' }, down: { zh: '不可用', tone: 'danger' } };
  const entry = map[health.status] || { zh: health.status || '未知', tone: 'neutral' };
  return ui.badge(entry.zh, entry.tone);
}

export async function mount(root, ctx) {
  let health = store.getHealth();
  if (!health) {
    try {
      health = await api.get('/health');
      store.setHealth(health);
    } catch (err) {
      health = null;
    }
  }
  const me = store.getMe() || {};
  const roles = store.roleRows();
  const rolesHtml =
    roles.length === 0
      ? '<span class="muted">当前用户没有应用角色；仅能查看基础信息。</span>'
      : `<div class="role-list">${roles
          .map(
            (row) =>
              `${ui.roleBadge(row.role)}<span class="chip">${ui.esc(
                (ui.SCOPE_TYPE[row.scopeType] || row.scopeType || '全局') + (row.scopeId ? ' · ' + row.scopeId : '')
              )}</span>`
          )
          .join(' ')}</div>`;

  root.innerHTML = `<div class="page">
    ${ui.pageHeader({
      title: '帮助 / 关于',
      subtitle: '版本信息、我的角色、状态与错误码说明',
      breadcrumb: [{ label: '工作台', href: '#/dashboard' }, { label: '帮助 / 关于' }],
      actions: '<a class="btn btn-sm" href="#/dashboard">返回工作台</a>'
    })}
    <div class="grid-2">
      ${section(
        '版本与环境',
        `<div class="about-list">
          <div class="about-item"><span class="about-key">产品</span><span class="about-val">变更请求工作台（CRW）</span></div>
          <div class="about-item"><span class="about-key">应用版本</span><span class="about-val">v${ui.esc(store.version())}</span></div>
          <div class="about-item"><span class="about-key">健康状态</span><span class="about-val">${healthBadge()} ${
            health && health.status !== 'ok' ? `<span class="muted small">部分组件降级，详见「配置 · 系统状态」</span>` : ''
          }</span></div>
          <div class="about-item"><span class="about-key">当前环境</span><span class="about-val">${ui.esc(store.environment())}</span></div>
          <div class="about-item"><span class="about-key">当前用户</span><span class="about-val">${ui.esc(
            me.displayName || '—'
          )} <span class="muted small">${ui.esc(me.user || '')}</span></span></div>
          <div class="about-item"><span class="about-key">管理员</span><span class="about-val">${
            store.isAdmin() ? '是（全部权限）' : '否'
          }</span></div>
          <div class="about-item"><span class="about-key">部署形态</span><span class="about-val">ICF 节点 + MIME 静态资源 + 原生 ES modules（零构建、零 CDN）</span></div>
          <div class="about-item"><span class="about-key">接口基地址</span><span class="about-val"><code>./api/v1</code>（同源，写请求带 <code>X-CRW-Request: 1</code>）</span></div>
        </div>`,
        '前端静态资产无构建产物'
      )}
      ${section(
        '我的角色',
        rolesHtml +
          `<div class="muted small" style="margin-top:10px">动作条按「当前状态 + 用户角色」展示；禁用项会给出原因。前端隐藏按钮只是体验，服务端仍会鉴权。</div>`,
        '角色来自 GET /api/v1/me'
      )}
    </div>
    ${section(
      '状态说明',
      STATUS_GROUPS.map(
        (group) => `<div class="form-section-title" style="margin-top:0">${ui.esc(group.title)}</div>
          <div class="toolbar" style="margin-bottom:12px">${group.items
            .map((code) => ui.statusBadge(code) + `<span class="chip mono">${ui.esc(code)}</span>`)
            .join(' ')}</div>`
      ).join(''),
      '颜色 + 文字双编码，颜色不单独承载语义'
    )}
    ${section(
      '错误提示与处理',
      `<div class="table-wrap"><table class="data">
        <thead><tr><th style="width:250px">错误码</th><th>前端处理约定</th></tr></thead>
        <tbody>${ERROR_HINTS.map(
          (row) => `<tr><td class="mono">${ui.esc(row[0])}</td><td class="small">${ui.esc(row[1])}</td></tr>`
        ).join('')}</tbody></table></div>
      <div class="muted small" style="margin-top:10px">错误提示会展示服务端消息与 correlationId（追踪号），便于对照服务端日志排查。</div>`,
      '错误信封：{status:"error", code, message, details, correlationId}'
    )}
    ${section(
      '界面约定',
      `<dl class="doc-list">
        <dt>深链与前进后退</dt><dd>所有页面使用 hash 路由（如 <code>#/requests/0000000123</code>），刷新与分享保持当前页面；筛选条件写入 URL。</dd>
        <dt>列表分页</dt><dd>服务端分页（默认 50 条/页，可切换 20 / 50 / 100 / 200），排序字段受服务端白名单约束。</dd>
        <dt>乐观锁</dt><dd>写请求都会携带 <code>version</code>；冲突（409 CONCURRENT_MODIFICATION）时提示「记录已被他人修改」并刷新数据。</dd>
        <dt>危险动作</dt><dd>取消、解绑、改期、驳回等需要二次确认；取消 / 驳回原因必填。</dd>
        <dt>快捷键</dt><dd><kbd>Esc</kbd> 关闭弹窗 / 抽屉；<kbd>Tab</kbd> 键盘可达；表单控件均有 label 关联。</dd>
        <dt>安全</dt><dd>所有渲染文本经过转义（XSS）；不在 URL 放敏感数据；导出文件名不使用用户输入。</dd>
      </dl>`
    )}
  </div>`;

  void ctx;
  return () => {};
}
