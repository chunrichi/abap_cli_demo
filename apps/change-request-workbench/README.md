# 变更请求工作台（CRW）

> 状态：M1（数据模型 + 服务层 + `/api/v1` + ICF 节点已打通；MIME/SPA 与审批中心页面进行中）。
> 这是**真实应用**，不是 demo；不套用 demo 的 `DMA` 命名与编号，契约见仓库 [`AGENTS.md`](../../AGENTS.md) §4A。
> 产品规划与决策记录：[docs/change-request-workbench-plan.md](../../docs/change-request-workbench-plan.md)。
> 架构与流程契约：[docs/architecture.md](docs/architecture.md)、[docs/workflow.md](docs/workflow.md)（v1，待定项已冻结）。
> 安装 / 升级 / 运维：[docs/runbook.md](docs/runbook.md)。交接文档：[docs/handoff.md](docs/handoff.md)。

在 SAP 内管理「变更请求 → 变更文档 → 任务/子任务 → 传输（含 ToC）→ 测试 → 计划导入 → 关闭」的全流程工作台，提供工作清单、详情、审批、传输视图、导入计划、仪表盘、报表与审计。

## 范围（D3 已确认）

- CR → CD → Task → SubTask 层级；CR/CD/Task 状态机、审批矩阵、审计历史。
- Transport 关联（DEV / ToC），CTS 只读展示（D4：实现但不做 live 验证）。
- 导入计划（计划时间 + 日程 + 到点/逾期提醒，不执行 TMS 导入）。
- 标准变更 `STD` 一期；紧急 `URG` P1；管理 `ADM` P2。

## 当前状态（2026-11-01）

- 预检：abap-cli 2.0.0；`abap doctor` ok；内置 ICF 2.0.0 current；active profile `test`（systemVersion 789）。
- 包：`$CRW` 本地包（super package `$TMP`，DLVUNIT LOCAL，无 transport）；AFF 见 `src/$crw.devc.json`。
- 数据模型：13 张 `ZCRW_*` 表、3 个号段（`ZCRW_REQ`/`ZCRW_CD`/`ZCRW_TASK`）、消息类 `ZCRW_MSG`、锁对象 `EZCRW_REQ`/`EZCRW_CD`。
- 服务层：`ZCL_CRW_UTIL` / `_NUMBER` / `_AUDIT` / `_AUTH` / `_WORKFLOW` / `_APPR_SVC` / `_SCHEDULE_SVC` / `_REQUEST_SVC` / `_CD_SVC` / `_TASK_SVC` / `_BOOTSTRAP` / `_SELFCHECK` / `_M1_SMOKE` / `_TEST_DATA`、`ZCX_CRW_ERROR`。
- **M1 API（已打通）**：ICF 节点 `ZCRW_APP` → `/sap/bc/zcrw`，`ZCL_CRW_HTTP_HANDLER` + `ZCL_CRW_API_ROUTER` + P0 控制器（`ME/HEALTH/DASHBOARD`、`REQUESTS`、`CHANGE-DOCUMENTS`、`TASKS`、`APPROVALS`）。
  - 统一 JSON 信封（§6.7）；写请求 `X-CRW-Request: 1` + 乐观锁 `version`；错误码 → HTTP 400/401/403/404/409/500/502 映射。
  - 实测：health/me/list/create/detail/action 经真实 HTTP 走通；`SUBMIT` 生成审批步骤；自审被 `SELF_APPROVAL(403)` 拦截；`SUBMIT_TEST` 守卫 `GUARD_FAILED(409)`。
- 初始化：`ZCL_CRW_BOOTSTRAP` v1.1.0（号段区间 + 版本行 + REQ/CD 审批矩阵 + `ADMIN`/`CHANGE_MANAGER` 角色），幂等。
- 自检：`ZCL_CRW_SELFCHECK` 只读，覆盖 13 表、号段、版本、消息类、角色、审批矩阵、ICF 节点（TADIR SICF）、E070 只读。
- 前端：`src/mime/` 原生 ES modules 单页（hash 路由，工作台/请求/变更文档/任务/审批/传输/计划/报表/配置页面）；构建与联调进行中，尚未上传 MIME。

