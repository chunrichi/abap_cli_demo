# 变更请求工作台（CRW）· 架构设计

> 状态：v1 契约（M1 冻结；作为后端 / API / 前端并行开发的共享契约，变更需评审）。
> 事实源：[CRW 规划](../../../docs/change-request-workbench-plan.md)（下称「规划」）；与规划冲突时以规划为准，与仓库契约冲突时以 [`AGENTS.md`](../../../AGENTS.md) §4A 为准。
> 配套文档：[workflow.md](workflow.md)（状态机 / 审批 / CTS / 计划语义）、`docs/runbook.md`（安装 / 升级 / 运维，待写）。
> 文档约定：状态码、动作码、错误码、字段名均为 ASCII 大写；字段名与 DDIC 一致；标注 **待定** 的条目表示规划未定义、需在对应里程碑前决策，不在实现中自行发明。
>
> **v1 冻结（2026-11-01，Phase 1）**：§10 的 A1–A22 已全部裁决（见“v1 决议”列）；正文中残留的“待定 / Axx”表述一律以 §10 决议为准；DTO、参数与排序白名单见 §6.7。
> **v1.2.0 增补（2026-11-02，M5）**：新增站内通知中心（`ZCRW_NOTIFY` + `ZCL_CRW_NOTIFY` / `ZCL_CRW_API_NOTIFY` + 报表 `ZCRW_REMIND_JOB`），数据模型 14 张表、版本 1.2.0；对象与触发点见 §4.2.2 / §5.8，API 见 §6.2 / §6.7，决议见 §10.1。P2 basis 类项（包迁移 / 索引 / 归档 / 权限 / Fiori）只出设计，见 [p2-basis.md](p2-basis.md)。

---

## 1. 定位与范围

### 1.1 应用定位

CRW 是 SAP 系统内的变更请求工作台：把「Change Request → Change Document → Task / SubTask → Transport（含 ToC）→ 测试 → 计划导入 → 关闭」的流程、审批、传输视图、导入计划与审计收敛到一个应用内。

- 形态：ABAP 后端（DDIC + 服务类 + ICF JSON API + CTS 只读集成）+ MIME 托管的原生单页前端；事务码 `ZCRW` 进入。
- 用户：请求人、变更经理、开发、测试、发布管理员、管理员（观察者 P2）。
- 边界：真实应用而非 demo；对象前缀 `ZCRW_` / `ZCL_CRW_` / `ZIF_CRW_` / `ZCX_CRW_`，包 `$CRW`。

### 1.2 架构目标

| # | 目标 | 落地手段 |
|---|---|---|
| G1 | 单节点同源 | 一个 ICF 节点 `ZCRW_APP` 同时提供静态资源与 `/api/v1`，无跨域 |
| G2 | 零外部依赖前端 | 原生 ES modules + 系统字体 + 内联 SVG；无 CDN、无 Node 构建链 |
| G3 | 业务规则可单测 | 状态机 / 守卫 / 审批矩阵 / 鉴权判定为纯逻辑类，不依赖真实 CTS 与数据库数据 |
| G4 | 可降级 | CTS 读取失败只降级为「未知」，不阻塞请求流程 |
| G5 | 可审计 | 状态变更只经动作、只追加历史表 |
| G6 | 可安装 / 可升级 / 可自检 | 幂等 bootstrap + 版本表 + 只读 selfcheck classrun |
| G7 | 本地包内可迭代 | `$CRW` 本地包免 transport，写路径不受传输请求约束 |

### 1.3 非目标

- 不替代 Solution Manager / Cloud ALM，不做跨系统、跨 client 的发布编排。
- 不在应用内创建 / 释放 / 删除 transport，不执行 TMS 导入（只读展示状态；写操作仍在 SE01 / STMS）。
- 不实现 retrofit / downgrade protection / 传输依赖自动修复；ToC 导入后的补做只做「提醒 + 标记」。
- 不做通用 BPM / 工作流引擎；审批矩阵是「按类型 + 优先级」的固定步骤。
- 不创建自定义权限对象（abap-cli 不支持 AUTH），用应用角色表 + 标准权限检查。
- 不做移动端、附件与全文检索（P2）；不碰生产系统写入。

### 1.4 技术基线

| 项 | 基线 | 说明 |
|---|---|---|
| 目标平台 | S/4HANA 2022+ | 需要 `/ui2/cl_json`、ABAP SQL 聚合 |
| 对象包 | `$CRW` | 本地包，super package `$TMP`，DLVUNIT LOCAL，无 transport |
| 开发工具 | abap-cli 2.0.0 | `$` 前缀本地包免 transport；内置 ICF 服务 2.0.0 |
| 当前环境 | profile `test`，systemVersion 789 | 环境差异写入 runbook 前置条件，不写死在代码里 |
| 数据模型 | 14 张透明表，char-only 字段 | 见 §5（M5 新增 `ZCRW_NOTIFY`） |
| 前端 | 原生 ES modules，hash 路由 | 无构建产物、无第三方库 |
| 语言 | 中文 UI，代码与标识符英文 | ABAP 注释英文 |

---

## 2. 系统上下文

### 2.1 上下文图

```
┌────────────────────┐          HTTPS（SAP 登录会话）           ┌──────────────────────────────────┐
│ 浏览器              │ ─────────────────────────────────────▶ │ SAP 系统（DEV / 测试）             │
│ 原生 SPA            │ ◀───────────────────────────────────── │                                  │
│ hash 路由           │    JSON（/api/v1） / 静态资源           │  ICF 节点 ZCRW_APP                │
│ 无构建链            │                                        │    /sap/bc/zcrw                   │
└────────────────────┘                                        │   ├─ ZCL_CRW_HTTP_HANDLER         │
                                                              │   ├─ ZCL_CRW_API_ROUTER           │
                                                              │   ├─ Controllers → Services       │
                                                              │   ├─ Repositories ── ZCRW_* 表    │
                                                              │   ├─ CTS Adapter（只读）          │
                                                              │   └─ MIME 根 /zcrw                │
                                                              └───────────────┬──────────────────┘
                                                                              │ 只读 SELECT
                                                                              ▼
                                                              ┌──────────────────────────────────┐
                                                              │ CTS 表 E070 / E071 / E07T / TMS  │
                                                              │ （应用不写、不释放、不导入）      │
                                                              └──────────────────────────────────┘
```

### 2.2 信任边界与数据流

| # | 边界 | 规则 |
|---|---|---|
| B1 | 浏览器 ↔ ICF | 身份 = SAP 登录会话（SSO / 表单 / Basic，按客户环境）；应用不保存密码；会话超时由 SAP 控制 |
| B2 | 应用 ↔ CTS | 严格只读；读取失败降级，不写任何 CTS 表，不调用 TMS 导入 API |
| B3 | 浏览器 ↔ 写接口 | 同源 + 自定义请求头 `X-CRW-Request: 1`；前端隐藏按钮只是体验，不是安全边界 |
| B4 | 应用 ↔ 审计 | 历史表只追加；应用级审计不等于合规级不可篡改（见 §8.5） |

写请求的数据流：`HTTP 请求 → 会话用户 → API context（用户 / 角色 / correlationId）→ controller 参数校验 → service 业务规则与守卫 → repository 写表 + 写历史 → COMMIT → DTO → JSON 响应`。

### 2.3 运行时组件

| 组件 | 运行位置 | 职责 |
|---|---|---|
| SPA | 浏览器（MIME 静态资源） | 页面、路由、表单、动作条、错误提示 |
| `ZCL_CRW_HTTP_HANDLER` | ICF 节点 `ZCRW_APP` | 实现 `IF_HTTP_EXTENSION`；区分 MIME / API；CSP 与缓存头 |
| `ZCL_CRW_API_ROUTER` | ABAP | 解析路径 / 方法 / 参数；异常转错误信封 |
| Controller 层 | ABAP | 参数校验 + DTO 转换，不含业务规则 |
| Service 层 | ABAP | 业务规则、事务边界、编排、历史写入 |
| Repository 层 | ABAP | 唯一 Open SQL 出口；分页、乐观锁 |
| CTS Adapter | ABAP | 只读 `E070` / `E071` / `E07T` / TMS 队列 |
| 通知服务 | ABAP | `ZCL_CRW_NOTIFY`：站内通知生成 / 去重 / 已读；预留邮件通道（不发信） |
| 提醒报表 | ABAP 报表 + `SM36` 作业 | `ZCRW_REMIND_JOB`：扫描待审批 / 逾期任务 / 逾期计划并生成通知；作业定义由 basis 配置（本轮不建） |
| Bootstrap / Migration / Selfcheck | ABAP classrun | 初始化、版本迁移、只读自检 |

### 2.4 外部依赖

- 无外部服务、无 CDN。站内通知不依赖外部系统；邮件通道 `ZCL_CRW_NOTIFY=>deliver_email` 已预留，SMTP 未配置前不发信（P2，需 basis 配 SCOT，见 [workflow.md](workflow.md) §9.6）。
- 后台作业：应用不创建 `SM36` 作业；`ZCRW_REMIND_JOB` 由 basis 按 [runbook.md](runbook.md) §2.13 配置为每日作业（本轮不建），逾期计算仍以读取时计算为准（[workflow.md](workflow.md) §8）。
- CTS 为唯一外部数据源，只读（D4 / D8）。
- 无自定义 AUTH 对象（P0/P1）；P2 权限对象只出设计，见 [p2-basis.md](p2-basis.md) §5。

---

## 3. 技术形态与约束

### 3.1 选型结论

| 选项 | 结论 | 原因 |
|---|---|---|
| ICF 节点 + MIME + 原生 ES modules | **采用** | abap-cli 现有能力已验证；零外部依赖；单节点同源；部署最简单 |
| SAPUI5 / Fiori（MIME 托管静态资源） | 备选 | 可行，但需打包、资源体积大、需 FLP 集成；无强制要求时收益低 |
| RAP + OData + Fiori Elements | 不采用 | CLI 对 RAP 工件支持不完整，写路径不可控 |
| BSP / Web Dynpro | 不采用 | CLI 不支持，维护成本高 |
| 经典报表 + ALV | 不采用 | 不是工作台形态，交互与深链能力弱 |

### 3.2 前端形态

- 静态资产放 `src/mime/`（`index.html`、`styles.css`、`js/` 模块），由 MIME 根 `/zcrw` 提供；不在仓库提交构建产物。
- 页面为 hash 路由（`#/dashboard`、`#/requests/{id}` 等），刷新与分享保持页面，浏览器前进 / 后退可用。
- 列表服务端分页（默认 50）；筛选条件写入 URL；动作条按「当前状态 + 角色」展示，禁用项给原因。
- 渲染文本全部转义（XSS）；导出文件名过滤用户输入；不在 URL 放敏感数据。
- 页面清单（16 页，M5 新增 `#/notifications`）与布局见规划 §6.1 / §6.2，本文不重复。

### 3.3 abap-cli 能力边界对本架构的影响

| 能力 | 状态 | 架构处理 |
|---|---|---|
| DDIC：DOMA / DTEL / TABL / STRU / TTYP / MSAG / ENQU / NROB | 支持 | `create --file` + `push` |
| CLAS / INTF / PROG / FUGR | 支持 | 主实现方式；单测用 testclasses sidecar |
| HTTP（ICF）/ TRAN（事务码）/ MIME | 支持 | `create --file`；MIME 用 `mime create` + `mime push` |
| AUTH 权限对象 | 不支持 | 应用角色表 `ZCRW_ROLE` + 标准权限检查；自定义 AUTH 人工创建（P2） |
| SM30 表维护生成器 | 不支持 | 配置用 bootstrap + 应用内配置界面（P1/P2） |
| 后台作业（SM36） | 不支持 | 应用提供可调度报表 `ZCRW_REMIND_JOB`；作业定义由 basis 在 SM36 创建（runbook §2.13），本轮不建 |
| 表数据 INSERT / UPDATE | 无 CLI 命令 | 初始化与冒烟数据由 classrun 写入 |
| Transport release / import | CLI 不执行 | 人工在 SE01 / STMS 操作，应用只读状态 |
| 建表 enhancement category | ICF handler 固定 char 类型 | 全部字段 char-only（见 §5.2） |
| 二级索引 | 无 CLI 入口 | 主键查询；P2 通过 GUI / DB02 补索引（A20 / D20，设计见 p2-basis §3） |

