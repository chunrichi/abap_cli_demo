# CRW 应用交接文档（Handoff）

> 用途：新会话接手/延续“变更请求工作台（CRW）”应用（M1–M5 已交付，见 §14）。
> 最后更新：2026-11-02（M5：站内通知中心 + 提醒报表）；基线：M4 完成于 2026-11-01 + M5 轮次。
> 工作区：`/Users/lei/Desktop/ai_abap/abap_cli_demo`；应用目录：`apps/change-request-workbench/`。

---

## 0. 新会话启动清单（先做这 6 步）

```bash
cd /Users/lei/Desktop/ai_abap/abap_cli_demo
git branch --show-current                 # 期望 feat/crw-notifications（M5 工作分支）
git log --oneline -5
git status --short
cd apps/change-request-workbench
abap doctor --json
abap deploy status --json
abap run ZCL_CRW_SELFCHECK --json
abap run ZCL_CRW_NOTIFY --json            # 只读通知探测
abap test ZCL_CRW_UTIL --json
abap run ZCL_CRW_M1_SMOKE --json          # 写数据，但会自动清理
```

期望：

- 当前分支 `feat/crw-notifications`；`git status` 中不应有 `.abap.json` / 凭证 / 日志等敏感文件（M5 改动由 Lead 统一提交）。
- `deploy status`：`status=current`、版本与 CLI 匹配（`match=true`）。
- selfcheck：`CRW_SELFCHECK_OK tables=14 rows=… intervals=3 version=1.2.0 messages=8 roles=… approvals=… notifications=… icf=OK cts=OK`。
- 通知探测：`abap run ZCL_CRW_NOTIFY --json` → `CRW_NOTIFY_OK rows=… unread=…`（只读统计）。
- 单测：util `passed=4`、workflow `passed=10`、json `passed=8`、notify `passed=5`（实测 4/4、10/10、8/8、5/5 通过）。
- smoke：`CRW_M1_SMOKE_OK req=… cd=… task=… sub=…`，执行后仅剩种子数据（`ZCRW_REQ/CD/TASK/HIST/NOTIFY` 业务行 0）。
- 演示数据（截图/联调用）：`abap run ZCL_CRW_DEMO_DATA --json` → `CRW_DEMO_DATA_OK requests=3 cds=1 tasks=2 schedules=1 notifications=…`；复位 `abap run ZCL_CRW_TEST_DATA --json`。

然后再读（按顺序）：

1. [`AGENTS.md`](../../../AGENTS.md) §2/§4A/§6/§7/§8/§13（仓库合约与写路径）
2. [`docs/change-request-workbench-plan.md`](../../../docs/change-request-workbench-plan.md)（规划、决策 D1–D25、里程碑）
3. [`architecture.md`](architecture.md)（类地图、数据模型、API 契约、通知模型、部署）
4. [`workflow.md`](workflow.md)（状态机、审批、CTS/计划、通知、审计）
5. [`p2-basis.md`](p2-basis.md)（P2 basis 类项设计：包迁移 / 索引 / 归档 / 权限 / Fiori / SMTP-SM36）
6. [`README.md`](../README.md)（当前状态、安装与验证命令）

技能路由：先 `.agents/skills/abap-cli/SKILL.md`，写 ABAP 前必须读 `.agents/skills/abap-style/SKILL.md`；ICF/MIME 参考 `demos/01-icf-mime-stats/`（handler + MIME + HTTP AFF 的完整参考实现）。

---

## 1. 目标与完成定义

**产品目标**：在 SAP 内实现 ChaRM 风格的变更请求工作台，管理
`Change Request → Change Document → Task/SubTask → Transport（DEV/ToC）→ 测试 → 计划导入 → 关闭`。

**这是真实应用，不是 demo**：对象 `ZCRW_*` / `ZCL_CRW_*` / `ZIF_CRW_*` / `ZCX_CRW_*`，包 `$CRW`；不使用 `DMA`、不写 demo 编号；UI 使用 ICF + MIME + 原生 ES modules，零构建、零外部依赖。

“完成”的验收口径：

- M1–M5 全部走通：标准变更全流程 + 紧急/管理类型的 P1 项 + 站内通知与提醒扫描。
- CR/CD/Task 状态机、审批、审计、角色鉴权、乐观锁、通知去重可被 ABAP Unit 与只读 `select` 验证。
- CTS 只读集成（D4/D8：实现但不做 live 验证），导入计划可用（D9：只提醒、不执行 TMS），通知可用（站内即时 + 日报表扫描）。
- 主页面（含 `#/notifications`）可用并有脱敏截图（M5 已重拍 9 张，见 README）；`docs/runbook.md` 可安装/升级。
- `abap check content` / `validate:aff` / `abap test` / selfcheck / smoke / 只读断言全部通过；连续两次一致。
- 无业务数据残留、无 URL/凭证/真实数据入库、不碰生产、不 release transport。

---

## 2. 当前完成度（事实清单，2026-11-02）

### 2.1 已完成

