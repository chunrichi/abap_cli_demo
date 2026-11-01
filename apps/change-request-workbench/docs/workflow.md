# 变更请求工作台（CRW）· 流程与状态机

> 状态：v1 契约（M1 冻结；状态机、审批矩阵、传输与计划语义的共享契约，变更需评审）。
> 事实源：[CRW 规划](../../../docs/change-request-workbench-plan.md)（下称「规划」）§4.5 / §5 / §7.4 / §8.4；冲突时以规划为准。
> 配套文档：[architecture.md](architecture.md)（分层、数据模型、API 契约、部署、安全）、[runbook.md](runbook.md)（运维，v1 骨架）。
> 文档约定：状态码 / 动作码 / 错误码为 ASCII 大写；字段名与 DDIC 一致；**待定** 表示规划未定义、需在对应里程碑前决策。
> v1 冻结（2026-11-01）：§12 的 W1–W30 已全部裁决；正文中标注“待定”的表述按 §12 “v1 决议”列执行。

---

## 1. 流程总览

### 1.1 生命周期

```
Change Request（CR）：
  NEW ──SUBMIT──▶ PENDING_APPROVAL
  PENDING_APPROVAL ──APPROVE_STEP（自环；末步通过）──▶ APPROVED
  PENDING_APPROVAL ──WITHDRAW──▶ NEW
  PENDING_APPROVAL ──REJECT──▶ REJECTED
  REJECTED ──REVISE──▶ NEW
  APPROVED ──START_PROGRESS──▶ IN_PROGRESS
  IN_PROGRESS ──CLOSE──▶ CLOSED
  非终态 ──CANCEL──▶ CANCELLED

Change Document（CD）：
  NEW ──START_DEV──▶ IN_DEV ──SUBMIT_TEST──▶ IN_TEST
  IN_TEST ──PASS_TEST（自环）──▶ IN_TEST
  IN_TEST ──SUBMIT_APPROVAL（自环）──▶ IN_TEST
  IN_TEST ──MARK_READY──▶ READY_TO_IMPORT
  READY_TO_IMPORT ──SCHEDULE_IMPORT──▶ IMPORT_SCHEDULED
  IMPORT_SCHEDULED ──SCHEDULE_IMPORT（取消计划）──▶ READY_TO_IMPORT
  READY_TO_IMPORT / IMPORT_SCHEDULED ──CONFIRM_IMPORT──▶ IMPORTED
  IMPORTED ──CLOSE──▶ CLOSED
  非终态 ──CANCEL──▶ CANCELLED

Task / SubTask：
  OPEN ──START──▶ IN_PROGRESS ──DONE──▶ DONE
  非终态 ──CANCEL──▶ CANCELLED（REOPEN P1）

Transport（DEV / ToC，只读快照）：
  E070：D（可修改）→ R（已释放）；导入状态由 TMS 只读判定
  ToC 业务态：CREATED → RELEASED → IMPORT_SCHEDULED → IMPORTED；RETROFIT_STATE 独立标记（P1）
```

### 1.2 统一动作协议

- 状态只能通过动作改变，**不接受** UI / API 直接写 `STATUS` 字段。
- 动作统一走 `POST /api/v1/{resource}/{id}/actions`，请求体至少含 `action` 与 `version`，可选 `comment` 及动作专属参数（如 `plannedImportAt`）；审批决策走 `POST /api/v1/approvals/{id}/decision`。
- 服务端处理顺序：**校验版本 → 取锁 → 校验当前状态 → 校验角色与数据范围 → 校验守卫 → 执行迁移 → 写副作用（历史 / 审批 / 计划）→ `version` +1 → `COMMIT` → 返回变更后对象摘要**。
- 失败返回统一错误信封：非法状态 `INVALID_TRANSITION`、守卫不满足 `GUARD_FAILED`、越权 `FORBIDDEN` / `APPROVER_MISMATCH` / `SELF_APPROVAL`、版本冲突 `CONCURRENT_MODIFICATION`（见 §10）。
- 动作幂等：重复提交且状态已变化 → `INVALID_TRANSITION`，不产生重复历史 / 审批记录。

### 1.3 核心不变量

| # | 不变量 |
|---|---|
| I1 | 状态只能通过动作改变，UI 不直接写 `STATUS` |
| I2 | 每次状态变更必须写一条 `ZCRW_HIST`，含操作人、时间、动作、旧 / 新状态、可选原因 |
| I3 | CR 审批未通过不能建 / 开发 CD；CD 导入前审批未通过不能进入 `READY_TO_IMPORT` |
| I4 | CD 关联的 DEV transport 未全部释放，CD 不能进入 `READY_TO_IMPORT`；ToC 导入前必须有计划导入时间 |
| I5 | Task 未全部关闭或取消，CD 不能关闭；CD 未全部关闭，CR 不能关闭 |
| I6 | 已释放的 transport 不能从 CD 解绑，只能标记「不再关联」并留审计 |
| I7 | 所有写操作校验 `VERSION`（乐观锁）；核心状态变更加 SAP 锁对象 |
| I8 | 服务端按角色鉴权；前端隐藏按钮只是体验，不是安全边界 |
| I9 | 审批意见、驳回原因、取消原因必填；备注可为空 |
| I10 | 历史表只追加，不提供删除入口；审计导出只读 |

### 1.4 对象与字段映射

| 概念 | 表 | 状态字段 | 版本字段 | 锁对象 |
|---|---|---|---|---|
| CR 请求 | `ZCRW_REQ` | `STATUS` CHAR20、`APPROVAL_STATE` CHAR10 | `VERSION` NUMC6 | `EZCRW_REQ` |
| CD 变更文档 | `ZCRW_CD` | `STATUS` CHAR20、`APPROVAL_STATE` CHAR10 | `VERSION` NUMC6 | `EZCRW_CD` |
| Task / SubTask | `ZCRW_TASK` | `STATUS` CHAR20 | `VERSION` NUMC6 | 无专用锁（随 CD / CR 加锁） |
| 审批步骤 | `ZCRW_APPR` | `APPR_STATE` CHAR10 | 无（随对象版本） | 随对象锁 |
| 传输关联 | `ZCRW_TR` | `TR_STATUS` CHAR1（E070 快照）、`SYNC_STATE` CHAR10 | 无 | 随 CD 锁 |
| 导入计划 | `ZCRW_SCHED` | `STATUS` CHAR10 | 无 | 随 CD / 计划动作加锁 |
| 审计 | `ZCRW_HIST` | —（只追加） | — | 无 |

---

## 2. 请求类型

| 类型 | 编码 | 流程差异 | 一期 |
|---|---|---|---|
| 标准变更 Standard | `STD` | 完整 CR 审批、CD 审批与传输流程；CD 至少 1 条 DEV transport 才能提交测试 | P0 |
| 紧急变更 Urgent | `URG` | 可跳过事前 CR 审批，走 ToC；生产导入后必须补审批与复盘；逾期进入「待补审」报表 | P1 |
| 管理变更 Administrative | `ADM` | 不产生 transport，用检查清单代替传输关联；关闭时校验清单完成 | P2 |

- `REQ_TYPE` 为 `CHAR4`，取值为 `STD` / `URG` / `ADM`；类型决定审批矩阵匹配、CD 守卫与关闭校验。
- 类型一经创建不可修改；需要换类型时新建 CR 并关联说明（规划未定义，**待定** W1）。

---

## 3. CR 状态机

### 3.1 状态