---

## 4. 分层与类地图

### 4.1 运行时调用链

```
浏览器 SPA
   │  HTTPS：/sap/bc/zcrw（ICF 节点 ZCRW_APP）
   ▼
ZCL_CRW_HTTP_HANDLER ── MIME 静态资源（/zcrw）+ SPA fallback
   ▼
ZCL_CRW_API_ROUTER ── 鉴权 / 上下文 / 错误信封
   ▼
Controllers（request / cd / task / approval / transport / schedule / dashboard / report / config / me / notify）
   ▼
Services（request / cd / task / workflow / approval / transport / schedule / report / auth / config / notify）
   ▼
Repositories（Open SQL）── ZCRW_* 表
CTS Adapter（只读）── E070 / E071 / E07T / TMS 队列
通知服务（ZCL_CRW_NOTIFY）── ZCRW_NOTIFY；提醒报表 ZCRW_REMIND_JOB（SM36 可调度）
支撑：Number / History / Log / JSON / MIME / Bootstrap / Migration / Selfcheck
```

### 4.2 已实现对象（M1，实际代码）

| 对象 | 类型 | 职责 | 关键实现 / 输出 | 状态 |
|---|---|---|---|---|
| `ZCL_CRW_UTIL` | CLAS | 时间 / GUID / 编号格式化 | `now( ) → CHAR14`（`sy-datum` + `sy-uzeit`）；`uuid( ) → CHAR32`（`cl_system_uuid=>create_uuid_c32_static`）；`number_id( number ) → 10 位零填充`；`format_id( prefix, number ) → PREFIX-0000000123` | 已实现，单测 4/4 |
| `ZCL_CRW_NUMBER` | CLAS | 号段区间与取号 | `ensure_intervals( )` 幂等建 3 个区间；`next( object ) → INRI-NR`（`NUMBER_GET_NEXT`，区间 `01`）；异常 `ZCX_CRW_ERROR` | 已实现 |
| `ZCL_CRW_AUDIT` | CLAS | 审计写入 | `log( object_type, object_id, action, field, old_value, new_value, comment, source = API )` 写一条 `ZCRW_HIST`；规划中名为 `ZCL_CRW_HISTORY`（A22） | 已实现 |
| `ZCL_CRW_REQUEST_SVC` / `ZCL_CRW_CD_SVC` / `ZCL_CRW_TASK_SVC` | CLAS | CR / CD / Task 服务骨架 | `create` / `get` / `list` / `update` / `change_status` / `display_id`；私有 `next_id`（号段取号）/ `validate_transition`（状态迁移校验）/ `bump_version`（乐观锁）；写审计 | 已实现（M1 骨架；守卫细化与仓储分层待收敛，见 A22） |
| `ZCL_CRW_BOOTSTRAP` | CLAS + classrun | 幂等初始化 | 建号段区间；种 `ZCRW_VERSION`（CRW 1.2.0）、`ZCRW_APPR_CFG`（`STD_DEFAULT` / step `01`）、`ZCRW_ROLE`（当前用户 ADMIN）；输出 `CRW_BOOTSTRAP_OK intervals=… config=…` | 已实现 |
| `ZCL_CRW_SELFCHECK` | CLAS + classrun | 只读自检 | 读 14 张表 + `NRIV`（3 区间）+ 版本行 + `T100`（`ZCRW_MSG`）+ ADMIN 角色 + 审批矩阵 + 通知数；输出 `CRW_SELFCHECK_OK tables=14 rows=… intervals=… version=… messages=… notifications=… icf=… cts=…`，失败输出 `CRW_SELFCHECK_FAIL …` | 已实现 |
| `ZCX_CRW_ERROR` | CX | 业务异常 | 继承 `CX_STATIC_CHECK`；`MV_CODE` / `MV_TEXT`；号段异常码 `NR_INIT` / `NR_UPDATE` / `NR_CLOSE` / `NR_GET`；通知异常码 `NOTIFY_*`（如 `NOTIFY_UUID` / `NOTIFY_INSERT` / `NOTIFY_NOT_FOUND`） | 已实现 |
| `ZCRW_MSG` | MSAG | 消息类 | 8 条：001 CR 不存在、002 非法迁移、003 需要审批、004 transport 不存在、005 无权限、006 CD 不存在、007 任务不存在、008 计划不存在 | 已实现 |
| `EZCRW_REQ` / `EZCRW_CD` | ENQU | 专用锁对象 | 主表分别为 `ZCRW_REQ` / `ZCRW_CD`，锁参数为主键 `REQ_ID` / `CD_ID`，排他锁 | 已建，调用留 M1 |
| `ZCRW_REQ` / `ZCRW_CD` / `ZCRW_TASK` | NROB | 号段对象 | CHAR10、无子对象、区间 `01`；区间由 bootstrap 维护 | 已建 |
| 14 张 `ZCRW_*` 表 | TABL | 数据模型 | 见 §5.3；M5 新增 `ZCRW_NOTIFY` | 已建 |
| `ZCL_CRW_M1_SMOKE` | CLAS + classrun | M1 端到端冒烟（验收用，非产品对象） | 建 CR → CD → Task / SubTask、走状态迁移并自动清理；输出 `CRW_M1_SMOKE_OK req=… cd=… task=… sub=…` | 已实现 |

### 4.2.1 M1 API / 审批 / 计划层（2026-11-01 已实现）

| 对象 | 类型 | 职责 | 关键实现 / 输出 | 状态 |
|---|---|---|---|---|
| `ZCL_CRW_JSON` | CLAS | JSON 序列化 / 反序列化 / 时间戳与日期转换 / PATCH 键检测 | `/ui2/cl_json` + `pretty_mode-camel_case`；`CRW_JSON_OK` 自检 | 已实现 |
| `ZCL_CRW_LOG` | CLAS | 应用日志写入（不阻塞业务） | `ZRW_LOG` 行；`write` / `write_and_commit` | 已实现 |
| `ZCL_CRW_AUTH` | CLAS | 角色装载与判定 | `load_roles` / `role_members` / `is_admin` / `has_role` / `require_any` | 已实现 |
| `ZCL_CRW_WORKFLOW` | CLAS | 状态机纯逻辑（REQ / CD / TASK） | `target_status` / `is_valid` / `is_terminal` / `allowed_actions` | 已实现（D19 提前落地） |
| `ZCL_CRW_APPR_SVC` | CLAS | 审批步骤生成 / 决策 / 跳过 / 列表 | 矩阵匹配 + ANY 规则 + 自审拦截 + 对象收尾；`ZCRW_APPR` | 已实现 |
| `ZCL_CRW_SCHEDULE_SVC` | CLAS | 导入计划 CRUD 与逾期计算 | `create_or_update` / `cancel` / `confirm` / `active_for_object` / `is_overdue` | 已实现（M3 复用） |
| `ZCL_CRW_API_TYPES` | CLAS | API DTO 类型集合 | camelCase DTO（§6.7） | 已实现 |
| `ZCL_CRW_API_MAP` | CLAS | DDIC 行 → DTO 映射 | `request` / `change_document` / `task` / `approval` / `transport` / `history` / `note` / `import_schedule` | 已实现 |
| `ZCL_CRW_API_CONTEXT` | CLAS | 请求/响应上下文 | method / path / body / user / roles / correlationId / 参数 / 响应载体 | 已实现 |
| `ZCL_CRW_API_ROUTER` | CLAS | `/api/v1` 路由、写保护、错误信封、HTTP 状态映射 | 资源分发 + 异常映射 + 日志 | 已实现 |
| `ZCL_CRW_HTTP_HANDLER` | CLAS | ICF 入口 | `/api/v1/*` 转 router；静态资源 + SPA fallback（MIME 于 M1 前端落地） | 已实现 |
| `ZCL_CRW_API_ME` | CLAS | `/me` `/health` `/dashboard` | 角色 / 版本 / 组件健康 / KPI | 已实现（KPI P0 版，M2 增强） |
| `ZCL_CRW_API_REQUEST` | CLAS | CR 控制器 | 列表 / 创建 / 详情 / PATCH / 动作 / history / notes / 子 CD | 已实现 |
| `ZCL_CRW_API_CD` | CLAS | CD 控制器 | 列表 / 详情 / PATCH / 动作 / tasks / transports / schedule | 已实现 |
| `ZCL_CRW_API_TASK` | CLAS | Task 控制器 | 列表 / 详情 / PATCH / 动作 / subtasks | 已实现 |
| `ZCL_CRW_API_APPROVAL` | CLAS | 审批控制器 | 待我审批 / 步骤 / 决策 | 已实现 |
| `ZCL_CRW_TEST_DATA` | CLAS + classrun | 测试数据复位 | 清业务表 + 种子审批角色；输出 `CRW_TEST_DATA_RESET rows=…` | 已实现（开发/安装用） |
| `ZCRW_APP` | HTTP（SICF） | `/sap/bc/zcrw` ICF 节点 | `handlerClass = ZCL_CRW_HTTP_HANDLER`；静态资源来自 MIME `/zcrw` | 已创建（TADIR SICF） |
| `ZIF_CRW_CTS_READER` | INTF | CTS 只读读取契约 | E070 / E071 / E07T / TMSBUFFER | 已实现 |
| `ZCL_CRW_CTS_ADAPTER` | CLAS | CTS 只读适配器（`ZIF_CRW_CTS_READER`） | `get_header` / `get_description` / `get_objects` / `get_import_state` | 已实现（D4：不做 live 导入验证） |
| `ZCL_CRW_TRANSPORT_SVC` | CLAS | 传输关联与快照 | link / unlink / mark-detached / sync / list；`DUPLICATE_LINK`、已释放不可解绑 | 已实现 |
| `ZCL_CRW_API_TRANSPORT` | CLAS | 传输控制器 | `/transports*` | 已实现 |
| `ZCL_CRW_API_SCHEDULE` | CLAS | 导入计划控制器 | `/schedules`、`/schedules/{id}/actions` | 已实现 |
| `ZCL_CRW_REPORT_SVC` | CLAS | 报表聚合（变更/时长/逾期/ToC/CSV） | 只读 SQL + 历史时间差 | 已实现 |
| `ZCL_CRW_API_REPORT` | CLAS | 报表控制器 | `/reports/*`、`/reports/export.csv` | 已实现 |
| `ZCL_CRW_API_CONFIG` | CLAS | 配置只读查看 | cycles / roles / approval-matrix / number-ranges | 已实现（编辑 P2） |
| `ZCL_CRW_MIGRATION` | CLAS + classrun | 版本迁移入口 | 幂等委托 bootstrap；`CRW_MIGRATION_OK from=… to=…` | 已实现（单步前向） |
| `ZCL_CRW_DEMO_DATA` | CLAS + classrun | 演示数据（安装/截图/联调） | 假用户拒绝真实数据；`CRW_DEMO_DATA_OK …` | 已实现（开发步骤） |
| `ZCRW_START` | PROG | 事务码入口报表 | 运行时拼系统 URL + ICF 路径，只展示不写死地址 | 已实现 |
| `ZCRW` | TRAN | 报表事务 | `reportTransaction` → `ZCRW_START` 1000 | 已创建（`abap tcode` 可解析） |