| 项 | 内容 | 验证 |
|---|---|---|
| M0 工具链 | abap-cli 2.0.0（Node 24）、内置 ICF 2.0.0 current、`$CRW` 本地包、`$` 本地包写路径 | `abap deploy status` / create-push-run-delete probe |
| M0 能力验证 | DDIC TABL、`/ui2/cl_json`、ABAP Unit、CTS 只读（E070/E071/E07T/TMSBUFFER）、ENQU、NROB、MSAG | 见规划附录 B |
| 数据模型 | 14 张 `ZCRW_*` 表，均 active（M5 新增 `ZCRW_NOTIFY`） | `DD02L` count=14 |
| 号段 | `ZCRW_REQ` / `ZCRW_CD` / `ZCRW_TASK`，区间 `01`（1..9999999999） | `NRIV` 3 行 |
| 消息类 | `ZCRW_MSG`，8 条 | `T100` 8 行 |
| 锁对象 | `EZCRW_REQ`（主表 `ZCRW_REQ`）、`EZCRW_CD`（主表 `ZCRW_CD`） | `DD25L` 2 行 |
| 初始化 | `ZCL_CRW_BOOTSTRAP`：号段区间 + version/审批矩阵/ADMIN 角色种子；幂等 | 首跑 `intervals=2 config=3`，再跑 `0/0`；M5 起版本 1.2.0 |
| 自检 | `ZCL_CRW_SELFCHECK`：14 表 + 区间 + 版本 + 消息类 + 角色 + 审批矩阵 + 通知数；只读 | `CRW_SELFCHECK_OK …` |
| 通知 | `ZCRW_NOTIFY` + `ZCL_CRW_NOTIFY` / `ZCL_CRW_API_NOTIFY` + 报表 `ZCRW_REMIND_JOB`；顶栏铃铛 + `#/notifications` | `CRW_NOTIFY_OK …`；通知页可见 |
| 服务层 | `ZCL_CRW_UTIL` / `_NUMBER` / `_AUDIT` / `_REQUEST_SVC` / `_CD_SVC` / `_TASK_SVC` / `ZCX_CRW_ERROR` | 语法/激活通过 |
| 端到端 | `ZCL_CRW_M1_SMOKE`：CR→CD→Task/SubTask、状态迁移、审计、自动清理 | `CRW_M1_SMOKE_OK …`，残留 0 行 |
| 单测 | `ZCL_CRW_UTIL` 4 个测试 | `passed=4` |
| 文档 | 规划 v8、architecture v1（740 行）、workflow v1（717 行）、README | 已提交 |

当前 SAP 侧**只有种子数据**：`ZCRW_VERSION` 1 行、`ZCRW_APPR_CFG` 1 行、`ZCRW_ROLE` 1 行、`T100` 8 条、`NRIV` 3 行；无 CR/CD/TASK/HIST 业务数据。

### 2.2 剩余（P2，详见 §14.3）

M1–M5 已于 2026-11-02 全部交付（API/UI/审批/锁/CTS/计划/报表/配置/迁移/通知/截图）。剩余为 P2：可传输包迁移（A19 / 工作项 A3）、索引（A20 / D20 / 工作项 D2）、数据归档（A18）、权限对象（A8）、Fiori tile、邮件通道启用（SMTP/SCOT 待 basis）、SM36 每日作业 `ZCRW_REMIND`（待 basis）、审批 ALL/改派/补审、ADM 检查清单、配置编辑、报表日期参数。

### 2.3 仓库/提交

| 仓库 | 状态 |
|---|---|
| `abap_cli_demo`（当前） | 工作分支 `feat/crw-notifications`（Lead 创建）；M5 代码 / 文档改动待 Lead 统一提交；仓库已发布到 GitHub（决策与流程见 `docs/github-workflow.md` / `CONTRIBUTING.md`） |
| `vibe_with_abap`（CLI） | abap-cli 2.0.1；NROB 空 subType、MSAG ADT→ICF fallback 修复已提交（见 `AGENTS.md` §13）；升级后需重新 `abap deploy --yes` |

⚠️ 新会话不要对他人仓库执行 `git reset --hard` / `git checkout .`；先 `git -C /Users/lei/Desktop/ai_abap/vibe_with_abap status` 确认状态，改动只在 CRW 仓库内进行。

---

## 3. 环境、对象与代码地图

### 3.1 环境

| 项 | 值 |
|---|---|
| SAP profile | `test`（S/4，systemVersion 789，client 100） |
| abap-cli | 2.0.1（Node 24 LTS），全局 `abap` 命令 |
| 内置 ICF | 部署 current（版本与 CLI 匹配） |
| 应用包 | `$CRW`（本地包，super `$TMP`，DLVUNIT LOCAL，无 transport） |
| app ICF | `ZCRW_APP` → `/sap/bc/zcrw`（已创建） |
| MIME 根 | `/zcrw`（已创建，含 `js/pages/notifications.js`） |
| 事务码 | `ZCRW`（报表事务 → `ZCRW_START`） |
| 已知警告 | `SESSION_STORE_FALLBACK` / `SESSION_REUSE_UNSTABLE` 是 CLI 会话存储提示，不影响结果 |

### 3.2 SAP 对象（`$CRW`，TADIR 113 项（M5 后实测；M5 前基线 108））

- 表（14）：`ZCRW_REQ` / `_CD` / `_TASK` / `_TR` / `_SCHED` / `_APPR` / `_HIST` / `_NOTE` / `_CYCLE` / `_ROLE` / `_APPR_CFG` / `_VERSION` / `_LOG` / `_NOTIFY`
- 类（M5 后约 38）：`ZCL_CRW_UTIL` / `_NUMBER` / `_AUDIT` / `_AUTH` / `_WORKFLOW` / `_REQUEST_SVC` / `_CD_SVC` / `_TASK_SVC` / `_APPR_SVC` / `_TRANSPORT_SVC` / `_SCHEDULE_SVC` / `_REPORT_SVC` / `_NOTIFY` / `_BOOTSTRAP` / `_MIGRATION` / `_SELFCHECK` / `_M1_SMOKE` / `_TEST_DATA` / `_DEMO_DATA` / `_API_*` / `_HTTP_HANDLER` / `ZCX_CRW_ERROR` 等
- 程序（2）：`ZCRW_START`（事务码入口）/ `ZCRW_REMIND_JOB`（提醒报表）
- 号段（3）：`ZCRW_REQ` / `ZCRW_CD` / `ZCRW_TASK`
- 消息类：`ZCRW_MSG`
- 锁对象（2）：`EZCRW_REQ` / `EZCRW_CD`
- ICF（1）：`ZCRW_APP`；事务码（1）：`ZCRW`；MIME：56 项
- 迁移基线（包迁移用）：TADIR 113 项（M5 后实测；M5 前基线 108）；接口（1）：`ZIF_CRW_CTS_READER`

