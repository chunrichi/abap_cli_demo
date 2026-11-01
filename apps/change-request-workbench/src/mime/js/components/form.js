/**
 * components/form.js — 筛选区与表单的组装 / 绑定。
 * 字段定义见 ui.field()；筛选条件与 URL 查询串一一对应。
 */

import * as ui from '../ui.js';

/** 从 URL 查询串提取筛选字段当前值。 */
export function queryValues(fields, query) {
  const values = {};
  (fields || []).forEach((def) => {
    const raw = query ? query[def.name] : undefined;
    values[def.name] = raw === undefined ? '' : raw;
  });
  return values;
}

/** 筛选区 HTML（form + 查询 / 重置 + 当前筛选提示）。 */
export function filterBar(fields, values = {}, options = {}) {
  const items = (fields || []).map((def) => ui.field(def, values[def.name], '')).join('');
  const active = (fields || [])
    .filter((def) => values[def.name] !== undefined && values[def.name] !== '')
    .map((def) => {
      const label = def.label;
      let shown = values[def.name];
      if (def.type === 'select' && def.options) {
        const hit = def.options.find((opt) => String(opt.value) === String(values[def.name]));
        if (hit) shown = hit.label;
      }
      return `<span class="chip">${ui.esc(label)}：${ui.esc(shown)}</span>`;
    })
    .join('');
  return `<form class="filters" data-filter-form role="search">
    <div class="filter-grid">${items}
      <div class="filter-actions">
        <button type="submit" class="btn btn-primary btn-sm">查询</button>
        <button type="button" class="btn btn-ghost btn-sm" data-filter-reset>重置</button>
      </div>
    </div>
    ${active ? `<div class="filter-foot"><div class="filter-chips">${active}</div></div>` : ''}
  </form>`;
}

/** 绑定筛选：提交时把非空字段写入 URL 查询串并回到第 1 页。 */
export function bindFilterBar(root, ctx, fields) {
  if (!root || typeof root.querySelector !== 'function') return;
  const form = root.querySelector('[data-filter-form]');
  if (!form) return;
  form.addEventListener('submit', (event) => {
    event.preventDefault();
    const values = ui.readFormValues(form);
    const patch = {};
    (fields || []).forEach((def) => {
      patch[def.name] = values[def.name] === undefined || values[def.name] === '' ? '' : values[def.name];
    });
    ctx.setQuery(patch);
  });
  ui.bind(form, '[data-filter-reset]', 'click', () => ctx.clearQuery());
}

/** 表单字段 + 内联错误展示（提交按钮由页面自己放）。 */
export function formBody(fields, values = {}) {
  return `<div data-form-fields>${ui.renderFields(fields, values)}</div>`;
}

/** 读取 + 校验表单；返回 { values, errors, ok }。 */
export function readAndValidate(root, fields) {
  const values = ui.readFormValues(root);
  const errors = ui.validateValues(values, fields);
  ui.showFieldErrors(root, errors);
  return { values, errors, ok: Object.keys(errors).length === 0 };
}