**实测口径（2026-11-01）**：health/me/list/create/detail/action 经真实 ICF HTTP 走通；错误映射实测 400/403/404/409；未登录由 ICF 标准登录过程返回 401（响应体为登录页，A1/D21 实测结论）；ICF 节点创建后需再 `abap activate ZCL_CRW_HTTP_HANDLER` 一次以刷新类运行时缓存。

### 4.2.2 M5 通知中心（v1.2.0，2026-11-02 已实现）

| 对象 | 类型 | 职责 | 关键实现 / 输出 | 状态 |
|---|---|---|---|---|
| `ZCRW_NOTIFY` | TABL | 站内通知（个人） | 字段与去重见 §5.3 / §5.8；`NOTIFY_ID` CHAR32 主键 | 已建 |
| `ZCL_CRW_NOTIFY` | CLAS + classrun | 通知服务 | `emit`（发布通知，dedup）/ `refresh_for_user` / `run_scan` / `list_for_user` / `unread_count` / `mark_read` / `mark_all_read`；事件钩子 `notify_approval_pending` / `notify_approval_rejected`；邮件预留 `deliver_email`；只读探测输出 `CRW_NOTIFY_OK rows=… unread=…` | 已实现（单测 5 例） |
| `ZCL_CRW_API_NOTIFY` | CLAS | 通知控制器 | `/notifications`、`/notifications/unread-count`、`/notifications/refresh`、`/notifications/{id}/read`、`/notifications/read-all` | 已实现 |
| `ZCL_CRW_API_MAP` | CLAS | DTO 映射 | 新增 `notification( )`（DDIC → §6.7 通知 DTO） | 已实现 |
| `ZCL_CRW_API_TYPES` | CLAS | DTO 类型 | 新增 `ty_notification` / `tt_notifications` | 已实现 |
| `ZCRW_REMIND_JOB` | PROG | 提醒报表（SM36 可调度） | 调用 `run_scan`；成功输出 `ZCRW_REMIND_JOB_OK approvals=… tasks=… schedules=… total=…`，失败输出 `ZCRW_REMIND_JOB_FAIL …` | 已实现（作业定义由 basis 在 SM36 建，本轮不建） |
| SPA（`src/mime/`） | MIME | 顶栏铃铛 + `#/notifications` 页面 | 未读徽标 60s 轮询、启动刷新、下拉最近 5 条未读、刷新 / 全部已读 / 标记已读 | 已实现（M5 截图已重拍） |

- **事件钩子**：`ZCL_CRW_APPR_SVC` 在审批步骤生成后调用 `notify_approval_pending`、驳回后调用 `notify_approval_rejected`；通知异常被吞掉，**不阻塞审批主流程**。
- **初始化 / 演示 / 复位**：`ZCL_CRW_BOOTSTRAP` 版本号升到 1.2.0；`ZCL_CRW_DEMO_DATA` 种子含通知（输出增加 `notifications=…`）；`ZCL_CRW_TEST_DATA` 复位清 `ZCRW_NOTIFY`。
- **自检**：`ZCL_CRW_SELFCHECK` 覆盖 14 表并在输出中增加 `notifications=…`（只读）。
- **前端导航**：侧栏「变更流程」组新增「通知」入口，顶栏铃铛与通知中心同源；路由 `#/notifications`，页面标题「通知中心」。

### 4.3 规划对象（M1–M4，含 M5 增补）

| 层 | 对象 | 职责 |
|---|---|---|
| 入口 | `ZCL_CRW_HTTP_HANDLER` | 实现 `IF_HTTP_EXTENSION`；路由 MIME / API；CSP / 缓存头 |
| 路由 | `ZCL_CRW_API_ROUTER` | 解析路径 / 方法 / 参数；异常转错误信封 |
| 上下文 | `ZCL_CRW_API_CONTEXT` | 当前用户、角色、请求体、correlation id |
| 控制器 | `ZCL_CRW_API_REQUEST` / `_CD` / `_TASK` / `_APPROVAL` / `_TRANSPORT` / `_SCHEDULE` / `_DASHBOARD` / `_REPORT` / `_CONFIG` / `_ME` / `_NOTIFY` | 参数校验 + DTO 转换，不含业务规则 |
| 服务 | `ZCL_CRW_WORKFLOW_SVC` / `_APPROVAL_SVC` / `_TRANSPORT_SVC` / `_SCHEDULE_SVC` / `_REPORT_SVC` / `_NOTIFY` | 业务规则、事务、编排（`_REQUEST_SVC` / `_CD_SVC` / `_TASK_SVC` 已在 M1 落地，见 §4.2） |
| 领域 | `ZCL_CRW_WORKFLOW`（状态机与守卫）、`ZCL_CRW_AUTH`（角色判定）、`ZCL_CRW_CONFIG` | 纯逻辑，可被 ABAP Unit 直接覆盖 |
| 数据 | `ZCL_CRW_REQUEST_REPO` / `_CD_REPO` / `_TASK_REPO` / `_TR_REPO` / `_SCHED_REPO` / `_APPR_REPO` / `_HIST_REPO` / `_NOTE_REPO` / `_ROLE_REPO` / `_LOG_REPO` | Open SQL、分页、乐观锁 |
| 集成 | `ZIF_CRW_CTS_READER` + `ZCL_CRW_CTS_ADAPTER` | 只读 `E070` / `E071` / `E07T` / TMS；可 mock 做单测 |
| 支撑 | `ZCL_CRW_LOG`、`ZCL_CRW_JSON`、`ZCL_CRW_MIME` | 日志、序列化、静态资源（审计 `ZCL_CRW_AUDIT` 已实现，见 §4.2） |
| 运维 | `ZCL_CRW_MIGRATION`、`ZCL_CRW_DEMO_DATA` | 版本迁移、演示 / 测试数据准备与清理 |
| 异常 | `ZCX_CRW_ERROR` 及子类 | 业务错误码 + 消息类 `ZCRW_MSG` |

### 4.4 分层规则

1. **依赖单向向下**：HTTP handler → router → controller → service → domain / repository → DDIC。禁止反向依赖与跨层直连。
2. **Controller 不含业务规则**：只做参数解析、必填校验、DTO 映射、调用 service、包装响应。
3. **Service 拥有规则与事务**：一个 API 写请求一个 LUW；服务层校验通过后写表 + 写历史，`COMMIT WORK AND WAIT`，异常不提交。
4. **领域类纯逻辑**：`ZCL_CRW_WORKFLOW` / `ZCL_CRW_AUTH` / `ZCL_CRW_CONFIG` 不直接读表、不依赖 CTS，便于 ABAP Unit 覆盖。
5. **Repository 是唯一 Open SQL 出口**：分页、排序白名单、乐观锁更新集中在仓储层；禁止在 controller / 前端拼接 SQL 语义。
6. **CTS 经接口隔离**：service 只依赖 `ZIF_CRW_CTS_READER`，单测注入 mock，不依赖真实 CTS。
7. **异常统一**：业务失败抛 `ZCX_CRW_ERROR` 及子类，由 router 映射为 API 错误码与 HTTP 状态（见 §6.4）。
8. **M1 现状偏差**：`*_SVC` 当前直接使用 Open SQL（仓储层未拆出），状态迁移校验以 `validate_transition` 内联在服务类；规划 §7.2 的 `ZCL_CRW_WORKFLOW` 领域类与仓储分层待收敛（A22）。

### 4.5 横切支撑

| 组件 | 职责 | 契约 |
|---|---|---|
| `ZCL_CRW_NUMBER` | 取号 | 区间 `01`，`NUMBER_GET_NEXT`，不做本地缓存；失败抛 `ZCX_CRW_ERROR` |
| `ZCL_CRW_AUDIT` | 审计写入 | 每次状态变更 / 审批 / 指派 / 关联 / 计划变更写一条 `ZCRW_HIST`；规划命名 `ZCL_CRW_HISTORY`（A22） |
| `ZCL_CRW_LOG` | 技术日志 | API 错误、CTS 失败、迁移、权限拒绝；带 `CORRELATION_ID` |
| `ZCL_CRW_JSON` | 序列化 | `/ui2/cl_json`，camelCase DTO；中文与嵌套已验证 |
| `ZCL_CRW_MIME` | 静态资源 | 按 MIME 路径读 `/zcrw` 下资产；未命中回退 `index.html` |
| `ZCL_CRW_NOTIFY` | 站内通知 | 仅在 `emit` 成功落库后调用邮件预留；去重与状态语义见 §5.8 |
| `ZCX_CRW_ERROR` | 异常 | `MV_CODE` 为内部异常码，router 映射为对外 API 错误码（如 `NR_*` → `NUMBER_RANGE_ERROR`、`*NOT_FOUND*` → `NOT_FOUND`） |

---

## 5. 数据模型

### 5.1 聚合关系

```
Cycle ──< Change Request ──< Change Document ──< Task ──< SubTask
                                    │              │
                                    ├──< TransportLink（DEV / ToC，引用 E070/E071，只读快照）
                                    └──< ImportSchedule（计划导入时间 / 窗口）
Change Request / Change Document ──< Approval
Change Request / Change Document / Task ──< History / Note
User ──< Notification（站内通知，接收人 = USER_ID）
User ──< RoleAssignment（全局 / 组件 / 周期）
配置：RequestType / ApprovalMatrix / Cycle
```

### 5.2 char-only DDIC 约束

**原因**：abap-cli 2.0.0 建表 ICF handler 的 enhancement category 固定为 `Can Be Enhanced (Char. Type)`，deep 类型与数值类型会报 enhancement category 错误（规划附录 B.4-3）。因此 14 张表全部只使用 `CHAR` / `NUMC` / `DATS` / `TIMS`；不使用 `DEC` / `INT` 等数值类型，不使用 `DATS` / `TIMS` 以外的时间类型，不使用 `RAW16` / `XSTRING`。

| 语义 | 类型 / 长度 | 编码 | 生成 / 转换 | 示例 |
|---|---|---|---|---|
| 时间戳 | `CHAR14` | `YYYYMMDDHHMMSS`，SAP 系统本地时间 | `ZCL_CRW_UTIL=>now( )`；API 出入参转 ISO 8601（§5.6） | `20261101220000` |
| GUID | `CHAR32` | UUID C32 | `ZCL_CRW_UTIL=>uuid( )`（`cl_system_uuid=>create_uuid_c32_static`） | `9f2c…`（32 位十六进制） |
| 乐观锁版本 | `NUMC6` | 从 `000001` 递增 | 每次写 +1；`WHERE version = 期望值` | `000004` |
| 业务编号 | `CHAR10` | 号段零填充 | `ZCL_CRW_NUMBER=>next( )`；显示加前缀 | `0000000123` |
| 工时 | `NUMC5` | 小时数 | DTO 层格式化 | `00040` |
| 日期 | `DATS` | `YYYYMMDD` | API 用 `YYYY-MM-DD` | `20261127` |
| 枚举 / 状态 | `CHARn` | 大写常量 | 服务层常量，禁止 UI 直写 | `PENDING_APPROVAL` |
| 长文本 | `CHAR255` | 文本 | 入参超 255 字符 → `VALIDATION_ERROR`，不静默截断（§10 A14 / W26） | — |

**架构后果**：

- 无原生时间戳 / UUID / 小数类型；排序依赖字符序 —— `CHAR14` 与零填充 `NUMC` 的字典序与时间 / 数值序一致，可直接用于 `ORDER BY`。
- 时间比较、加减、时区换算在 ABAP 侧完成（`CONVERT` / 运算后回写 `CHAR14`）。
- 数值聚合（报表工时、时长）需在 ABAP 侧 `CAST` / 转换后计算；不允许对 `CHAR` 列直接做数值运算。
- 字段长度上限 `CHAR255`：审批意见、备注、原因、描述均受此限；超出需求需评估分表或长文本表（待定）。

### 5.3 14 张表摘要