### 3.3 `src/` 文件

```
apps/change-request-workbench/src/
├── $crw.devc.json                  # 包 AFF（重建用）
├── ezcrw_req.enqu.json / ezcrw_cd.enqu.json
├── zcrw_req/cd/task.nrob.json      # 号段
├── zcrw_msg.msag.json              # 消息类
├── zcrw_<entity>.tabl.{json,ddic,settings.json}   # 14 张表（M5 含 zcrw_notify）
├── zcl_crw_<role>.clas.abap        # 服务/工具/初始化/自检/smoke/通知
├── zcl_crw_<role>.clas.testclasses.abap  # ABAP Unit sidecar（util / workflow / json / notify）
├── zcrw_start.prog.abap            # 事务码入口报表
├── zcrw_remind_job.prog.abap       # 提醒报表（SM36 可调度）
├── zcrw_app.http.json / zcrw.tran.json
└── mime/                           # 前端资产（index.html / styles.css / js/）
```

- 类文件用**单文件** `.clas.abap`；不要提交 CLI 自动生成的 `.clas.definitions.abap` / `.implementations.abap` / `.macros.abap` / `.clas.json` 等拆分副产物。
- 前端资产在 `src/mime/`；截图放 `screenshots/`（M5 已重拍 9 张）。
- `tmp/` 已 gitignore；不要提交拉取副产物。

---

## 4. 已验证的运维/验证命令

```bash
cd apps/change-request-workbench

# 环境
abap doctor --json
abap deploy status --json

# 只读自检（README 运行验证可用）
abap run ZCL_CRW_SELFCHECK --json

# 单元测试
abap test ZCL_CRW_UTIL --json
abap test ZCL_CRW_NOTIFY --json

# 通知只读探测
abap run ZCL_CRW_NOTIFY --json

# 幂等初始化（写：仅首次生效）
abap run ZCL_CRW_BOOTSTRAP --json

# 端到端冒烟（写 + 自动清理）
abap run ZCL_CRW_M1_SMOKE --json

# 提醒报表（写通知；运维步骤，非只读验证）
abap run-report ZCRW_REMIND_JOB --json

# 只读断言
abap select --table DD02L --where "TABNAME LIKE 'ZCRW%'" --count-only --json
abap select --table ZCRW_NOTIFY --count-only --json
abap select --table NRIV --where "OBJECT LIKE 'ZCRW%'" --json
abap select --table T100 --where "ARBGB = 'ZCRW_MSG'" --json
```

注意：`ZCL_CRW_SELFCHECK` / `ZCL_CRW_NOTIFY`（classrun 只统计）必须保持只读；`ZCL_CRW_BOOTSTRAP` / `ZCL_CRW_M1_SMOKE` / `ZCRW_REMIND_JOB` 会写数据，只能放在“安装与初始化/开发验证/运维”，不要放进只读的“运行与验证”清单。

---

## 5. 下一步工作分解（按顺序，可直接开工）

### Phase 1 — 冻结契约（0.5–1 天，先做）

1. 按 §6 的建议冻结关键待定项，回写 `architecture.md` / `workflow.md` / 规划，规划升 v9。
2. 补 `docs/runbook.md` 骨架（安装顺序、MIME/ICF 步骤、权限、号段、重置、回滚）。
3. 确认 CLI 仓库修复状态（见 §2.3），必要时提交。

验收：文档中不再有影响 M1/M2 实现的“待定”；`abap check content` 全绿。

### Phase 2 — `/api/v1` + ICF 节点（M1 核心，2–3 天）

新增对象（建议按此命名）：

| 对象 | 职责 |
|---|---|
| `ZCL_CRW_HTTP_HANDLER` | `IF_HTTP_EXTENSION~HANDLE_REQUEST`；区分 `/api/v1/*`、静态资源、SPA fallback |
| `ZCL_CRW_API_ROUTER` | 方法+路径匹配、参数解析、controller 分发、异常→错误信封 |
| `ZCL_CRW_API_CONTEXT` | 当前用户、角色、correlation id、请求体 |
| `ZCL_CRW_JSON` | `/ui2/cl_json` 封装（camelCase、错误信封） |
| `ZCL_CRW_API_REQUEST` / `_CD` / `_TASK` | P0 controller：列表/详情/创建/状态动作 |

P0 端点（完整 40 个见 architecture §6.2）：

- `GET /api/v1/me`、`GET /api/v1/health`
- `GET/POST /api/v1/requests`、`GET/PATCH /api/v1/requests/{id}`、`POST /api/v1/requests/{id}/actions`
- `GET /api/v1/change-documents`、`GET/PATCH /api/v1/change-documents/{id}`、`POST /api/v1/change-documents/{id}/actions`
- `GET /api/v1/tasks`、`GET/PATCH /api/v1/tasks/{id}`、`POST /api/v1/tasks/{id}/actions`
- `GET /api/v1/requests/{id}/history`（P0 只读）
- `GET /api/v1/requests` 先支持 `page/size/status/owner`；排序白名单先冻结 `createdAt/id/title/status`