| 编码 | 中文 | 含义 | 终态 |
|---|---|---|---|
| `NEW` | 新建 | 草稿 / 待提交，可编辑、可删除（删除语义**待定** W30） | 否 |
| `PENDING_APPROVAL` | 待审批 | 已提交，等待 CR 审批步骤完成 | 否 |
| `REJECTED` | 已拒绝 | 审批驳回，可修改后重新提交 | 否 |
| `APPROVED` | 已批准 | 可建 CD | 否 |
| `IN_PROGRESS` | 进行中 | 至少一个 CD 在开发 / 测试 / 导入中 | 否 |
| `CLOSED` | 已关闭 | 终态，只读 | 是 |
| `CANCELLED` | 已取消 | 终态，必须填原因 | 是 |

### 3.2 状态迁移（边列表）

```
NEW ──SUBMIT──▶ PENDING_APPROVAL
PENDING_APPROVAL ──APPROVE_STEP（自环；末步通过）──▶ APPROVED
PENDING_APPROVAL ──WITHDRAW──▶ NEW
PENDING_APPROVAL ──REJECT──▶ REJECTED
REJECTED ──REVISE──▶ NEW
APPROVED ──START_PROGRESS──▶ IN_PROGRESS
IN_PROGRESS ──CLOSE──▶ CLOSED
非终态 ──CANCEL──▶ CANCELLED（NEW 由请求人；其余由变更经理）
```

### 3.3 动作、迁移、角色、守卫与副作用

| 动作 | 迁移 | 允许角色 | 守卫 | 副作用 | 失败码 |
|---|---|---|---|---|---|
| `SUBMIT` | `NEW → PENDING_APPROVAL` | 请求人、变更经理 | 必填项完整（字段集合**待定** W2） | 按审批矩阵生成 CR 审批步骤（`ZCRW_APPR`）；写历史 | `VALIDATION_ERROR` |
| `WITHDRAW` | `PENDING_APPROVAL → NEW` | 请求人、变更经理 | — | 未决审批步骤置 `SKIPPED`；写历史 | `INVALID_TRANSITION` |
| `APPROVE_STEP` | `PENDING_APPROVAL → PENDING_APPROVAL` | 当前步骤审批人 | 操作人是当前步骤审批人；非请求人本人 | 当前步骤 `APPROVED` + `DECIDED_AT` + 意见（可选）；末步通过后转 `APPROVED`；写历史 | `APPROVER_MISMATCH` / `SELF_APPROVAL` |
| `REJECT` | `PENDING_APPROVAL → REJECTED` | 当前步骤审批人 | 意见必填 | 终止本次审批流；写历史 | `VALIDATION_ERROR` / `APPROVER_MISMATCH` |
| `REVISE` | `REJECTED → NEW` | 请求人、变更经理 | — | 保留全部历史；再次 `SUBMIT` 时重新生成审批步骤 | `INVALID_TRANSITION` |
| `START_PROGRESS` | `APPROVED → IN_PROGRESS` | 变更经理、开发 | 必须存在至少 1 个 CD | 写历史 | `GUARD_FAILED` |
| `CLOSE` | `IN_PROGRESS → CLOSED` | 变更经理 | 所有 CD 已关闭或取消 | `CLOSED_AT` 置时间；写历史 | `GUARD_FAILED` |
| `CANCEL` | 非终态 → `CANCELLED` | 请求人（仅 `NEW`）、变更经理 | 原因必填 | `CANCEL_REASON` + `CLOSED_AT`；未决审批步骤终止；写历史 | `VALIDATION_ERROR` / `FORBIDDEN` |

### 3.4 规则补充

- **审批中可撤回、不可编辑**：`PENDING_APPROVAL` 期间头部字段只读，避免审批对象与审批内容不一致；撤回后回到 `NEW` 再编辑。
- **自环动作不算状态变更**：`APPROVE_STEP` / `PASS_TEST` / `SUBMIT_APPROVAL` 的 `STATUS` 不变，但审批步骤与历史必须落库，前端按 `APPROVAL_STATE` 刷新。
- **驳回后可修改重提**：`REJECTED` 允许 `PATCH` 头部字段；重提时旧审批步骤保留（历史可查），新步骤按最新矩阵生成。
- **关闭是终态**：`CLOSED` / `CANCELLED` 只读，不提供重开；需要继续时新建 CR 并关联说明（规划未定义关联字段，**待定** W1）。
- **`APPROVAL_STATE`**：M1 服务类常量已使用 `PENDING` / `APPROVED` / `REJECTED`；`SKIPPED` / `NONE` 与取消对象的标记方式规划未枚举，**待定**（W3）。

---

## 4. CD 状态机

### 4.1 状态

| 编码 | 中文 | 含义 | 终态 |
|---|---|---|---|
| `NEW` | 新建 | 刚创建，可编辑、可拆分任务 | 否 |
| `IN_DEV` | 开发中 | 有开发任务进行 | 否 |
| `IN_TEST` | 测试中 | 开发完成，等待测试结论 | 否 |
| `READY_TO_IMPORT` | 待导入 | 测试通过、审批通过、DEV transport 已全部释放 | 否 |
| `IMPORT_SCHEDULED` | 已计划导入 | 有生效中的导入计划 | 否 |
| `IMPORTED` | 已导入 | 发布管理员确认导入 | 否 |
| `CLOSED` | 已关闭 | 终态 | 是 |
| `CANCELLED` | 已取消 | 终态，必须填原因 | 是 |

### 4.2 状态迁移（边列表）

```
NEW ──START_DEV──▶ IN_DEV
IN_DEV ──SUBMIT_TEST──▶ IN_TEST
IN_TEST ──PASS_TEST（自环；记录结论）──▶ IN_TEST
IN_TEST ──SUBMIT_APPROVAL（自环；生成导入审批）──▶ IN_TEST
IN_TEST ──MARK_READY──▶ READY_TO_IMPORT
READY_TO_IMPORT ──SCHEDULE_IMPORT──▶ IMPORT_SCHEDULED
IMPORT_SCHEDULED ──SCHEDULE_IMPORT（取消计划）──▶ READY_TO_IMPORT
READY_TO_IMPORT / IMPORT_SCHEDULED ──CONFIRM_IMPORT──▶ IMPORTED
IMPORTED ──CLOSE──▶ CLOSED
非终态 ──CANCEL──▶ CANCELLED
```

### 4.3 动作、迁移、角色、守卫与副作用

| 动作 | 迁移 | 允许角色 | 守卫 | 副作用 | 失败码 |
|---|---|---|---|---|---|
| `START_DEV` | `NEW → IN_DEV` | 开发、变更经理 | 必须有 `OWNER` | 可自动建开发任务（是否自动**待定** W4）；写历史 | `GUARD_FAILED` |
| `SUBMIT_TEST` | `IN_DEV → IN_TEST` | 开发、测试 | 开发任务与子任务全部关闭；`STD` 类型至少 1 条 DEV transport | 写历史 | `GUARD_FAILED` |
| `PASS_TEST` | `IN_TEST → IN_TEST` | 测试 | 存在待测试任务 / 测试结论已记录 | 记录测试结论；关闭测试任务；写历史 | `GUARD_FAILED` |
| `SUBMIT_APPROVAL` | `IN_TEST → IN_TEST` | 变更经理 | 测试已通过（P0 可配置为不需要 CD 审批） | 按矩阵生成 CD 导入审批步骤；写历史 | `GUARD_FAILED` |
| `MARK_READY` | `IN_TEST → READY_TO_IMPORT` | 发布管理员、变更经理 | 测试通过；CD 审批通过；DEV transport 全部释放 | 写历史 | `GUARD_FAILED` |
| `SCHEDULE_IMPORT` | `READY_TO_IMPORT ↔ IMPORT_SCHEDULED` | 发布管理员 | 必须有计划导入时间 | 写 / 改 `ZCRW_SCHED`；同步 `PLANNED_IMPORT_AT`；写历史 | `SCHEDULE_CONFLICT` |
| `CONFIRM_IMPORT` | `* → IMPORTED` | 发布管理员 | 必须有生效计划或人工确认 | 写导入时间；关联计划置 `DONE`；写历史 | `GUARD_FAILED` |
| `CLOSE` | `IMPORTED → CLOSED` | 变更经理 | 所有任务关闭；ToC retrofit 标记（P1） | `CLOSED_AT`；写历史 | `GUARD_FAILED` |
| `CANCEL` | 非终态 → `CANCELLED` | 变更经理 | 原因必填 | 未决计划取消；已释放 transport 不回滚；写历史 | `VALIDATION_ERROR` |