通用约定：所有表以 `MANDT` 为第一主键列；`ZCRW_REQ` / `ZCRW_CD` / `ZCRW_TASK` / `ZCRW_SCHED` 统一带 `CREATED_AT` / `CREATED_BY` / `CHANGED_AT` / `CHANGED_BY`（`CHAR14` / `CHAR12`），下表不再重复；`ZCRW_TR` / `ZCRW_HIST` / `ZCRW_NOTE` / `ZCRW_LOG` / `ZCRW_NOTIFY` 使用各自的时间与操作人列（`LINKED_*` / `CHANGED_*` / `CREATED_*` / `TIMESTAMP` / `USER_ID`）。

| 表 | 用途 | 主键 | 关键字段（摘要） |
|---|---|---|---|
| `ZCRW_REQ` | CR 请求头（聚合根） | `REQ_ID` CHAR10 | `REQ_TYPE` CHAR4（STD/URG/ADM）、`TITLE` CHAR80、`DESCRIPTION` CHAR255、`STATUS` CHAR20、`PRIORITY` CHAR2、`COMPONENT` CHAR20、`CYCLE_ID` CHAR16、`REQUESTER` / `OWNER` CHAR12、`APPROVAL_STATE` CHAR10、`PLANNED_START` / `PLANNED_END` / `DUE_DATE` DATS、`VERSION` NUMC6、`CLOSED_AT` CHAR14、`CANCEL_REASON` CHAR80 |
| `ZCRW_CD` | 变更文档（技术批次） | `CD_ID` CHAR10 | `REQ_ID` CHAR10、`CYCLE_ID` CHAR16、`TITLE` CHAR80、`STATUS` CHAR20、`OWNER` / `DEV_LEAD` / `TEST_LEAD` CHAR12、`TARGET_SYS` CHAR10、`PLANNED_IMPORT_AT` CHAR14、`APPROVAL_STATE` CHAR10、`VERSION` NUMC6、`CLOSED_AT` CHAR14 |
| `ZCRW_TASK` | 任务 / 子任务 | `TASK_ID` CHAR10 | `REQ_ID`、`CD_ID`、`PARENT_TASK_ID` CHAR10（空 = Task）、`TASK_LEVEL` CHAR1（T/S）、`TASK_TYPE` CHAR10（DEV/TEST/IMPORT/RETROFIT）、`TITLE` CHAR80、`ASSIGNEE` CHAR12、`STATUS` CHAR20、`DUE_DATE` DATS、`EST_HOURS` NUMC5、`VERSION` NUMC6 |
| `ZCRW_TR` | 传输关联与状态快照 | `TRKORR` CHAR10 | `CD_ID`、`TASK_ID`、`TR_KIND` CHAR10（DEV/TOC）、`TARSYSTEM` CHAR10、`TR_STATUS` CHAR1、`TR_STATUS_TXT` CHAR30、`RELEASED_AT` / `IMPORT_SCHEDULED_AT` / `IMPORTED_AT` / `LAST_SYNC_AT` / `LINKED_AT` CHAR14、`RETROFIT_STATE` CHAR10（NA/PENDING/DONE）、`SYNC_STATE` CHAR10、`LINKED_BY` CHAR12、`DESCRIPTION` CHAR60 |
| `ZCRW_SCHED` | 导入计划 | `SCHED_ID` CHAR32 | `OBJECT_TYPE` CHAR10（CD/TOC）、`OBJECT_ID` CHAR20、`TARGET_SYS` CHAR10、`SCHEDULED_AT` CHAR14、`STATUS` CHAR10（PLANNED/DONE/MISSED/CANCELLED）、`NOTE` CHAR255 |
| `ZCRW_APPR` | 审批步骤实例 | `APPR_ID` CHAR32 | `OBJECT_TYPE` CHAR10（REQ/CD）、`OBJECT_ID` CHAR10、`STEP_NO` NUMC2、`APPROVER` CHAR12、`APPR_STATE` CHAR10（PENDING/APPROVED/REJECTED/SKIPPED）、`DECIDED_AT` CHAR14、`COMMENT_TXT` CHAR255 |
| `ZCRW_HIST` | 审计 / 历史（只追加） | `HIST_ID` CHAR32 | `OBJECT_TYPE`、`OBJECT_ID` CHAR20、`ACTION` CHAR30、`FIELD` CHAR30、`OLD_VALUE` / `NEW_VALUE` CHAR255、`COMMENT_TXT` CHAR255、`CHANGED_BY` CHAR12、`CHANGED_AT` CHAR14、`SOURCE` CHAR10（UI/API/SYNC） |
| `ZCRW_NOTE` | 备注 / 评论 | `NOTE_ID` CHAR32 | `OBJECT_TYPE`、`OBJECT_ID` CHAR20、`AUTHOR` CHAR12、`TEXT` CHAR255、`CREATED_AT` CHAR14、`VISIBILITY` CHAR10 |
| `ZCRW_CYCLE` | 变更窗口 / 周期 | `CYCLE_ID` CHAR16 | `DESCRIPTION` CHAR60、`START_DATE` / `END_DATE` / `FREEZE_DATE` DATS、`STATUS` CHAR10、`TARGET_SYS` CHAR10 |
| `ZCRW_ROLE` | 应用角色分配 | `USER_ID` + `ROLE` + `SCOPE_TYPE` + `SCOPE_ID` | `ROLE` CHAR20、`SCOPE_TYPE` CHAR10（GLOBAL/COMPONENT/CYCLE）、`SCOPE_ID` CHAR20、`VALID_FROM` / `VALID_TO` DATS |
| `ZCRW_APPR_CFG` | 审批矩阵 | `PROFILE_ID` CHAR20 + `STEP_NO` NUMC2 | `APPROVER_ROLE` CHAR20、`APPROVER_USER` CHAR12、`OBJECT_TYPE` CHAR10（REQ/CD）、`REQ_TYPE` CHAR4、`PRIORITY` CHAR2、`MANDATORY` CHAR1 |
| `ZCRW_VERSION` | 版本 / 迁移记录 | `COMPONENT` CHAR20 + `VERSION_NO` CHAR10 | `APPLIED_AT` CHAR14、`APPLIED_BY` CHAR12、`TRANSPORT` CHAR10、`NOTES` CHAR255 |
| `ZCRW_LOG` | 应用日志 | `LOG_ID` CHAR32 | `TIMESTAMP` CHAR14、`USER_ID` CHAR12、`AREA` CHAR20、`SEVERITY` CHAR10、`MESSAGE` CHAR255、`CONTEXT` CHAR255、`CORRELATION_ID` CHAR32 |
| `ZCRW_NOTIFY` | 站内通知（个人） | `NOTIFY_ID` CHAR32 | `USER_ID` CHAR12、`NOTIFY_TYPE` CHAR20（APPROVAL_PENDING/APPROVAL_REJECTED/TASK_OVERDUE/SCHED_OVERDUE/INFO）、`OBJECT_TYPE` CHAR10、`OBJECT_ID` CHAR20、`TITLE` CHAR80、`MESSAGE` CHAR255、`LINK_PAGE` CHAR80、`SEVERITY` CHAR10（INFO/WARN/CRITICAL）、`STATUS` CHAR10（UNREAD/READ/DISMISSED）、`DEDUP_KEY` CHAR80、`SOURCE` CHAR10（EVENT/SCAN/API）、`CREATED_AT` CHAR14、`CREATED_BY` CHAR12、`READ_AT` CHAR14 |

补充：

- P2 新增 `ZCRW_ATTACH`（附件，表存 xstring，有大小限制）与 `ZCRW_CFG_*` 细分配置表；一期不建。
- `PRIORITY` 为 `CHAR2`：`1` 紧急 / `2` 高 / `3` 中 / `4` 低；空 = 未定；规划 §8.3 示例的 `MEDIUM` 不再使用（见 §10 A5 / D11）。
- 头部 `APPROVAL_STATE`：`NONE` / `PENDING` / `APPROVED` / `REJECTED` / `SKIPPED`（见 §10 A6 / D12）。
- 通知（M5）：`NOTIFY_TYPE` / `SEVERITY` / `STATUS` / `SOURCE` 四个枚举由 `ZCL_CRW_NOTIFY` 常量约束，禁止 UI 直写；`DEDUP_KEY` 与 `USER_ID` 组合做幂等（§5.8）。

### 5.4 编号与显示 ID

| 对象 | 号段 / 生成方式 | 存储 | 显示 | API 路径 |
|---|---|---|---|---|
| CR | NROB `ZCRW_REQ`，区间 `01` | `REQ_ID` CHAR10 零填充 | `CR-0000000123` | `/requests/0000000123` |
| CD | NROB `ZCRW_CD`，区间 `01` | `CD_ID` CHAR10 零填充 | `CD-0000000123` | `/change-documents/0000000123` |
| Task / SubTask | NROB `ZCRW_TASK`，区间 `01` | `TASK_ID` CHAR10 零填充 | `T-000000045` / `ST-000000046`（前缀由 `TASK_LEVEL` 决定） | `/tasks/000000045` |
| 审批 / 历史 / 备注 / 计划 / 通知 | UUID C32 | `*_ID` CHAR32 | 原样展示 | 原样 |

- API 路径与 `OBJECT_ID` 一律使用**裸 10 位零填充编号**，不带业务前缀；`CR-` / `CD-` / `T-` / `ST-` 前缀只用于 UI 展示，由 `ZCL_CRW_UTIL=>format_id( )` 生成。
- 不做「按请求类型分号段」；类型体现在展示层前缀，避免号段膨胀。
- 号段区间由 `ZCL_CRW_NUMBER=>ensure_intervals( )` 幂等创建（`NUMBER_RANGE_UPDATE_INIT` → `NUMBER_RANGE_INTERVAL_UPDATE` → `NUMBER_RANGE_UPDATE_CLOSE` + `COMMIT`），取号用 `NUMBER_GET_NEXT`，不做本地缓存。

### 5.5 引用完整性、索引与锁

| 项 | 现状 | 规则 |
|---|---|---|
| 外键 | AFF 未定义 DDIC 外键 | 引用完整性由 service 层校验（父对象存在、层级合法、跨表状态一致）；不做级联删除 |
| 二级索引 | abap-cli 2.0.0 无建索引入口 | v1 仅主键查询；P2 走 SAP GUI / DB02 补索引（A20 / D20，清单与步骤见 [p2-basis.md](p2-basis.md) §3）；`ZCRW_NOTIFY` 建议评估 `USER_ID + STATUS + CREATED_AT` |
| 悲观锁 | `EZCRW_REQ` / `EZCRW_CD` 已建 | 关键动作（审批、状态迁移、关联传输、改计划）按对象类型加锁；锁等待超时返回冲突 |
| 乐观锁 | `VERSION` NUMC6（REQ / CD / TASK） | 更新 `WHERE version = 期望值`；影响 0 行返回 `CONCURRENT_MODIFICATION` |
| 号段并发 | `NUMBER_GET_NEXT` | 由 SAP 号段保证唯一，不在应用层加锁 |
| 删除 | API 无 DELETE 端点 | 终态通过 `CANCELLED` 表达；历史 / 审计不删除；`NEW` 可 `CANCEL`（原因必填），不提供物理/软删除（§10 A21 / D17） |

### 5.6 时间表示与 API 转换

| 层 | 表示 | 说明 |
|---|---|---|
| DDIC | `CHAR14`（`YYYYMMDDHHMMSS`）/ `DATS` | 系统本地时间；由 `ZCL_CRW_UTIL=>now( )` 生成 |
| 业务逻辑 | `CHAR14` 比较、ABAP 日期运算 | 不引入时间类型 |
| DTO / API | 时间戳 ISO 8601 含时区；日期 `YYYY-MM-DD` | 入参解析、出参格式化在 DTO 层完成 |
| 展示 | 本地化格式 | 前端按浏览器时区展示 |

