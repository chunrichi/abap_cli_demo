/**
 * components/approval-drawer.js — 审批抽屉：对象摘要 + 审批步骤 + 通过 / 驳回。
 * 驳回意见必填（workflow I9）；决策携带对象 version。
 */

import * as ui from '../ui.js';
import { api, describeError, isVersionConflict } from '../api.js';
import * as store from '../store.js';

async function loadApprovalContext(approval) {
  const requests = [
    api.get('/approvals/steps', { objectType: approval.objectType, objectId: approval.objectId }),
    approval.objectType === 'REQ'
      ? api.get('/requests/' + encodeURIComponent(approval.objectId))
      : api.get('/change-documents/' + encodeURIComponent(approval.objectId))
  ];
  const [stepsRaw, object] = await Promise.all(requests);
  return { steps: ui.listOf(stepsRaw), object };
}

function stepsTable(steps, currentId) {
  if (!steps.length) {
    return ui.emptyPanel({ icon: 'approval', title: '暂无审批步骤', hint: '提交审批后按审批矩阵生成步骤。' });
  }
  const rows = steps
    .map((step) => {
      const current = step.id === currentId ? ' style="background:#f8fafc"' : '';
      return `<tr${current}>
        <td>${ui.esc(step.stepNo)}</td>
        <td>${ui.esc(step.approver || '—')}</td>
        <td>${ui.apprStateBadge(step.apprState)}</td>
        <td>${ui.fmtDateTime(step.decidedAt)}</td>
        <td class="small">${ui.esc(step.comment || '—')}</td>
      </tr>`;
    })
    .join('');
  return `<div class="table-wrap"><table class="data">
    <thead><tr><th style="width:48px">步骤</th><th style="width:130px">审批人</th><th style="width:96px">状态</th><th style="width:150px">决策时间</th><th>意见</th></tr></thead>
    <tbody>${rows}</tbody></table></div>`;
}

function objectSummary(approval, object) {
  const status = object && object.status ? object.status : '';
  const title = object && object.title ? object.title : approval.objectTitle || '';
  const version = object && object.version !== undefined ? object.version : '—';
  const link =
    approval.objectType === 'REQ'
      ? `#/requests/${encodeURIComponent(approval.objectId)}`
      : `#/change-documents/${encodeURIComponent(approval.objectId)}`;
  return `<div class="panel" style="margin-bottom:14px">
    <div class="panel-body tight">
      ${ui.kvList([
        { label: '对象', value: ui.objectTypeLabel(approval.objectType) + ' ' + (approval.objectDisplayId || approval.objectId) },
        { label: '标题', value: title },
        { label: '当前状态', html: status ? ui.statusBadge(status) : '—' },
        { label: '审批状态', html: object && object.approvalState ? ui.apprStateBadge(object.approvalState) : '—' },
        { label: '版本', value: version }
      ])}
      <div style="margin-top:10px"><a href="${link}" data-drawer-link>打开对象详情 →</a></div>
    </div>
  </div>`;
}