### 4.4 规则补充

- **`CONFIRM_IMPORT` 的来源态**：规划写 `* → IMPORTED`，字面允许任意状态；本文建议限定 `READY_TO_IMPORT` / `IMPORT_SCHEDULED`，具体以服务层守卫为准，**待定**（W5）。
- **`SCHEDULE_IMPORT` 双向**：`READY_TO_IMPORT → IMPORT_SCHEDULED` 创建 / 更新计划；`IMPORT_SCHEDULED → READY_TO_IMPORT` 表示取消计划（计划置 `CANCELLED`）。改期不改变 CD 状态，只更新计划时间。
- **`SUBMIT_APPROVAL` 可关闭**：P0 允许配置为不需要 CD 导入审批；关闭时 `MARK_READY` 的「CD 审批通过」守卫自动满足（配置键与默认值**待定** W6）。
- **测试通过 ≠ 待导入**：`PASS_TEST` 只记录结论，进入 `READY_TO_IMPORT` 仍需 `MARK_READY` 的三项守卫，避免测试通过后被误判为可导入。
- **关闭条件中的「取消」**：规划要求「Task 未全部关闭或取消，CD 不能关闭」；`CANCELLED` 任务是否满足父任务 / CD 关闭条件，**待定**（W7）。
- **取消不回滚传输**：已释放 transport 保持已释放状态，只记录取消原因与历史；不回滚 CTS。

---

## 5. Task / SubTask 状态机

### 5.1 层级与字段

- 层级最多两级：`TASK_LEVEL = T`（Task，`PARENT_TASK_ID` 为空）与 `TASK_LEVEL = S`（SubTask，`PARENT_TASK_ID` 指向父 Task）。
- 任务必须挂在 CD 下（`CD_ID`），并冗余 `REQ_ID` 便于按请求查询；任务归属在创建时确定，是否允许跨 CD 移动规划未定义（**待定** W29）。
- 任务类型 `TASK_TYPE`：`DEV`（开发）、`TEST`（测试）、`IMPORT`（导入确认）、`RETROFIT`（补做，P1）。
- 指派字段 `ASSIGNEE`；`DUE_DATE` 截止日；`EST_HOURS` 预估工时（`NUMC5`）。

### 5.2 状态与动作

| 动作 | 迁移 | 允许角色 | 守卫 | 副作用 |
|---|---|---|---|---|
| `START` | `OPEN → IN_PROGRESS` | 被指派人、开发、变更经理 | 任务存在且未终态 | 写历史 |
| `DONE` | `IN_PROGRESS → DONE` | 被指派人、开发、测试、变更经理 | 若为父 Task，所有子任务关闭 | 写历史；可能解锁 CD `SUBMIT_TEST` / `CLOSE` |
| `CANCEL` | 非终态 → `CANCELLED` | 变更经理（子任务可由父任务负责人） | 原因必填 | 写历史 |
| `REOPEN` | 终态 → `OPEN`（P1） | 变更经理 | 规划未定义可重开状态与次数，**待定**（W8） | 写历史 |

- 状态：`OPEN` / `IN_PROGRESS` / `DONE` / `CANCELLED`；`DONE` / `CANCELLED` 为终态。
- 所有任务动作同样校验 `VERSION` 并写 `ZCRW_HIST`。
- 任务动作的角色细化（谁可 `START` / `DONE` / `CANCEL`）与取消级联规则规划未逐条定义；表中角色为按角色表推导的初始约定，实现前冻结（**待定** W29）。

### 5.3 父子不变量

1. 子任务关闭**不自动**关闭父任务。
2. 父任务 `DONE` 要求其所有子任务已关闭（`DONE` 或 `CANCELLED`，后者**待定** W7）。
3. 子任务只能挂在一级 Task 下，禁止三级层级。
4. 父任务取消不自动取消子任务；子任务需显式取消，避免静默丢失工作量记录（规划未定义，本文按「不级联」处理，**待定** W29）。

### 5.4 任务类型与流程挂钩

| 类型 | 典型用途 | 与流程的挂钩 |
|---|---|---|
| `DEV` | 开发 / 配置实现 | CD `SUBMIT_TEST` 要求开发任务与子任务全部关闭 |
| `TEST` | 测试执行 | CD `PASS_TEST` 关闭测试任务并记录结论 |
| `IMPORT` | 导入执行确认 | 与 `CONFIRM_IMPORT` 配合；是否强制存在导入任务**待定**（W9） |
| `RETROFIT` | ToC 导入后补做（P1） | 与 `ZCRW_TR.RETROFIT_STATE` 联动，只提醒与标记，不自动生成 |

---

## 6. 审批流程

### 6.1 两级审批

| 级别 | 触发 | 对象 | 一期 |
|---|---|---|---|
| CR 审批 | CR `SUBMIT` 后 | `OBJECT_TYPE = REQ` | P0 |
| CD 导入审批 | CD `SUBMIT_APPROVAL` 后，进入待导入前 | `OBJECT_TYPE = CD` | P0（可配置为关闭） |

### 6.2 审批矩阵数据模型

`ZCRW_APPR_CFG`（主键 `PROFILE_ID` + `STEP_NO`）：

| 字段 | 含义 |
|---|---|
| `PROFILE_ID` | 审批配置组 |
| `STEP_NO` | 步骤序号（`NUMC2`，决定顺序） |
| `APPROVER_ROLE` | 步骤角色（角色编码**待定** W10） |
| `APPROVER_USER` | 指定用户（与角色二选一） |
| `OBJECT_TYPE` | `REQ` / `CD` |
| `REQ_TYPE` | `STD` / `URG` / `ADM` |
| `PRIORITY` | 优先级匹配（`CHAR2`；编码集合与通配约定**待定** W10） |
| `MANDATORY` | 是否强制步骤（`X` = 必须；空值语义**待定** W11） |

- 匹配规则：按「对象类型 + 请求类型 + 优先级」匹配一组有序步骤，按 `STEP_NO` 升序推进；通配写法（如 `CD/STD/*`）规划示例使用 `*`，但字段为 `CHAR2`，落地约定**待定**（W10）。
- 每步指定角色或指定用户；步骤内「任意一人」或「全部」两种通过规则 —— 当前表结构**无字段承载**该规则，**待定**（W12）。
- 一期审批矩阵写死在表里、由 bootstrap 种子 + 管理界面维护（P1/P2）；不做图形化流程设计器。

### 6.3 步骤生成与推进

