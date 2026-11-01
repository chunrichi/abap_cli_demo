# 变更请求工作台（CRW）· 需求与实施规划

> 状态：规划草案 v9（2026-11-02）。D1–D25 已确认（D24/D25 为 P2 通知增补）；M0 核心验证通过（NROB/MSAG 已修复）；M1–M5 已交付（M5 = P2 站内通知中心 + 提醒报表）；其余 P2 项见 §12.3 / 附录 C。
> 定位：**真实应用**，不是 demo。对象、包、升级、权限均按产品标准处理；与 [`AGENTS.md`](../AGENTS.md) 的 demo 契约差异见 §10.4。
> 技术形态参考 [`demos/01-icf-mime-stats`](../demos/01-icf-mime-stats/README.md)：ICF 节点 + JSON API + MIME 静态单页，本应用沿用并扩展。
> 文中的 ChaRM 指 SAP Solution Manager 的 Change Request Management，仅作功能参照；本应用不复用其产品名，也不追求完整对标。

## 1. 一页摘要

- **做什么**：在 SAP 内建一个变更请求工作台，管理「Change Request → Change Document → Task / SubTask → Transport（含 ToC）→ 测试 → 计划导入 → 关闭」全流程，提供工作清单、详情、审批、传输视图、导入计划、仪表盘、报表和审计。
- **谁用**：请求人、变更经理（审批）、开发、测试、发布管理员、管理员。
- **形态**：ABAP 后端（DDIC + 服务类 + ICF JSON API + CTS 只读集成 + 站内通知）+ MIME 托管的原生单页前端；事务码 `ZCRW` 进入。
- **已确认**：产品名 `CRW`；仓库放 `apps/change-request-workbench/`；一期做 CR→CD→Task/SubTask、ToC、定时导入计划；CTS 做只读集成、不做 live 验证；UI 用 ICF + 原生 SPA；demo 路线图保留。
- **写路径**：`$CRW` 本地包支持已在 abap-cli 2.0.x 落地（本地仓库 commit `3dd443d`，内置 ICF 服务同步升级）；create / push / run / delete / DDIC 写路径均已验证。
- **M0 状态**：写路径、DDIC、`/ui2/cl_json`、ABAP Unit、CTS 只读、NROB、MSAG、ENQU 均已通过；NROB/MSAG 的 CLI 修复已 live 验证（附录 B.4）；ICF 节点 / MIME / 事务码 / ICF 认证留到 M1 与前端一起验证。
- **M1 进度（历史）**：13 张表 + 3 个号段 + 消息类 + 2 个锁对象已建；`ZCL_CRW_UTIL` / `ZCL_CRW_NUMBER` / `ZCL_CRW_AUDIT` / `ZCL_CRW_REQUEST_SVC` / `ZCL_CRW_CD_SVC` / `ZCL_CRW_TASK_SVC` / `ZCL_CRW_BOOTSTRAP` / `ZCL_CRW_SELFCHECK` / `ZCX_CRW_ERROR` 已建并验证（bootstrap 幂等、selfcheck 通过、UTIL 单测 4/4、M1 SMOKE 端到端通过且自动清理）；API/前端待做。
- **M5 进度（2026-11-02）**：14 张表（新增 `ZCRW_NOTIFY`）、通知服务 `ZCL_CRW_NOTIFY` / 控制器 `ZCL_CRW_API_NOTIFY`、`/notifications*` API、顶栏铃铛 + `#/notifications` 页面、提醒报表 `ZCRW_REMIND_JOB`（SM36 由 basis 配置，本轮不建）、版本 1.2.0；邮件通道仅预留（SMTP 未配置，不发信）。P2 basis 类项（包迁移 / 索引 / 归档 / 权限 / Fiori）只出设计，见 [`p2-basis.md`](../apps/change-request-workbench/docs/p2-basis.md)。
- **怎么交付**：M0 决策与验证 → M1 数据模型与骨架 → M2 流程闭环 → M3 传输/ToC/计划 → M4 报表与产品化 → M5 通知与提醒；每阶段有可机器判定的验收。
- **已确认口径**：D8 = CTS 只读 + 手工关联、不做 live 验证；D9 = 计划导入 + 提醒、不执行 TMS 导入；D10 = CLI 升级到 2.0.x（`$` 本地包支持，已合并）。见 §12。

## 2. 背景与定位

### 2.1 要解决的问题

以下为基于常见 SAP 开发团队情况的假设，M1 开始前用试点访谈确认；若与实际不符，调整功能优先级：

1. 变更请求靠邮件/IM/Excel 流转，状态不可查，无法回答「这个需求现在到哪了」。
2. 开发直接建 transport，业务请求与传输请求没有关联，发布清单靠人工整理。
3. 审批留痕缺失：谁批的、什么时候批的、批的什么范围都说不清。
4. 测试结论、导入结果、驳回原因散落在聊天记录里，审计追溯成本高。
5. 缺少「我的待办 / 待审批 / 待导入 / 我的任务」的统一入口，管理靠人盯。

### 2.2 与 ChaRM 的关系