- 时区基准已冻结（§10 A9 / D16）：存 SAP 系统本地时间（`sy-datum` + `sy-uzeit`），API 返回 ISO 字符串并附 `timezone:"SAP_SYSTEM"`，不做跨时区换算；逾期计算同基准。

### 5.7 数据增长与保留

- `ZCRW_HIST` / `ZCRW_LOG` / `ZCRW_NOTIFY` 只追加或按状态更新，按年增长；报表限时间窗（默认 90 天），历史 / 日志 / 通知分页加载（通知默认 20 条 / 页、上限 100）。
- 归档 / 清理策略 P2，runbook 说明；一期不删除任何业务行。通知的按年归档与应用级清理设计见 [p2-basis.md](p2-basis.md) §4。
- 测试数据由 `ZCL_CRW_DEMO_DATA`（规划）准备与清理，连续两次重跑结果一致（规划 §9.2）；`ZCL_CRW_TEST_DATA` 复位会清 `ZCRW_NOTIFY`。

### 5.8 通知模型、触发点与去重（v1.2.0）

**归属与枚举**

- 每条通知归属一个 `USER_ID`；读写 API 只返回 / 只更新当前用户的通知，服务层强制过滤，跨用户请求返回 `NOT_FOUND`。
- `NOTIFY_TYPE`：`APPROVAL_PENDING` / `APPROVAL_REJECTED` / `TASK_OVERDUE` / `SCHED_OVERDUE` / `INFO`；`SEVERITY`：`INFO` / `WARN` / `CRITICAL`（`CRITICAL` 枚举预留，当前生成方使用 `INFO` / `WARN`）；`STATUS`：`UNREAD` / `READ` / `DISMISSED`（`DISMISSED` 枚举预留，本期无 dismiss 端点）；`SOURCE`：`EVENT` / `SCAN` / `API`。

**触发点与接收人**

| 触发 | 生成方 | 接收人 | `NOTIFY_TYPE` | `DEDUP_KEY` | `SOURCE` |
|---|---|---|---|---|---|
| 审批步骤生成（CR `SUBMIT` / CD `SUBMIT_APPROVAL`） | `ZCL_CRW_APPR_SVC` → `notify_approval_pending` | 当前步骤审批人 | `APPROVAL_PENDING` | `APPR:{APPR_ID}` | `EVENT` |
| 审批驳回 | `ZCL_CRW_APPR_SVC` → `notify_approval_rejected` | 请求人（`APPROVER` 不能自审） | `APPROVAL_REJECTED` | `REJ:{OBJECT_TYPE}:{OBJECT_ID}:{APPR_ID}` | `EVENT` |
| 用户刷新 / 打开通知（`POST /notifications/refresh`） | `ZCL_CRW_NOTIFY=>refresh_for_user` | 当前用户；计划逾期仅 `CHANGE_MANAGER` / `ADMIN` | 待审批 / 任务逾期 / 计划逾期 | `APPR:{APPR_ID}` / `TASK_OVERDUE:{TASK_ID}:{DUE_DATE}` / `SCHED_OVERDUE:{SCHED_ID}:{SCHEDULED_AT}` | `SCAN` |
| 每日报表 `ZCRW_REMIND_JOB`（SM36） | `ZCL_CRW_NOTIFY=>run_scan` | 待审批 → 审批人；逾期任务 → 指派人；逾期计划 → `CHANGE_MANAGER` + `ADMIN` | 同上 | 同上一行 | `SCAN` |
| 演示数据 | `ZCL_CRW_DEMO_DATA` | 当前用户 | `INFO` | `DEMO:INFO:{USER}` | `API` |

- 任务逾期扫描条件：`DUE_DATE < sy-datum` 且非 `DONE` / `CANCELLED`；计划逾期条件：`STATUS = PLANNED` 且 `SCHEDULED_AT < now`；扫描单类最多取 500 行（`gc_max_scan_rows`），避免一次作业过大。
- 通知生成失败（异常）被吞掉，**不阻塞审批 / 扫描主流程**；邮件通道未启用时同样不影响站内通知落库。

**去重规则**

- 幂等键 = `USER_ID + DEDUP_KEY`（服务层先查后写）；同键通知已存在（含已读 / 已忽略）时**不再创建**，返回原通知 id 且 `created=false`。
- 因此 `run_scan` / `refresh` 可重复执行；跨天需要重新提醒时由 `DEDUP_KEY` 中的日期（如 `DUE_DATE`）区分。
- `DEDUP_KEY` 超 80 字符时截断（与 DDIC 长度一致），截断后仍保证同一业务事件键稳定。

**已读 / 未读语义与刷新时机**

- `UNREAD`：新建默认；`mark_read` 仅把 `UNREAD → READ` 并写 `READ_AT`（幂等：已读行不产生更新，计 0）；`mark_all_read` 批量更新当前用户全部 `UNREAD`。
- `unread_count` 统计 `USER_ID + UNREAD`；前端顶栏徽标 60 秒轮询一次（只读），页面动作 / 路由变化后按事件刷新。
- 刷新时机：应用启动（一次 `POST /notifications/refresh`，失败不阻塞）、打开铃铛下拉（先 refresh 再取最近 5 条未读）、打开 `#/notifications` 页面、页面手动「刷新」、每日 `ZCRW_REMIND_JOB`。
- 列表：`status` 过滤在数据库侧（`ALL` / `UNREAD` / `READ` / `DISMISSED`），`type` 过滤在内存（v1 表量小），按 `CREATED_AT DESC` 排序，`page` 默认 1、`size` 默认 20 / 上限 100。
- 邮件：`emit` 落库后调用预留方法 `deliver_email`；SMTP 未配置时不发信、不影响站内通知。启用与边界见 [workflow.md](workflow.md) §9.6、[p2-basis.md](p2-basis.md) §7.1。

---

## 6. `/api/v1` JSON 契约

### 6.1 通用约定

| 项 | 约定 |
|---|---|
| Base | `/sap/bc/zcrw/api/v1`（ICF 节点 `ZCRW_APP` 内） |
| Content-Type | 请求 / 响应 `application/json; charset=utf-8` |
| 成功信封 | `{"status":"success","data":...}` |
| 失败信封 | `{"status":"error","code":"...","message":"...","details":{...},"correlationId":"..."}` |
| 分页 | 查询参数 `page`（默认 1）、`size`（默认 50，最大 200）、`sort`、`order`（`asc` / `desc`） |
| 分页响应 | `{"items":[...],"page":1,"pageSize":50,"total":123}` |
| 日期 / 时间 | 日期 `YYYY-MM-DD`；时间戳 ISO 8601 含时区 |
| 命名 | DTO 字段 camelCase（`/ui2/cl_json`）；ABAP 内部按 abap-style 命名 |
| 写保护 | 所有写操作要求请求头 `X-CRW-Request: 1` 且同源；缺失或值不为 1 → `VALIDATION_ERROR`（§10 A15） |
| 乐观锁 | 写请求体带 `version`；不匹配返回 `CONCURRENT_MODIFICATION`（409） |
| 鉴权 | 依赖 SAP 会话；服务端按角色 + 数据范围校验 |
| 排序 | 字段白名单，禁止动态拼接 SQL；白名单已冻结：`createdAt|changedAt|id|title|status|priority|dueDate`（§6.7 / A12） |
| 幂等 | 动作重复提交：状态已变化返回 `INVALID_TRANSITION`，不产生重复历史 / 审批记录 |

### 6.2 端点

**身份与健康**

| 方法 | 路径 | 用途 |
|---|---|---|
| GET | `/me` | 当前用户、角色、数据范围、环境标识 |
| GET | `/health` | 版本与组件健康（只读，不含敏感信息） |
| GET | `/dashboard` | KPI 与最近动态 |

**请求 CR**

| 方法 | 路径 | 用途 |
|---|---|---|
| GET | `/requests` | CR 列表（服务端过滤 / 排序 / 分页） |
| POST | `/requests` | 新建 CR（草稿，状态 `NEW`） |
| GET | `/requests/{id}` | CR 详情（含 CD 汇总） |
| PATCH | `/requests/{id}` | 编辑头部字段（仅 `NEW` / `REJECTED`） |
| POST | `/requests/{id}/actions` | CR 状态动作 |
| GET | `/requests/{id}/change-documents` | CR 下的 CD |
| POST | `/requests/{id}/change-documents` | 新建 CD |
| GET | `/requests/{id}/history` | 历史 / 审计 |
| GET | `/requests/{id}/notes` | 备注列表 |
| POST | `/requests/{id}/notes` | 新增备注 |

**变更文档 CD**

| 方法 | 路径 | 用途 |
|---|---|---|
| GET | `/change-documents` | CD 列表 |
| GET | `/change-documents/{id}` | CD 详情 |
| PATCH | `/change-documents/{id}` | CD 编辑 |
| POST | `/change-documents/{id}/actions` | CD 状态动作（含 `SCHEDULE_IMPORT`） |
| GET | `/change-documents/{id}/tasks` | CD 下任务 |
| POST | `/change-documents/{id}/tasks` | 新建任务 |
| GET | `/change-documents/{id}/transports` | CD 下 transport（DEV / ToC） |
| GET | `/change-documents/{id}/schedule` | CD 的导入计划 |
| POST | `/change-documents/{id}/schedule` | 创建 / 修改计划 |

**任务 Task / SubTask**

| 方法 | 路径 | 用途 |
|---|---|---|
| GET | `/tasks` | 我的任务 / 全部任务 |
| GET | `/tasks/{id}` | 任务详情 |
| PATCH | `/tasks/{id}` | 改派 / 改期 |
| POST | `/tasks/{id}/actions` | 开始 / 完成 / 取消 |
| GET | `/tasks/{id}/subtasks` | 子任务 |
| POST | `/tasks/{id}/subtasks` | 新建子任务 |

**审批**

| 方法 | 路径 | 用途 |
|---|---|---|
| GET | `/approvals` | 待我审批 / 我审批过的 / 全部待办 |
| GET | `/approvals/steps?objectType=&objectId=` | 对象审批步骤 |
| POST | `/approvals/{id}/decision` | 通过 / 驳回（带意见） |

**传输与 ToC（只读集成 + 手工关联）**

| 方法 | 路径 | 用途 |
|---|---|---|
| GET | `/transports` | 传输列表（按 CD / 周期 / 类型 / 状态） |
| GET | `/transports/{trkorr}` | 传输详情（对象清单 / 时间线） |
| POST | `/transports/link` | 关联 DEV / ToC |
| POST | `/transports/{trkorr}/unlink` | 解绑（仅「可修改」） |
| POST | `/transports/{trkorr}/mark-detached` | 标记不再关联（已释放 / 已导入） |
| POST | `/transports/sync` | 同步单条 / 批量状态快照 |

**导入计划**

| 方法 | 路径 | 用途 |
|---|---|---|
| GET | `/schedules` | 计划列表（按日期 / 周期 / 目标系统） |
| POST | `/schedules/{id}/actions` | 改期 / 取消 / 确认完成 |

**通知（M5 / v1.2.0）**

| 方法 | 路径 | 用途 | 写保护 |
|---|---|---|---|
| GET | `/notifications?status=&type=&page=&size=` | 当前用户通知列表（`status`：`ALL` / `UNREAD` / `READ` / `DISMISSED`；`type`：通知类型） | — |
| GET | `/notifications/unread-count` | 当前用户未读数 `{count}` | — |
| POST | `/notifications/refresh` | 触发当前用户的扫描并返回 `{created,unread}` | `X-CRW-Request: 1` |
| POST | `/notifications/{id}/read` | 标记单条已读，返回 `{id,status,unread}` | `X-CRW-Request: 1` |
| POST | `/notifications/read-all` | 全部标记已读，返回 `{updated,unread}` | `X-CRW-Request: 1` |