1. `SUBMIT` / `SUBMIT_APPROVAL` 时按矩阵生成 `ZCRW_APPR` 行：`APPR_ID`（CHAR32）、`OBJECT_TYPE`、`OBJECT_ID`、`STEP_NO`、`APPROVER`、`APPR_STATE = PENDING`、`CREATED_AT`。
2. 审批人执行 `APPROVE_STEP` / `REJECT` 或 `POST /approvals/{id}/decision`：更新当前步骤 `APPR_STATE`、`DECIDED_AT`、`COMMENT_TXT`。
3. 末步通过 → 对象转 `APPROVED`（CR）/ 允许 `MARK_READY`（CD）；头部 `APPROVAL_STATE` 同步。
4. 驳回 → 终止本次审批流（未决步骤处理方式**待定** W13）；`REVISE` 后重新 `SUBMIT` 重新生成步骤。
5. `WITHDRAW` → 未决步骤置 `SKIPPED`。

- 步骤生成幂等：重复提交同一动作且状态已变化 → `INVALID_TRANSITION`，不重复生成步骤。
- 审批决策是否需要携带对象 `version`，**待定**（W14）。

### 6.4 通过 / 驳回规则

- 通过意见可选，驳回意见必填（`VALIDATION_ERROR`）。
- 请求人不能审批自己的请求（`SELF_APPROVAL`）；管理员显式配置代理是 P2 能力。
- 非当前步骤审批人 → `APPROVER_MISMATCH`。
- 审批人离职 / 缺失：由变更经理改派或管理员调整矩阵（P1 配置界面；一期 runbook 手工步骤，**待定** W15）。

### 6.5 示例矩阵

| 匹配 | 步骤 | 审批角色 | 通过规则 | 说明 |
|---|---|---|---|---|
| `REQ` / `STD` / 高优先级 | 1 | 变更经理 | 任意一人 | 业务审批 |
| `REQ` / `STD` / 高优先级 | 2 | 应用负责人 | 全部 | 应用侧确认 |
| `CD` / `STD` / 任意 | 1 | 变更经理 | 任意一人 | 导入前审批 |
| `REQ` / `URG` / 任意 | — | — | — | 跳过事前审批，走事后补审（P1） |

### 6.6 审批视图

- 「我的待办」：当前用户为当前步骤审批人的 `PENDING` 步骤。
- 「我审批过的」：当前用户已决策的步骤（含通过 / 驳回）。
- 「全组待办」：按角色聚合的待办（变更经理 / 发布管理员视角）。
- 列表返回对象摘要 + 步骤信息，前端抽屉展示对象摘要与历史（规划 §6.3）。

### 6.7 与状态机联动

| 动作 | 对审批的影响 |
|---|---|
| CR `SUBMIT` | 生成 CR 审批步骤；`APPROVAL_STATE = PENDING` |
| CR `APPROVE_STEP` | 当前步骤 `APPROVED`；末步 → CR `APPROVED` |
| CR `REJECT` | 本次审批流终止；CR `REJECTED` |
| CR `WITHDRAW` | 未决步骤 `SKIPPED`；CR 回 `NEW` |
| CR `REVISE` | 历史保留；下次 `SUBMIT` 重新生成步骤 |
| CD `SUBMIT_APPROVAL` | 生成 CD 导入审批步骤 |
| CD `MARK_READY` | 要求 CD 审批通过（或该级审批被配置关闭） |
| CD / CR `CANCEL` | 未决步骤终止 |

---

## 7. 传输与 ToC（只读集成）

### 7.1 边界（D4 / D8）

- 应用**只读** CTS：`E070`（传输头 / 状态 / 目标系统 / 所有人）、`E071`（对象清单）、`E07T`（描述）、TMS 队列表（导入状态）。
- 传输在 SE01 或 abap-cli 创建，应用只做「关联 + 展示 + 状态快照」；**不创建、不释放、不删除、不导入**。
- 不调用 TMS 导入 API；不在应用内释放 transport；不实现 retrofit / downgrade protection。
- D4 口径：实现只读集成与手工关联，**不做 live 验证**；未验证项在 M4 前补验证或明确接受风险（§7.9）。

### 7.2 关联模型与字段

`ZCRW_TR`（主键 `TRKORR` CHAR10）：

| 字段 | 含义 |
|---|---|
| `TRKORR` | transport 号（引用 `E070.TRKORR`，不建 DDIC 外键） |
| `CD_ID` / `TASK_ID` | 关联的 CD / 任务（任务关联可选） |
| `TR_KIND` | `DEV`（开发传输）/ `TOC`（Transport of Copies） |
| `TARSYSTEM` | 目标系统（`E070.TARSYSTEM` 快照） |
| `TR_STATUS` / `TR_STATUS_TXT` | `E070.TRSTATUS` 快照与文本（`D` / `R` 等） |
| `RELEASED_AT` / `IMPORT_SCHEDULED_AT` / `IMPORTED_AT` | 释放 / 计划导入 / 导入时间（`CHAR14`） |
| `RETROFIT_STATE` | `NA` / `PENDING` / `DONE`（P1） |
| `SYNC_STATE` | 同步状态（`ERROR` 表示读取失败；其余取值**待定** W16） |
| `LAST_SYNC_AT` / `LINKED_AT` / `LINKED_BY` | 最近同步 / 关联时间与关联人 |
| `DESCRIPTION` | 描述快照（`E07T`） |

> 规划 §5.2 写作 `TRKIND`，DDIC 字段为 `TR_KIND`；本文与实现以 `TR_KIND` 为准。

### 7.3 关联流程与校验

1. 用户在 SE01 / abap-cli 创建 transport（DEV 或 ToC）。
2. 在 CD 详情 / 传输工作台执行 `POST /transports/link`（`cdId`、`trkorr`、`trKind`，可选 `taskId`）。
3. 服务端校验：`TRKORR` 在 `E070` 存在；未被其他 CD 关联（`DUPLICATE_LINK`）；`TR_KIND` 合法；目标系统与 CD 计划系统不一致时**警告**（允许变更经理确认后继续）。
4. 写入 `ZCRW_TR` 快照并写 `ZCRW_HIST`（动作 `LINK_TR`）。

- 关联只写应用表，不改 `E070` / `E071`。
- 同一 CD 可关联多条 DEV transport（按批次）；同一 transport 只能关联一个 CD。

### 7.4 状态映射（展示用，不改变 `E070`）

| 展示状态 | 判定来源（M0 已确认可读，字段判定 M3 细化） |
|---|---|
| 可修改 | `E070.TRSTATUS = D` |
| 已释放 | `E070.TRSTATUS = R` |
| 已导入 | TMS 队列 / 导入历史显示目标系统导入成功 |
| 导入失败 / 有错误 | 导入日志有错误 |
| 未知 | 读不到或字段无法判定，显示「未知，请到 STMS 确认」 |

- 展示状态只用于业务展示与筛选，不回写 CTS。
- ToC 的业务态（`CREATED` / `RELEASED` / `IMPORT_SCHEDULED` / `IMPORTED`）由 `TR_STATUS` + 计划 + `IMPORTED_AT` 派生；`ZCRW_TR` 无独立 ToC 状态列，是否新增字段**待定**（W17）。

### 7.5 同步

| 触发 | 行为 |
|---|---|
| 打开传输工作台 / CD 详情 | 按需刷新（节流，避免每次请求都打 CTS） |
| `POST /transports/sync` | 手动同步单条或批量状态 |
| P1 定时同步 | 管理员用 SM36 定时跑同步报表（abap-cli 不支持建作业，人工配置） |

