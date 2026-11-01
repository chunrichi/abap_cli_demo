/**
 * components/timeline.js — 历史 / 审计时间线。
 */

import * as ui from '../ui.js';

const FIELD_LABELS = {
  STATUS: '状态',
  APPROVAL_STATE: '审批状态',
  PRIORITY: '优先级',
  OWNER: '负责人',
  ASSIGNEE: '指派人',
  TITLE: '标题',
  DUE_DATE: '截止日',
  PLANNED_START: '计划开始',
  PLANNED_END: '计划结束',
  PLANNED_IMPORT_AT: '计划导入时间',
  TARGET_SYSTEM: '目标系统',
  CYCLE_ID: '周期',
  DESCRIPTION: '描述'
};

function fieldLabel(field) {
  if (!field) return '';
  return FIELD_LABELS[field] || field;
}

function valueLabel(field, value) {
  if (value === null || value === undefined || value === '') return '（空）';
  const raw = String(value);
  if (field === 'STATUS' || field === 'APPROVAL_STATE' || field === 'PRIORITY') {
    if (field === 'PRIORITY') return ui.PRIORITY[raw] ? ui.PRIORITY[raw].zh : raw;
    if (ui.STATUS[raw]) return ui.STATUS[raw].zh;
    if (ui.APPROVAL_STATE[raw]) return ui.APPROVAL_STATE[raw].zh;
  }
  return raw;
}

function dotTone(history) {
  const action = String(history.action || '');
  if (/CANCEL|REJECT|FAIL|ERROR/.test(action)) return 'danger';
  if (/APPROVE|CLOSE|CONFIRM|DONE|SUBMIT|CREATE|START/.test(action)) return 'ok';
  return '';
}

/**
 * @param {Array} history 历史 DTO 数组
 * @param {object} options { compact, emptyText }
 */
export function timeline(history, options = {}) {
  const rows = Array.isArray(history) ? history : [];
  if (rows.length === 0) {
    return ui.emptyPanel({
      icon: 'history',
      title: options.emptyTitle || '暂无历史记录',
      hint: options.emptyHint || '状态动作、审批决策与字段变更会记录在这里。'
    });
  }
  const items = rows
    .map((entry) => {
      const tone = dotTone(entry);
      const changes =
        entry.field && (entry.oldValue !== undefined || entry.newValue !== undefined)
          ? `<div class="tl-changes"><div class="tl-change"><span class="field-name">${ui.esc(
              fieldLabel(entry.field)
            )}</span>${ui.esc(valueLabel(entry.field, entry.oldValue))} → ${ui.esc(valueLabel(entry.field, entry.newValue))}</div></div>`
          : '';
      const source = entry.source
        ? `<span class="chip">${ui.esc(entry.source)}</span>`
        : '';
      const comment = entry.comment
        ? `<div class="tl-comment">${ui.esc(entry.comment)}</div>`
        : '';
      return `<div class="tl-item">
        <span class="tl-dot ${tone}"></span>
        <div class="tl-head"><span class="tl-action">${ui.esc(ui.actionLabel(entry.action))}</span>${source}</div>
        <div class="tl-meta"><span>${ui.esc(entry.changedBy || '—')}</span><span>${ui.fmtDateTime(
          entry.changedAt
        )}</span><span>${ui.fmtRelative(entry.changedAt)}</span></div>
        ${changes}
        ${comment}
      </div>`;
    })
    .join('');
  return `<div class="timeline">${items}</div>`;
}
