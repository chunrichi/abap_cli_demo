/**
 * pages/request-new.js — 新建请求三步向导：基本信息 → 影响与计划 → 确认提交。
 * 必填内联校验；创建后可选择仅保存草稿或直接提交审批；离开时提示未保存修改。
 */

import { api, describeError } from '../api.js';
import * as ui from '../ui.js';
import { queryValues } from '../components/form.js';

const STEP_FIELDS = [
  [
    {
      name: 'requestType',
      label: '请求类型',
      type: 'select',
      required: true,
      options: [
        { value: 'STD', label: '标准变更（STD）' },
        { value: 'URG', label: '紧急变更（URG）' },
        { value: 'ADM', label: '管理变更（ADM）' }
      ],
      hint: '类型创建后不可修改'
    },
    {
      name: 'priority',
      label: '优先级',
      type: 'select',
      required: true,
      options: [
        { value: '1', label: '紧急' },
        { value: '2', label: '高' },
        { value: '3', label: '中' },
        { value: '4', label: '低' }
      ]
    },
    {
      name: 'title',
      label: '标题',
      type: 'text',
      required: true,
      maxlength: 120,
      span: 'all',
      placeholder: '一句话描述变更内容（必填）'
    },
    {
      name: 'description',
      label: '描述',
      type: 'textarea',
      rows: 5,
      span: 'all',
      placeholder: '背景、影响范围、验收标准（可选）'
    }
  ],
  [
    {
      name: 'component',
      label: '组件',
      type: 'text',
      required: true,
      placeholder: '如 MM-PUR',
      hint: '受影响的模块 / 组件'
    },
    { name: 'cycleId', label: '周期', type: 'select', options: [] },
    { name: 'owner', label: '负责人', type: 'text', placeholder: 'SAP 用户名（可选）' },
    {
      name: 'plannedStart',
      label: '计划开始',
      type: 'date',
      required: true,
      hint: '日期格式 yyyy-MM-dd'
    },
    { name: 'plannedEnd', label: '计划结束', type: 'date', required: true },
    { name: 'dueDate', label: '截止日', type: 'date' }
  ]
];

const STEP_TITLES = ['基本信息', '影响与计划', '确认提交'];