实现步骤：

1. 复制 `demos/01-icf-mime-stats/src/zcl_dma_01_stats.clas.abap` 的 handler/MIME 读取模式（不要复用对象名）。
2. 写 `ZCL_CRW_HTTP_HANDLER` + router + P0 controller；`check syntax` → `push` → `abap run`/浏览器验证。
3. 建 `src/zcrw_app.http.json`（`handlerClass=ZCL_CRW_HTTP_HANDLER`、`servicePath=/sap/bc/zcrw`）；`abap create HTTP` 需要临时副本加顶层 `name`（参考 01 demo 的 S7）。
4. 用浏览器打开 `/sap/bc/zcrw/api/v1/health`（先走 SAP 登录）；验证 JSON 200。
5. 记录未登录 / 401 行为（A1），决定 JSON 401 vs 登录重定向。

验收：health/me 返回 JSON；CR 列表/详情/创建/动作经 API 走通；错误码符合 architecture §6.4；`abap test` 至少覆盖 router 映射与错误信封。

### Phase 3 — MIME + SPA 前端（M1，3–5 天）

1. `src/mime/`：`index.html`、`styles.css`、`app.js` + 按页面拆 ES modules；零依赖、无 CDN。
2. 页面 P0：工作台（列表+筛选+KPI）、CR 详情（头部/动作/CD/任务/历史）、CD 详情（头部/任务/传输/计划）、任务列表、审批中心（P1）、传输/计划（P1）。
3. 用 `abap mime create /zcrw --package '$CRW' …` + `abap mime push src/mime --root /zcrw --yes --json`；验证 MIME 目录/文件/子目录。
4. 验证 SPA fallback：非 API GET 返回 `index.html` 200；刷新深链不 404。
5. 验证 ICF 认证（普通用户可访问且鉴权正确）。
6. 截取 6 个页面截图（脱敏），放 `screenshots/` 并在 README 嵌入。

验收：六个页面可用；截图脱敏；MIME/SPA/认证三项 M0 遗留检查通过；前端不直连 SAP 内部表，只走 API。

### Phase 4 — 审批 / 角色 / 历史（M1–M2，2–3 天）

1. 冻结角色矩阵（7 角色）与数据范围；新增 `ZCL_CRW_AUTH`。
2. `ZCL_CRW_APPR_SVC`：生成步骤、通过/驳回、跳过、改派；`ZCRW_APPR` + `ZCRW_APPR_CFG`。
3. 历史查询 API + 备注 API（`ZCRW_HIST` / `ZCRW_NOTE`）。
4. CR/CD 状态动作加角色守卫、锁对象、版本校验；非法动作/越权/并发返回契约错误码。
5. 状态机单测：用 testclasses sidecar 覆盖每个状态的所有合法/非法迁移（不写真实数据，纯逻辑）。

验收：审批链路 CR 提交→审批→通过→可建 CD；驳回/跳过/越权/并发均有测试；`abap test` 全绿。

### Phase 5 — M2 流程闭环（2–3 天）

- 任务板/我的工作、KPI/仪表盘、历史/备注 UI。
- 审批中心页面、任务看板（P1）。
- 测试数据 reset 类 `ZCL_CRW_TEST_DATA`（准备/清理，幂等）；连续两次跑一致。
- 锁对象真正调用（`ENQUEUE_EZCRW_REQ` / `_CD`），锁冲突返回 `OBJECT_LOCKED`。

### Phase 6 — M3 传输 / ToC / 计划（3–5 天）

1. `ZIF_CRW_CTS_READER` + `ZCL_CRW_CTS_ADAPTER`：只读 `E070` / `E071` / `E07T` / `TMSBUFFER`；不 release、不执行 TMS。
2. `ZCL_CRW_TRANSPORT_SVC`：手工关联 DEV/ToC、解绑/标记解绑、同步状态快照（`ZCRW_TR`）。
3. `ZCL_CRW_SCHEDULE_SVC`：计划创建/改期/取消、到期/逾期计算（读取时计算，无后台作业）、导入确认（不执行 TMS）。
4. 页面：传输工作台、计划视图；逾期/未关联告警。
5. 降级：CTS 读取失败返回 `CTS_READ_ERROR`/未知状态，页面可展示人工确认。

### Phase 7 — M4 报表与产品化（2–3 天）

- 报表：变更分布/趋势、审批时长、逾期、ToC 漏斗、CSV 导出。
- 配置 UI（周期/审批矩阵/角色）；版本迁移 `ZCL_CRW_MIGRATION`。
- runbook 完整化、性能（1 万 CR 规模 p95）、截图更新、试点反馈。
- 产品化路径（P2）：`$CRW` 本地包不可跨系统，需迁移到可传输包；AFF 已按单一来源管理。

---

## 6. 关键待定项与建议默认值

完整清单：architecture §10 A1–A22、workflow 附录 W1–W30。以下 12 项会阻塞 M1/M2，建议**默认采纳**（除非用户另行指定）：

