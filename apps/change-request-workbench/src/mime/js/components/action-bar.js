/**
 * components/action-bar.js — 状态动作条。
 *
 * 动作可见性 / 禁用原因由页面按「当前状态 + 用户角色」计算；
 * 危险动作（取消 / 解绑 / 改期 / 驳回）通过 confirm 弹二次确认并采集原因。
 */

import * as ui from '../ui.js';
import { describeError, isVersionConflict } from '../api.js';
import { noteConflict } from '../store.js';

const TONE_CLASS = {
  primary: 'btn-primary',
  danger: 'btn-danger',
  'danger-solid': 'btn-danger-solid',
  ghost: 'btn-ghost',
  default: ''
};

/**
 * @param {Array} actions [{ key,label,tone,icon,disabledReason,hidden,confirm,successMessage,run }]
 */
export function actionBar(actions) {
  const visible = (actions || []).filter((action) => action && !action.hidden);
  if (visible.length === 0) {
    return `<div class="action-bar"><span class="label">当前状态无可用动作</span><span class="spacer"></span><span class="muted small">如需调整，请联系变更经理</span></div>`;
  }
  const blocked = visible.find((action) => action.disabledReason);
  const disabledReason = blocked ? blocked.disabledReason : '';
  const buttons = visible
    .map((action) => {
      const cls = ['btn', TONE_CLASS[action.tone || 'default'] || '', action.disabledReason ? '' : '']
        .filter(Boolean)
        .join(' ');
      const disabled = action.disabledReason ? ' disabled aria-disabled="true"' : '';
      const title = action.disabledReason ? ` title="${ui.esc(action.disabledReason)}"` : action.title ? ` title="${ui.esc(action.title)}"` : '';
      const iconHtml = action.icon ? ui.icon(action.icon, 15) : '';
      return `<button type="button" class="${cls}" data-action-key="${ui.esc(action.key)}"${disabled}${title}>${iconHtml}${ui.esc(
        action.label || ui.actionLabel(action.key)
      )}</button>`;
    })
    .join('');
  return `<div class="action-bar" data-action-bar>
    <span class="label">动作</span>
    ${buttons}
    ${disabledReason ? `<span class="reason">${ui.icon('info', 13)}${ui.esc(disabledReason)}</span>` : '<span class="spacer"></span>'}
  </div>`;
}

/**
 * 绑定动作条。动作 run(values, ctx) 抛错时由这里统一 toast；
 * 409 版本冲突 / 锁占用时自动刷新页面数据。
 */
export function bindActionBar(root, ctx, actions) {
  ui.bindAll(root, '[data-action-key]', 'click', async (event, el) => {
    const key = el.getAttribute('data-action-key');
    const action = (actions || []).find((item) => item && item.key === key);
    if (!action) return;
    if (action.disabledReason) {
      ui.toast(action.disabledReason, { type: 'warn', title: '当前不可执行' });
      return;
    }
    let values = {};
    if (action.confirm) {
      const result = await ui.confirmDialog(
        Object.assign(
          {
            title: action.label || ui.actionLabel(key),
            message: '',
            confirmText: action.confirm.confirmText || '确定',
            danger: action.tone === 'danger' || action.tone === 'danger-solid'
          },
          action.confirm
        )
      );
      if (result === null) return;
      values = result || {};
    }
    ui.setBusy(el, true);
    try {
      const outcome = (await action.run(values, ctx)) || {};
      if (outcome.message !== false) {
        ui.toast(outcome.message || action.successMessage || '操作成功。', { type: 'success' });
      }
      if (outcome.reload !== false) ctx.reload();
    } catch (err) {
      const info = describeError(err);
      ui.toast(info.message, { title: info.title, type: 'error', correlationId: info.correlationId });
      if (isVersionConflict(err)) {
        noteConflict();
        setTimeout(() => ctx.reload(), 800);
      }
    } finally {
      ui.setBusy(el, false);
    }
  });
}

/**
 * 通用写操作执行器：表单提交 / 弹窗确认后调用。
 * 返回 outcome 或 null（失败时已提示）。
 */
export async function runMutation(fn, options = {}) {
  const { ctx, button, successMessage, reload = true } = options;
  if (button) ui.setBusy(button, true);
  try {
    const outcome = (await fn()) || {};
    if (outcome.message !== false) {
      ui.toast(outcome.message || successMessage || '操作成功。', { type: 'success' });
    }
    if (outcome.reload !== false && reload && ctx) ctx.reload();
    return outcome;
  } catch (err) {
    const info = describeError(err);
    ui.toast(info.message, { title: info.title, type: 'error', correlationId: info.correlationId });
    if (isVersionConflict(err) && ctx) {
      noteConflict();
      setTimeout(() => ctx.reload(), 800);
    }
    return null;
  } finally {
    if (button) ui.setBusy(button, false);
  }
}