export async function mount(root, ctx) {
  const draft = {
    requestType: 'STD',
    priority: '3',
    title: '',
    description: '',
    component: '',
    cycleId: '',
    owner: '',
    plannedStart: '',
    plannedEnd: '',
    dueDate: ''
  };
  let step = 0;
  let cycles = [];
  let submitting = false;

  try {
    const raw = await api.get('/config/cycles');
    cycles = ui.listOf(raw);
  } catch (err) {
    cycles = [];
  }
  STEP_FIELDS[1][1].options = [{ value: '', label: '不指定周期' }].concat(
    cycles.map((cycle) => ({ value: cycle.id, label: cycle.id + (cycle.description ? ' · ' + cycle.description : '') }))
  );

  root.innerHTML = `<div class="page">
    ${ui.pageHeader({
      title: '新建请求',
      subtitle: '创建变更请求草稿，提交后进入审批流程',
      breadcrumb: [{ label: '工作台', href: '#/dashboard' }, { label: '请求 CR', href: '#/requests' }, { label: '新建请求' }],
      actions: '<a class="btn" href="#/requests">取消</a>'
    })}
    <div class="panel">
      <div class="panel-body">
        <div class="wizard-steps" data-wizard-steps></div>
        <form data-wizard-form novalidate></form>
      </div>
    </div>
  </div>`;

  const formEl = root.querySelector('[data-wizard-form]');
  const stepsEl = root.querySelector('[data-wizard-steps]');

  function stepsHtml() {
    return STEP_TITLES.map((title, index) => {
      const cls = index === step ? 'active' : index < step ? 'done' : '';
      return `<span class="wizard-step ${cls}"><span class="n">${
        index < step ? '✓' : index + 1
      }</span>${ui.esc(title)}</span>${index < STEP_TITLES.length - 1 ? '<span class="wizard-sep">→</span>' : ''}`;
    }).join('');
  }

  function currentFields() {
    return STEP_FIELDS[step] || [];
  }

  function renderStep() {
    if (!formEl || !stepsEl) return;
    stepsEl.innerHTML = stepsHtml();
    if (step === 2) {
      renderConfirm();
      return;
    }
    const values = queryValues(currentFields(), draft);
    formEl.innerHTML =
      `<div data-step-fields>${ui.renderFields(currentFields(), values)}</div>
      <div class="form-actions">
        ${step > 0 ? '<button type="button" class="btn" data-wizard="prev">上一步</button>' : '<span class="left muted small">带 * 为必填项</span>'}
        <button type="button" class="btn btn-primary" data-wizard="next">下一步</button>
      </div>`;
  }

  function renderConfirm() {
    if (!formEl) return;
    const typeLabel = (ui.REQUEST_TYPE[draft.requestType] || {}).zh || draft.requestType;
    const priorityLabel = (ui.PRIORITY[draft.priority] || {}).zh || '未定';
    formEl.innerHTML =
      `<div class="form-section-title">确认信息</div>
      ${ui.kvList([
        { label: '请求类型', value: typeLabel + '（' + draft.requestType + '）' },
        { label: '优先级', html: ui.priorityBadge(draft.priority) },
        { label: '标题', value: draft.title },
        { label: '组件', value: draft.component },
        { label: '周期', value: draft.cycleId || '不指定' },
        { label: '负责人', value: draft.owner || '—' },
        { label: '计划开始', value: draft.plannedStart || '—' },
        { label: '计划结束', value: draft.plannedEnd || '—' },
        { label: '截止日', value: draft.dueDate || '—' }
      ])}
      <div class="desc-block"><div class="field-label">描述</div><div>${ui.esc(draft.description || '（未填写）')}</div></div>
      <div class="form-actions">
        <span class="left muted small">${ui.icon('info', 13)} 创建后状态为「新建」；提交审批会按审批矩阵生成步骤。</span>
        <button type="button" class="btn" data-wizard="prev">上一步</button>
        <button type="button" class="btn" data-wizard="draft">仅保存草稿</button>
        <button type="button" class="btn btn-primary" data-wizard="submit">创建并提交审批</button>
      </div>`;
  }

  function readCurrentIntoDraft() {
    if (!formEl) return {};
    const values = ui.readFormValues(formEl);
    currentFields().forEach((def) => {
      if (Object.prototype.hasOwnProperty.call(values, def.name)) draft[def.name] = values[def.name];
    });
    return values;
  }

  function validateStep() {
    const values = readCurrentIntoDraft();
    const errors = ui.validateValues(values, currentFields());
    if (step === 1 && draft.plannedStart && draft.plannedEnd && draft.plannedEnd < draft.plannedStart) {
      errors.plannedEnd = '计划结束不能早于计划开始';
    }
    ui.showFieldErrors(formEl, errors);
    if (Object.keys(errors).length > 0) {
      ui.toast(Object.values(errors)[0], { type: 'warn', title: '请检查表单' });
      return false;
    }
    return true;
  }

  function validateAll() {
    const allFields = STEP_FIELDS[0].concat(STEP_FIELDS[1]);
    const errors = ui.validateValues(draft, allFields);
    if (draft.plannedStart && draft.plannedEnd && draft.plannedEnd < draft.plannedStart) {
      errors.plannedEnd = '计划结束不能早于计划开始';
    }
    if (Object.keys(errors).length > 0) {
      const firstKey = Object.keys(errors)[0];
      step = STEP_FIELDS[0].some((def) => def.name === firstKey) ? 0 : 1;
      renderStep();
      const values = queryValues(currentFields(), draft);
      formEl.innerHTML = `<div data-step-fields>${ui.renderFields(currentFields(), values)}</div>
        <div class="form-actions"><span class="left"></span><button type="button" class="btn btn-primary" data-wizard="next">下一步</button></div>`;
      ui.showFieldErrors(formEl, errors);
      ui.toast(errors[firstKey], { type: 'warn', title: '还有必填项未完成' });
      return false;
    }
    return true;
  }

  function createBody() {
    const body = {
      requestType: draft.requestType,
      title: draft.title,
      description: draft.description,
      priority: draft.priority,
      component: draft.component,
      plannedStart: draft.plannedStart,
      plannedEnd: draft.plannedEnd
    };
    if (draft.cycleId) body.cycleId = draft.cycleId;
    if (draft.owner) body.owner = draft.owner;
    if (draft.dueDate) body.dueDate = draft.dueDate;
    return body;
  }

  async function submit(submitApproval, button) {
    if (submitting) return;
    if (!validateAll()) return;
    submitting = true;
    ui.setBusy(button, true, submitApproval ? '创建中…' : '保存中…');
    try {
      const created = await api.post('/requests', createBody());
      const id = created && created.id;
      if (!id) throw new Error('创建请求失败：响应缺少 id');
      let submitError = null;
      if (submitApproval) {
        try {
          await api.post('/requests/' + encodeURIComponent(id) + '/actions', {
            action: 'SUBMIT',
            version: created.version !== undefined ? Number(created.version) : 1
          });
        } catch (err) {
          submitError = err;
        }
      }
      dirty = false;
      const displayId = created.displayId || id;
      if (submitError) {
        const info = describeError(submitError);
        ui.toast('草稿已创建，但提交审批失败：' + info.message, {
          type: 'warn',
          title: '已保存草稿',
          correlationId: info.correlationId
        });
      } else {
        ui.toast(
          submitApproval ? '创建成功，已提交审批。' : '创建成功，已保存为草稿。',
          { type: 'success' }
        );
      }
      ctx.navigate('#/requests/' + encodeURIComponent(id));
      void displayId;
    } catch (err) {
      const info = describeError(err);
      ui.toast(info.message, { title: info.title, type: 'error', correlationId: info.correlationId });
      submitting = false;
      ui.setBusy(button, false);
    }
  }

  ui.bindOnce(root, 'request-new', () =>
    ui.delegate(root, '[data-wizard]', 'click', (event, el) => {
      const action = el.getAttribute('data-wizard');
      if (action === 'next') {
        if (!validateStep()) return;
        step = 1;
        renderStep();
      } else if (action === 'prev') {
        readCurrentIntoDraft();
        step = 0;
        renderStep();
      } else if (action === 'draft') {
        submit(false, el);
      } else if (action === 'submit') {
        submit(true, el);
      }
    })
  );

  // 未保存修改提示（浏览器刷新 / 关闭；hash 内跳转由用户主动点击导航）
  let dirty = false;
  const onInput = () => {
    dirty = true;
  };
  const onBeforeUnload = (event) => {
    if (!dirty) return;
    event.preventDefault();
    event.returnValue = '';
    return '';
  };
  if (formEl) formEl.addEventListener('input', onInput);
  if (typeof window !== 'undefined' && window.addEventListener) {
    window.addEventListener('beforeunload', onBeforeUnload);
  }

  renderStep();

  return () => {
    ui.releaseOnce(root, 'request-new');
    if (typeof window !== 'undefined' && window.removeEventListener) {
      window.removeEventListener('beforeunload', onBeforeUnload);
    }
  };
}