| ID | 问题 | 建议默认 | 影响/备注 |
|---|---|---|---|
| D11 | `PRIORITY` 编码（CHAR2） | `1`=紧急、`2`=高、`3`=中、`4`=低；空=未定 | 现有 smoke 用 `3`；UI 映射中文标签；审批矩阵空值通配 |
| D12 | `APPROVAL_STATE` 枚举 | `NONE` / `PENDING` / `APPROVED` / `REJECTED` / `SKIPPED` | 创建时 `NONE`，提交时 `PENDING`；当前代码创建即 `PENDING`，需调整 |
| D13 | 审批“任意/全部”规则 | v1 默认 `ANY`；表暂不加字段，命中多人时任一人通过即推进 | 需 `ZCRW_APPR_CFG` 加 `APPROVAL_RULE` 时需重建表（CLI 无 ALTER） |
| D14 | `CONFIRM_IMPORT` 来源态 | 允许 `READY_TO_IMPORT` / `IMPORT_SCHEDULED`；已 `IMPORTED` 重复提交返回 `INVALID_TRANSITION` | 其他态拒绝 |
| D15 | `PLANNED_IMPORT_AT` 与 `ZCRW_SCHED` 权威 | `ZCRW_SCHED` 为权威；`ZCRW_CD.PLANNED_IMPORT_AT` 只做冗余展示，计划创建/改期时同步 | 避免双写漂移 |
| D16 | 时区基准 | 存 SAP 系统本地时间（`sy-datum` + `sy-uzeit`），CHAR14；API 返回 `yyyy-MM-ddTHH:mm:ss` + `timezone:"SAP_SYSTEM"` | 不做跨时区换算；UI 只显示 |
| D17 | NEW 状态 CR 删除 | 不提供物理 DELETE；用 `CANCELLED` 软取消，历史保留；API 无 DELETE | 与审计只追加一致；若用户坚持删除，需设计软删标记 |
| D18 | `ZCRW_HIST.OBJECT_TYPE` 是否含 `NOTE` | v1 不含；备注通过 `ZCRW_NOTE` 自身留痕 | 如需要再加 `NOTE` |
| D19 | 状态机/仓储拆分与审计类命名 | M1 保持 `*_SVC` 内联校验 + `ZCL_CRW_AUDIT`；M2 再抽 `ZCL_CRW_WORKFLOW`，不重命名 AUDIT | 避免 M1 返工；A22 已记录 |
| D20 | 索引策略 | M1 不做二级索引；M4 压测后按需建（需 GUI/DB02） | CLI 2.0.0 无建索引入口 |
| D21 | ICF 未登录行为 | `/api/v1/*` 返回 JSON 401；页面路由重定向登录页 | 待 ICF 节点实测确认（A1） |
| D22 | 事务码 `ZCRW` | 先做 SAP GUI 参数事务/报表事务 `ZCRW_START`，调用 `cl_gui_frontend_services=>execute` 打开 ICF URL；P2 再评估 Fiori tile | AFF 无 URL 类型 TRAN；需实测 |
| D23 | 自检 CTS/ICF 检查 | M2 补 `ZCL_CRW_SELFCHECK`：ICF 节点存在 + E070 可读（只读） | A11 |

> 冻结后把决定写回 `architecture.md` 的 §10、`workflow.md` 的待定附录和规划 §12；不要只改代码不改文档。

---

## 7. 已知坑与操作规范（重要）

1. **CLI 仓库会被外部 reset**：当前 `vibe_with_abap` 的 NROB/MSAG 修复是未提交改动；新会话先 `git status`，不要 reset，先提交/备份。`abap deploy` 已把含 NROB 修复的 ICF 服务部署到 2.0.0；CLI 的 MSAG fallback 在 `dist` 中，若重新 build 需确保源码修改还在。
2. **本地包无 transport**：所有写命令不要传 `--tr`；`$CRW` → `NO_TRANSPORT` 已由 2.0.0 解决。不要误删 `$CRW` 包或批量删对象。
3. **自定义 ICF 节点不是 `abap deploy`**：`abap deploy` 只更新内置服务；应用节点用 `abap create HTTP … --file …`（需临时副本顶层 `name`），handler 类必须先激活。
4. **建表限制（char-only）**：ICF handler 的 exclass 固定为 char 类型；字段只能用 `CHAR/NUMC/DATS/TIMS`。时间戳 `CHAR14`、GUID `CHAR32`、版本 `NUMC6`、工时 `NUMC5`；不要用 `STRING/TIMESTAMPL/INT4/RAW16`。
5. **表结构变更代价高**：CLI 2.0.0 没有 ALTER；加字段/改类型要删除重建表（数据丢失）。新增字段前先想清楚，或走新表/迁移程序。
6. **`COMMENT` 是保留字**：字段名用 `COMMENT_TXT`（已固定）。
7. **ABAP 参数类型兼容**：定长 `CHAR` 之间长度不同不能直接传给形参；`TYPE string` 形参也不能直接接收 `CHAR10`（需 `CONV string( … )`）。`ZCL_CRW_AUDIT` 的参数已是 string，调用时变量要 `CONV string`；字面量可以直接传。
8. **号段区间创建**：`NUMBER_RANGE_UPDATE_INIT` → `NUMBER_RANGE_INTERVAL_UPDATE`（`INRIV` 表，`PROCIND='I'`）→ `NUMBER_RANGE_UPDATE_CLOSE`（`commit=abap_true`）；`ERROR_IV` 必须传空表；否则 NROB 对象存在但没有区间，`NUMBER_GET_NEXT` 失败。
9. **DB INSERT 不支持 `ACCEPTING DUPLICATE KEYS`**：该语法在本地校验报错；用 `INSERT …` + `sy-subrc = 4` 判断重复，或先 SELECT。
10. **班级 AFF 文件**：单文件 `.clas.abap`；不要提交 push 生成的 `definitions/implementations/macros/json` 拆分副产物；testclasses 用 `.clas.testclasses.abap`，`abap test` 可识别。
11. **验证只读**：README 的“运行与验证”只能用只读命令；`BOOTSTRAP`/`SMOKE`/`TEST_DATA` 属安装/开发步骤，写到“安装与初始化”或开发文档。`SMOKE` 写后必须清理。
12. **CTS 只读**：`E070/E071/E07T/TMSBUFFER` 只读；不 release transport、不执行 TMS 导入、不做 live 验证（D4/D8）。手工关联即可。
13. **不碰生产**：只对 `test` profile 写；不提交 `.abap.json`、URL、用户名、真实业务数据；截图脱敏。
14. **会话警告**：`SESSION_STORE_FALLBACK` / `SESSION_REUSE_UNSTABLE` 不影响命令结果，不必修。
15. **号段有空洞**：冒烟测试消耗过 REQ 号（NRLEVEL=4），这是正常的；不要手工重置 NRIV。
16. **通知去重是「一次事件一条」**：`dedup_key = USER_ID + DEDUP_KEY`，已存在（含已读 / 已忽略）**不会重建**；不要为「重新提醒」手工删通知，应由新的业务事件（新 `APPR_ID` / 新 `DUE_DATE`）产生新键。
17. **通知 / 邮件边界**：站内通知已实现；`deliver_email` 只是预留，SMTP 未配置时**不发信**，不要把它当失败；`SM36` 作业 `ZCRW_REMIND` 本轮未建，由 basis 按 runbook §2.13 配置。
18. **提醒报表会写数据**：`abap run-report ZCRW_REMIND_JOB` 会生成 `ZCRW_NOTIFY` 记录，不是只读验证命令；只读探测用 `abap run ZCL_CRW_NOTIFY --json`（classrun 只统计）。