- 通知无 `version`（个人通知不走乐观锁）；`{id}` 不属于当前用户时返回 `NOT_FOUND`。
- 通知不做 `POST …/actions`，标记已读是独立端点（`/read`、`/read-all`）；`status=DISMISSED` 枚举预留、无 dismiss 端点。

**配置与报表**

| 方法 | 路径 | 用途 |
|---|---|---|
| GET | `/config/cycles` | 周期列表 |
| GET | `/reports/changes` | 变更分布 / 趋势 |
| GET | `/reports/duration` | 审批 / 关闭时长 |
| GET | `/reports/overdue` | 逾期与异常 |
| GET | `/reports/to-c` | ToC / 导入漏斗（P1） |
| GET | `/reports/export.csv` | 报表导出（P1） |

### 6.3 请求 / 响应示例

新建 CR：

```json
POST /api/v1/requests
{
  "requestType": "STD",
  "title": "示例：审批阈值配置调整",
  "description": "调整审批阈值配置，影响组件示例模块。",
  "priority": "HIGH",
  "component": "MM-PUR",
  "plannedStart": "2026-11-10",
  "plannedEnd": "2026-11-21"
}
```

响应（DTO 字段全集已冻结，见 §6.7：`id` / `displayId` / `status` / `version` 必返）：

```json
{
  "status": "success",
  "data": { "id": "0000000123", "status": "NEW", "version": 1 }
}
```

新建 CD：

```json
POST /api/v1/requests/0000000123/change-documents
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
POST /api/v1/change-documents/0000000045/actions
{
  "action": "SCHEDULE_IMPORT",
  "version": 4,
  "comment": "计划 11-27 晚导入 QAS",
  "plannedImportAt": "2026-11-27T22:00:00+08:00"
}
```

关联 ToC：

```json
POST /api/v1/transports/link
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
  "correlationId": "9f2c0b1d4e6f4a8b9c0d1e2f3a4b5c6d"
}
```

### 6.4 错误信封、错误码与 HTTP 状态映射

- `details` 只放可安全暴露的上下文（当前状态、动作、缺失守卫项），不返回内部表名、堆栈或系统信息。
- `message` 取消息类 `ZCRW_MSG` 文本（支持占位符）；`correlationId` 与 `ZCRW_LOG.CORRELATION_ID` 一致，前端错误提示可展示该 ID 便于排查。

| code | HTTP | 含义 | 典型触发 |
|---|---|---|---|
| `VALIDATION_ERROR` | 400 | 参数 / 字段校验失败 | 必填缺失、格式非法、写请求头缺失 |
| `NOT_FOUND` | 404 | 对象不存在 | CR / CD / 任务 / transport / 计划不存在 |
| `FORBIDDEN` | 403 | 角色 / 数据范围不允许 | 越权动作、跨组件读取 |
| `APPROVER_MISMATCH` | 403 | 非当前步骤审批人 | 审批人不在当前步骤 |
| `SELF_APPROVAL` | 403 | 请求人不能审批自己 | 请求人点击通过 |
| `INVALID_TRANSITION` | 409 | 当前状态不允许该动作 | 状态已变化、重复动作 |
| `GUARD_FAILED` | 409 | 前置条件不满足 | 审批未完成、transport 未释放、任务未关闭 |
| `CONCURRENT_MODIFICATION` | 409 | 版本冲突 | `version` 不匹配 |
| `OBJECT_LOCKED` | 409 | SAP 锁占用 | 锁等待超时 |
| `DUPLICATE_LINK` | 409 | transport 已关联其他 CD | 重复关联 |
| `SCHEDULE_CONFLICT` | 409 | 计划冲突 / 已存在生效计划 | 改期冲突 |
| `CTS_READ_ERROR` | 502 | CTS 读取失败（降级为未知状态） | `E070` / TMS 读取异常 |
| `NUMBER_RANGE_ERROR` | 500 | 号段取号失败 | `NRIV` 区间缺失 / `NUMBER_GET_NEXT` 失败 |
| `INTERNAL_ERROR` | 500 | 未分类错误 | 未捕获异常 |

**HTTP 状态总则**：400 参数 / 校验；401 未登录；403 无权限；404 不存在；409 冲突 / 非法迁移；500 内部错误；502 上游（CTS）读取失败。

- 401 已冻结（§10 A1 / D21）：`/api/v1/*` 未登录返回 JSON 401 `UNAUTHORIZED`；页面路径由 ICF 登录过程重定向。
- 内部异常码到 API 错误码的映射在 router 层集中完成：`ZCX_CRW_ERROR.MV_CODE` 的 `NR_*` → `NUMBER_RANGE_ERROR`，`ZCRW_MSG` 001 / 004 / 006 / 007 / 008 → `NOT_FOUND`，002 → `INVALID_TRANSITION`，003 → `GUARD_FAILED`，005 → `FORBIDDEN`。
- 通知（M5）复用上述映射：`NOTIFY_NOT_FOUND` → `NOT_FOUND`(404)，`VALIDATION_ERROR`(400)（缺少 `id` / 非法类型 / 非法分页），`NOTIFY_UUID` / `NOTIFY_INSERT` → `INTERNAL_ERROR`(500)；不新增对外错误码。

### 6.5 并发与幂等

- 所有写请求带 `version`；service 用 `WHERE version = 期望值` 更新，0 行即冲突。
- 关键动作额外加 `EZCRW_REQ` / `EZCRW_CD` 排他锁；锁等待超时返回 `OBJECT_LOCKED`，前端提示重试。
- 动作幂等：同一动作重复提交且状态已变化 → `INVALID_TRANSITION`，不写第二条历史、不生成重复审批步骤。
- 一个写请求一个 LUW；任一校验失败或写表失败整体回滚，不产生部分写入。

### 6.6 版本与兼容

- 路径带 `v1`；字段**只增不删、不改语义**；破坏性变更升 `v2` 并保留 `v1` 一个迭代。
- 前端与后端同包发布；版本号写 `ZCRW_VERSION` 并由 `/health` 返回，页面显示版本。
- DTO 字段命名 camelCase；ABAP 内部命名按 abap-style，映射集中在 DTO 层，不在 controller 里散落。
- `PATCH` 局部更新语义已冻结（§6.7 / §10 A16）：只更新请求体出现的键，出现空字符串表示清空可选字段，未出现不变；`version` 必填。

---

### 6.7 v1 冻结点：DTO、动作、参数与排序白名单

> 2026-11-01 冻结（Phase 1）；与 §10 决议、[workflow.md](workflow.md) §13 决议一致。字段**只增不删**；DDIC 字段 ↔ DTO 映射只在 controller / DTO 层完成。

**通用规则**

| 项 | 冻结值 |
|---|---|
| 写保护 | 非 GET 请求必须带 `X-CRW-Request: 1`（同源）；缺失 / 值不为 1 → `VALIDATION_ERROR`(400) |
| 乐观锁 | 写请求体必带数字 `version`；缺失 → `VALIDATION_ERROR`；不匹配 → `CONCURRENT_MODIFICATION`(409) |
| PATCH 语义 | 只更新请求体中**出现的键**（按原始 JSON 键判定）；出现空字符串 = 清空可选字段；未出现 = 不变；`version` 必填 |
| 分页 | `page`（默认 1）、`size`（默认 50，最大 200）；响应 `{items,page,pageSize,total}` |
| 排序 | `sort` 白名单：`createdAt` / `changedAt` / `id` / `title` / `status` / `priority` / `dueDate`；`order=asc\|desc`；默认 `createdAt desc`；非法值 → `VALIDATION_ERROR` |
| 搜索 | 列表 `q`：标题模糊匹配（`TITLE LIKE %q%`，大小写不敏感由 DB 决定） |
| 时间 | 时间戳 `yyyy-MM-ddTHH:mm:ss` + `timezone:"SAP_SYSTEM"`（系统本地时间，不做换算）；日期 `yyyy-MM-dd`；入参接受 ISO（含偏移时忽略偏移）或 `yyyyMMddHHmmss` |
| ID | 路径与 `OBJECT_ID` = 裸 10 位零填充号；DTO 同时返回 `displayId`（`CR-…` / `CD-…` / `T-…` / `ST-…`） |
| 未登录 | `/api/v1/*` → JSON 401 `{"status":"error","code":"UNAUTHORIZED",…}`；页面路径由 ICF 登录过程重定向（Phase 2 实测） |
| 空值 | CHAR 字段空值出参为 `""`；DATS 空值出参为 `""`；`estHours` 为数字（空 = 0） |

**DTO（camelCase，出参字段全集；M1 先实现 P0，P1 字段随后补）**

```text
Me          { user, displayName, roles:[{role,scopeType,scopeId}], admin, environment, version }
Health      { version, status:"ok|degraded|down", components:{icf,tables,numberRanges,approvalMatrix,cts,version} }
Dashboard   { kpis:{myApprovals,myTasks,pendingRequests,inDev,readyToImport,overdue},
              recent:[{objectType,objectId,displayId,title,action,changedAt,changedBy}] }
Request     { id, displayId, requestType, title, description, status, priority, component, cycleId,
              requester, owner, approvalState, plannedStart, plannedEnd, dueDate,
              version, createdAt, createdBy, changedAt, changedBy, closedAt, cancelReason }
CD          { id, displayId, reqId, reqDisplayId, cycleId, title, status, owner, devLead, testLead,
              targetSystem, plannedImportAt, approvalState, version,
              createdAt, createdBy, changedAt, changedBy, closedAt }
Task        { id, displayId, reqId, cdId, parentTaskId, taskLevel:"T|S", taskType, title, assignee,
              status, dueDate, estHours, version, createdAt, createdBy, changedAt, changedBy }
Approval    { id, objectType:"REQ|CD", objectId, objectDisplayId, objectTitle, stepNo, approver,
              apprState, decidedAt, comment, createdAt }
Transport   { trkorr, cdId, taskId, trKind:"DEV|TOC", targetSystem, trStatus:"D|R|…", trStatusText,
              releasedAt, importScheduledAt, importedAt, lastSyncAt, linkedAt, linkedBy,
              retrofitState:"NA|PENDING|DONE", syncState:"OK|ERROR|DETACHED|UNKNOWN",
              description, linked, degraded }
TransportDetail = Transport + { objects:[{pgmid,object,objName,objType,objNameText}], schedule? }
Schedule    { id, objectType:"CD|TOC", objectId, objectDisplayId, targetSystem, scheduledAt,
              status:"PLANNED|DONE|MISSED|CANCELLED", note, overdue }
Cycle       { id, description, startDate, endDate, freezeDate, status, targetSystem }
RoleRow     { userId, role, scopeType, scopeId, validFrom, validTo }
MatrixRow   { profileId, stepNo, approverRole, approverUser, objectType, reqType, priority, mandatory }
History     { id, objectType, objectId, action, field, oldValue, newValue, comment, changedBy, changedAt, source }
Note        { id, objectType, objectId, author, text, createdAt, visibility }
Notification { id, notifyType:"APPROVAL_PENDING|APPROVAL_REJECTED|TASK_OVERDUE|SCHED_OVERDUE|INFO",
              objectType, objectId, objectDisplayId, title, message, linkPage,
              severity:"INFO|WARN|CRITICAL", status:"UNREAD|READ|DISMISSED", createdAt, readAt }
ChangesRpt  { byStatus:[{key,count}], byType:[{key,count}], byPriority:[{key,count}],
              trend:[{date,created,closed}] }
DurationRpt { approval:{avgHours,minHours,maxHours,count}, closure:{avgHours,minHours,maxHours,count} }
OverdueRpt  { items:[{kind:"TASK|SCHEDULE|APPROVAL",objectType,objectId,displayId,title,dueAt,daysOverdue}] }
ToCRpt      { funnel:[{stage,count}], items:[{trkorr,cdId,targetSystem,trStatus,importedAt,retrofitState}] }
```

**列表筛选参数（冻结）**