- 同步写 `ZCRW_TR` 快照字段与 `LAST_SYNC_AT`；同步本身写 `ZCRW_HIST`（`SOURCE = SYNC`）或日志（按规划 §5.7「传输状态同步」属审计范围，具体动作名**待定** W18）。
- 详情页对象清单实时读 `E071`；读取失败则不展示清单，不影响头部状态。

### 7.6 解绑与标记

| transport 状态 | 允许操作 | 审计 |
|---|---|---|
| 可修改（`D`） | `unlink` 解绑 | 写历史（`UNLINK_TR`），保留关联快照 |
| 已释放 / 已导入（`R` / 已导入） | 只允许 `mark-detached` 标记「不再关联」 | 写历史，保留记录 |
| 任意 | 不提供物理删除 | — |

- 解绑后 `CD_ID` 置空或保留标记，由实现约定；无论哪种都必须保留可审计痕迹（**待定** W19）。

### 7.7 ToC 流程与 retrofit

- ToC 是 `TR_KIND = TOC` 的 `ZCRW_TR` 记录：单独展示类型、目标系统、计划导入时间、导入状态。
- 导入后提示「补做 / retrofit 待确认」（P1）；`RETROFIT_STATE` 从 `NA` → `PENDING` → `DONE`，由人工标记，**不自动**生成补做传输、不自动判定 retrofit 范围。
- 紧急变更（`URG`）走 ToC：计划导入时间可提前；生产导入后必须补审批与复盘（P1 流程细节**待定** W20）。
- ToC 导入前必须有计划导入时间（D9，不变量 I4）。

### 7.8 降级

- CTS 读取失败不阻塞请求流程：状态显示「未知」、`SYNC_STATE = ERROR`、写 `ZCRW_LOG`，返回业务数据 + 降级标记。
- 直接依赖 CTS 的查询（传输列表 / 详情）返回 `CTS_READ_ERROR`（502）或降级数据（按端点语义，**待定** W21）。
- 报表可筛选 `SYNC_STATE = ERROR` 的关联，供发布管理员集中处理。

### 7.9 未验证项（D4）

| 项 | 状态 | 处理 |
|---|---|---|
| `E070` / `E071` / `E07T` 可读 | 已验证（只读） | — |
| TMS 队列表字段与导入状态判定 | 部分验证（`TMSBUFFER` 字段可查，业务判定留 M3） | M3 细化映射；失败降级 |
| 最终用户 CTS 表权限 | 未验证 | 服务层读 + `AUTHORITY-CHECK` 后降级（M1/M3 与 basis 确认） |
| live transport 关联与状态展示 | 不做 live 验证（D4） | M4 前补验证或明确接受风险 |

---

## 8. 导入计划语义

### 8.1 语义定义（D9）

「定时传输」在应用内落地为**计划 + 提醒 + 状态跟踪**，**不执行 TMS 导入**：

- 计划记录：CD / ToC 可设置计划导入时间与目标系统，写 `ZCRW_SCHED`。
- 日程视图：按日期 / 周期 / 目标系统分组，显示 `PLANNED` / `DONE` / `MISSED`。
- 提醒：到点未导入标 `MISSED`（读取时计算）+ 首页 / 我的工作提醒；**不发送后台通知**（无 SM36）。
- 确认：实际导入后由发布管理员确认（或 CTS 同步判定），计划置 `DONE`。
- 若后续要求「到点自动导入」，需评估 TMS RFC / API、权限与风险，另立变更（非本计划范围）。

### 8.2 数据与状态

`ZCRW_SCHED`（主键 `SCHED_ID` CHAR32）：

| 字段 | 含义 |
|---|---|
| `OBJECT_TYPE` | `CD` / `TOC` |
| `OBJECT_ID` | 对象编号（CD 为 CHAR10 编号，ToC 为 transport 号；`CHAR20` 兼容） |
| `TARGET_SYS` | 目标系统 |
| `SCHEDULED_AT` | 计划导入时间（`CHAR14`） |
| `STATUS` | `PLANNED` / `DONE` / `MISSED` / `CANCELLED` |
| `NOTE` | 备注（`CHAR255`） |

| 状态 | 含义 | 进入方式 |
|---|---|---|
| `PLANNED` | 已计划，未到点 | `SCHEDULE_IMPORT` 创建计划 |
| `DONE` | 已导入并确认 | `CONFIRM_IMPORT` 确认或 CTS 同步判定 |
| `MISSED` | 到点未导入 | 读取时按 `SCHEDULED_AT < 当前时间` 且未确认计算 |
| `CANCELLED` | 计划取消 | `SCHEDULE_IMPORT` 回退（`IMPORT_SCHEDULED → READY_TO_IMPORT`）或显式取消 |

### 8.3 计划生命周期

```
（无计划）──SCHEDULE_IMPORT──▶ PLANNED ──到点未导入──▶ MISSED ──确认导入──▶ DONE
                                  │  ▲                      │
                                  │  └──改期（仍 PLANNED）──┘
                                  └──取消──▶ CANCELLED
```

- 一个 CD / ToC 同一时间只允许一条生效计划（`PLANNED` / `MISSED`）；重复创建返回 `SCHEDULE_CONFLICT`。
- 改期：更新 `SCHEDULED_AT` 与备注，状态保持 `PLANNED`（若原为 `MISSED`，改期后回到 `PLANNED`）。
- 取消：计划置 `CANCELLED`，CD 从 `IMPORT_SCHEDULED` 回到 `READY_TO_IMPORT`。
- 逾期后补导入：`MISSED` 计划在确认导入后置 `DONE`，历史保留原计划时间与逾期事实。

### 8.4 到点 / 逾期计算与提醒

- `MISSED` 在读取时计算，不依赖后台作业；判定基准为「计划时间 < 当前系统时间且未确认导入」。
- 提醒出口：首页 KPI（逾期数）、我的工作（待导入 / 逾期）、导入日程视图；不发送邮件 / 站内消息（P1/P2 再评估）。
- 时区基准（系统时区 / 用户时区）**待定**（W22），与 `architecture.md` §5.6 同源问题。

### 8.5 冲突、改期与取消

| 场景 | 行为 | 错误码 |
|---|---|---|
| 已有生效计划再创建 | 拒绝 | `SCHEDULE_CONFLICT` |
| 改期到与另一生效计划冲突（同目标系统 / 时间窗，判定规则**待定** W23） | 拒绝或警告 | `SCHEDULE_CONFLICT` |
| 取消已 `DONE` 的计划 | 拒绝（已发生，只能补备注；是否允许取消规划未定义，**待定** W23） | `INVALID_TRANSITION` |
| 对非 `READY_TO_IMPORT` / `IMPORT_SCHEDULED` 的 CD 设计划 | 拒绝 | `INVALID_TRANSITION` |

### 8.6 与 CD / ToC 的联动

- CD 的 `PLANNED_IMPORT_AT` 与 `ZCRW_SCHED.SCHEDULED_AT` 存在冗余：规划未定义权威来源，**待定**（W24）；建议以 `ZCRW_SCHED` 为权威、`PLANNED_IMPORT_AT` 作为最近计划快照，实现前冻结。
- `SCHEDULE_IMPORT` 同时更新 CD 状态与计划；`CONFIRM_IMPORT` 同时写导入时间、计划 `DONE` 与 CD `IMPORTED`。
- ToC 计划以 `OBJECT_TYPE = TOC`、`OBJECT_ID = TRKORR` 记录；导入确认后进入 retrofit 提醒（P1）。

### 8.7 明确不做