---

## 8. 并行/Agent Teams 建议

- **可并行**：架构/契约文档、前端静态资源（`src/mime/`）、ABAP Unit 测试骨架、runbook/截图、测试数据 reset 类。
- **写 SAP 必须串行/分对象**：同一时间只让一个成员执行 `abap create/push/delete`，避免 AFF 文件与 SAP 激活竞争；不同对象前缀也不行（CLI 会话与 ICF 会话可能互相影响）。
- 建议分工：Lead 负责 API/服务/状态机；teammate A 负责 MIME/SPA 页面（只写 `src/mime/` + 截图）；teammate B 负责 docs/runbook/测试清单。共享任务写清楚 write scopes。
- 每完成一个页面/端点，立即跑 `check syntax`/`push`/`abap test`，不要攒到最后。

---

## 9. 验收清单（完成时逐项打勾）

- [ ] M1 API：P0 端点全部返回契约 JSON；401/403/404/409/500 映射正确
- [ ] M1 UI：工作台/CR 列表/CR 详情/CD 详情/审批/传输或计划 六个页面可用并截图
- [ ] MIME 目录/子目录/SPA fallback/ICF 认证验证通过
- [ ] 审批：提交→审批→通过/驳回/跳过；请求人不能自审；审批人匹配
- [ ] 角色：7 角色 + 数据范围；越权用例被拒
- [ ] 状态机：CR/CD/Task 所有迁移有单测；非法迁移/并发冲突被拒
- [ ] 历史/备注：只追加、可分页查询；审计字段完整
- [ ] CTS：E070/E071/E07T/TMSBUFFER 只读；DEV/ToC 手工关联；解绑标记；失败降级
- [ ] 计划：创建/改期/取消、到期/逾期计算、导入确认（不执行 TMS）
- [ ] 报表：分布/时长/逾期/ToC/CSV
- [ ] selfcheck 覆盖表/号段/版本/消息类/角色/审批/ICF/CTS
- [ ] `abap test` 全绿；`validate:aff`/`check content` 全绿
- [ ] 连续两次 bootstrap/selfcheck/smoke/测试数据 reset 结果一致
- [ ] 无业务数据残留；`abap select` 只读断言通过
- [ ] `docs/runbook.md` + README + 截图齐全；无 URL/凭证/真实数据
- [ ] 每个里程碑一个 commit；工作区干净

---

## 10. 关键文件与提交

| 资源 | 路径 |
|---|---|
| 仓库合约 | [`AGENTS.md`](../../../AGENTS.md) |
| 规划/决策 | [`docs/change-request-workbench-plan.md`](../../../docs/change-request-workbench-plan.md) |
| 架构/API 契约 | [`apps/change-request-workbench/docs/architecture.md`](architecture.md) |
| 状态机/审批/CTS 契约 | [`apps/change-request-workbench/docs/workflow.md`](workflow.md) |
| P2 basis 类项设计 | [`apps/change-request-workbench/docs/p2-basis.md`](p2-basis.md) |
| 应用 README | [`apps/change-request-workbench/README.md`](../README.md) |
| ICF/MIME 参考实现 | [`demos/01-icf-mime-stats/`](../../../demos/01-icf-mime-stats/) |
| ABAP 风格 | [`.agents/skills/abap-style/SKILL.md`](../../../.agents/skills/abap-style/SKILL.md) |
| CLI 路由 skill | [`.agents/skills/abap-cli/SKILL.md`](../../../.agents/skills/abap-cli/SKILL.md) |
| demo 仓库提交 | `254988e`（docs+services）、`a5210ce`、`91c8c23`、`83f859a`、`bd4f412` |
| CLI 仓库 | `vibe_with_abap`，2.0.0；NROB/MSAG 修复未提交（原 `c1367d6` 被 reset） |

---

## 11. 可以直接复制给新会话的 Prompt