| 资源 | 参数 |
|---|---|
| `/requests` | `status` `requestType` `priority` `component` `cycleId` `owner` `requester` `q` |
| `/change-documents` | `reqId` `status` `cycleId` `owner` `targetSystem` `q` |
| `/tasks` | `assignee` `status` `taskType` `cdId` `reqId` `parentTaskId` `dueDateFrom` `dueDateTo` `q` |
| `/approvals` | `scope=mine\|decided\|all`（默认 `mine`） |
| `/transports` | `cdId` `trKind` `targetSystem` `syncState` `q`(trkorr/描述) |
| `/schedules` | `from` `to` `targetSystem` `status` `objectType` `overdue=true` |
| `/notifications` | `status=ALL\|UNREAD\|READ\|DISMISSED`（默认 `ALL`）、`type=<NOTIFY_TYPE>`、`page`（默认 1）、`size`（默认 20，上限 100）；仅返回当前用户数据 |

**通知写端点（不走 `…/actions`）**

| 端点 | body / 语义 | 返回 |
|---|---|---|
| `POST /notifications/refresh` | 无 body；触发当前用户扫描并落库 | `{created,unread}` |
| `POST /notifications/{id}/read` | 无 body；仅本人通知，`UNREAD → READ` 才更新 | `{id,status:"READ",unread}` |
| `POST /notifications/read-all` | 无 body；当前用户全部 `UNREAD → READ` | `{updated,unread}` |

- 通知端点无 `version`；`X-CRW-Request: 1` 写保护同样适用；`{id}` 不存在或不属于当前用户 → `NOT_FOUND`。

**动作与专属参数（`POST …/actions`，body `{action, version, comment?, …}`）**

| 对象 | action | 专属参数 / 说明 |
|---|---|---|
| CR | `SUBMIT` `WITHDRAW` `APPROVE_STEP` `REJECT` `SKIP_STEP` `REVISE` `START_PROGRESS` `CLOSE` `CANCEL` | `REJECT`/`CANCEL` 需 `comment`；`CANCEL` 写 `cancelReason` |
| CD | `START_DEV` `SUBMIT_TEST` `PASS_TEST` `SUBMIT_APPROVAL` `MARK_READY` `SCHEDULE_IMPORT` `CONFIRM_IMPORT` `CLOSE` `CANCEL` | `SCHEDULE_IMPORT` 需 `plannedImportAt`，取消计划传 `cancelSchedule:true`；`PASS_TEST` 可带 `comment`；`CONFIRM_IMPORT` 可带 `importedAt`（缺省 now） |
| Task | `START` `DONE` `CANCEL` | `CANCEL` 需 `comment` |
| Schedule | `/schedules/{id}/actions`：`RESCHEDULE`（`scheduledAt` 必填）、`CANCEL`、`CONFIRM` | 确认完成写 `DONE` 并从 `PLANNED`/`MISSED` 迁移 |
| Approval | `/approvals/{id}/decision`：`{decision:"APPROVED"\|"REJECTED", comment, version}` | `REJECTED` 需 `comment` |

**创建/编辑载荷（冻结字段；`POST` 用创建字段，`PATCH` 用可编辑字段）**

- `POST /requests`：`requestType` `title` `description?` `priority` `component` `cycleId?` `owner?` `plannedStart` `plannedEnd` `dueDate?`（`requester` 取会话用户）。
- `PATCH /requests/{id}`：`title` `description` `priority` `component` `cycleId` `owner` `plannedStart` `plannedEnd` `dueDate`。
- `POST /requests/{id}/change-documents`：`title` `cycleId?` `targetSystem` `owner?` `devLead?` `testLead?` `plannedImportAt?` `version`（父 CR version）。
- `PATCH /change-documents/{id}`：`title` `cycleId` `targetSystem` `owner` `devLead` `testLead` `plannedImportAt`。
- `POST /change-documents/{id}/tasks`：`title` `taskType` `assignee` `dueDate?` `estHours?`。
- `POST /tasks/{id}/subtasks`：`title` `taskType` `assignee` `dueDate?` `estHours?`。
- `PATCH /tasks/{id}`：`title` `assignee` `dueDate` `estHours`。
- `POST /transports/link`：`cdId` `trkorr` `trKind` `taskId?`。
- `POST /approvals/{id}/decision`：见上表。

**错误码补充**：`UNAUTHORIZED` = 401（未登录）；其余见 §6.4。

---

## 7. 部署：ICF 节点、MIME 与 SPA

### 7.1 ICF 节点

| 项 | 值 |
|---|---|
| 节点名 | `ZCRW_APP` |
| 路径 | `/sap/bc/zcrw` |
| 处理器类 | `ZCL_CRW_HTTP_HANDLER`（实现 `IF_HTTP_EXTENSION`） |
| 创建方式 | AFF `create HTTP --file`（仓库内保留规范 AFF；执行时生成带顶层 `name` 的临时副本） |
| 状态 | **已创建并实测（2026-11-01）**：`GET /`、静态资产、SPA fallback、`GET /api/v1/*` 均 200；无尾斜杠 `/sap/bc/zcrw` 302 到带斜杠 URL；未登录由 ICF 标准登录过程返回 401 |
| MIME | 根 `/zcrw` + 子目录 `/zcrw/js`、`/zcrw/js/components`、`/zcrw/js/pages`；`mime push` 会把目录内容**扁平**上传到 `--root`，因此按层级分别 push（见 runbook S9） |
| 认证 | SAP 登录（SSO / 表单 / Basic，按客户环境）；应用不保存密码 |
| 会话 | 由 SAP 控制超时 |

### 7.2 路由与 MIME 根

| 请求路径（节点内） | 处理 |
|---|---|
| `/api/v1/...` | `ZCL_CRW_API_ROUTER` → controller → service → repo |
| 静态资源命中（`/zcrw` 下存在） | `ZCL_CRW_MIME` 读取并返回 |
| 其它非 API GET | SPA fallback：返回 `index.html`（200），保证直接访问子路径 / 刷新不 404 |

- MIME 根：`/zcrw`；前端资产在 `src/mime/`，用 `mime create` + `mime push src/mime --root /zcrw` 上传。
- MIME 目录 / 文件、子目录、SPA fallback 已随 M1 前端一起验证（规划附录 B.2 #7 / #8）；新增页面 / 样式随每次前端变更按层级重推（runbook S9）。
- 不提交构建产物；不引用 CDN、外部字体与图标库。

### 7.3 缓存与响应头

| 项 | 约定 |
|---|---|
| API 响应 | `Content-Type: application/json; charset=utf-8`；不缓存 |
| 静态资源 | `Cache-Control: no-cache` + URL 版本参数 `?v=<version>`；API `no-store`；ETag 不实现（§10 A13） |
| CSP | `default-src 'self'`；禁止内联脚本（除 hash） |
| 安全头 | 同源校验；写接口要求 `X-CRW-Request: 1` |
| 错误响应 | 不暴露内部细节、表名、堆栈、系统信息 |

### 7.4 安装顺序

域 / 数据元素（如需）→ 表（14 张，含 `ZCRW_NOTIFY`）→ 号段对象 → 锁对象 → 消息类 → 类 / 接口（含 `ZCL_CRW_NOTIFY` / `ZCL_CRW_API_NOTIFY`）→ 报表程序 `ZCRW_REMIND_JOB` → ICF 节点 → 事务码 → MIME → `ZCL_CRW_BOOTSTRAP` → `ZCL_CRW_MIGRATION` → `ZCL_CRW_SELFCHECK`。

- 主对象上报前必须 `abap check content`（`.abap`）/ `abap validate:aff`（JSON）；写 SAP 顺序 `check syntax` → `push` → `inspect --activation`。
- M5 起已交付「14 表 + 3 号段 + 消息类 + 2 锁对象 + 通知服务 / 控制器 + 提醒报表 + 前端 16 页面（含 `#/notifications`）」；ICF / MIME / TRAN / ICF 认证已随 M1 前端验证（规划附录 B.2）。M5 实测：selfcheck `tables=14 version=1.2.0 notifications=0`（复位后）、单测 4 套全绿（util 4 / workflow 10 / json 8 / notify 5）、M1 smoke、演示数据（notifications=2）、提醒报表与通知 API 控制器探针均通过；浏览器 HTTP 端到端待人工复核。
- 详细命令与排障见 [runbook.md](runbook.md)。

### 7.5 事务码

| 项 | 值 |
|---|---|
| 事务码 | `ZCRW` |
| 类型与参数 | 参数事务 `ZCRW` → 报表 `ZCRW_START` 打开 ICF URL（`cl_gui_frontend_services=>execute`）；AFF 无 URL 类型 TRAN，实测后回写（§10 A2 / D22） |

### 7.6 本地包限制与部署边界

- `$CRW` 为本地包（super package `$TMP`，DLVUNIT LOCAL，无 transport）：对象不产生 transport，**不可跨系统部署**到 QA / 生产。
- 本地包不可传输；若后续要产品化部署，需迁移到可传输包（P2 只出设计，路径 / CLI 限制 / 验收见 [p2-basis.md](p2-basis.md) §2，本轮暂不做）。
- abap-cli 升级后必须重新 `abap deploy --yes` 并确认 `deploy status` current，否则 DDIC / ICF 写路径可能失败。

---

## 8. 安全与权限

### 8.1 认证

- 身份来自 ICF 节点的 SAP 登录（SSO / 表单 / Basic，按客户环境）；应用不保存、不传递密码。
- 会话超时由 SAP 控制；未登录时 API 返回 JSON 401 `UNAUTHORIZED`（§10 A1 / D21）。

### 8.2 应用角色模型

| 角色 | 职责 | 数据范围 | 一期 |
|---|---|---|---|
| 请求人 Requester | 新建 / 编辑 / 提交 / 撤回自己的请求，补充说明，查看进度 | 自己的请求 | P0 |
| 变更经理 Change Manager | 审批 / 驳回、指派 Owner、调整优先级与计划、关闭异常 | 全部请求 | P0 |
| 开发 Developer | 接任务 / 子任务，推进 CD 开发 / 测试状态，关联 transport | 指派给本人的任务 / CD | P0 |
| 测试 Tester | 执行测试、记录结论、驳回 | 指派给本人的测试任务 | P0 |
| 发布管理员 Release Manager | 维护 transport 状态、确认导入、维护导入计划 | 全部 transport 与计划 | P0 |
| 管理员 Admin | 角色分配、配置、号段、初始化、迁移、审计导出 | 全部 | P0 |
| 观察者 Viewer | 只读查看报表与请求 | 按组件 / 周期 | P2 |

- 角色存于 `ZCRW_ROLE`：`USER_ID` + `ROLE` + `SCOPE_TYPE`（GLOBAL / COMPONENT / CYCLE）+ `SCOPE_ID` + 有效期 `VALID_FROM` / `VALID_TO`。
- 角色编码已冻结（§10 A7 / W10）：`REQUESTER` / `CHANGE_MANAGER` / `DEVELOPER` / `TESTER` / `RELEASE_MANAGER` / `ADMIN`（`VIEWER` P2）。
- bootstrap 把当前执行用户初始化为 `ADMIN`（初始管理员）；后续角色分配走管理界面（P1）或 runbook 手工步骤。
- 通知数据范围：只返回 / 只更新本人通知（`USER_ID = 当前用户`）；计划逾期提醒仅发给 `CHANGE_MANAGER` / `ADMIN`（`run_scan` 与 `refresh_for_user` 一致）。

### 8.3 服务端鉴权与数据范围

- 每个写操作在 service 层校验「角色 + 数据范围 + 当前状态」；前端隐藏按钮只是体验，不作为安全边界。
- 读操作按角色与数据范围过滤（请求人仅自己的请求；开发 / 测试按指派；变更经理 / 发布管理员 / 管理员全量；观察者按组件 / 周期）。
- 审批人校验额外两条：非当前步骤审批人 → `APPROVER_MISMATCH`；请求人审批自己 → `SELF_APPROVAL`。
- 标准权限叠加：v1 不做 `AUTHORITY-CHECK`，依赖 SAP 登录 + 应用角色；basis 级增强 P2（§10 A8）。
- 不创建自定义 AUTH 对象（abap-cli 不支持）；生产级自定义权限人工配置。