- 不执行 TMS 导入、不排队、不触发 STMS。
- 不建后台作业（abap-cli 不支持 SM36）。
- 不做自动通知（邮件 / IM / 站内消息推送）。
- 不做跨系统、跨 client 的发布编排。

---

## 9. 审计与历史不变量

### 9.1 记录范围

以下动作必须写 `ZCRW_HIST`：

| 类别 | 示例动作 | 对象 |
|---|---|---|
| 状态迁移 | CR / CD / Task 的所有状态动作 | `REQ` / `CD` / `TASK` |
| 审批 | 步骤生成、通过、驳回、撤回跳过 | `REQ` / `CD` |
| 指派与计划 | 改派任务、改负责人、改期 | `TASK` / `CD` |
| 创建 | 新建 CD、任务、子任务 | `CD` / `TASK` |
| 传输 | 关联、解绑、标记不再关联、状态同步 | `TR` |
| 导入计划 | 创建、改期、取消、确认完成 | `SCHED` |
| 配置变更 | bootstrap / 迁移 / 管理界面改矩阵与角色 | `CONFIG` |
| 取消与驳回 | 含原因 | 各对象 |

### 9.2 字段与来源

| 字段 | 约定 |
|---|---|
| `OBJECT_TYPE` | `REQ` / `CD` / `TASK` / `TR` / `SCHED` / `CONFIG`（是否含 `NOTE` **待定** W25） |
| `OBJECT_ID` | 对象编号（CHAR32 对象直接用 GUID） |
| `ACTION` | 与状态机动作名一致；非状态动作使用 `CREATE_*` / `LINK_*` / `UNLINK_*` / `UPDATE_*` / `SYNC_*` 前缀（完整清单实现时冻结，**待定** W18） |
| `FIELD` / `OLD_VALUE` / `NEW_VALUE` | 字段级变更；状态变更可用 `STATUS` / 旧新状态 |
| `COMMENT_TXT` | 操作备注 / 驳回原因 / 取消原因 |
| `CHANGED_BY` / `CHANGED_AT` | 操作人（`SY-UNAME`）与时间（`CHAR14`） |
| `SOURCE` | `UI` / `API` / `SYNC` |

### 9.3 写入不变量

1. **一次状态变更一条历史**：动作成功即写一条；失败不写。
2. **同一 LUW**：业务写与历史写在同一事务内提交，禁止「状态变了但没历史」。
3. **只追加**：无删除 / 更新历史入口；`ZCRW_HIST` 不参与业务更新。
4. **必填原因**：驳回、取消的原因同时进历史与对象字段。
5. **无敏感数据**：不记录凭证、系统地址、真实业务数据；长文本按 255 截断（截断规则**待定** W26）。
6. **审计导出只读**：按请求 / 时间 / 操作人过滤，CSV 下载（P1）。

### 9.4 与审批 / 日志的分工

| 数据 | 用途 | 生命周期 |
|---|---|---|
| `ZCRW_HIST` | 业务审计：谁在何时对什么做了什么、为什么 | 只追加，长期保留 |
| `ZCRW_APPR` | 审批步骤的当前状态与决策（可查询、可驱动流程） | 随审批流 |
| `ZCRW_NOTE` | 协作备注 / 评论（可空、可多条） | 长期保留 |
| `ZCRW_LOG` | 技术日志：API 错误、CTS 失败、迁移、权限拒绝 | 按运维策略清理（P2） |

- 历史不等于审批记录：审批状态以 `ZCRW_APPR` 为准，历史提供完整追溯链。
- 历史不等于日志：日志面向排障，历史面向业务审计。

### 9.5 合规边界

- 应用级审计**不是**合规级不可篡改：管理员仍可直接改表；runbook 必须写明该边界。
- 审计导出只读，不提供编辑；导出文件名过滤用户输入（防注入 / 路径穿越）。

---

## 10. 错误语义

### 10.1 错误信封

```json
{
  "status": "error",
  "code": "GUARD_FAILED",
  "message": "当前状态 IN_TEST 不允许执行 MARK_READY",
  "details": { "currentStatus": "IN_TEST", "action": "MARK_READY", "missing": ["ALL_DEV_TR_RELEASED"] },
  "correlationId": "9f2c0b1d4e6f4a8b9c0d1e2f3a4b5c6d"
}
```

- `details` 只放安全上下文（当前状态、动作、缺失守卫项），不返回内部表名 / 堆栈 / 系统信息。
- `correlationId` 与 `ZCRW_LOG.CORRELATION_ID` 一致，前端展示便于排障。
- HTTP 状态总则：400 参数 / 校验、401 未登录、403 无权限、404 不存在、409 冲突 / 非法迁移、500 内部错误、502 CTS 读取失败。

### 10.2 流程相关错误码

| code | HTTP | 流程含义 | 典型场景 |
|---|---|---|---|
| `INVALID_TRANSITION` | 409 | 当前状态不允许该动作 | 对 `NEW` 执行 `MARK_READY`；状态已被他人推进后重复动作 |
| `GUARD_FAILED` | 409 | 前置条件不满足 | 审批未通过、DEV transport 未全部释放、任务未关闭、无 CD 却 `START_PROGRESS` |
| `VALIDATION_ERROR` | 400 | 参数 / 必填校验失败 | 驳回无意见、取消无原因、缺少计划时间、缺少写请求头 |
| `FORBIDDEN` | 403 | 角色 / 数据范围不允许 | 开发执行 `CLOSE`、跨组件读取 |
| `APPROVER_MISMATCH` | 403 | 非当前步骤审批人 | 越过当前步骤审批 |
| `SELF_APPROVAL` | 403 | 请求人不能审批自己 | 请求人点通过 |
| `CONCURRENT_MODIFICATION` | 409 | 版本冲突 | `version` 不匹配 |
| `OBJECT_LOCKED` | 409 | SAP 锁占用 | 锁等待超时 |
| `DUPLICATE_LINK` | 409 | transport 已关联其他 CD | 重复关联 |
| `SCHEDULE_CONFLICT` | 409 | 计划冲突 / 已存在生效计划 | 重复建计划、改期冲突 |
| `CTS_READ_ERROR` | 502 | CTS 读取失败（降级为未知） | `E070` / TMS 读取异常 |
| `NOT_FOUND` | 404 | 对象不存在 | CR / CD / 任务 / transport / 计划不存在 |
| `NUMBER_RANGE_ERROR` | 500 | 号段取号失败 | `NRIV` 区间缺失 |
| `INTERNAL_ERROR` | 500 | 未分类错误 | 未捕获异常 |

**区分原则**：

- `INVALID_TRANSITION` = 「这个状态根本不允许这个动作」（状态机层判定）。
- `GUARD_FAILED` = 「状态允许，但前置条件没满足」（守卫层判定），`details.missing` 列出缺失守卫项。
- `VALIDATION_ERROR` = 「请求本身不合法」，前端应做字段级内联提示。

### 10.3 幂等与并发

- 写请求带 `version`；不匹配 → `CONCURRENT_MODIFICATION`，前端提示「记录已被他人修改」并刷新，不静默覆盖。
- 关键动作加 `EZCRW_REQ` / `EZCRW_CD` 锁；锁等待超时 → `OBJECT_LOCKED`。
- 动作重复提交且状态已变化 → `INVALID_TRANSITION`，不写重复历史 / 审批步骤。
- 一个写请求一个 LUW：任一校验失败整体回滚，不产生部分写入。

### 10.4 降级