/** 打开审批抽屉；处理完成后关闭并刷新页面。 */
export async function openApprovalDrawer(approval, ctx) {
  const me = store.userName();
  const canDecide = approval.apprState === 'PENDING';
  const isApprover = approval.approver === me;
  const drawer = ui.openDrawer({
    title: '审批处理',
    subtitle: `${ui.objectTypeLabel(approval.objectType)} ${approval.objectDisplayId || approval.objectId} · 第 ${
      approval.stepNo || '—'
    } 步`,
    body: ui.loadingPanel('正在加载审批步骤…'),
    footer: '<button type="button" class="btn" data-drawer-close>关闭</button>'
  });
  if (!drawer) return;

  ui.bind(drawer.el, '[data-drawer-close]', 'click', () => drawer.close());
  ui.bindAll(drawer.el, '[data-drawer-link]', 'click', (event, el) => {
    event.preventDefault();
    drawer.close();
    ctx.navigate(el.getAttribute('href'));
  });

  let steps = [];
  let object = null;
  try {
    const loaded = await loadApprovalContext(approval);
    steps = loaded.steps;
    object = loaded.object;
  } catch (err) {
    const info = describeError(err);
    if (drawer.body) {
      drawer.body.innerHTML = ui.errorPanel({ title: info.title, message: info.message, correlationId: info.correlationId });
    }
    return;
  }

  const disabledReason = !canDecide
    ? '该步骤已处理，不能重复决策。'
    : !isApprover
      ? `你不是当前步骤审批人（${approval.approver || '未指定'}），无法决策。`
      : '';

  if (drawer.body) {
    drawer.body.innerHTML =
      objectSummary(approval, object) +
      `<div class="panel"><div class="panel-head"><span class="panel-title">审批步骤</span>
        <span class="right muted small">共 ${steps.length} 步</span></div>
        <div class="panel-body flush">${stepsTable(steps, approval.id)}</div></div>
      <div class="panel"><div class="panel-head"><span class="panel-title">审批意见</span></div>
        <div class="panel-body">
          ${
            disabledReason
              ? ui.banner(disabledReason, 'warn', 'info')
              : ui.banner('通过意见可选；驳回必须填写原因。决策会携带对象版本号做乐观锁。', 'info', 'info')
          }
          <div data-field="comment">
            <label class="field-label" for="approval-comment">意见 <span class="muted small">（驳回必填）</span></label>
            <textarea class="textarea" id="approval-comment" data-approval-comment rows="3" placeholder="填写审批意见或驳回原因"></textarea>
            <div class="field-error" data-error-for="comment"></div>
          </div>
        </div>
      </div>`;
  }

  const canReassign = canDecide && (isApprover || store.hasAnyRole(['CHANGE_MANAGER', 'ADMIN']));
  if (drawer.foot) {
    drawer.foot.innerHTML =
      '<button type="button" class="btn" data-drawer-close>关闭</button>' +
      `<button type="button" class="btn" data-reassign${canReassign ? '' : ' disabled title="仅当前审批人或变更经理/管理员可改派"'}>改派</button>` +
      `<button type="button" class="btn btn-danger" data-approval="REJECTED"${disabledReason ? ' disabled title="' + ui.esc(disabledReason) + '"' : ''}>驳回</button>` +
      `<button type="button" class="btn btn-primary" data-approval="APPROVED"${disabledReason ? ' disabled title="' + ui.esc(disabledReason) + '"' : ''}>通过</button>`;
    ui.bind(drawer.foot, '[data-drawer-close]', 'click', () => drawer.close());
  }

  const decide = async (decision, button) => {
    const commentEl = drawer.body ? drawer.body.querySelector('[data-approval-comment]') : null;
    const comment = commentEl && typeof commentEl.value === 'string' ? commentEl.value.trim() : '';
    const fieldWrap = drawer.body ? drawer.body.querySelector('[data-field="comment"]') : null;
    const errorEl = drawer.body ? drawer.body.querySelector('[data-error-for="comment"]') : null;
    if (decision === 'REJECTED' && !comment) {
      if (fieldWrap) fieldWrap.classList.add('invalid');
      if (errorEl) errorEl.textContent = '驳回意见必填';
      if (commentEl && typeof commentEl.focus === 'function') commentEl.focus();
      return;
    }
    if (fieldWrap) fieldWrap.classList.remove('invalid');
    if (errorEl) errorEl.textContent = '';
    ui.setBusy(button, true);
    try {
      await api.post('/approvals/' + encodeURIComponent(approval.id) + '/decision', {
        decision,
        comment,
        version: object && object.version !== undefined ? Number(object.version) : 0
      });
      drawer.close();
      ui.toast(decision === 'APPROVED' ? '已通过该审批步骤。' : '已驳回该审批步骤。', { type: 'success' });
      ctx.reload();
    } catch (err) {
      const info = describeError(err);
      ui.toast(info.message, { title: info.title, type: 'error', correlationId: info.correlationId });
      if (isVersionConflict(err)) {
        drawer.close();
        setTimeout(() => ctx.reload(), 800);
      }
    } finally {
      ui.setBusy(button, false);
    }
  };

  if (drawer.foot) {
    ui.bindAll(drawer.foot, '[data-approval]', 'click', (event, el) => {
      if (el.disabled) return;
      decide(el.getAttribute('data-approval'), el);
    });
  }

  if (drawer.foot) {
    ui.bind(drawer.foot, '[data-reassign]', 'click', async (event, el) => {
      if (el.disabled) return;
      const values = await ui.confirmDialog({
        title: '改派审批人',
        message: '改派会写审计并通知新审批人；当前步骤此前未读的通知会被标记已读。',
        confirmText: '改派',
        fields: [
          {
            name: 'approver',
            label: '新审批人',
            required: true,
            maxlength: 12,
            placeholder: 'SAP 用户名（≤12 字符）',
            hint: '不能是请求人本人。'
          },
          { name: 'comment', label: '说明', type: 'textarea', rows: 2, placeholder: '改派原因（可选）' }
        ]
      });
      if (!values) return;
      ui.setBusy(el, true);
      try {
        await api.post('/approvals/' + encodeURIComponent(approval.id) + '/reassign', {
          approver: values.approver,
          comment: values.comment || ''
        });
        drawer.close();
        ui.toast('已改派给 ' + values.approver + '。', { type: 'success' });
        ctx.reload();
      } catch (err) {
        const info = describeError(err);
        ui.toast(info.message, { title: info.title, type: 'error', correlationId: info.correlationId });
      } finally {
        ui.setBusy(el, false);
      }
    });
  }
}

export default { openApprovalDrawer };