### 8.4 Web 安全基线

- 渲染文本全部转义（XSS）；导出文件名不含用户输入；错误信息不暴露内部细节。
- 写接口要求自定义请求头并校验同源（CSRF 防线）；不依赖 Cookie 之外的隐式凭证。
- 返回 CSP 头（`default-src 'self'`）；禁止内联脚本（除 hash）。
- 不在 URL 放敏感数据；日志不记录敏感字段。
- 不落真实业务数据到演示数据 / 截图；测试 / QA 数据可重置。

### 8.5 审计边界

- 应用级审计（`ZCRW_HIST`）只追加、无删除入口、导出只读，但**不是合规级不可篡改**：管理员仍可直接改表，runbook 必须写明该边界。
- 审计写入与业务写入同一 LUW，避免「状态变了但没历史」。

---

## 9. 版本、迁移与运维

### 9.1 版本标识

- `ZCRW_VERSION`（`COMPONENT` + `VERSION_NO`）记录已应用版本；bootstrap 种 `CRW` / `1.2.0`（版本路径：1.0.0 → 1.1.0 → 1.2.0，M5 通知中心）。
- `/health` 返回版本与组件状态；页面显示版本；枚举已冻结（§10 A10）：`status` = `ok|degraded|down`，`components` = `{icf,tables,numberRanges,approvalMatrix,cts,version}`。

### 9.2 Bootstrap 与 Migration

| 程序 | 语义 | 契约 |
|---|---|---|
| `ZCL_CRW_BOOTSTRAP` | 幂等初始化 | 建 3 个号段区间；INSERT 种子行（版本、审批矩阵 `STD_DEFAULT`、初始管理员）；重复执行结果一致（已存在则跳过，不更新）；输出 `CRW_BOOTSTRAP_OK intervals=… config=…` |
| `ZCL_CRW_MIGRATION` | 按版本号执行幂等迁移 | 读 `ZCRW_VERSION` 判断待应用版本；执行后写版本行 + 审计（`OBJECT_TYPE=CONFIG`）+ 日志 |

### 9.3 Selfcheck 契约

- 只读；输出固定标记 `CRW_SELFCHECK_OK tables=14 rows=… intervals=3 version=… messages=… roles=… approvals=… notifications=… icf=OK cts=OK`；失败输出 `CRW_SELFCHECK_FAIL …`。
- 覆盖：14 表可读（含 `ZCRW_NOTIFY`）、通知行数、3 个号段区间、最新版本行、`ZCRW_MSG` 消息数、ADMIN 角色、审批矩阵种子行、**ICF 节点存在（TADIR SICF）**、**E070 只读**（A11 / D23 已实现；CTS 读取失败降级为 `cts=DEGRADED`，ICF 缺失判 FAIL）。
- 用于只读验收：`abap run ZCL_CRW_SELFCHECK --json`（只读白名单内）。

### 9.4 日志与可观测

- `ZCRW_LOG`：API 错误、CTS 同步失败、迁移执行、权限拒绝；字段 `AREA` / `SEVERITY` / `MESSAGE` / `CONTEXT` / `CORRELATION_ID`。
- 错误响应带 `correlationId`，与日志行一致，便于从用户报错定位日志。
- 定期只读检查 `abap dumps` 确认无运行时错误（规划 §7.8）。

### 9.5 升级流程

1. CLI 升级后 `abap deploy --yes`，确认 `deploy status` = current。
2. `abap check content` / `abap validate:aff` 静态校验。
3. 按依赖顺序 `check syntax` → `push` → `inspect --activation`（M5 顺序：DDIC 表 → `ZCL_CRW_NOTIFY` → `ZCL_CRW_API_NOTIFY` / `_API_MAP` / `_API_TYPES` / `_API_ROUTER` → `ZCRW_REMIND_JOB` → `ZCL_CRW_HTTP_HANDLER`）。
4. 运行 `ZCL_CRW_BOOTSTRAP`（补号段 / 种子 / 版本 1.2.0）。
5. 运行 `ZCL_CRW_MIGRATION`（按版本执行）。
6. 运行 `ZCL_CRW_SELFCHECK`，确认 `CRW_SELFCHECK_OK`（`tables=14`、`version=1.2.0`）。
7. 前端资产 `mime push`；页面版本号与 `/health` 一致（M5 含 `js/pages/notifications.js`）。
8. 需要每日提醒时，由 basis 按 [runbook.md](runbook.md) §2.13 建 `SM36` 作业 `ZCRW_REMIND`（本轮不建）。

### 9.6 回滚

- 回滚策略已冻结（§10 A17）：AFF 重推上一版本 + bootstrap/migration 幂等；数据不回滚；表结构变更需删除重建（CLI 无 ALTER）；详见 `docs/runbook.md`。

---

## 10. 关键决策与 v1 决议（A1–A22）

| 编号 | 问题 | 影响 | v1 决议（2026-11-01 冻结） |
|---|---|---|---|---|
| A1 | ICF 认证方式与未登录时 API 行为 | 前端错误处理、API 契约 | `/api/v1/*` 返回 JSON 401 `UNAUTHORIZED`；页面路径由 ICF 登录过程重定向（Phase 2 实测回写；见 D21） |
| A2 | 事务码 `ZCRW` 的类型与参数 | 入口体验 | 参数事务 `ZCRW` → 报表 `ZCRW_START`（`cl_gui_frontend_services=>execute` 打开 ICF URL）；P2 评估 Fiori tile（D22） |
| A3 | MIME 子目录与 SPA fallback | 前端路由与部署 | 静态资源按路径命中；非 API GET 未命中返回 `index.html` 200；Phase 3 实测 |
| A4 | API 展示编号与 DTO 字段全集 | 前端展示、契约冻结 | 冻结见 §6.7：路径用裸 10 位号，DTO 同时返回 `displayId` 与 `timezone` |
| A5 | `PRIORITY` 编码集合与通配 | 审批矩阵、列表筛选 | `1` 紧急 / `2` 高 / `3` 中 / `4` 低；空 = 未定；矩阵空 = 通配（D11） |
| A6 | 头部 `APPROVAL_STATE` 取值集合 | 审批联动、列表过滤 | `NONE` / `PENDING` / `APPROVED` / `REJECTED` / `SKIPPED`（D12，语义见 workflow W3） |
| A7 | 角色编码集合 | 鉴权、bootstrap 种子 | `REQUESTER` / `CHANGE_MANAGER` / `DEVELOPER` / `TESTER` / `RELEASE_MANAGER` / `ADMIN`（`VIEWER` P2）（W10） |
| A8 | 标准权限检查项与降级 | 安全验收 | v1 不做 `AUTHORITY-CHECK`：依赖 SAP 登录 + 应用角色；basis 级增强 P2 |
| A9 | 时区基准与换算 | 计划导入、逾期计算 | 存 SAP 系统本地时间；API 返回 ISO 无偏移 + `timezone:"SAP_SYSTEM"`；不换算（D16） |
| A10 | `/health` 组件状态枚举 | 运维、自检 | `{version,status:ok\|degraded\|down,components:{icf,tables,numberRanges,approvalMatrix,cts,version}}`；组件值 `ok`/`degraded`/`down`/`unknown` |
| A11 | selfcheck 的 CTS / ICF 检查 | 只读验收 DoD | M2 增 ICF 节点存在与 E070 只读检查，输出 `icf=` / `cts=`；ICF 缺失 FAIL、CTS 失败 DEGRADED（D23） |
| A12 | 分页排序字段白名单 | 列表契约、性能 | 冻结见 §6.7：`createdAt|changedAt|id|title|status|priority|dueDate` |
| A13 | 静态资源缓存策略 | 前端发布、缓存失效 | 静态资源 `Cache-Control: no-cache` + `?v=<version>`；API `no-store`；ETag 不实现 |
| A14 | `CHAR255` 长文本超长处理 | 数据完整性 | 入参 > 255 字符 → `VALIDATION_ERROR`，不静默截断；内部拼接文本截断 255（W26） |
| A15 | 写请求头缺失 / 非同源错误码 | 安全用例 | `VALIDATION_ERROR`(400)（缺 `X-CRW-Request: 1` 或值不为 1） |
| A16 | `PATCH` 局部更新语义 | API 契约、前端表单 | 只更新请求体出现的键；空字符串清空；未出现不变；`version` 必填（§6.7） |
| A17 | 应用级回滚流程与数据兼容 | 升级运维 | runbook：AFF 重推上一版本 + bootstrap/migration 幂等；数据不回滚；表结构变更需删除重建 |
| A18 | 数据保留 / 归档策略 | 性能、存储 | P2；只出设计（SARA/AOBJ、按年归档 HIST/LOG/NOTIFY，见 [p2-basis.md](p2-basis.md) §4）；一期不删除任何业务行 |
| A19 | 可传输包迁移路径 | 产品化部署 | P2；本轮**暂不做**（保持 `$CRW` 本地包，不可跨系统）；路径 / CLI 限制 / 验收见 [p2-basis.md](p2-basis.md) §2 |
| A20 | 索引创建方式与查询路径 | 列表性能 | v1 不建二级索引（CLI 无入口）；**后置**（A20 / D20）；建议清单与 SE11 步骤见 [p2-basis.md](p2-basis.md) §3 |
| A21 | `NEW` 状态 CR 删除语义 | 数据完整性、审计 | 不提供物理/软删除 API；`NEW` 可 `CANCEL`（原因必填），审计只追加（D17） |
| A22 | 状态机 / 仓储分层与审计类命名 | 分层一致性、可测试性 | M2 抽 `ZCL_CRW_WORKFLOW`（纯逻辑）+ `ZCL_CRW_AUTH`；`ZCL_CRW_AUDIT` 不重命名；仓储层单拆留 P2（D19） |

### 10.1 v1.2.0 增补决议（2026-11-02，通知中心）

| 编号 | 问题 | 决议 |
|---|---|---|
| N1 | 通知模型与去重 | 独立表 `ZCRW_NOTIFY`，按 `USER_ID` 归属；`NOTIFY_TYPE` / `SEVERITY` / `STATUS` / `SOURCE` 枚举固定；幂等键 `USER_ID + DEDUP_KEY`，已存在（含已读）不重复创建；扫描幂等（对应规划 D24，语义见 §5.8） |
| N2 | 邮件通道 | `ZCL_CRW_NOTIFY=>deliver_email` 预留；SMTP / SCOT 未配置前不发信、不阻塞站内通知与业务动作；启用步骤见 [p2-basis.md](p2-basis.md) §7.1、[workflow.md](workflow.md) §9.6（对应规划 D25） |
| N3 | P2 basis 类项 | 包迁移（A19）、索引（A20 / D20）、归档（A18）、权限对象（A8）、Fiori（D22）本轮**只出设计**，见 [p2-basis.md](p2-basis.md)；本轮暂不做 / 后置的决策记录同步到规划 §12.3 |


---

## 11. 参考

- [CRW 规划](../../../docs/change-request-workbench-plan.md)：范围、决策 D1–D10、里程碑与验收、M0 验证结果。
- [workflow.md](workflow.md)：状态机、审批矩阵、CTS 只读集成、导入计划、通知、审计与错误语义。
- [p2-basis.md](p2-basis.md)：P2 basis 类项（包迁移 / 索引 / 归档 / 权限对象 / Fiori）设计与可执行清单。
- [README](../README.md)：产品说明、当前状态、安装与验证命令。
- [`AGENTS.md`](../../../AGENTS.md) §4A：应用单元契约（目录、命名、包与写路径、DoD）。