- CTS 读取失败：返回业务数据 + 「未知」状态 + `SYNC_STATE = ERROR`，写日志；不阻塞 CR / CD / 任务流程。
- 号段不可用：阻塞创建类动作（`NUMBER_RANGE_ERROR`），提示管理员执行 bootstrap / 检查 `NRIV`。
- 配置缺失（无审批矩阵 / 无管理员角色）：selfcheck 报 `CRW_SELFCHECK_FAIL`；运行时拒绝需审批的动作并提示执行 bootstrap。

### 10.5 前端处理约定

| HTTP / code | 前端行为 |
|---|---|
| 400 `VALIDATION_ERROR` | 字段级内联提示；不提交 |
| 401 | 按 ICF 认证过程处理（重定向或提示重新登录，**待定** W27） |
| 403 `FORBIDDEN` / `APPROVER_MISMATCH` / `SELF_APPROVAL` | 提示无权限；刷新动作条 |
| 404 `NOT_FOUND` | 提示对象不存在 / 已删除；返回列表 |
| 409 `CONCURRENT_MODIFICATION` / `OBJECT_LOCKED` | 提示记录已变化，刷新后重试 |
| 409 `INVALID_TRANSITION` / `GUARD_FAILED` | 展示 `details.missing` 对应原因，刷新状态 |
| 502 `CTS_READ_ERROR` | 展示「状态未知，请到 STMS 确认」，不阻塞其它操作 |
| 500 | 通用错误 + 展示 `correlationId`，允许重试 |

### 10.6 消息类映射

`ZCRW_MSG` 8 条消息与 API 错误码的对应（`message` 取消息文本）：

| 消息 | 文本 | API code |
|---|---|---|
| 001 | Change request &1 not found | `NOT_FOUND` |
| 002 | Invalid status transition: &1 -> &2 | `INVALID_TRANSITION` |
| 003 | Approval required before action &1 | `GUARD_FAILED` |
| 004 | Transport request &1 not found | `NOT_FOUND` |
| 005 | No authorization for action &1 | `FORBIDDEN` |
| 006 | Change document &1 not found | `NOT_FOUND` |
| 007 | Task &1 not found | `NOT_FOUND` |
| 008 | Import schedule &1 not found | `NOT_FOUND` |

- 消息类只覆盖高频错误；其余错误码由 `ZCX_CRW_ERROR` 的 `MV_CODE` 映射（`NR_*` → `NUMBER_RANGE_ERROR`，未映射 → `INTERNAL_ERROR`）。

---

## 11. 端到端流程

### 11.1 标准变更（STD）

| # | 角色 | 动作 | 状态变化 | 审计 / 副作用 |
|---|---|---|---|---|
| 1 | 请求人 | `POST /requests` | — → CR `NEW` | 历史：`CREATE_REQ` |
| 2 | 请求人 | CR `SUBMIT` | `NEW → PENDING_APPROVAL` | 生成 CR 审批步骤；历史：`SUBMIT` |
| 3 | 变更经理 | CR `APPROVE_STEP`（末步） | `PENDING_APPROVAL → APPROVED` | 审批 `APPROVED`；历史：`APPROVE_STEP` |
| 4 | 变更经理 | `POST /requests/{id}/change-documents` | — → CD `NEW` | 历史：`CREATE_CD` |
| 5 | 变更经理 | CR `START_PROGRESS` | `APPROVED → IN_PROGRESS` | 历史：`START_PROGRESS` |
| 6 | 变更经理 / 开发 | CD `START_DEV` | `NEW → IN_DEV` | 可建开发任务；历史：`START_DEV` |
| 7 | 开发 | 关联 DEV transport（`POST /transports/link`） | — | `ZCRW_TR` 快照；历史：`LINK_TR` |
| 8 | 开发 | 关闭开发任务 / 子任务 | 任务 `DONE` | 历史：`DONE` |
| 9 | 开发 | CD `SUBMIT_TEST` | `IN_DEV → IN_TEST` | 守卫：开发任务全关闭 + ≥1 DEV transport；历史 |
| 10 | 测试 | CD `PASS_TEST` | `IN_TEST → IN_TEST` | 记录测试结论；关闭测试任务；历史 |
| 11 | 变更经理 | CD `SUBMIT_APPROVAL` | `IN_TEST → IN_TEST` | 生成 CD 导入审批步骤；历史 |
| 12 | 变更经理 | CD 审批通过 | `IN_TEST → IN_TEST` | 审批 `APPROVED`；历史 |
| 13 | 发布管理员 | CD `MARK_READY` | `IN_TEST → READY_TO_IMPORT` | 守卫：测试通过 + 审批通过 + DEV transport 全释放 |
| 14 | 发布管理员 | CD `SCHEDULE_IMPORT` | `READY_TO_IMPORT → IMPORT_SCHEDULED` | 写 `ZCRW_SCHED`；历史 |
| 15 | 发布管理员 | 在 STMS 导入（应用外）→ CD `CONFIRM_IMPORT` | `IMPORT_SCHEDULED → IMPORTED` | 写导入时间；计划 `DONE`；历史 |
| 16 | 变更经理 | CD `CLOSE` | `IMPORTED → CLOSED` | 守卫：任务全关闭；历史 |
| 17 | 变更经理 | CR `CLOSE` | `IN_PROGRESS → CLOSED` | 守卫：所有 CD 关闭 / 取消；历史 |

### 11.2 紧急变更（URG，P1）

1. CR 标记 `URG`，可跳过事前审批（规划口径，具体跳过方式**待定** W20）。
2. 直接建 CD，走 ToC：`POST /transports/link` 且 `trKind = TOC`。
3. 计划导入时间可提前；`SCHEDULE_IMPORT` → `IMPORT_SCHEDULED`。
4. 在 STMS 导入（应用外）→ `CONFIRM_IMPORT`。
5. 生产导入后必须补审批与复盘记录；`RETROFIT_STATE` 标记（P1）。
6. 逾期未补审进入「待补审」报表（P1）。

### 11.3 管理变更（ADM，P2）

1. CR 标记 `ADM`，不产生 transport。
2. 用检查清单代替传输关联；清单模型规划未定义（**待定** W28）。
3. 关闭时校验清单完成；其余审批与关闭流程同 `STD`。

---

## 12. 待定问题与 v1 决议（W1–W30，已冻结）