只取 ChaRM 的**骨架**：Change Request、Change Document、Task、Transport（含 ToC）、审批、状态生命周期、计划导入、审计；不复制其平台化能力（项目周期阶段模型、TMS 调度执行、retrofit / downgrade protection、工作流引擎、SAP Cloud ALM 集成）。完整对照见[附录 A](#附录-a与-sap-charm-的功能对照)。

### 2.3 非目标

- 不替代 Solution Manager / Cloud ALM，不做跨系统、跨 client 的发布编排。
- 不在应用内释放 transport 或执行 TMS 导入（只读展示状态，写操作仍在 SE01/STMS）。
- 不实现 retrofit / downgrade protection / 传输依赖自动修复；ToC 导入后的补做仅做「提醒 + 标记」。
- 不做通用 BPM 引擎；审批矩阵是「按类型 + 优先级」的固定步骤。
- 不做自定义权限对象（abap-cli 不支持 AUTH），用应用角色表 + 标准权限检查，生产级自定义权限走人工配置。
- 不做移动端、附件与全文检索（P2）。
- 不碰生产系统写入；应用部署按「DEV 开发 → QA 验证 → 生产由 basis 安装」的常规流程。

### 2.4 角色

| 角色 | 能做什么 | 数据范围 | 一期 |
|---|---|---|---|
| 请求人 Requester | 新建/编辑/提交/撤回自己的请求，补充说明，查看进度 | 自己的请求 | P0 |
| 变更经理 Change Manager | 审批/驳回、指派 Owner、调整优先级与计划、关闭异常 | 全部请求 | P0 |
| 开发 Developer | 接任务/子任务、推进 CD 开发/测试状态、关联 transport | 指派给本人的任务/CD | P0 |
| 测试 Tester | 执行测试、记录结论、驳回 | 指派给本人的测试任务 | P0 |
| 发布管理员 Release Manager | 维护 transport 状态、确认导入、维护导入计划 | 全部 transport 与计划 | P0 |
| 管理员 Admin | 角色分配、配置、号段、初始化、迁移、审计导出 | 全部 | P0 |
| 观察者 Viewer | 只读查看报表与请求 | 按组件/周期 | P2 |

### 2.5 典型场景

**标准变更**：开发提交 CR，填写组件、影响说明、计划窗口；变更经理审批通过并指派变更负责人；负责人建 CD（可来自模板），拆 Task/SubTask 分派给开发；开发把 SE01/CLI 创建的 transport 关联到 CD/任务；测试通过后设「计划导入时间」，发布管理员在 STMS 导入并确认；CD 关闭，CR 全部 CD 关闭后自动关闭；全程历史可查。

**紧急变更**（P1）：CR 标记 `URG`，可跳过事前审批，走 ToC：ToC 关联到 CD、计划导入时间可提前；生产导入后必须补审批与复盘记录；逾期进入「待补审」报表。

**管理变更**（P2）：不产生 transport 的配置类变更，用检查清单代替传输关联，关闭时校验清单完成。

### 2.6 为什么按产品做，而不是 demo

- 命名不带 `NN` 序号、不带 `DMA`，避免后续改名与传播成本。
- 对象用专用包、有版本与迁移、有真实用户和试点，而不是 `$TMP` 删除重建。
- 有配置数据、业务数据、权限、审计、运维手册，demo 契约不覆盖。
- 验收从「跑通一次」升级为「可安装、可升级、可运维、有审计、有试点」。

### 2.7 成功标准

- 标准变更 100% 在工作台有记录，审批不再走邮件。
- 「我的待办」「待审批」「待导入」「本周导入计划」可直接用于日常站会。
- 发布前可在传输工作台生成完整的「本周期导入清单」。
- 任一请求可在 1 分钟内导出完整审计链（谁、何时、做了什么、为什么）。

## 3. 功能清单

优先级：P0 一期必做；P1 二期；P2 按试点反馈再排。

| 模块 | 功能点 | 优先级 | 说明 |
|---|---|---|---|
| 请求 CR | 新建/编辑/提交/撤回/复制 | P0 | 表单校验、必填项、影响说明 |
| 请求 CR | 列表：筛选、排序、分页、列配置、保存视图 | P0 | 服务端过滤与分页 |
| 请求 CR | 详情：头部、描述、状态时间线、CD 汇总 | P0 | 深链可分享 |
| 变更文档 CD | 创建/编辑/取消，按 CR 汇总 | P0 | 一个 CR 可多 CD（按批次/周期） |
| 变更文档 CD | 状态机、开发/测试/待导入/计划导入/已导入/关闭 | P0 | 见 §5 |
| 任务 | Task / SubTask 创建、指派、改期、状态、我的任务 | P0 | 层级最多两级 |
| 任务 | 任务板视图（按状态列） | P1 | 便于站会 |
| 审批 | CR 审批 + CD 导入前审批；审批矩阵、我的待办 | P0 | 固定步骤 |
| 审批 | 转交/代理、超时提醒 | P1/P2 | |
| 传输 | 手工关联 DEV transport、状态快照、解绑（受限） | P0 | transport 在 SE01/CLI 创建 |
| 传输 | ToC 关联、导入状态、retrofit 提醒（标记） | P0/P1 | 不创建/释放/导入 |
| 传输 | 同步 CTS 状态、传输工作台、未关联告警 | P0/P1 | 只读 E070/E071/TMS |
| 定时导入 | 计划导入时间/窗口、导入日程视图、到点/逾期提醒 | P0 | 见 D9；不执行 TMS 导入 |
| 周期 | 变更窗口/周期维护、按周期筛选 | P1 | Change cycle 的轻量替代 |
| 工作台 | 首页 KPI、趋势、最近动态、快捷入口 | P0/P1 | KPI P0，图表 P1 |
| 报表 | 分布、时效、逾期、审批时长、传输漏斗 | P1 | CSV 导出 P1 |
| 配置 | 类型/审批矩阵/角色/周期维护界面 | P1/P2 | 一期用初始化程序 + 表 |
| 通知 | 站内待办、逾期与计划到期提醒 | P0/P1（已落地） | 顶栏铃铛 + `#/notifications`；审批 / 驳回 / 逾期任务 / 逾期计划；`dedup_key` 去重；邮件 P2（需 basis 配 SMTP） |
| 管理 | 配置初始化、演示数据、版本迁移、健康检查 | P0 | classrun 程序 |
| 权限 | 应用角色 + 服务端校验；标准权限检查 | P0/P1 | 自定义 AUTH 对象 P2（人工） |
| API | REST v1、统一错误信封、分页 | P0 | 见 §8 |
| 导出 | CSV 导出（列表/报表/审计） | P1 | |
| 附件 | 请求附件、截图 | P2 | 表存 xstring，有大小限制 |
| 国际化 | 中文 UI，代码英文；英文 UI | P2 | |

## 4. 领域模型

### 4.1 聚合关系

```
Cycle ──< Change Request ──< Change Document ──< Task ──< SubTask
                                    │              │
                                    ├──< TransportLink（DEV / ToC，引用 E070/E071，只读快照）
                                    └──< ImportSchedule（计划导入时间/窗口）
Change Request / Change Document ──< Approval
Change Request / Change Document / Task ──< History / Note
User ──< RoleAssignment（全局 / 组件 / 周期）
Config：RequestType / ApprovalMatrix / Cycle
```

### 4.2 主要实体（已落地 AFF）

已落地到 `apps/change-request-workbench/src/`，并在 `$CRW` 完成建表（M5 起 **14 张表**；M5 前为 13 张）。受 abap-cli 2.0.0 建表 ICF 约束（enhancement category 固定为 char 类型，见 B.4-3），字段类型只用 `CHAR` / `NUMC` / `DATS` / `TIMS`：时间戳用 `CHAR14`（`YYYYMMDDHHMMSS`）、GUID 用 `CHAR32`、版本用 `NUMC6`、工时用 `NUMC5`。

| 表 | 用途 | 关键字段（除 MANDT 外） | 键 |
|---|---|---|---|
| `ZCRW_REQ` | 请求头（CR） | `REQ_ID`(CHAR10)、`REQ_TYPE`(CHAR4：STD/URG/ADM)、`TITLE`(CHAR80)、`DESCRIPTION`(CHAR255)、`STATUS`(CHAR20)、`PRIORITY`(CHAR2)、`COMPONENT`(CHAR20)、`CYCLE_ID`(CHAR16)、`REQUESTER`/`OWNER`(CHAR12)、`APPROVAL_STATE`(CHAR10)、`PLANNED_START`/`PLANNED_END`/`DUE_DATE`(DATS)、`VERSION`(NUMC6)、`CREATED_AT`/`CHANGED_AT`/`CLOSED_AT`(CHAR14)、`CREATED_BY`/`CHANGED_BY`(CHAR12)、`CANCEL_REASON`(CHAR80) | 主键 `REQ_ID` |
| `ZCRW_CD` | 变更文档（技术批次） | `CD_ID`(CHAR10)、`REQ_ID`、`CYCLE_ID`、`TITLE`(CHAR80)、`STATUS`(CHAR20)、`OWNER`/`DEV_LEAD`/`TEST_LEAD`(CHAR12)、`TARGET_SYS`(CHAR10)、`PLANNED_IMPORT_AT`(CHAR14)、`APPROVAL_STATE`(CHAR10)、`VERSION`(NUMC6)、`CREATED_AT`/`CHANGED_AT`/`CLOSED_AT`(CHAR14)、`CREATED_BY`/`CHANGED_BY`(CHAR12) | 主键 `CD_ID` |
| `ZCRW_TASK` | 任务/子任务 | `TASK_ID`(CHAR10)、`REQ_ID`、`CD_ID`、`PARENT_TASK_ID`(CHAR10，空=Task)、`TASK_LEVEL`(CHAR1：T/S)、`TASK_TYPE`(CHAR10：DEV/TEST/IMPORT/RETROFIT)、`TITLE`(CHAR80)、`ASSIGNEE`(CHAR12)、`STATUS`(CHAR20)、`DUE_DATE`(DATS)、`EST_HOURS`(NUMC5)、`VERSION`(NUMC6)、`CREATED_AT`/`CHANGED_AT`(CHAR14)、`CREATED_BY`/`CHANGED_BY`(CHAR12) | 主键 `TASK_ID` |
| `ZCRW_TR` | 传输关联与状态快照 | `TRKORR`(CHAR10)、`CD_ID`、`TASK_ID`、`TR_KIND`(CHAR10：DEV/TOC)、`TARSYSTEM`(CHAR10)、`TR_STATUS`(CHAR1)、`TR_STATUS_TXT`(CHAR30)、`RELEASED_AT`/`IMPORT_SCHEDULED_AT`/`IMPORTED_AT`/`LAST_SYNC_AT`/`LINKED_AT`(CHAR14)、`RETROFIT_STATE`(CHAR10：NA/PENDING/DONE)、`SYNC_STATE`(CHAR10)、`LINKED_BY`(CHAR12)、`DESCRIPTION`(CHAR60) | 主键 `TRKORR` |
| `ZCRW_SCHED` | 导入计划 | `SCHED_ID`(CHAR32)、`OBJECT_TYPE`(CHAR10：CD/TOC)、`OBJECT_ID`(CHAR20)、`TARGET_SYS`(CHAR10)、`SCHEDULED_AT`(CHAR14)、`STATUS`(CHAR10：PLANNED/DONE/MISSED/CANCELLED)、`NOTE`(CHAR255)、`CREATED_AT`/`CHANGED_AT`(CHAR14)、`CREATED_BY`/`CHANGED_BY`(CHAR12) | 主键 `SCHED_ID` |
| `ZCRW_APPR` | 审批步骤实例 | `APPR_ID`(CHAR32)、`OBJECT_TYPE`(CHAR10：REQ/CD)、`OBJECT_ID`(CHAR10)、`STEP_NO`(NUMC2)、`APPROVER`(CHAR12)、`APPR_STATE`(CHAR10：PENDING/APPROVED/REJECTED/SKIPPED)、`DECIDED_AT`(CHAR14)、`COMMENT_TXT`(CHAR255)、`CREATED_AT`(CHAR14) | 主键 `APPR_ID` |
| `ZCRW_HIST` | 审计/历史（只追加） | `HIST_ID`(CHAR32)、`OBJECT_TYPE`、`OBJECT_ID`、`ACTION`(CHAR30)、`FIELD`(CHAR30)、`OLD_VALUE`/`NEW_VALUE`(CHAR255)、`COMMENT_TXT`(CHAR255)、`CHANGED_BY`(CHAR12)、`CHANGED_AT`(CHAR14)、`SOURCE`(CHAR10：UI/API/SYNC) | 主键 `HIST_ID` |
| `ZCRW_NOTE` | 备注/评论 | `NOTE_ID`(CHAR32)、`OBJECT_TYPE`、`OBJECT_ID`、`AUTHOR`(CHAR12)、`TEXT`(CHAR255)、`CREATED_AT`(CHAR14)、`VISIBILITY`(CHAR10) | 主键 `NOTE_ID` |
| `ZCRW_CYCLE` | 变更窗口/周期 | `CYCLE_ID`(CHAR16)、`DESCRIPTION`(CHAR60)、`START_DATE`/`END_DATE`/`FREEZE_DATE`(DATS)、`STATUS`(CHAR10)、`TARGET_SYS`(CHAR10) | 主键 `CYCLE_ID` |
| `ZCRW_ROLE` | 应用角色分配 | `USER_ID`(CHAR12)、`ROLE`(CHAR20)、`SCOPE_TYPE`(CHAR10：GLOBAL/COMPONENT/CYCLE)、`SCOPE_ID`(CHAR20)、`VALID_FROM`/`VALID_TO`(DATS) | 主键 `USER_ID`+`ROLE`+`SCOPE_TYPE`+`SCOPE_ID` |
| `ZCRW_APPR_CFG` | 审批矩阵 | `PROFILE_ID`(CHAR20)、`STEP_NO`(NUMC2)、`APPROVER_ROLE`(CHAR20)、`APPROVER_USER`(CHAR12)、`OBJECT_TYPE`(CHAR10：REQ/CD)、`REQ_TYPE`(CHAR4)、`PRIORITY`(CHAR2)、`MANDATORY`(CHAR1) | 主键 `PROFILE_ID`+`STEP_NO` |
| `ZCRW_VERSION` | 版本/迁移记录 | `COMPONENT`(CHAR20)、`VERSION_NO`(CHAR10)、`APPLIED_AT`(CHAR14)、`APPLIED_BY`(CHAR12)、`TRANSPORT`(CHAR10)、`NOTES`(CHAR255) | 主键 `COMPONENT`+`VERSION_NO` |
| `ZCRW_LOG` | 应用日志 | `LOG_ID`(CHAR32)、`TIMESTAMP`(CHAR14)、`USER_ID`(CHAR12)、`AREA`(CHAR20)、`SEVERITY`(CHAR10)、`MESSAGE`(CHAR255)、`CONTEXT`(CHAR255)、`CORRELATION_ID`(CHAR32) | 主键 `LOG_ID` |
| `ZCRW_NOTIFY` | 站内通知（M5） | `NOTIFY_ID`(CHAR32)、`USER_ID`(CHAR12)、`NOTIFY_TYPE`(CHAR20：APPROVAL_PENDING/APPROVAL_REJECTED/TASK_OVERDUE/SCHED_OVERDUE/INFO)、`OBJECT_TYPE`(CHAR10)、`OBJECT_ID`(CHAR20)、`TITLE`(CHAR80)、`MESSAGE`(CHAR255)、`LINK_PAGE`(CHAR80)、`SEVERITY`(CHAR10：INFO/WARN/CRITICAL)、`STATUS`(CHAR10：UNREAD/READ/DISMISSED)、`DEDUP_KEY`(CHAR80)、`SOURCE`(CHAR10：EVENT/SCAN/API)、`CREATED_AT`(CHAR14)、`CREATED_BY`(CHAR12)、`READ_AT`(CHAR14) | 主键 `NOTIFY_ID` |

- **锁对象**：`EZCRW_REQ`（主表 `ZCRW_REQ`）、`EZCRW_CD`（主表 `ZCRW_CD`），均已建。原计划的通用 `EZCRW_OBJ` 改为两个专用锁对象（ENQU 参数来自主表主键，比通用锁表简单）。
- **二级索引**：abap-cli 2.0.0 没有建索引入口；M1 先用主键查询，性能阶段（P1）再通过 SAP GUI / 后续 CLI 支持补索引。
- P2：`ZCRW_ATTACH`（附件）、`ZCRW_CFG_*` 细分配置表。

### 4.3 编号策略

- 业务主键用**号段 + 可读编号**，不用 GUID 直接暴露给用户：
  - 请求 CR：号段 `ZCRW_REQ`，CHAR10 零填充，UI 显示 `CR-0000000123`。
  - 变更文档 CD：号段 `ZCRW_CD`，UI 显示 `CD-0000000123`。
  - 任务/子任务：号段 `ZCRW_TASK`，UI 显示 `T-000000045` / `ST-000000046`（前缀由 `TASK_LEVEL` 决定）。
  - 审批/历史/备注/计划：`CHAR32` GUID（UUID C32）。
- 号段对象用 CLI 类型 `NROB` 创建；号段区间在初始化程序里用标准 FM 维护（M0 验证；不行则 runbook 写 SNRO 手工步骤）。
- 不做「按类型分号段」；类型体现在展示层前缀，避免号段爆炸。

### 4.4 配置模型

- 可配置（表）：请求类型、审批矩阵、周期、角色。
- 一期写死（代码常量 + 迁移程序管理）：状态集合、状态迁移、守卫规则。理由：状态机是应用核心逻辑，过早做成配置会放大测试面；P2 再评估是否把迁移表放到 `ZCRW_CFG_TRANS` + 管理 UI。
- 配置初始化程序 `ZCL_CRW_BOOTSTRAP` 幂等：插入默认类型、审批矩阵、管理员角色、版本行；重复执行结果一致。
- 配置变更必须留审计：初始化程序与管理 UI 都写 `ZCRW_HIST`（`OBJECT_TYPE=CONFIG`）。

### 4.5 关键不变量

1. 状态只能通过动作（action）改变，不接受 UI 直接写 `STATUS` 字段。
2. 每次状态变更必须写一条 `ZCRW_HIST`，含操作人、时间、动作、旧/新状态、可选原因。
3. CR 审批未通过不能建/开发 CD；CD 导入前审批未通过不能进入 `READY_TO_IMPORT`。
4. CD 关联的 DEV transport 未全部释放，CD 不能进入 `READY_TO_IMPORT`；ToC 导入前必须有计划导入时间（D9）。
5. Task 未全部关闭或取消，CD 不能关闭；CD 未全部关闭，CR 不能关闭。
6. 已释放的 transport 不能从 CD 解绑，只能标记为「不再关联」并留审计。
7. 所有写操作校验 `VERSION`（乐观锁）；核心状态变更加 SAP 锁对象。
8. 服务端按角色鉴权，前端隐藏按钮只是体验，不作为安全边界。
9. 审批意见、驳回原因、取消原因必填；备注可为空。
10. 历史表只追加，不提供删除入口；审计导出只读。

## 5. 流程与状态机

### 5.1 请求类型

| 类型 | 编码 | 说明 | 一期 |
|---|---|---|---|
| 标准变更 Standard | `STD` | 走完整 CR 审批、CD 审批与传输流程 | P0 |
| 紧急变更 Urgent | `URG` | 可跳过事前审批，走 ToC；事后补审与复盘 | P1 |
| 管理变更 Administrative | `ADM` | 无 transport，用检查清单 | P2 |

### 5.2 状态定义

CR：

| 编码 | 中文 | 含义 |
|---|---|---|
| `NEW` | 新建 | 草稿/待提交，可编辑、可删除 |
| `PENDING_APPROVAL` | 待审批 | 已提交，等待 CR 审批步骤完成 |
| `REJECTED` | 已拒绝 | 审批驳回，可修改后重新提交 |
| `APPROVED` | 已批准 | 可建 CD |
| `IN_PROGRESS` | 进行中 | 至少一个 CD 在开发/测试/导入中 |
| `CLOSED` | 已关闭 | 终态，只读 |
| `CANCELLED` | 已取消 | 终态，必须填原因 |

CD：

| 编码 | 中文 | 含义 |
|---|---|---|
| `NEW` | 新建 | 刚创建，可编辑、可拆分任务 |
| `IN_DEV` | 开发中 | 有开发任务进行 |
| `IN_TEST` | 测试中 | 开发完成，等待测试结论 |
| `READY_TO_IMPORT` | 待导入 | 测试通过、审批通过、DEV transport 已全部释放 |
| `IMPORT_SCHEDULED` | 已计划导入 | 有生效中的导入计划 |
| `IMPORTED` | 已导入 | 发布管理员确认导入 |
| `CLOSED` | 已关闭 | 终态 |
| `CANCELLED` | 已取消 | 终态，必须填原因 |

Task / SubTask：`OPEN` → `IN_PROGRESS` → `DONE`；非终态可 `CANCELLED`。

ToC（`ZCRW_TR.TRKIND=TOC`）：`CREATED` → `RELEASED` → `IMPORT_SCHEDULED` → `IMPORTED`；`RETROFIT_STATE` 单独标记 `NA/PENDING/DONE`（P1）。

### 5.3 状态迁移

动作统一走 `POST /{object}/{id}/actions`，服务端校验「当前状态 + 角色 + 守卫」，失败返回 `INVALID_TRANSITION` / `FORBIDDEN` / `GUARD_FAILED`。

CR：

| 动作 | 迁移 | 允许角色 | 守卫与副作用 |
|---|---|---|---|
| `SUBMIT` | `NEW → PENDING_APPROVAL` | 请求人、变更经理 | 必填项完整；生成 CR 审批步骤 |
| `WITHDRAW` | `PENDING_APPROVAL → NEW` | 请求人、变更经理 | 未决审批步骤标 SKIPPED |
| `APPROVE_STEP` | `PENDING_APPROVAL → PENDING_APPROVAL` | 当前步骤审批人 | 意见可选；末步通过后转 `APPROVED` |
| `REJECT` | `PENDING_APPROVAL → REJECTED` | 审批人 | 意见必填 |
| `REVISE` | `REJECTED → NEW` | 请求人、变更经理 | 保留历史 |
| `START_PROGRESS` | `APPROVED → IN_PROGRESS` | 变更经理、开发 | 必须存在至少 1 个 CD |
| `CLOSE` | `IN_PROGRESS → CLOSED` | 变更经理 | 所有 CD 已关闭/取消 |
| `CANCEL` | 非终态 → `CANCELLED` | 请求人（仅 `NEW`）/变更经理 | 原因必填 |

CD：

| 动作 | 迁移 | 允许角色 | 守卫与副作用 |
|---|---|---|---|
| `START_DEV` | `NEW → IN_DEV` | 开发、变更经理 | 必须有 Owner；可自动建开发任务 |
| `SUBMIT_TEST` | `IN_DEV → IN_TEST` | 开发、测试 | 开发任务和子任务全部关闭；至少 1 条 DEV transport（STD） |
| `PASS_TEST` | `IN_TEST → IN_TEST` | 测试 | 记录测试结论；测试任务关闭 |
| `SUBMIT_APPROVAL` | `IN_TEST → IN_TEST` | 变更经理 | 生成 CD 导入审批步骤（P0 简化：可配置为不需要） |
| `MARK_READY` | `IN_TEST → READY_TO_IMPORT` | 发布管理员、变更经理 | 测试通过、CD 审批通过、DEV transport 全部释放 |
| `SCHEDULE_IMPORT` | `READY_TO_IMPORT ↔ IMPORT_SCHEDULED` | 发布管理员 | 必须有计划导入时间；写 `ZCRW_SCHED`；可改期/取消计划 |
| `CONFIRM_IMPORT` | `* → IMPORTED` | 发布管理员 | 必须有计划或人工确认；写导入时间；ToC 可走同一动作 |
| `CLOSE` | `IMPORTED → CLOSED` | 变更经理 | 所有任务关闭；ToC retrofit 标记（P1） |
| `CANCEL` | 非终态 → `CANCELLED` | 变更经理 | 原因必填；已释放 transport 不回滚 |

Task / SubTask：`START`（OPEN→IN_PROGRESS）、`DONE`、`CANCEL`、`REOPEN`（P1）；子任务关闭不自动关闭父任务，父任务关闭需所有子任务关闭。

### 5.4 审批模型

- 审批分两级：CR 审批（提交后）、CD 导入审批（进入待导入前，可配置为关闭）。
- 审批矩阵按「对象类型 + 请求类型 + 优先级」匹配一组有序步骤，每步指定角色或指定用户；步骤内支持「任意一人」或「全部」两种通过规则。
- 示例：`REQ/STD/HIGH` → 步骤 1「变更经理」（任意一人）、步骤 2「应用负责人」（全部）；`CD/STD/*` → 步骤 1「变更经理」。
- 请求人不能审批自己的请求（除非管理员显式配置代理，P2）。
- 驳回即终止本次审批流；修改后重新提交重新生成步骤并保留历史。
- 审批意见：通过可选、驳回必填；支持「我的待办」「我审批过的」「全组待办」三个视图。

### 5.5 与 CTS 的同步

- 应用**只读** CTS：`E070`（传输头/状态/目标系统/所有人）、`E071`（对象清单）、`E07T`（描述）、TMS 队列表（导入状态；具体表与字段 M0 验证）。
- 传输在 SE01 或 abap-cli 创建，应用只做「关联 + 展示 + 状态快照」，不创建、不释放、不删除、不导入。
- 同步时机：打开传输工作台/CD 详情时按需刷新（节流）；`POST /transports/sync` 手动刷新；P1 可选管理员用 SM36 定时跑同步报表。
- 状态映射（业务展示用，不改变 E070）：

| 展示状态 | 判定来源（M0 确认） |
|---|---|
| 可修改 | `E070.TRSTATUS = D` |
| 已释放 | `E070.TRSTATUS = R` |
| 已导入 | TMS 队列/导入历史显示目标系统导入成功 |
| 导入失败/有错误 | 导入日志有错误 |
| 未知 | 读不到或字段无法判定，显示「未知，请到 STMS 确认」 |

- ToC：单独 `TR_KIND=TOC`，展示类型、目标系统、计划导入时间、导入状态；导入后提示「补做/retrofit 待确认」（P1 标记）。
- 解绑规则：`可修改` 的 transport 允许解绑；已释放/已导入的 transport 只允许标记「不再关联」，保留审计；不做物理删除。
- 关联校验：TRKORR 必须存在；不能重复关联；目标系统与 CD 计划系统不一致时警告（允许变更经理确认）。

### 5.6 定时导入（计划传输）

- 「定时传输」在应用内落地为**计划 + 提醒 + 状态跟踪**，不执行 TMS 导入（见 D9）：
  - CD / ToC 可设置计划导入时间与目标系统，写 `ZCRW_SCHED`。
  - 传输工作台提供「导入日程」视图：按日期/周期/目标系统分组，显示 `PLANNED / DONE / MISSED`。
  - 到点未导入：`MISSED`（读取时计算）+ 首页/我的工作提醒；不发送后台通知（无 SM36）。
  - 实际导入后由发布管理员确认（或 CTS 同步判定），计划置 `DONE`。
- 若后续要求「到点自动导入」，需评估 TMS RFC/API、权限与风险，另立变更（非本计划范围）。

### 5.7 审计

- 每次状态迁移、审批、指派、创建 CD/任务、关联/解绑传输、修改计划、配置变更都写 `ZCRW_HIST`。
- 历史记录：对象、动作、字段、旧值、新值、操作人、时间、来源（UI/API/SYNC）、备注。
- 审计导出按请求/时间/操作人过滤，CSV 下载（P1）。
- 应用级审计不是合规级不可篡改：管理员仍可直接改表，runbook 需说明该边界。

## 6. 工作台信息架构

### 6.1 布局

```
┌──────────────────────────────────────────────────────────────┐
│ 顶栏：产品名  全局搜索  新建请求  通知  用户/角色  帮助        │
├──────────────┬───────────────────────────────────────────────┤
│ 侧边导航      │ 内容区                                         │
│ 工作台        │  页面标题 + 操作条                             │
│ 我的工作      │  筛选区                                        │
│ 请求 CR       │  表格 / 卡片 / 详情                            │
│ 变更文档 CD   │  分页 / 空状态 / 错误状态                       │
│ 任务          │                                               │
│ 审批          │                                               │
│ 传输          │                                               │
│ 导入计划      │                                               │
│ 报表          │                                               │
│ 配置(管理员)  │                                               │
└──────────────┴───────────────────────────────────────────────┘
```

### 6.2 页面清单

| # | 页面 | 路由（hash） | 目的与关键区域 | 一期 |
|---|---|---|---|---|
| 1 | 工作台首页 | `#/dashboard` | KPI（我的待办/待审批/开发中/待导入/逾期）、趋势、最近动态、快捷入口 | P0 简化 / P1 图表 |
| 2 | 我的工作 | `#/my-work` | 待审批 / 我的请求 / 我的 CD / 我的任务 / 我的传输 | P0 |
| 3 | 请求列表 | `#/requests` | 筛选（状态/类型/优先级/组件/周期/负责人/日期）、排序、分页、保存视图、CSV 导出、新建 | P0 |
| 4 | 新建请求 | `#/requests/new` | 三步向导：基本信息 → 影响与计划 → 确认提交 | P0 |
| 5 | 请求详情 | `#/requests/{id}` | 头部 + 动作条 + 概览/时间线/审批/CD/任务/备注 tab | P0 |
| 6 | 变更文档列表 | `#/change-documents` | 按 CR/状态/周期/负责人筛选，批量查看 | P0 |
| 7 | 变更文档详情 | `#/change-documents/{id}` | 头部 + 动作条 + 任务/子任务/传输/ToC/计划/审批/历史 | P0 |
| 8 | 任务列表 | `#/tasks` | 按指派人/状态/截止日/类型筛选；任务板视图 P1 | P0 简化 / P1 |
| 9 | 审批中心 | `#/approvals` | 待我审批 / 我审批过的 / 全部待办；审批抽屉 | P0 |
| 10 | 传输工作台 | `#/transports` | transport 列表（TRKORR/类型/描述/目标系统/状态/导入时间/关联 CD）、同步、未关联告警 | P0 |
| 11 | 传输详情 | `#/transports/{trkorr}` | 状态时间线、对象清单（E071）、关联 CD、同步日志 | P1 |
| 12 | 导入计划 | `#/schedule` | 按日/周期/目标系统查看计划、改期、取消、到期/逾期提醒 | P0 |
| 13 | 报表 | `#/reports` | 变更分布、审批时长、关闭时长、逾期清单、ToC/导入漏斗、CSV 导出 | P1 |
| 14 | 配置 | `#/admin/*` | 类型/角色/审批矩阵/周期/号段/迁移状态 | P1/P2 |
| 15 | 帮助/关于 | `#/about` | 版本、我的角色、操作手册链接、当前环境标识 | P0 |
| 16 | 通知中心（M5） | `#/notifications` | 站内通知列表（状态 / 类型筛选、分页）、刷新、全部已读、单条标记已读；顶栏铃铛入口 | P0/P1（已落地） |

### 6.3 交互规范

- **列表**：服务端分页（默认 50），筛选条件写入 URL 便于分享；空状态给下一步动作；加载态骨架屏；错误态给重试。
- **动作条**：按当前状态 + 角色展示可用动作，禁用项给出原因（tooltip）；危险动作（取消、解绑、改期）二次确认并填原因。
- **并发**：提交时带 `version`；冲突返回 409，前端提示「记录已被他人修改」并刷新，不静默覆盖。
- **层级**：CR → CD → Task → SubTask 用面包屑与折叠面板，SubTask 在 Task 行内展开，不单独开一级导航。
- **表单**：必填校验内联提示；离开有未保存修改时确认；长文本自动保存草稿（P2）。
- **审批**：抽屉内展示对象摘要与历史，通过/驳回落库后刷新待办计数；驳回意见必填。
- **深链**：hash 路由，刷新与分享保持页面；浏览器前进/后退可用。
- **安全**：所有渲染文本转义（XSS）；不在 URL 放敏感数据；导出文件名不含用户输入。
- **可访问性**：键盘可达、焦点可见、表单 label 关联；表格有 caption（P1）。

### 6.4 视觉与可用性基线

- 中文 UI；不引用 CDN，字体用系统字体；无外部图标库（用内联 SVG 或字符）。
- 颜色语义：状态色板固定（待审批/进行中/待导入/已完成/拒绝/取消），同时显示文字，不单靠颜色。
- 响应式最小集：1280 及以上完整布局，1024 收起侧栏；不承诺移动端。
- 截图：每个主页面一张，脱敏（无系统地址、client、真实用户名与业务数据）。

## 7. 技术架构

### 7.1 总览

```
浏览器（原生 ES modules 单页）
   │  HTTPS（ICF 节点 ZCRW_APP，/sap/bc/zcrw）
   ▼
ZCL_CRW_HTTP_HANDLER  ── MIME 静态资源（/zcrw）+ SPA fallback
   ▼
ZCL_CRW_API_ROUTER ── 鉴权/上下文/错误信封
   ▼
Controllers（request/cd/task/approval/transport/schedule/dashboard/report/config/me）
   ▼
Services（request / cd / task / workflow / approval / transport / schedule / report / auth / config）
   ▼
Repositories（Open SQL）── ZCRW_* 表
CTS Adapter（只读）── E070 / E071 / E07T / TMS 队列
Number / History / Log / Bootstrap / Migration / Selfcheck
```

### 7.2 分层与类清单

命名前缀：`ZCL_CRW_*` / `ZIF_CRW_*` / `ZCX_CRW_*`；ABAP 内部命名遵循 [`.agents/skills/abap-style/SKILL.md`](../.agents/skills/abap-style/SKILL.md)。

| 层 | 对象 | 职责 |
|---|---|---|
| 入口 | `ZCL_CRW_HTTP_HANDLER` | 实现 `IF_HTTP_EXTENSION`；路由 MIME/API；CSP/缓存头 |
| 路由 | `ZCL_CRW_API_ROUTER` | 解析路径/方法/参数；异常转错误信封 |
| 上下文 | `ZCL_CRW_API_CONTEXT` | 当前用户、角色、请求体、correlation id |
| 控制器 | `ZCL_CRW_API_REQUEST` / `_CD` / `_TASK` / `_APPROVAL` / `_TRANSPORT` / `_SCHEDULE` / `_DASHBOARD` / `_REPORT` / `_CONFIG` / `_ME` / `_NOTIFY`（M5） | 参数校验 + DTO 转换，不含业务规则 |
| 服务 | `ZCL_CRW_REQUEST_SVC` / `_CD_SVC` / `_TASK_SVC` / `_WORKFLOW_SVC` / `_APPROVAL_SVC` / `_TRANSPORT_SVC` / `_SCHEDULE_SVC` / `_REPORT_SVC` / `_NOTIFY`（M5 通知；报表 `ZCRW_REMIND_JOB` 调用 `run_scan`） | 业务规则、事务、编排 |
| 领域 | `ZCL_CRW_WORKFLOW`（状态机与守卫）、`ZCL_CRW_AUTH`（角色判定）、`ZCL_CRW_CONFIG` | 纯逻辑，可被 ABAP Unit 直接覆盖 |
| 数据 | `ZCL_CRW_REQUEST_REPO` / `_CD_REPO` / `_TASK_REPO` / `_TR_REPO` / `_SCHED_REPO` / `_APPR_REPO` / `_HIST_REPO` / `_NOTE_REPO` / `_ROLE_REPO` / `_LOG_REPO` | Open SQL、分页、乐观锁 |
| 集成 | `ZIF_CRW_CTS_READER` + `ZCL_CRW_CTS_ADAPTER` | 只读 E070/E071/E07T/TMS；可 mock 做单测 |
| 支撑 | `ZCL_CRW_NUMBER`、`ZCL_CRW_HISTORY`、`ZCL_CRW_LOG`、`ZCL_CRW_JSON`、`ZCL_CRW_MIME` | 号段、审计、日志、序列化、静态资源 |
| 运维 | `ZCL_CRW_BOOTSTRAP`、`ZCL_CRW_MIGRATION`、`ZCL_CRW_SELFCHECK`、`ZCL_CRW_DEMO_DATA` | 初始化、迁移、自检、演示数据 |
| 异常 | `ZCX_CRW_ERROR` 及子类 | 业务错误码 + 消息类 `ZCRW_MSG` |

### 7.3 数据访问与性能

- 只用 Open SQL / ABAP SQL；报表用聚合查询；目标 S/4HANA 2022+（`/ui2/cl_json`、ABAP SQL 聚合可用）。
- 列表分页：先 `COUNT(*)` 再按页取数；默认 50，最大 200；排序字段白名单，禁止动态拼接 SQL。
- 索引按查询路径建：状态、负责人、请求人、周期、创建时间、指派人、计划时间。
- 传输/对象清单读 CTS 表一次批量取，按 TRKORR 内表 `FOR ALL ENTRIES` / `IN`，避免逐条 SELECT。
- 详情页一次取头部 + 关联对象，备注/历史首屏限制条数（如 50，翻页加载）。
- 报表限时间范围（默认 90 天），禁止全表扫；必要时加汇总表（P2）。
- 大表增长：历史/日志按年归档或清理策略（P2，runbook 说明）。

### 7.4 事务、锁与并发

- 每个 API 写请求一个 LUW：服务层校验通过后写表 → `COMMIT WORK AND WAIT`；异常不提交。
- 乐观锁：`ZCRW_REQ.VERSION`、`ZCRW_CD.VERSION`、`ZCRW_TASK.VERSION`；更新 `WHERE version = 期望值`，影响 0 行返回 `CONCURRENT_MODIFICATION`。
- 关键动作（审批、状态迁移、关联传输、改计划）加锁对象 `EZCRW_REQ` / `EZCRW_CD`（按对象类型选，参数为对象 ID）；锁等待超时返回冲突。
- 动作幂等：重复提交同一动作时，若状态已变化返回 `INVALID_TRANSITION`，不产生重复历史/审批记录。
- 号段使用 `NUMBER_GET_NEXT`，不做本地缓存；区间初始化由 bootstrap 完成。

### 7.5 安全与权限

- **认证**：ICF 节点使用 SAP 登录（SSO/表单/Basic，按客户环境），应用不保存密码；会话超时由 SAP 控制。
- **授权**：应用角色表 `ZCRW_ROLE` 判定；服务端每个写操作校验角色 + 数据范围；读操作按角色过滤。
- **标准权限**：敏感动作可叠加 `AUTHORITY-CHECK`（`S_DEVELOP`、`S_CTS_ADMI` 等）；具体检查项 M1 与 basis 确认。
- **Web 安全**：SPA 渲染全部转义；写接口要求自定义请求头（如 `X-CRW-Request: 1`）并校验同源；返回 CSP 头（`default-src 'self'`）；禁止内联脚本（除 hash）；上传/导出文件名过滤；错误信息不暴露内部细节。
- **审计**：见 §5.7；日志不记录敏感字段。
- **数据边界**：不落真实业务数据到演示/截图；test/QA 数据可重置。

### 7.6 CTS 只读集成

- 读取对象：`E070`、`E071`、`E07T`、TMS 导入队列/日志表（具体表名与字段在目标系统用 `abap fields`/`select` 确认）。
- 不写任何 CTS 表；不调用 TMS 导入 API；ToC 仅作为 `ZCRW_TR` 的一种类型记录与展示。
- 权限：最终用户通常无 CTS 表权限；服务以应用逻辑读取，必要时申请只读权限或 `AUTHORITY-CHECK` 后降级（M1 确认）。
- 失败降级：CTS 读取失败不阻塞请求流程，状态显示「未知」并记录日志；`SYNC_STATE=ERROR` 供报表筛选。
- 快照与实时：`ZCRW_TR` 存最近快照，页面可手动刷新；详情页对象清单实时读 `E071`（失败则不展示）。
- **按 D4：实现只读集成与手工关联，不做 live 验证**（记录为已知未验证项，M4 前补验证或明确接受风险）。

### 7.7 部署、初始化与升级

- 专用包 `$CRW`（本地包，已由 CLI 创建，super package `$TMP`、DLVUNIT LOCAL、无 transport）。abap-cli 2.0.0 起原生支持 `$` 前缀本地包免 transport（本地仓库 commit `3dd443d`）；`abap deploy` 已把内置 ICF 服务升到 2.0.0。
- 安装顺序：域/数据元素（如需）→ 表 → 号段对象 → 锁对象 → 消息类 → 类/接口 → ICF 节点 → 事务码 → MIME → `ZCL_CRW_BOOTSTRAP` → `ZCL_CRW_SELFCHECK`。
- 主对象上报前必须 `check content` / `validate:aff`；写 SAP 顺序 `check syntax` → `push` → `inspect --activation`。
- 升级：`ZCRW_VERSION` 记录已应用版本；`ZCL_CRW_MIGRATION` 按版本号执行幂等迁移；导入后运行一次并写审计/日志。
- 运行手册 `docs/runbook.md`：安装、升级、权限配置、SICF 节点属性、号段区间、定时同步、故障排查。
- 本地包限制：对象不可传输，无法通过 CTS 部署到 QA/生产；若后续要产品化部署，需迁移到可传输包（P2 再评估）。

### 7.8 日志与可观测

- `ZCRW_LOG`：API 错误、CTS 同步失败、迁移执行、权限拒绝；含 `CORRELATION_ID`，前端错误提示带该 ID。
- `ZCL_CRW_SELFCHECK`：输出 `CRW_SELFCHECK_OK` + 关键计数（配置行数、表可读、号段可取、CTS 可读、ICF 节点存在），供只读验收。
- 健康端点 `GET /api/v1/health`（只读）：版本、组件状态；不含敏感信息。
- 定期检查 `abap dumps`（只读）确认无运行时错误。

### 7.9 为什么选 ICF + MIME + 原生 SPA

| 选项 | 结论 | 原因 |
|---|---|---|
| ICF 节点 + MIME + 原生 ES modules | 推荐 | abap-cli 现有 01 demo 已验证；零外部依赖；单节点同源；部署最简单 |
| SAPUI5/Fiori（MIME 托管静态资源） | 备选 | 可行但需打包/资源体积/FLP 集成；团队无强制要求时收益低 |
| RAP + OData + Fiori Elements | 不推荐 | CLI 对 RAP 工件支持不完整，写路径不可控 |
| BSP / Web Dynpro | 不推荐 | CLI 不支持，维护成本高 |
| 经典报表 + ALV | 不推荐 | 不是工作台形态，交互与深链能力弱 |

### 7.10 abap-cli 能力边界（对本项目的影响）

| 能力 | 状态 | 处理方式 |
|---|---|---|
| DDIC：DOMA/DTEL/TABL/STRU/TTYP/MSAG/ENQU/NROB | 支持 | `create --file` + `push` |
| CLAS/INTF/PROG/FUGR | 支持 | 主实现方式 |
| DDLS（CDS） | S/4 支持 | 报表可选；不做 RAP |
| HTTP（ICF）、TRAN（事务码） | 支持 | `create --file` |
| MIME 目录/文件 | 支持 | `mime create` + `mime push`；子目录支持 M0 验证 |
| AUTH 权限对象 | 不支持 | 应用角色表 + 标准权限检查；生产级自定义 AUTH 人工创建 |
| SM30 表维护生成器 | 不支持 | 配置用 bootstrap + 应用内配置界面 |
| 后台作业（SM36） | 不支持 | 计划导入用「记录 + 到点计算 + 提醒」；不自动执行 |
| BSP/增强/BAdI | 不支持 | 不需要 |
| 表数据 INSERT/UPDATE | 无 CLI 命令 | 初始化/冒烟数据由 classrun 程序写入 |
| Transport release/import | CLI 不 release（仓库规则） | 人工在 SE01/STMS 操作，应用只读状态 |
| 非 `$TMP` 本地包写对象 | abap-cli 2.0.0 支持 | `$` 前缀本地包按 transport-free 处理（附录 B.3） |

## 8. API 契约（v1 草案）

### 8.1 通用约定

- Base：`/sap/bc/zcrw/api/v1`；请求/响应 `application/json; charset=utf-8`。
- 成功：`{"status":"success","data":...}`；失败：`{"status":"error","code":"...","message":"...","details":{...},"correlationId":"..."}`。
- 分页：`{"items":[...],"page":1,"pageSize":50,"total":123}`；查询参数 `page`/`size`/`sort`/`order`。
- 日期 `YYYY-MM-DD`；时间戳 ISO 8601（含时区）；金额/工时按 DTO 固定格式。
- 所有写操作校验 `X-CRW-Request: 1` 请求头与同源；`version` 字段用于乐观锁。
- 错误 HTTP 状态：400 参数/校验、401 未登录、403 无权限、404 不存在、409 冲突/非法迁移、500 内部错误。

### 8.2 端点

| 方法 | 路径 | 用途 |
|---|---|---|
| GET | `/me` | 当前用户、角色、数据范围、环境标识 |
| GET | `/health` | 版本与组件健康 |
| GET | `/dashboard` | KPI 与最近动态 |
| GET | `/requests` | CR 列表 |
| POST | `/requests` | 新建 CR（草稿） |
| GET | `/requests/{id}` | CR 详情（含 CD 汇总） |
| PATCH | `/requests/{id}` | 编辑头部字段（仅 NEW/REJECTED） |
| POST | `/requests/{id}/actions` | CR 状态动作 |
| GET | `/requests/{id}/change-documents` | CR 下的 CD |
| POST | `/requests/{id}/change-documents` | 新建 CD |
| GET | `/requests/{id}/history` | 历史/审计 |
| GET/POST | `/requests/{id}/notes` | 备注 |
| GET | `/change-documents` | CD 列表 |
| GET/PATCH | `/change-documents/{id}` | CD 详情/编辑 |
| POST | `/change-documents/{id}/actions` | CD 状态动作（含 SCHEDULE_IMPORT） |
| GET/POST | `/change-documents/{id}/tasks` | CD 下任务 |
| GET | `/change-documents/{id}/transports` | CD 下 transport（DEV/ToC） |
| GET | `/change-documents/{id}/schedule` | CD 的导入计划 |
| POST | `/change-documents/{id}/schedule` | 创建/修改计划 |
| GET | `/tasks` | 我的任务/全部任务 |
| GET/PATCH | `/tasks/{id}` | 任务详情/改派/改期 |
| POST | `/tasks/{id}/actions` | 任务开始/完成/取消 |
| GET/POST | `/tasks/{id}/subtasks` | 子任务 |
| GET | `/approvals` | 待我审批/我审批过的/全部 |
| POST | `/approvals/{id}/decision` | 通过/驳回（意见） |
| GET | `/approvals/steps?objectType=&objectId=` | 审批步骤 |
| GET | `/transports` | 传输列表（按 CD/周期/类型/状态） |
| POST | `/transports/link` | 关联 DEV/ToC |
| POST | `/transports/{trkorr}/unlink` | 解绑（仅可修改） |
| POST | `/transports/{trkorr}/mark-detached` | 标记不再关联（已释放） |
| POST | `/transports/sync` | 同步单条/批量状态 |
| GET | `/transports/{trkorr}` | 传输详情（对象清单/时间线） |
| GET | `/schedules` | 导入计划列表（日期/周期/目标系统） |
| POST | `/schedules/{id}/actions` | 改期/取消/确认完成 |
| GET | `/config/cycles` | 周期列表 |
| GET | `/reports/changes` | 变更分布/趋势 |
| GET | `/reports/duration` | 审批/关闭时长 |
| GET | `/reports/overdue` | 逾期与异常 |
| GET | `/reports/to-c` | ToC/导入漏斗（P1） |
| GET | `/reports/export.csv` | 报表导出（P1） |

通知（M5）：

| 方法 | 路径 | 用途 |
|---|---|---|
| GET | `/notifications?status=&type=&page=&size=` | 当前用户通知列表（默认 20/页，上限 100） |
| GET | `/notifications/unread-count` | 当前用户未读数 |
| POST | `/notifications/refresh` | 触发扫描，返回 `{created,unread}` |
| POST | `/notifications/{id}/read` | 标记单条已读 |
| POST | `/notifications/read-all` | 全部标记已读 |

### 8.3 关键示例

新建 CR：

```json
POST /requests
{
  "requestType": "STD",
  "title": "采购订单审批阈值调整",
  "description": "将 PO 审批阈值从 5 万调整到 10 万，涉及 ZCL_PO_APPROVAL。",
  "priority": "MEDIUM",
  "component": "MM-PUR",
  "plannedStart": "2026-11-10",
  "plannedEnd": "2026-11-21"
}
```

新建 CD：

```json
POST /requests/0000000123/change-documents
{
  "title": "2026-11 发布批次",
  "cycleId": "2026-11",
  "targetSystem": "QAS",
  "devLead": "DEVELOPER01",
  "plannedImportAt": "2026-11-27T22:00:00+08:00",
  "version": 2
}
```

状态动作：

```json
POST /change-documents/0000000045/actions
{
  "action": "SCHEDULE_IMPORT",
  "version": 4,
  "comment": "计划 11-27 晚导入 QAS",
  "plannedImportAt": "2026-11-27T22:00:00+08:00"
}
```

关联 ToC：

```json
POST /transports/link
{
  "cdId": "0000000045",
  "trkorr": "QASK900123",
  "trKind": "TOC"
}
```

错误：

```json
{
  "status": "error",
  "code": "INVALID_TRANSITION",
  "message": "当前状态 IN_TEST 不允许执行 MARK_READY",
  "details": { "currentStatus": "IN_TEST", "action": "MARK_READY", "missing": ["ALL_DEV_TR_RELEASED"] },
  "correlationId": "9f2c..."
}
```

### 8.4 错误码

| code | HTTP | 含义 |
|---|---|---|
| `VALIDATION_ERROR` | 400 | 参数/字段校验失败 |
| `NOT_FOUND` | 404 | 对象不存在 |
| `FORBIDDEN` | 403 | 角色/数据范围不允许 |
| `INVALID_TRANSITION` | 409 | 当前状态不允许该动作 |
| `GUARD_FAILED` | 409 | 前置条件不满足（审批未完成、传输未释放等） |
| `CONCURRENT_MODIFICATION` | 409 | 版本冲突 |
| `OBJECT_LOCKED` | 409 | SAP 锁占用 |
| `DUPLICATE_LINK` | 409 | transport 已关联其他 CD |
| `SCHEDULE_CONFLICT` | 409 | 计划时间冲突/已存在生效计划 |
| `CTS_READ_ERROR` | 502 | CTS 读取失败（降级为未知状态） |
| `APPROVER_MISMATCH` | 403 | 非当前步骤审批人 |
| `SELF_APPROVAL` | 403 | 请求人不能审批自己 |
| `NUMBER_RANGE_ERROR` | 500 | 号段取号失败 |
| `INTERNAL_ERROR` | 500 | 未分类错误 |

### 8.5 版本与兼容

- 路径带 `v1`；字段只增不删、不改语义；破坏性变更升 `v2` 并保留 `v1` 一个迭代。
- DTO 字段命名 camelCase（`/ui2/cl_json` pretty mode）；ABAP 内部按 abap-style 命名。
- 前端与后端同包发布，版本号写 `ZCRW_VERSION` 并在 `/health` 返回；页面显示版本。

## 9. 里程碑与验收

### 9.1 里程碑

| 阶段 | 目标 | 主要交付 | 验收（机器可判定） | 粗估 |
|---|---|---|---|---|
| M0 决策与验证 | 锁定范围、命名、包、技术路线 | D1–D10 决策、M0 验证清单结果、AGENTS.md 修订、数据模型/API 评审稿 | 写路径 / DDIC / cl_json / ABAP Unit / CTS / NROB / MSAG / ENQU 已过；ICF/MIME/TRAN 留 M1 | 3–5 人日（基本完成） |
| M1 数据模型与骨架 | 13 张表、初始化/自检、CR+CD+Task/SubTask CRUD、角色、列表/详情页 | DDIC + 服务 + API 骨架 + 前端框架 + 部署 README | 13 表 + 3 号段 + 消息类 + 2 锁对象 + bootstrap/selfcheck + CR/CD/Task 服务 + SMOKE 已完成；API/页面待做 | 12–18 人日（进行中） |
| M2 流程闭环 | CR/CD/Task/SubTask 状态机、两级审批、审计、我的工作、KPI | 状态动作、审批中心、历史、任务板（P1） | 端到端标准变更用例通过；非法迁移/越权/并发被拒；连续两次重跑一致 | 12–18 人日 |
| M3 传输/ToC/计划 | CTS 只读、DEV/ToC 关联、传输工作台、导入计划与提醒 | 传输/计划服务、页面、未关联/逾期告警 | 关联真实 transport 后状态展示正确；计划到期/逾期计算正确；CTS 失败降级 | 10–15 人日 |
| M4 报表与产品化 | 报表、配置 UI、迁移/runbook、通知、截图、试点 | 报表 + CSV、配置界面、runbook、试点反馈 | DoD 清单全过；试点用户走通一个真实变更 | 8–12 人日 |
| M5 P2 通知与提醒（2026-11-02 已交付） | 站内通知中心（B1）+ 提醒报表 / SM36（C1）+ P2 basis 设计（E） | `ZCRW_NOTIFY`、`ZCL_CRW_NOTIFY` / `ZCL_CRW_API_NOTIFY`、`/notifications*`、顶栏铃铛 + `#/notifications`、`ZCRW_REMIND_JOB`、`p2-basis.md` | `CRW_SELFCHECK_OK tables=14 version=1.2.0`；notify 单测 5/5；`CRW_NOTIFY_OK rows=0`（复位后）；`ZCRW_REMIND_JOB_OK`；通知 API 控制器探针通过（浏览器 HTTP 待人工） | — |

合计约 45–68 人日（单开发，含验证与返工）；agent 协作可压缩实现时间，但评审、试点、验收不省。

### 9.2 验收标准（DoD）

- **静态**：`abap check content`（.abap）/ `abap validate:aff`（JSON）全部通过；文件命名符合 AFF。
- **单元测试**：`abap test` 通过；覆盖 CR/CD/Task 状态机、守卫、审批矩阵、权限判定、乐观锁；不依赖真实 CTS。
- **自检**：`abap run ZCL_CRW_SELFCHECK --json` 输出含 `CRW_SELFCHECK_OK`，含配置/表/号段/CTS/ICF 检查结果。
- **只读数据断言**：`abap select` 断言配置种子行、CR/CD/任务/历史/审批/计划行。
- **端到端**：CR → CD → Task/SubTask → 关联 transport（含 ToC）→ 计划 → 导入确认 → 关闭；审批、驳回、取消、并发冲突至少各一次。
- **UI**：主页面（工作台 / CR 列表 / CR 详情 / CD 详情 / 审批 / 传输或计划 / 通知中心）截图，脱敏；截图与当前实现一致（M5 已重拍 9 张，含通知中心 / 通知铃铛面板）。
- **可重跑**：清理测试数据（reset classrun）后连续两次结果一致。
- **部署**：在目标系统按 runbook 安装成功；升级路径验证一次。
- **性能**：1 万 CR / 5 万任务 / 2 万传输关联规模下列表 p95 < 1.5s（测试数据由脚本准备）。
- **安全**：越权、XSS、CSRF、版本冲突用例通过；无 URL/凭证/真实数据入库。

### 9.3 并行开发建议

M0 完成后可按契约并行：

1. **数据/后端**：DDIC + 仓储 + 服务 + 状态机。
2. **API**：路由/控制器/DTO + 错误信封（先冻结契约，前端可 mock）。
3. **前端**：页面/组件/路由 + 用 mock JSON 开发。
4. **CTS 适配器**：E070/E071/TMS 读取 + 降级。
5. **验收工具**：自检 classrun、测试数据准备/清理、ABAP Unit 脚手架。

共享契约：`docs/architecture.md`（数据模型 + API）与 `docs/workflow.md`（状态机）先冻结，再分头实现。

## 10. 仓库、命名与部署

### 10.1 目录结构（已确认）

```
apps/change-request-workbench/
├── README.md                 # 产品说明、状态、安装、验证、截图索引
├── docs/
│   ├── architecture.md       # 架构、数据模型、API 契约
│   ├── workflow.md           # 状态机、审批矩阵、CTS 同步、计划导入、通知
│   ├── runbook.md            # 安装/升级/权限/运维/故障排查/SM36
│   ├── handoff.md            # 交接文档
│   └── p2-basis.md           # P2 basis 类项设计（包迁移/索引/归档/权限/Fiori）
├── src/                      # AFF：DDIC/CLAS/INTF/HTTP/TRAN/NROB/ENQU/MSAG + testclasses sidecar
├── src/mime/                 # 前端资产（index.html/styles.css/js）
└── screenshots/              # 主页面截图（脱敏）
```

- 与 demo 的差异：应用单元允许 `docs/`；`src/` 按 AFF 扁平布局；前端资产在 `src/mime/`（沿用 01 demo 约定）。
- 不引入 Node 构建链（前端零依赖，浏览器原生 ES modules）。
- **工作目录**：所有 `abap create/pull` 在 `apps/change-request-workbench/` 下执行，保证拉取文件落在本应用的 `src/`，不污染仓库根目录。

### 10.2 命名规范（已确认 `CRW`）

| 对象 | 规则 | 示例 |
|---|---|---|
| 包 | 本地包 | `$CRW` |
| 表/结构/域/数据元素 | `ZCRW_<ENTITY>` | `ZCRW_REQ`、`ZCRW_CD`、`ZCRW_SCHED` |
| 类 | `ZCL_CRW_<ROLE>` | `ZCL_CRW_WORKFLOW` |
| 接口 | `ZIF_CRW_<ROLE>` | `ZIF_CRW_CTS_READER` |
| 异常类 | `ZCX_CRW_<ROLE>` | `ZCX_CRW_ERROR` |
| 消息类 | `ZCRW_MSG` | — |
| 锁对象 | `EZCRW_REQ` / `EZCRW_CD`（ENQU，主表 `ZCRW_REQ` / `ZCRW_CD`） | — |
| 号段对象 | `ZCRW_REQ` / `ZCRW_CD` / `ZCRW_TASK` | — |
| ICF 节点 | `ZCRW_APP` → `/sap/bc/zcrw` | — |
| 事务码 | `ZCRW` | 类型与参数 M0 验证 |
| MIME 根 | `/zcrw` | — |
| 版本表 | `ZCRW_VERSION` | — |

要求：全大写、≤30 字符、无 `DMA`、无 `NN` 序号、无 demo/测试字样；命名与产品名解耦前不写死「ChaRM」。

### 10.3 包、传输与环境

- **D1 已确认**：对象放本地包 `$CRW`（已通过 `abap create DEVC` 创建：super package `$TMP`、DLVUNIT LOCAL、无 transport）。
- **写路径（已落地）**：abap-cli 2.0.0 原生支持 `$` 前缀本地包免 transport（本地仓库 commit `3dd443d`，内置 ICF 服务同步升级到 2.0.0）；`$CRW` 下 create / push / delete / run 均已验证。升级 CLI 后先运行 `abap deploy --yes` 并确认 `deploy status` current。
- 本地包不产生 transport、不可跨系统部署；如果后续要部署到 QA/生产，需要迁移到可传输包 + 传输请求（P2 再评估）。
- 目标环境：DEV/测试系统（当前 active profile `test`，systemVersion 789，ICF 2.0.0 current）；不碰生产。
- 环境差异（S/4 版本、`/ui2/cl_json`、CTS 表权限）写入 runbook 前置条件，不写死在代码里。

### 10.4 需要修订的仓库契约

`AGENTS.md` 当前只定义 demo 单元；本项目需要新增/修订：

1. 新增「应用单元契约」：`apps/<slug>/` 目录（README + docs + src + src/mime + screenshots）、命名用产品前缀（不含 `DMA`、不含编号）、允许 `docs/`。
2. 明确应用走**本地包**（`$CRW`，用户已确认），与 demo 的 `$TMP` 规则并列；记录 abap-cli 2.0.0 的本地包支持这一前置条件（附录 B.3）。
3. 应用验证方式 = `abap test` + 自检 classrun + 只读 `select` + 截图；HTTP URL 不写入仓库；不保存证据文件。
4. DoD 增加「设计文档/runbook/迁移/试点/截图」项。
5. 根 README：新增「应用」索引区；`docs/demo-library-plan.md` 标注 demo 线与应用线的关系。
6. `scripts/check-demos.mjs`（若落地）：支持 `apps/` 校验。

### 10.5 与现有 demo 库的关系

- demo 01 保留；本项目是第二个旗舰项目，但**不是 demo**，独立于 demo 路线图的编号体系。
- D7 已确认：demo 线（02–12）保留，应用独立成线；`docs/demo-library-plan.md` 只加一句交叉引用。

## 11. 风险与对策

| 风险 | 影响 | 对策 |
|---|---|---|
| 范围蔓延（做成半个 ChaRM） | 周期失控 | §2.3 非目标清单；每阶段验收后才加功能 |
| abap-cli 升级导致本地包/ICF 行为变化 | `$CRW` 写路径或读写接口失效 | 升级后先 `abap deploy --yes` + `deploy status`，回归 `$CRW` 写路径与 DDIC/ICF probe |
| CLI 能力盲区（AUTH/SM30/作业/MIME 子目录/SICF 认证） | 方案返工 | M0 逐项 spike；不支持的用应用层/人工流程替代并写 runbook |
| CTS 表语义/权限不确定（D4 不验证） | 传输状态不准 | 实现降级「未知」；M4 前补验证或明确接受风险 |
| 真实数据/权限要求高 | 安全与合规风险 | 应用角色 + 标准权限；审计；不落敏感数据；生产由 basis 部署 |
| 前端零依赖 SPA 代码量增长 | 可维护性下降 | 按页面/模块拆文件；组件/渲染函数复用；P1 可加 Lint |
| 历史/日志表增长 | 性能下降 | 分页/索引；归档策略；报表限时间窗 |
| 并发/锁处理错误 | 数据不一致 | 乐观锁 + 锁对象 + 单测覆盖冲突场景 |
| 层级过深（CR→CD→Task→SubTask） | 操作繁琐、用户不用 | 面包屑 + 折叠；默认只展示必要层级；试点验证 |
| 计划导入语义误解（D9） | 预期不符 | 明确「记录+提醒，不执行 TMS」；若要自动导入另立评估 |
| agent 大上下文开发漂移 | 质量/一致性 | 冻结契约、小步提交、每模块验收、Lead 统一评审 |

## 12. 决策记录

### 12.1 已确认（D1–D10）

| 编号 | 决策 | 结论 |
|---|---|---|
| D1 | 产品名/对象前缀/包 | `CRW`；前缀 `ZCRW_`；包 `$CRW`（本地包，已创建） |
| D2 | 仓库形态 | `apps/change-request-workbench/`，修订 AGENTS.md 增加应用单元契约 |
| D3 | 一期范围 | CR → CD → Task/SubTask + ToC + 定时导入计划；报表/周期 P1 |
| D4 | CTS 集成 | 实现只读集成 + 手工关联；不做 live 验证 |
| D5 | UI 技术 | ICF + MIME + 原生 ES modules SPA |
| D6 | 环境 | `test` profile（systemVersion 789，ICF 2.0.0 current）；试点用户待定 |
| D7 | demo 02–12 路线图 | demo 线保留；应用独立成线 |
| D8 | D4 口径 | 只读 + 手工关联 + 状态降级；不包含应用内创建/释放/导入 transport |
| D9 | 定时传输语义 | 计划导入 + 日程 + 到点/逾期提醒 + 确认；不执行 TMS 导入 |
| D10 | `$CRW` 写路径 | 升级 abap-cli 到 2.0.0（`$` 前缀本地包免 transport，含 ICF 服务端修复）；已部署 2.0.0 并验证 |

### 12.2 变更记录

- 2026-11-01：D8/D9 按 §12.1 口径执行；D10 由 abap-cli 2.0.0 落地（commit `3dd443d`，含 ICF 2.0.0 部署）。M0 结果与剩余限制见附录 B。
- 2026-11-01：v1 冻结决策 D11–D23 与 workflow W1–W30 全量裁决（Phase 1 完成）。
- 2026-11-02：M5（P2 通知与提醒）交付：`ZCRW_NOTIFY` + `ZCL_CRW_NOTIFY` / `ZCL_CRW_API_NOTIFY` + `/notifications*` API + 顶栏铃铛 / `#/notifications` 页面 + 提醒报表 `ZCRW_REMIND_JOB`；版本升 1.2.0；邮件通道仅预留（SMTP 未配置，不发信）；P2 basis 类项只出设计（`apps/change-request-workbench/docs/p2-basis.md`）。决策 D24/D25 与 P2 决策记录见 §12.3。

### 12.3 v1 冻结与 P2 增补决策（D11–D25，2026-11-01 / 11-02）

| 编号 | 决策 | 结论 |
|---|---|---|
| D11 | `PRIORITY` 编码 | `1` 紧急 / `2` 高 / `3` 中 / `4` 低；空 = 未定；矩阵空 = 通配；UI 映射中文 |
| D12 | `APPROVAL_STATE` 枚举 | `NONE` / `PENDING` / `APPROVED` / `REJECTED` / `SKIPPED`（语义同 workflow W3） |
| D13 | 审批通过规则 | v1 = `ANY`（任一人）；`ALL` 留 P1 |
| D14 | `CONFIRM_IMPORT` 来源态 | `READY_TO_IMPORT` / `IMPORT_SCHEDULED`；其余拒绝 |
| D15 | 计划权威 | `ZCRW_SCHED` 权威；`ZCRW_CD.PLANNED_IMPORT_AT` 为快照同步 |
| D16 | 时区 | SAP 系统本地时间 `CHAR14`；API ISO 无时区偏移 + `timezone:"SAP_SYSTEM"`；不做换算 |
| D17 | 删除语义 | 无 DELETE API；`CANCELLED` 软取消，审计只追加 |
| D18 | `ZCRW_HIST.OBJECT_TYPE` | 不含 `NOTE` |
| D19 | 分层 | v1 保留 `*_SVC` 内联状态机；M2 抽 `ZCL_CRW_WORKFLOW`（纯逻辑）+ `ZCL_CRW_AUTH`；`ZCL_CRW_AUDIT` 不重命名；仓储层单拆留 P2 |
| D20 | 索引 | v1 不建二级索引（CLI 无入口）；压测后 GUI/DB02 按需建 |
| D21 | 未登录行为 | `/api/v1/*` JSON 401；页面重定向登录 |
| D22 | 事务码 | 参数事务 `ZCRW` → 报表 `ZCRW_START` 打开 ICF URL；P2 评估 Fiori tile |
| D23 | selfcheck | 增 ICF 节点与 `E070` 只读检查（ICF 缺失 FAIL；CTS 读取失败 DEGRADED） |
| D24 | 通知模型与去重 | 独立表 `ZCRW_NOTIFY`，按 `USER_ID` 归属；`NOTIFY_TYPE` / `SEVERITY` / `STATUS` / `SOURCE` 枚举固定；幂等键 `USER_ID + DEDUP_KEY`，重复扫描 / 刷新不重复创建（已读 / 已忽略不重建）；通知不驱动状态机（语义见 architecture §5.8、workflow §9） |
| D25 | 邮件通道 | 本轮只预留 `ZCL_CRW_NOTIFY=>deliver_email`；SMTP / SCOT 未配置前不发信、不影响站内通知；启用前置与验收见 `p2-basis.md` §7.1（SMTP/SCOT）+ runbook §2.13（SM36） |

**P2 basis 决策记录（2026-11-02）**

- **A19 可传输包迁移（本轮工作项 A3）：暂不做。** 保持 `$CRW` 本地包；当前只服务 test 试点，迁移涉及 SE03 批量重指派与 ICF / MIME 重激活，风险高于本轮收益。路径 / CLI 限制 / 验收 / 重启条件见 `p2-basis.md` §2。
- **A20 二级索引（D20；本轮工作项 D2）：后置。** abap-cli 无索引入口，当前数据量小；建索引前先有慢查询 / 压测证据。建议清单与 SE11 步骤见 `p2-basis.md` §3。
- **A18 数据归档、A8 权限对象、D22 Fiori/FLP：只出设计，不实施。** 分别见 `p2-basis.md` §4 / §5 / §6。
- **SMTP / SM36：** 由 basis 配置；应用侧提供预留方法与可调度报表，本轮不建作业、不发信（`p2-basis.md` §7）。

## 13. 下一步行动（M5 后 / P2）

1. **P2 basis 类项**：按 `p2-basis.md` 的顺序决策与启动——可传输包迁移（A19，暂不做）→ 索引（A20/D20，后置）→ 权限对象（A8）→ 归档（A18）；Fiori/FLP 保持事务码入口。
2. **通知增强**：basis 配 SMTP 后启用 `deliver_email`；basis 建 SM36 作业 `ZCRW_REMIND`（每日 07:00）；补通知清理 / 归档。
3. **M5 新 UI 截图重拍**：顶栏铃铛 + `#/notifications`，脱敏后替换 README 截图。
4. **审批与配置增强**：审批 ALL 规则 / 改派 / 事后补审（W20）、ADM 检查清单（W28）、配置页面编辑、报表日期范围参数化。
5. **试点反馈收敛**：按试点结果调整通知事件与严重度、列表默认排序 / 分页、报表口径。

## 附录 A：与 SAP ChaRM 的功能对照

| SAP ChaRM 概念 | 本应用映射 | 一期 | 说明 |
|---|---|---|---|
| Change Request（CR） | `ZCRW_REQ` 聚合根 | 是 | 业务变更请求 |
| Change Document（CD） | `ZCRW_CD` | 是 | 技术批次；一个 CR 可多 CD |
| Task / 工作项 | `ZCRW_TASK`（Task + SubTask） | 是 | 两级 |
| Transport Request（CTS） | `ZCRW_TR`（`TR_KIND=DEV`） | 是 | 不创建/释放/导入 |
| Transport of Copies（ToC） | `ZCRW_TR`（`TR_KIND=TOC`） | 是 | 记录/展示/计划；retrofit 仅标记 |
| Change cycle / project cycle | `ZCRW_CYCLE` 轻量替代 | P1 | 不做阶段审批矩阵 |
| Approval procedure | 审批矩阵（CR + CD，类型 + 优先级） | 是 | 固定步骤，无图形化设计器 |
| Status profile | 状态机（代码常量 + 迁移动作） | 是 | P2 再配置化 |
| Normal / Urgent / Administrative change | CR 类型 `STD` / `URG` / `ADM` | STD 一期；URG P1；ADM P2 | |
| Scheduled import | `ZCRW_SCHED` + 计划视图 + 提醒 | 是（D9） | 不执行 TMS 导入 |
| Retrofit / downgrade protection | 不实现 | 否 | ToC 导入后只标记 retrofit 状态（P1） |
| TMS import orchestration | 只读展示导入状态，导入仍在 STMS | 否 | |
| SMSE / BPM workflow | 站内审批 + 待办；邮件 P2 | 简化 | |
| Reporting / dashboards | 报表模块 + KPI | P1 | |
| Roles/authorization | 应用角色表 + 标准权限检查 | 简化 | 自定义 AUTH 人工配置 |
| 审计/变更历史 | `ZCRW_HIST`（只追加） | 是 | 应用级审计 |

## 附录 B：M0 预检结果与验证清单

### B.1 预检结果（2026-11-01）

| 项 | 结果 |
|---|---|
| abap-cli 版本 | 2.0.0（本地仓库 commit `3dd443d`） |
| `abap doctor` | ok（环境 7 项全部 ok） |
| 内置 ICF 服务 | 已 `abap deploy --yes` 升级：`status=current`、2.0.0 匹配 |
| active profile | `test`（systemVersion 789） |
| `$CRW` 包 | 已创建：super package `$TMP`、DLVUNIT LOCAL、无 transport；AFF 文件在 `apps/change-request-workbench/src/$crw.devc.json` |
| `$CRW` 写路径 | **已验证**：2.0.0 下 create / push / run / delete 全通；class probe 输出 `CRW_M0_OK`，transport 为空，delete 无 `--tr` |
| DDIC TABL probe | **已通过**：`create TABL --file` → `select --count-only`（count=0）→ `delete`（无 `--tr`）→ search 无匹配；对象已清理 |
| CRW 建表 | **已通过**：13 张 `ZCRW_*` 表全部建立，`abap select --count-only` 均 0 行；AFF 在 `apps/change-request-workbench/src/` |
| 锁对象 | **已建**：`EZCRW_REQ` / `EZCRW_CD`（ENQU）；DD25L 验证 `ROOTTAB=ZCRW_REQ` |
| `/ui2/cl_json` + ABAP Unit | **已通过**：classrun 输出 `CRW_M0_JSON_OK`（camelCase + 中文）；`abap test` 1 passed，testclasses sidecar push 可用 |
| CTS 只读 | **已通过**：`E070` / `E071` / `E07T` 可读；`TMSBUFFER` 字段可查 |
| NROB | **已通过（CLI 修复后）**：`ZCRW_REQ` / `ZCRW_CD` / `ZCRW_TASK` 已建；TNRO 3 行，`DTELSOBJ` 为空 |
| MSAG | **已通过（CLI 修复后）**：`ZCRW_MSG` 已建（ADT 失败自动回退 ICF）；T100 8 条 |
| CLI 本地修复 | NROB 空 subType + MSAG ADT→ICF fallback（工作区外 CLI 仓库，当前未提交；原 `c1367d6` 被外部 reset）；完整单测 229 文件 / 2201 用例全绿 |
| MIME/ICF/TRAN/ENQU | ENQU 两个锁对象已建；MIME/ICF/TRAN 留到 M1 与真实 handler/前端一起验证 |
| 本机 Node | 宿主已升级到 Node v24.22.2（CLI 2.0.0 的 Node 24 LTS 要求）；`tmp/` 下的 Electron Node wrapper 仅为历史 fallback，不再需要 |

### B.2 M0 验证清单（待执行）

| # | 验证项 | 命令/方式 | 通过标准 | 状态 |
|---|---|---|---|---|
| 1 | 包与写路径 | `$CRW` 下 `create` + `push` + `run` + `delete` | transport 为空、对象可建可删 | **已通过**（`CRW_M0_OK`） |
| 2 | DDIC 表 | 按 AFF 模板 `create TABL --file`；`select` 验证 | create → select → delete | **已通过**：13 张 CRW 表（0 行） |
| 3 | 号段 | `create NROB --file` | 号段对象可建、可分配号 | **已通过（修复后）**：3 个号段对象已建；区间创建留 bootstrap |
| 4 | 锁对象 | `create ENQU --file` | 锁可加/释放 | **部分通过**：EZCRW_REQ / EZCRW_CD 已建；锁调用留 M1 |
| 5 | 消息类 | `create MSAG --file` | 消息文本可取 | **已通过（修复后）**：ZCRW_MSG / T100 8 条 |
| 6 | ICF 节点 | `create HTTP --file` + 访问 `/sap/bc/zcrw` | 返回页面/JSON | 留到 M1（需 handler 类） |
| 7 | MIME 目录与文件 | `mime create` + `mime push` | 文件可访问 | 留到 M1（需前端资产） |
| 8 | SPA fallback | GET 非 API 路径返回 index.html | 刷新深链不 404 | 留到 M1（随 ICF 节点） |
| 9 | JSON 序列化 | `/ui2/cl_json` 序列化中文/嵌套 | 正确 | **已通过**（`CRW_M0_JSON_OK`） |
| 10 | CTS 读取 | `abap select E070/E071/E07T` | 有数据、字段可判定状态 | **已通过**（只读） |
| 11 | TMS 导入状态 | `abap fields` + `select` 队列表 | 能判定已导入 | 部分：`TMSBUFFER` 字段可查，业务判定留 M3 |
| 12 | ABAP Unit | `abap test <class> --json` | 通过 | **已通过**（1 passed，testclasses sidecar） |
| 13 | 事务码 | `create TRAN --file` | 可跳转 | 留到 M1（AFF 无 URL 事务类型，可能用参数事务/书签替代） |
| 14 | ICF 认证 | 浏览器/ICF 节点登录过程 | 普通用户可访问且鉴权正确 | 留到 M1（需节点与普通用户） |

### B.3 abap-cli 2.0.0 本地包支持（已落地，2026-11-01）

**背景**：abap-cli 1.3.0 的 create / push / delete 只把 `$TMP` 当作免 transport；`$CRW` 等其他 `$` 本地包会报 `NO_TRANSPORT`。

**落地**：本地 CLI 仓库已升级到 2.0.0（`fddd7a9`，合并提交 `3dd443d`）：

- `$` 前缀本地包在 create / push / delete / deploy 全链路免 transport；误传 `--tr` 会被丢弃且不报告为已使用。
- 内置 ICF 服务同步修复：ENQU / NROB create、XSLT create、VIEW / SHLP / TRAN delete 接受任意 `$` 本地包。
- 运行时基线提升到 Node.js 24 LTS。
- 本机已运行 `abap deploy --yes`：`deploy status` = current / 2.0.0。

**验证**：

- 本应用侧 M0 probe 全通过：class（`CRW_M0_OK`）、DDIC TABL、`/ui2/cl_json` + ABAP Unit、CTS 只读；对象已清理。
- CLI 侧提交信息记录 `npm run verify` 与真实 SAP 六阶段运行。

**说明**：升级 CLI 后必须重新运行 `abap deploy --yes` 使 ICF 服务与 CLI 版本匹配；不再需要手工补丁。

### B.4 工具链问题与修复（2026-11-01，M0 发现）

| # | 现象 | 根因 | 处理 | 状态 |
|---|---|---|---|---|
| 1 | NROB create 报 `NROB create needs ... interval.subType` | ICF handler 要求 `subType` 非空；SAP 本身允许无子对象 | 本地 CLI 放宽校验：空 `subType` → 空 `DTELSOBJ`；`abap deploy` 已更新 ICF | **已修复并验证**：`ZCRW_REQ` / `ZCRW_CD` / `ZCRW_TASK` 已建 |
| 2 | MSAG create 报 `No URI-Mapping defined for URI` | 通道探测按 release（789）选 ADT，但本系统 ADT 无 message-class 端点（`profile test`: msag.adt=absent, msag.icf=ok） | 本地 CLI 的 create / pull / push MSAG 在 ADT 端点缺失时自动回退 ICF | **已修复并验证**：`ZCRW_MSG` 已建，T100 8 条 |
| 3 | 建表时 deep / 数值类型报 enhancement category 错误 | ICF 建表 handler 的 exclass 固定为 '2'（Can Be Enhanced (Char. Type)），未从 AFF 读取 | 设计改为 char-only 类型（见 §4.2） | **已按约束落地**；后续可推动 CLI 支持 exclass，再引入 deep/数值类型 |

**说明**：1/2 的 CLI 修复已提交到 `vibe_with_abap` 仓库（MSAG 为 `5cf7395`，NROB 含于 `3dd443d`；CLI 工作区干净）；完整单测 229 文件 / 2201 用例全绿；升级 CLI 后需重新 `abap deploy --yes`。

## 附录 C：文档状态

- `docs/architecture.md`：**已完成（2026-11-02，v1.2.0）**；含系统上下文、类地图、14 表摘要、通知模型 / 触发点 / 去重（§5.8）、`/api/v1` 契约（含通知端点）、部署、安全、版本与 22 项决议（A1–A22）+ v1.2.0 增补（§10.1）。
- `docs/workflow.md`：**已完成（2026-11-02，v1.2.0）**；含 CR/CD/Task 状态机、审批、传输/ToC、导入计划、通知（§9）、审计与错误语义，30 项待定（W1–W30）已冻结（§13）。
- `docs/runbook.md`：**已完成（2026-11-02，v1.2.0 更新）**；含 14 表安装顺序、通知 / 提醒作业（SM36，§2.13）、静态校验、升级、权限与角色、号段、重置、回滚、运维边界与排障（历史实测值以 `<...>` 占位）。
- `apps/change-request-workbench/docs/p2-basis.md`：**新建（2026-11-02）**；P2 basis 类项设计：包迁移（A19 / 工作项 A3）、索引（A20 / D20 / 工作项 D2）、归档（A18）、权限对象（A8）、Fiori/FLP（D22）与 SMTP / SM36 前置。
- `apps/change-request-workbench/README.md`：已完成产品说明、安装/初始化、验证命令、通知能力与当前状态（M5）。
- `docs/handoff.md`：**已完成（2026-11-02）**；新会话交接文档；M1–M5 完成记录与 P2 待办（§14.5 为 M5 记录，实测值待 Lead 回填）。