```text
你是接手 CRW（变更请求工作台）的新会话，工作区 /Users/lei/Desktop/ai_abap/abap_cli_demo。
先完整阅读 apps/change-request-workbench/docs/handoff.md，然后按其中“新会话启动清单”执行环境检查。
目标：完成 CRW 应用（M1 API/UI → M2 流程闭环 → M3 传输/计划 → M4 报表/产品化）。
约束：
- 遵循 AGENTS.md §4A（apps 应用契约）；对象前缀 ZCRW_/ZCL_CRW_/ZIF_CRW_/ZCX_CRW_，包 $CRW；
- 不碰生产；不 release transport；不 push --all；不批量删对象；写 ABAP 前读 .agents/skills/abap-style/SKILL.md；
- 每里程碑一个 commit；验证只用只读命令，写数据的 bootstrap/smoke 放在安装/开发步骤；
- CLI 仓库可能有未提交的 NROB/MSAG 修复，先 git status 保护，不要 reset。
先做 Phase 1（冻结 handoff §6 的待定项并回写文档），再按 Phase 2–7 顺序实现；每完成一个阶段跑 handoff §4 的验证命令并汇报。
```

---

## 14. M1–M5 完成记录（M1–M4：2026-11-01；M5：2026-11-02）

### 14.1 交付

- **M1**：数据模型/服务层（既有延续）；`/api/v1`（`ZCL_CRW_API_ROUTER` / `_HTTP_HANDLER` / 控制器）；ICF 节点 `ZCRW_APP`；MIME/SPA（`src/mime/`，15 页面）；事务码 `ZCRW`（报表事务 → `ZCRW_START`）；`/health`、`/me`、`/dashboard`；审批步骤服务。
- **M2**：`ZCL_CRW_WORKFLOW`（纯逻辑，单测 10）；CR/CD/Task 动作与守卫；两级审批（矩阵、ANY、驳回填意见、自审拦截、SKIP）；ENQUEUE 锁；历史/备注 API；我的工作/审批中心/看板；乐观锁与 409。
- **M3**：`ZIF_CRW_CTS_READER` + `ZCL_CRW_CTS_ADAPTER`（E070/E071/E07T/TMSBUFFER 只读 + 降级）；传输关联/解绑/标记/同步；导入计划改期/取消/确认/逾期；CD 计划快照；传输工作台与计划页面。
- **M4**：报表（分布/趋势、时长、逾期、ToC、CSV）；配置只读页面；`ZCL_CRW_MIGRATION`；runbook；脱敏截图；`ZCL_CRW_DEMO_DATA`。
- **M5（P2 通知与提醒）**：`ZCRW_NOTIFY` + `ZCL_CRW_NOTIFY` / `ZCL_CRW_API_NOTIFY`（通知服务 / API / DTO）；审批事件钩子（生成 / 驳回）；顶栏铃铛 + `#/notifications` 页面；`ZCRW_REMIND_JOB` 提醒报表（SM36 可调度）；`ZCL_CRW_SELFCHECK` 升到 14 表并输出 `notifications=`；bootstrap / migration 版本 1.2.0；`deliver_email` 邮件通道预留。
- **验证（M5 实测）**：selfcheck `tables=14 rows=7 intervals=3 version=1.2.0 messages=8 roles=1 approvals=2 notifications=0 icf=OK cts=OK`（复位后）；`abap test ZCL_CRW_NOTIFY` 5/5；`abap run ZCL_CRW_NOTIFY` → `CRW_NOTIFY_OK rows=0 unread=0`（复位后；演示数据后 rows=2 unread=2）；`abap run-report ZCRW_REMIND_JOB` → `ZCRW_REMIND_JOB_OK approvals=0 tasks=0 schedules=0 total=0`（演示数据刷新后运行，去重生效）；通知 API 控制器探针（列表/未读数/刷新/已读/全部已读）返回契约 JSON；浏览器页面与 HTTP 端到端待人工复核。
- **提交**：`c3a8d19`（Phase 1 冻结）、`fbe659c`（Phase 2 API），Phase 3–7 见 `git log`；M5 提交见本轮 `feat/crw-notifications`。

### 14.2 实测口径与坑

- ICF：节点创建后需再 `abap activate ZCL_CRW_HTTP_HANDLER`，否则 500 `Class interface changed at runtime`；无尾斜杠 `/sap/bc/zcrw` 已 302 到带斜杠地址。
- MIME：`abap mime push <dir>` 会把目录内容**扁平**上传到 `--root`；必须按层级分别 push（runbook S9），且偶发单文件未落地时按文件重推。M5 新增 `js/pages/notifications.js` 与样式，按页分别重推后验证 200。
- 未登录：`/api/v1/*` 由 ICF 标准登录过程接管，返回 401 + 登录页（非 JSON）；D21 实测结论。
- ENQU：AFF 的 `lockParameters[].active` 必须显式为 `true`，否则生成的 `ENQUEUE_*` 只有 `MODE_*` 参数（已修正并重推）。
- ABAP 类缓存：`abap push` 后 `abap run` 可能仍执行旧版本，`abap session reset` 后重跑可刷新（HTTP 侧同理，必要时重激活 handler）。
- `ZCRW_HIST.OBJECT_ID` 为 CHAR20，放不下 32 字符的计划 UUID：动态/历史按前缀回查（已实现）。
- `abap-cli` 在 HOME 不可写时会回退 workspace session store；为稳定写路径本会话使用了临时 HOME + fixture keychain + derived session key（`tmp/abapx` 属历史做法，gitignored，不属交付物）。
- **M5 通知**：`dedup_key` 去重为「一次事件一条」（已读 / 已忽略不重建）；`deliver_email` 是预留空实现，SMTP 未配置不发信；提醒报表会写 `ZCRW_NOTIFY`（属运维步骤）。