| 编号 | 问题 | v1 决议（已冻结） | 实施里程碑 |
|---|---|---|---|
| W1 | CR 类型创建后是否可改、终态后是否可重开并关联原请求（影响：流程完整性） | CR 类型创建后不可修改；终态不复用、不重开；新 CR 在 `DESCRIPTION` 说明关联 | M2 |
| W2 | CR `SUBMIT` 的必填字段集合（影响：表单校验、API 契约） | 必填：`REQ_TYPE` / `TITLE` / `PRIORITY` / `COMPONENT` / `PLANNED_START` / `PLANNED_END`；`DESCRIPTION` 选填 | M2 |
| W3 | 头部 `APPROVAL_STATE` 取值集合（影响：审批联动、列表过滤） | 取值为 `NONE` / `PENDING` / `APPROVED` / `REJECTED` / `SKIPPED`：创建 `NONE`；`SUBMIT` / `SUBMIT_APPROVAL` 置 `PENDING`；末步通过 `APPROVED`；驳回 `REJECTED`；撤回回 `NONE` 且未决步骤 `SKIPPED`；取消时 `PENDING`→`SKIPPED`，否则保留 | M1 |
| W4 | CD `START_DEV` 是否自动创建开发任务（影响：交互、任务生成） | `START_DEV` 不自动创建任务（任务显式创建） | M2 |
| W5 | `CONFIRM_IMPORT` 的允许来源态（影响：状态机严谨性） | 允许来源 `READY_TO_IMPORT` / `IMPORT_SCHEDULED`；`IMPORTED` 重复提交与其他状态均 `INVALID_TRANSITION` | M3 |
| W6 | CD 审批「可配置为关闭」的配置键与默认值（影响：审批开关） | 由审批矩阵表达：无匹配 CD 步骤 = 免审批（`SUBMIT_APPROVAL` 直接 `APPROVED` 并写历史）；bootstrap 默认种 CD/STD 1 步（`CHANGE_MANAGER`） | M2 |
| W7 | `CANCELLED` 任务是否满足父任务 / CD 关闭条件（影响：关闭守卫） | `CANCELLED` 视为终止，满足父任务 `DONE` 与 CD `CLOSE` 守卫 | M2 |
| W8 | `REOPEN` 可重开的状态与次数（影响：任务生命周期） | v1 不实现（P1） | P1 |
| W9 | `IMPORT` 类型任务是否为 `CONFIRM_IMPORT` 的强制条件（影响：流程完整性） | `IMPORT` 类型任务不强制；`CONFIRM_IMPORT` 不校验导入任务 | M3 |
| W10 | 角色编码集合、优先级编码集合与审批矩阵通配约定（影响：鉴权、矩阵匹配） | 角色编码固定为 `REQUESTER` / `CHANGE_MANAGER` / `DEVELOPER` / `TESTER` / `RELEASE_MANAGER` / `ADMIN`（`VIEWER` P2）；优先级码 `1` 紧急 / `2` 高 / `3` 中 / `4` 低 / 空 = 未定；审批矩阵匹配字段为空 = 通配（`PRIORITY` 空 = 任意） | M2 |
| W11 | `ZCRW_APPR_CFG.MANDATORY` 空值语义（影响：审批推进） | `MANDATORY = 'X'` 为强制；空 = 可选，`CHANGE_MANAGER` / `ADMIN` 可 `SKIP_STEP` 跳过；v1 实现 `SKIP_STEP` | M2 |
| W12 | 步骤「任意一人 / 全部」通过规则的存储字段（影响：审批正确性） | v1 固定「任意一人」（`ANY`）：同一角色解析多人时每人生成一条 `PENDING` 步骤，任一人决策后同步骤其余置 `SKIPPED`；`ALL` 规则 P1（需新字段） | M2 |
| W13 | 驳回后未决步骤置 `SKIPPED` 还是保留 `PENDING`（影响：审批查询、历史） | 驳回后未决步骤置 `SKIPPED` | M2 |
| W14 | 审批决策是否携带对象 `version`（影响：并发控制） | 审批决策携带对象 `version`，不匹配返回 `CONCURRENT_MODIFICATION` | M2 |
| W15 | 审批人缺失 / 离职时的改派与矩阵调整流程（影响：运维） | v1 无审批改派 UI；人员变化通过角色解析自动生效；固定 `APPROVER_USER` 的改派 P2 | P1 |
| W16 | `ZCRW_TR.SYNC_STATE` 取值集合（影响：降级展示、报表筛选） | `OK` / `ERROR` / `DETACHED` / `UNKNOWN`（未同步） | M3 |
| W17 | ToC 业务状态是否需要独立字段（影响：数据模型） | 不新增 ToC 独立状态字段；由 `TR_STATUS` + `ZCRW_SCHED` + `IMPORTED_AT` 派生展示 | M3 |
| W18 | 非状态动作的 `ACTION` 编码清单（影响：审计契约） | 编码固定为 `CREATE` / `UPDATE` / `SUBMIT` / `WITHDRAW` / `APPROVE_STEP` / `REJECT` / `SKIP_STEP` / `REVISE` / `START_PROGRESS` / `CLOSE` / `CANCEL` / `START` / `DONE` / `CREATE_CD` / `CREATE_TASK` / `CREATE_SUBTASK` / `LINK_TR` / `UNLINK_TR` / `MARK_DETACHED` / `SYNC_TR` / `SCHEDULE_CREATE` / `SCHEDULE_UPDATE` / `SCHEDULE_CANCEL` / `CONFIRM_IMPORT` / `CREATE_NOTE` | M2 |
| W19 | 解绑后 `CD_ID` 置空还是保留标记（影响：数据一致性、审计） | unlink 置 `CD_ID` 为空（历史保留原关联）；mark-detached 不置空，置 `SYNC_STATE = DETACHED` | M3 |
| W20 | URG 跳过事前审批的方式与事后补审时限（影响：紧急变更流程） | URG v1 仍走审批；矩阵无匹配步骤 = 免事前审批；事后补审 P2 | P2 |
| W21 | CTS 读取失败时按端点返回 502 还是降级数据（影响：API 契约） | 列表 / 详情返回降级数据 + `degraded=true`（不返回 502）；`POST /transports/sync` 失败返回 `CTS_READ_ERROR`(502) | M3 |
| W22 | `MISSED` 计算的时区基准（影响：逾期准确性） | 按 SAP 系统本地时间计算（与 architecture D16 一致） | M3 |
| W23 | 计划冲突判定规则（影响：计划校验） | v1 只校验同一对象（重复生效计划）；跨对象时间窗冲突不校验（P1） | M3 |
| W24 | `ZCRW_CD.PLANNED_IMPORT_AT` 与 `ZCRW_SCHED` 的权威关系（影响：数据一致性） | `ZCRW_SCHED` 为权威；`ZCRW_CD.PLANNED_IMPORT_AT` 只是快照，创建 / 改期 / 取消计划时同步（取消清空） | M3 |
| W25 | `ZCRW_HIST.OBJECT_TYPE` 是否包含 `NOTE`（影响：审计范围） | 不含 `NOTE`（备注自身留痕） | M2 |
| W26 | 历史长文本（> 255）截断规则（影响：审计完整性） | 长文本入参超过 255 字符返回 `VALIDATION_ERROR`，不静默截断；服务端拼接文本超长时截断 255 | M2 |
| W27 | 未登录时 API 的 401 行为（影响：前端处理） | `/api/v1/*` 返回 JSON 401（`UNAUTHORIZED`）；页面路由由 ICF 登录过程重定向；M1 实测确认 | M1 |
| W28 | ADM 检查清单的数据模型（影响：ADM 流程） | P2，不建表 | P2 |
| W29 | 任务动作的角色细化、跨 CD 移动、父任务取消是否级联子任务（影响：任务流程严谨性） | `START` / `DONE` = assignee + `DEVELOPER` / `TESTER` / `CHANGE_MANAGER` / `ADMIN`；`CANCEL` = `CHANGE_MANAGER` / `ADMIN`（或父任务负责人）；不允许跨 CD 移动；父任务取消不级联子任务；子任务 `CANCELLED` 满足父 `DONE` 守卫 | M2 |
| W30 | `NEW` 状态 CR 的删除语义（影响：数据完整性、审计） | 同 W1 口径：不提供物理 / 软删除 API；`NEW` 只能 `CANCEL`（原因必填）；审计只追加 | M2 |

---

## 13. 参考

- [CRW 规划](../../../docs/change-request-workbench-plan.md)：§4.5 关键不变量、§5 流程与状态机、§7.4 事务与并发、§8.4 错误码。
- [architecture.md](architecture.md)：数据模型、API 契约、部署、安全、版本与升级。
- [README](../README.md)：当前状态与验证命令。
- [`AGENTS.md`](../../../AGENTS.md) §4A：应用单元契约。