## 安装与初始化

前置：`abap doctor` ok、`abap deploy status` current、`$CRW` 本地包已存在、当前连接为 dev/test。

1. `abap deploy status --json`：确认 ICF current（过期则 `abap deploy --yes --json`）。
2. 按依赖顺序校验并推送对象：`abap check content` / `abap validate:aff` → `check syntax` → `push` → `inspect --activation`（完整顺序与命令模板见 [docs/runbook.md](docs/runbook.md) §2）。
3. 创建 ICF 节点（handler 必须先激活；HTTP AFF 需带顶层 `name` 的临时副本）：`abap create HTTP ZCRW_APP --file tmp/zcrw_app.create.http.json --package '$CRW' --description 'CRW workbench ICF node' --yes --json`。
4. `abap run ZCL_CRW_BOOTSTRAP --json`：幂等；期望 `CRW_BOOTSTRAP_OK intervals=3 config=…`。
5. `abap run ZCL_CRW_SELFCHECK --json`：期望 `CRW_SELFCHECK_OK tables=13 rows=… intervals=3 version=1.1.0 messages=8 roles=… approvals=2 icf=OK cts=OK`。
6. `abap run ZCL_CRW_M1_SMOKE --json`：端到端冒烟（写数据，自动清理）；期望 `CRW_M1_SMOKE_OK …`。
7. `abap run ZCL_CRW_TEST_DATA --json`：重置业务数据（仅开发/安装，**非只读**）；期望 `CRW_TEST_DATA_RESET rows=…`。

## 运行与验证（只读）

```bash
abap run ZCL_CRW_SELFCHECK --json        # 12 表/号段/版本/消息/角色/矩阵/ICF/CTS 自检
abap run ZCL_CRW_JSON --json             # JSON camelCase 自检，期望 CRW_JSON_OK
abap test ZCL_CRW_UTIL --json            # ABAP Unit
abap select --table DD02L --where "TABNAME LIKE 'ZCRW%'" --count-only --json
abap select --table NRIV --where "OBJECT LIKE 'ZCRW%'" --json
abap select --table T100 --where "ARBGB = 'ZCRW_MSG'" --json
```

HTTP 自检（浏览器登录后，替换 `<host>`；不把系统地址写入仓库）：

- `GET <host>/sap/bc/zcrw/api/v1/health` → `data.status=ok`、`components.icf=ok`
- `GET <host>/sap/bc/zcrw/api/v1/me` → 当前用户 / 角色 / `version=1.1.0`
- `GET <host>/sap/bc/zcrw/api/v1/requests?page=1&size=20` → 分页 DTO

> `ZCL_CRW_BOOTSTRAP` / `_M1_SMOKE` / `_TEST_DATA` 会写数据，只属于安装与开发步骤，不在只读验证清单内。

## 目录

```
apps/change-request-workbench/
├── README.md
├── docs/            # architecture / workflow / runbook / handoff
├── src/             # AFF：DDIC / CLAS / INTF / HTTP / TRAN / NROB / ENQU / MSAG
├── src/mime/        # 前端资产（原生 ES modules）
└── screenshots/     # 主页面截图（脱敏）
```

## 工作约定

- 所有 `abap create/pull` 在本目录执行，避免拉取文件落到仓库根 `src/`。
- 对象前缀 `ZCRW_` / `ZCL_CRW_` / `ZIF_CRW_` / `ZCX_CRW_`；包 `$CRW`。
- 写 SAP 顺序：`check content` / `validate:aff` → `check syntax` → `push` → `inspect --activation` / `run` / `test`。
- 不 release transport；不碰生产；不提交凭证、URL、真实业务数据。

## 下一步

1. MIME `/zcrw` + SPA 上传与 ICF 认证 / SPA fallback 验证（M1 UI）。
2. 审批中心、历史/备注、我的工作与 KPI 页面（M2）。
3. CTS 只读适配器、传输工作台、导入计划页面（M3）。
4. 报表 / 配置 / 迁移 / 截图与产品化收尾（M4）。