### 14.3 P2 待办（M5 后）

可传输包迁移（A19 / 工作项 A3，暂不做）；二级索引（A20 / D20 / 工作项 D2，后置）；数据归档（A18，只设计）；权限对象（A8，只设计）；Fiori tile / FLP（D22，不采用，可选 URL tile）；邮件通道启用（SMTP/SCOT 待 basis）；SM36 每日作业 `ZCRW_REMIND`（待 basis）；审批 ALL 规则、改派、事后补审；ADM 检查清单（W28）；配置页面编辑；报表日期范围；M5 新 UI 截图重拍。以上设计见 [`p2-basis.md`](p2-basis.md)。

### 14.4 下个会话启动（P2）

同 §0，另加：

1. `git log --oneline -10` 了解 M1–M5 提交；读 `README.md` 当前状态与 `docs/runbook.md` §10。
2. `abap run ZCL_CRW_SELFCHECK --json` 应输出 `tables=14 version=1.2.0 icf=OK cts=OK`；`abap run ZCL_CRW_NOTIFY --json` 应输出 `CRW_NOTIFY_OK`；`abap tcode ZCRW --json` 应解析到 `ZCRW_START`。
3. 若环境需干净数据：`abap run ZCL_CRW_TEST_DATA --json`（写数据，属开发步骤；会清 `ZCRW_NOTIFY`）。
4. P2 涉及包迁移 / 权限对象 / 归档 / SMTP / SM36 等 basis 配置，先与用户确认环境与范围，按 [`p2-basis.md`](p2-basis.md) 的 owner / 前置 / 验收执行。

### 14.5 M5 完成记录（2026-11-02，P2 通知与提醒）

**交付清单**

| 类别 | 内容 |
|---|---|
| DDIC | `ZCRW_NOTIFY`（14 表，版本 1.2.0；`notify_id` CHAR32 主键、`dedup_key` CHAR80 等） |
| 服务 | `ZCL_CRW_NOTIFY`：`emit`（发布通知，dedup）/ `refresh_for_user` / `run_scan` / `list_for_user` / `unread_count` / `mark_read` / `mark_all_read`；事件钩子 `notify_approval_pending` / `notify_approval_rejected`；邮件预留 `deliver_email`；classrun 只读探测 `CRW_NOTIFY_OK rows=… unread=…`；单测 5 例 |
| API | `ZCL_CRW_API_NOTIFY`：`GET /notifications`、`GET /notifications/unread-count`、`POST /notifications/refresh`、`POST /notifications/{id}/read`、`POST /notifications/read-all`（写保护 `X-CRW-Request: 1`） |
| 集成 | `ZCL_CRW_APPR_SVC` 生成步骤 / 驳回时建通知；`ZCL_CRW_API_MAP` / `_API_TYPES` / `_API_ROUTER` 接入；`ZCL_CRW_DEMO_DATA` 含通知种子；`ZCL_CRW_TEST_DATA` 清 `ZCRW_NOTIFY`；`ZCL_CRW_SELFCHECK` 覆盖 14 表 + `notifications=` |
| 报表 | `ZCRW_REMIND_JOB`：扫描待审批 / 逾期任务 / 逾期计划 → 通知；输出 `ZCRW_REMIND_JOB_OK …` / `ZCRW_REMIND_JOB_FAIL …`；SM36 作业由 basis 配置（本轮不建） |
| 前端 | 顶栏通知铃铛（未读徽标 + 下拉最近 5 条未读 + 全部已读 / 查看全部）；`#/notifications` 页面（状态 / 类型筛选、分页、刷新、全部已读、单条标记已读）；60s 未读数轮询；启动刷新 |
| 文档 | `p2-basis.md`（新建）、architecture / workflow / runbook / README / 本文件 / 规划同步：14 表、1.2.0、通知 API 与去重语义、SM36 步骤、P2 basis 决策 |

**验证口径（2026-11-02 实测）**

| 项 | 命令 | 期望 / 实测 |
|---|---|---|
| 自检 | `abap run ZCL_CRW_SELFCHECK --json` | `CRW_SELFCHECK_OK tables=14 rows=7 intervals=3 version=1.2.0 messages=8 roles=1 approvals=2 notifications=0 icf=OK cts=OK`（实测，复位后） |
| 单测 | `abap test ZCL_CRW_NOTIFY --json` | 5/5 通过（实测） |
| 通知探测 | `abap run ZCL_CRW_NOTIFY --json` | `CRW_NOTIFY_OK rows=0 unread=0`（实测，复位后；演示数据后 rows=2 unread=2） |
| 提醒报表 | `abap run-report ZCRW_REMIND_JOB --json` | `ZCRW_REMIND_JOB_OK approvals=0 tasks=0 schedules=0 total=0`（实测；演示数据刷新后运行，去重生效） |
| HTTP | `GET /notifications`、`/notifications/unread-count` 等 | 200 + 契约 JSON（API 控制器层实测通过；浏览器 HTTP 待人工复核） |
| UI | `#/notifications` + 顶栏铃铛 | 页面可见、标记已读生效（M5 截图已重拍 9 张；浏览器交互回归待人工） |

**未完成 / 边界**：SMTP 未配置（邮件不发）；SM36 作业定义未建（basis）；`DISMISSED` 枚举预留、无忽略端点；包迁移 / 索引 / 归档 / 权限对象 / Fiori 只出设计（[`p2-basis.md`](p2-basis.md)）。
