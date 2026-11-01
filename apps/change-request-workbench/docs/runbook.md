# 变更请求工作台（CRW）· 运行手册（Runbook）

> 状态：v1 骨架（2026-11-01）；对应 [architecture.md](architecture.md) v1、[workflow.md](workflow.md) v1 的冻结契约。
> 适用：SAP S/4HANA 2022+、abap-cli 2.0.0（Node.js 24 LTS）、包 `$CRW`（本地包，无 transport）。
> 使用约定：所有命令都在 `apps/change-request-workbench/` 下执行；`<...>` 为占位符，按目标系统替换；**写 SAP 的命令必须先人工确认目标环境为 dev / test / trial**。
> 脱敏：本文不记录主机名、URL、client、用户名、transport 号与真实业务数据；M1 实测后再回写的命令行以 `<...>` 标注。
> 标注规则：§10 的验证清单全部只读；“安装 / 开发步骤”会写 SAP，明确标注，不得当作日常只读验证使用。

---

## 1. 范围与前置条件

### 1.1 适用系统与工具

| 项 | 要求 | 检查方式 |
|---|---|---|
| SAP 系统 | S/4HANA 2022+（`IF_HTTP_EXTENSION`、`CL_MIME_REPOSITORY_API`、ABAP SQL 聚合可用） | `abap doctor --json` |
| abap-cli | 2.0.0（Node.js 24 LTS），`$` 前缀本地包免 transport | `abap --version`、`node -v` |
| profile | `system` 必须为 `dev` / `test` / `trial`；写操作前人工确认非生产 | `abap init --show-config --json` |
| 内置 ICF 服务 | 已部署且 `deploy status` 为 `current`（版本与 CLI 匹配） | `abap deploy status --json` |
| 应用包 | `$CRW` 本地包（super package `$TMP`、DLVUNIT LOCAL、无 transport） | §2 S1（已存在返回 `OBJECT_EXISTS`，忽略） |
| 代码来源 | `src/` 的 AFF 文件是唯一来源；`src/mime/` 为前端资产 | 仓库 `apps/change-request-workbench/` |

### 1.2 边界与安全约定

- `$CRW` 是本地包：对象不产生 transport，**不可跨系统部署**（QA / 生产不可用 CTS 传输）；换系统必须在新系统按 §2 重新安装。
- 不碰生产；不 release transport；不执行 TMS 导入；不 `push --all`、不 `abap check --all`；一次只写本应用对象。
- 写 SAP 的顺序固定：`check content` / `validate:aff` → `check syntax` → `push` → `inspect --activation`。
- 不提交 `.abap.json`、凭证、URL、client、用户名、真实业务数据；截图必须脱敏。
- CLI 的 `SESSION_STORE_FALLBACK` / `SESSION_REUSE_UNSTABLE` 是会话存储提示（WARN），不影响命令结果。

### 1.3 预检命令（只读）

```bash
cd apps/change-request-workbench
abap --version
node -v
abap doctor --json
abap init --show-config --json
abap deploy status --json
```

期望：`abap doctor` 为 `status=success` 且 `data.environment[].status` 全部 ok；profile 的 `system` ∈ {`dev`,`test`,`trial`}；`deploy status` 为 `data.status=current`、`data.match=true`。

失败处理：`CONFIG_ERROR` / `AUTH_ERROR` / `TLS_ERROR` → 读 `.agents/skills/abap-cli-setup/SKILL.md`；ICF 服务非 current → `abap deploy --yes --json` 后重跑；**无法确认非生产环境时停止，先问人**。

---

## 2. 首次安装顺序

> 顺序不可乱：DDIC / ICF 写路径依赖内置 ICF 服务；类有编译依赖；ICF 节点要求 handler 先激活；MIME 必须在 ICF 节点后。
> 当前 test 环境已具备 13 表、3 号段对象、2 锁对象、消息类与 M1 服务类；本节用于**全新系统重装**与**升级补齐**，未交付对象（标 M1/M2/M3）在入库后执行。

### 2.1 步骤总览

| 步骤 | 内容 | 完成标志 |
|---|---|---|
| S1 | 本地包 `$CRW`（如缺） | 包存在 |
| S2 | 13 张 `ZCRW_*` 表 | `DD02L` 13 行 |
| S3 | 号段对象 `NROB` | `TNRO` 3 行 |
| S4 | 锁对象 `ENQU` | `DD25L` 2 行 |
| S5 | 消息类 `MSAG` | `T100` 8 行 |
| S6 | 类 / 接口（依赖序）+ testclasses | 全部 active |
| S7 | ICF 节点 `ZCRW_APP` | `ICFSERVICE` 1 行 |
| S8 | 事务码 `ZCRW`（参数事务） | `abap tcode ZCRW` 可解析 |
| S9 | MIME `/zcrw` | `mime push` 上传成功 |
| S10 | `ZCL_CRW_BOOTSTRAP` | `CRW_BOOTSTRAP_OK` |
| S11 | `ZCL_CRW_MIGRATION` | 版本一致 |
| S12 | `ZCL_CRW_SELFCHECK` | `CRW_SELFCHECK_OK` |

### 2.2 S1 创建本地包 `$CRW`（如缺）

```bash
abap create DEVC '$CRW' --package '$TMP' \
  --description 'Change Request Workbench local package' \
  --package-type development --yes --json
```

期望：`status=success`、`data.activated=true`。已存在时返回 `OBJECT_EXISTS`，可忽略并继续。

### 2.3 S2 创建 13 张表

先做本地 AFF 校验，再逐张创建与推送（`push` 必须显式给文件路径）：

```bash
abap validate:aff src/ --json
# 每张表执行一次：<表> 用下表对象名，<file> 用对应 AFF 文件名
abap create TABL <表> --file src/<file>.tabl.json --package '$CRW' \
  --description '<表> table' --yes --json
abap push src/<file>.tabl.json --yes --json
```

| 表 | AFF 文件 | 说明 |
|---|---|---|
| `ZCRW_REQ` | `src/zcrw_req.tabl.json` | CR 请求头 |
| `ZCRW_CD` | `src/zcrw_cd.tabl.json` | 变更文档（CD） |
| `ZCRW_TASK` | `src/zcrw_task.tabl.json` | Task / SubTask |
| `ZCRW_TR` | `src/zcrw_tr.tabl.json` | 传输关联快照 |
| `ZCRW_SCHED` | `src/zcrw_sched.tabl.json` | 导入计划（权威） |
| `ZCRW_APPR` | `src/zcrw_appr.tabl.json` | 审批步骤实例 |
| `ZCRW_APPR_CFG` | `src/zcrw_appr_cfg.tabl.json` | 审批矩阵配置 |
| `ZCRW_HIST` | `src/zcrw_hist.tabl.json` | 审计历史（只追加） |
| `ZCRW_NOTE` | `src/zcrw_note.tabl.json` | 备注 |
| `ZCRW_CYCLE` | `src/zcrw_cycle.tabl.json` | 周期（P1 轻量） |
| `ZCRW_ROLE` | `src/zcrw_role.tabl.json` | 应用角色 |
| `ZCRW_VERSION` | `src/zcrw_version.tabl.json` | 版本与迁移记录 |
| `ZCRW_LOG` | `src/zcrw_log.tabl.json` | 技术日志（只追加） |

期望：每次 `create` 为 `status=success`、`data.activated=true`；`push` 为 `data.failed=0`、`data.results[0].activated=true`。
说明：表只允许 `CHAR` / `NUMC` / `DATS` / `TIMS` 字段（CLI 建表 exclass 限制）；表结构变更没有 `ALTER`，只能删除重建（见 §8）。

### 2.4 S3 创建号段对象（`NROB`）

```bash
abap create NROB ZCRW_REQ  --file src/zcrw_req.nrob.json  --package '$CRW' --description 'CRW request number range' --yes --json
abap create NROB ZCRW_CD   --file src/zcrw_cd.nrob.json   --package '$CRW' --description 'CRW change document number range' --yes --json
abap create NROB ZCRW_TASK --file src/zcrw_task.nrob.json --package '$CRW' --description 'CRW task number range' --yes --json
```

期望：`status=success`、`data.activated=true`。号段的**区间**（`01`）由 S10 bootstrap 创建，此处只建对象。

### 2.5 S4 创建锁对象（`ENQU`）

```bash
abap create ENQU EZCRW_REQ --file src/ezcrw_req.enqu.json --package '$CRW' --description 'CRW request lock' --yes --json
abap create ENQU EZCRW_CD  --file src/ezcrw_cd.enqu.json  --package '$CRW' --description 'CRW change document lock' --yes --json
```

期望：`status=success`、`data.activated=true`。主表分别为 `ZCRW_REQ` / `ZCRW_CD`。

### 2.6 S5 创建消息类（`MSAG`）

```bash
abap create MSAG ZCRW_MSG --file src/zcrw_msg.msag.json --package '$CRW' --description 'CRW messages' --yes --json
```

期望：`status=success`；后续 `T100` 计数为 8（只读核对见 §10）。

### 2.7 S6 按依赖序创建类 / 接口 + testclasses

依赖序（后项引用前项）：`ZCX_CRW_ERROR` → `ZCL_CRW_UTIL` → `ZCL_CRW_NUMBER` → `ZCL_CRW_AUDIT` → `ZCL_CRW_LOG` → `ZCL_CRW_JSON` → `ZCL_CRW_AUTH` → `ZCL_CRW_WORKFLOW` → `ZCL_CRW_REQUEST_SVC` / `ZCL_CRW_CD_SVC` / `ZCL_CRW_TASK_SVC` → `ZCL_CRW_APPR_SVC` → `ZCL_CRW_TRANSPORT_SVC` / `ZCL_CRW_SCHEDULE_SVC` → `ZCL_CRW_REPORT_SVC` → `ZCL_CRW_API_*` → `ZCL_CRW_HTTP_HANDLER` → 运维类（`ZCL_CRW_BOOTSTRAP` / `ZCL_CRW_MIGRATION` / `ZCL_CRW_SELFCHECK` / `ZCL_CRW_TEST_DATA`）。

接口（如 `ZIF_CRW_CTS_READER`）在引用它的类之前创建；仓储 / 控制器 / 其他支撑类（`ZCL_CRW_MIME`、`ZCL_CRW_CONFIG` 等）按 architecture §4 清单随所属层推送，依赖序不变（`ZCL_CRW_MIME` 必须在 `ZCL_CRW_HTTP_HANDLER` 之前）。

```bash
for c in ZCX_CRW_ERROR ZCL_CRW_UTIL ZCL_CRW_NUMBER ZCL_CRW_AUDIT ZCL_CRW_LOG ZCL_CRW_JSON ZCL_CRW_AUTH \
         ZCL_CRW_WORKFLOW ZCL_CRW_REQUEST_SVC ZCL_CRW_CD_SVC ZCL_CRW_TASK_SVC ZCL_CRW_APPR_SVC \
         ZCL_CRW_TRANSPORT_SVC ZCL_CRW_SCHEDULE_SVC ZCL_CRW_REPORT_SVC ZCL_CRW_API_CONTEXT \
         ZCL_CRW_API_TYPES ZCL_CRW_API_REQUEST ZCL_CRW_API_CD ZCL_CRW_API_TASK ZCL_CRW_API_ROUTER \
         ZCL_CRW_HTTP_HANDLER ZCL_CRW_BOOTSTRAP ZCL_CRW_MIGRATION ZCL_CRW_SELFCHECK ZCL_CRW_TEST_DATA; do
  f="src/$(printf '%s' "$c" | tr '[:upper:]' '[:lower:]').clas.abap"
  abap create CLAS "$c" --package '$CRW' --no-pull --description 'CRW class' --yes --json
  abap check syntax "$f" --json
  abap push "$f" --yes --json
  abap inspect "$c" --activation --json
done

# testclasses sidecar（如 ZCL_CRW_UTIL）
abap push src/zcl_crw_util.clas.testclasses.abap --yes --json
abap test ZCL_CRW_UTIL --json
```

期望：`create` 为 `status=success`（已存在为 `OBJECT_EXISTS`，跳过该对象）；`check syntax` 为 `data.failure=false`；`push` 为 `data.failed=0`、`data.results[0].activated=true`；`inspect` 为 `data.activation.ok=true`。
说明：`--no-pull` 防止 `create` 后拉取空骨架覆盖仓库内 `src/` 权威源码；`ZCX_CRW_ERROR` 必须保持 `INHERITING FROM cx_static_check`（父类属性不符时激活报错，按错误信息修正创建方式后重推）。

### 2.8 S7 创建 ICF 节点 `ZCRW_APP`

前提：`ZCL_CRW_HTTP_HANDLER` 已激活（`abap inspect ZCL_CRW_HTTP_HANDLER --activation --json` → `data.activation.ok=true`）。
AFF：`src/zcrw_app.http.json`（M1 与 handler 一起入库；`handlerClass = ZCL_CRW_HTTP_HANDLER`、`servicePath = /sap/bc/zcrw`）。
仓库内 AFF 为规范文件（不含 CLI 信封字段），`create HTTP` 需要顶层 `name`，先生成临时副本：

```bash
mkdir -p tmp
node -e '
const fs = require("fs");
const src = JSON.parse(fs.readFileSync("src/zcrw_app.http.json", "utf8"));
fs.writeFileSync("tmp/zcrw_app.create.http.json",
  JSON.stringify({ name: "ZCRW_APP", ...src }, null, 2));
'
abap create HTTP ZCRW_APP --file tmp/zcrw_app.create.http.json --package '$CRW' \
  --description 'CRW workbench ICF node' --yes --json
```

期望：`data.action=created`；节点在 `TADIR` 中登记为 `PGMID=R3TR / OBJECT=SICF / OBJ_NAME=ZCRW…`（只读核对：`abap select --table TADIR --where "OBJ_NAME LIKE 'ZCRW%'" --json`，其中含 `SICF` 行）。
失败：`VALIDATION_ERROR Missing required field: name` → 临时副本缺顶层 `name`；`HTTP_CREATE_FAILED` → handler 未激活、`servicePath` 冲突或父节点 `/sap/bc` 不存在。
节点创建后访问返回 500 `Class interface changed at runtime` → 对 handler 类再执行一次 `abap activate ZCL_CRW_HTTP_HANDLER --yes --json` 后重试（ICF 的类运行时缓存）。

安装后校验（只读，`<host>` 为运行环境的系统地址，不写入仓库）：
1. `abap run ZCL_CRW_JSON --json` → `CRW_JSON_OK`（JSON 序列化 / camelCase 自检）。
2. 浏览器登录后访问 `<host>/sap/bc/zcrw/api/v1/health` → `status=success`、`data.status=ok`、`components.icf=ok`。
3. 访问 `<host>/sap/bc/zcrw/api/v1/me` → 当前用户、角色、`admin`、`version=1.1.0`。
4. 未携带登录会话访问 `/api/v1/*` 返回 401（ICF 标准登录过程接管，响应体为登录页而非 JSON；A1/D21 实测口径）。

### 2.9 S8 事务码 `ZCRW`（参数事务，实测后回写）

入口：参数事务 `ZCRW` → 报表 `ZCRW_START` 打开 ICF 节点相对路径 `/sap/bc/zcrw`（不写主机名）。

```bash
# 1) 报表 ZCRW_START（PROG）
abap create PROG ZCRW_START --package '$CRW' --description 'CRW workbench launcher' --yes --json
abap push src/zcrw_start.prog.abap --yes --json

# 2) 事务码 ZCRW（AFF TRAN；参数事务的 URL 参数 AFF 无对应类型）
abap create TRAN ZCRW --file <TRAN AFF 文件> --package '$CRW' --description 'CRW workbench' --yes --json
```

期望：`status=success`；只读核对 `abap tcode ZCRW --json` 能解析到入口程序 `ZCRW_START`。
说明：AFF 无 URL 类型 TRAN，参数事务的跳转参数需在 SAP GUI（SE93）人工确认/补录，仅使用相对路径 `/sap/bc/zcrw`，不记录主机名；M1 实测后把 `<TRAN AFF 文件>` 与参数写法回写本节。
失败：`OBJECT_EXISTS` → `pull` 后 `push`，或删除重建；`VALIDATION_ERROR` → 检查 AFF 文件与占位符是否替换。

### 2.10 S9 创建 MIME 根 `/zcrw` 并上传前端资产

```bash
abap mime push src/mime --root /zcrw --dry-run --json   # 先预览清单（不写 SAP）
abap mime create /zcrw --package '$CRW' --description 'CRW workbench assets' --yes --json
abap mime push src/mime --root /zcrw --yes --json
```

期望：`create` 为 `data.action=created`；`push` 为 `data.uploaded=<n>`（与 `src/mime/` 文件数一致，M1 起 > 0）。
失败：`OBJECT_EXISTS` → `abap mime delete /zcrw --recursive --yes --json` 后重试；`NOT_FOUND` → 检查 `create` 是否成功。

### 2.11 S10–S12 初始化、迁移、自检

```bash
# S10 幂等初始化（写 SAP：号段区间 + 种子行）
abap run ZCL_CRW_BOOTSTRAP --json
# S11 按版本执行迁移（M4 交付后；交付前可跳过，bootstrap 已写入 1.0.0）
abap run ZCL_CRW_MIGRATION --json
# S12 只读自检
abap run ZCL_CRW_SELFCHECK --json
```

期望：
- bootstrap：`data.output` 含 `CRW_BOOTSTRAP_OK intervals=3 config=<n>`（首次安装：3 区间 + 版本/审批矩阵/角色种子；1.1.0 起种子含 `REQ/STD` 与 `CD/STD` 两条矩阵步骤和 `ADMIN` + `CHANGE_MANAGER` 角色）；再次运行为 `intervals=0 config=0`（幂等）。
- migration：`status=success`、`data.exitCode=0`；输出标记与版本号在实现时冻结并回写本节（交付前跳过）。
- selfcheck：`data.output` 含 `CRW_SELFCHECK_OK tables=13 rows=<n> intervals=3 version=<v> messages=8 roles=<n> approvals=<n> icf=OK cts=OK`（version 取最新版本行，1.1.0；ICF 检查基于 `TADIR` 的 `SICF` 行，CTS 读取失败降级为 `cts=DEGRADED`）。`CRW_SELFCHECK_FAIL` → 按输出定位缺失项（`intervals=` / `version-missing` / `icf-missing` 等），回对应安装步骤。

### 2.12 安装完成判据

- [ ] 13 张表可读（`DD02L` 13 行）
- [ ] 3 个号段对象 + 3 个区间（`TNRO` / `NRIV`）
- [ ] 2 个锁对象（`DD25L` 2 行）
- [ ] 消息类 8 条（`T100`）
- [ ] 类与接口全部 active（`inspect --activation`）
- [ ] ICF 节点 `ZCRW_APP` 存在且 handler 指向 `ZCL_CRW_HTTP_HANDLER`
- [ ] 事务码 `ZCRW` 可解析
- [ ] MIME `/zcrw` 资产可访问（页面 `/sap/bc/zcrw/` 可打开）
- [ ] `CRW_BOOTSTRAP_OK`、`CRW_SELFCHECK_OK`
- [ ] §10 只读验证清单通过

---

## 3. 静态校验与写路径

### 3.1 顺序与期望

| 阶段 | 命令 | 期望 | 写 SAP |
|---|---|---|---|
| 本地 AFF 校验 | `abap validate:aff <file-or-dir> --json` | `status=success` | 否 |
| 本地源码结构校验 | `abap check content <file>.abap --json` | `data.failure=false` | 否 |
| SAP 侧语法检查 | `abap check syntax <file>.abap --json` | `data.failure=false` | 否（语法检查不改对象） |
| 推送并激活 | `abap push <file> --yes --json` | `data.failed=0`、`data.results[0].activated=true` | 是 |
| 激活状态复核 | `abap inspect <对象> --activation --json` | `data.activation.ok=true` | 否 |

一次只推本应用文件；**禁止** `abap push --all`、`abap check --all`；JSON（DDIC / HTTP / TRAN / MSAG）用 `--file` 创建或显式路径 push，不走 `--all`。

### 3.2 错误路由

| `error.code` | 含义 | 处理 |
|---|---|---|
| `SYNTAX_ERROR` | SAP 语法检查失败 | 读 `error.details.issues[]` → 改代码 → 重跑 `check syntax` / `push` |
| `ACTIVATION_FAILED` | 写入成功但激活失败 | 读 `error.details.results[].messages[]` → 修代码 / 补前序依赖 → 重推；未激活版本可用 `inspect --activation` 确认 |
| `NO_TRANSPORT` | 对象被当作需要 transport | 确认包名为 `'$CRW'`（单引号）、CLI ≥ 2.0.0、未误传 `--tr`；`abap deploy status --json` 必须 current |
| `OBJECT_EXISTS` | 对象已存在 | `pull` + `push` 覆盖，或 `abap delete <对象> --yes --json` 后重建 |
| `OBJECT_NOT_ACTIVE` | 引用对象未激活 | `abap inspect <对象> --activation --json` 确认 → `abap activate <对象> --yes --json` → 重推 |
| `VALIDATION_ERROR` | 入参 / AFF 校验失败 | 读 `error.details`，按提示修 AFF / 命令参数 |
| `LOCK_FAILED` | SAP 锁占用 | `abap inspect <对象> --locks --json` 只读确认归属；等锁释放，不要强杀 |

---

## 4. 升级流程（同系统）

> `$CRW` 本地包不可跨系统部署；升级只针对已安装的同一系统。升级前先按 §8.1 备份。

1. **升级 CLI**：安装目标版本后 `abap --version`、`abap doctor --json` 确认环境正常（Node 24 LTS）。
2. **重部署内置 ICF 服务**：`abap deploy --yes --json`，再 `abap deploy status --json` 确认 `data.status=current`、`data.match=true`。ICF 过期时 DDIC / ICF 写路径可能失败。
3. **静态校验**：按 §3.1 对全部 AFF 与 `.abap` 文件执行 `check content` / `validate:aff`。
4. **按依赖序推送**：`ZCX_CRW_ERROR` → … → `ZCL_CRW_HTTP_HANDLER` → 运维类（顺序同 §2.7），每个对象 `check syntax` → `push` → `inspect --activation`。
5. **初始化补齐**：`abap run ZCL_CRW_BOOTSTRAP --json`（幂等，只补缺失号段区间 / 种子行）。
6. **执行迁移**：`abap run ZCL_CRW_MIGRATION --json`（只前进，幂等；版本记录写 `ZCRW_VERSION`）。
7. **自检**：`abap run ZCL_CRW_SELFCHECK --json` 期望 `CRW_SELFCHECK_OK`。
8. **更新前端资产**：`abap mime push src/mime --root /zcrw --yes --json`，期望 `data.uploaded=<n>`。
9. **版本一致性**：`abap select --table ZCRW_VERSION --fields VERSION_NO --json` 的版本与页面 `/health`（相对路径 `/sap/bc/zcrw/api/v1/health`）返回的 `components.version` 一致；`abap test ZCL_CRW_UTIL --json` 无失败。

失败处理：任一步失败即停止，不继续后续步骤；按 §11 路由；ICF 升级回退到 `abap deploy --yes` 后重跑，仍失败则按 `.agents/skills/abap-cli-setup/SKILL.md` 排查。

---

## 5. 权限与角色

### 5.1 角色编码（已冻结，W10）

| 角色 | 职责 | v1 |
|---|---|---|
| `REQUESTER` | 新建 / 编辑 / 提交 / 撤回自己的请求，查看进度 | P0 |
| `CHANGE_MANAGER` | 审批 / 驳回、指派 Owner、调整优先级与计划、关闭异常 | P0 |
| `DEVELOPER` | 接任务 / 子任务，推进 CD 开发 / 测试，关联 transport | P0 |
| `TESTER` | 执行测试、记录结论、驳回 | P0 |
| `RELEASE_MANAGER` | 维护 transport 状态、确认导入、维护导入计划 | P0 |
| `ADMIN` | 角色分配、配置、号段、初始化、迁移、审计导出 | P0 |
| `VIEWER` | 只读查看报表与请求 | P2 |

### 5.2 角色表 `ZCRW_ROLE`

| 字段 | 含义 |
|---|---|
| `USER_ID` | SAP 用户 |
| `ROLE` | 角色编码（见 §5.1） |
| `SCOPE_TYPE` | 数据范围类型：`GLOBAL` / `COMPONENT` / `CYCLE` |
| `SCOPE_ID` | 范围 ID（`GLOBAL` 时为空） |
| `VALID_FROM` / `VALID_TO` | 有效期（`DATS`） |

### 5.3 初始管理员

bootstrap 把**执行用户**写成 `ADMIN`（`SCOPE_TYPE = GLOBAL`、有效期到 `99991231`），且幂等（重复执行不重复插入）。
只读核对：

```bash
abap select --table ZCRW_ROLE \
  --fields USER_ID,ROLE,SCOPE_TYPE,SCOPE_ID,VALID_FROM,VALID_TO --json
```

期望：至少 1 行 `ROLE=ADMIN`、`SCOPE_TYPE=GLOBAL`，`USER_ID` 为当前登录用户（文档中不写具体用户名）。

### 5.4 角色与审批矩阵维护（v1 手工 / 管理配置，P2 界面）

- v1 无角色维护 UI：新增 / 调整角色与审批矩阵通过**一次性 classrun 或迁移程序**写入（ABAP 代码；abap-cli 无 insert 命令，禁止用 SE16 手工录入）。
- 审批矩阵表 `ZCRW_APPR_CFG` 字段：`PROFILE_ID` / `STEP_NO` / `APPROVER_ROLE` / `APPROVER_USER` / `OBJECT_TYPE` / `REQ_TYPE` / `PRIORITY` / `MANDATORY`；匹配字段为空 = 通配（`PRIORITY` 空 = 任意，W10）。
- 只读核对矩阵：

```bash
abap select --table ZCRW_APPR_CFG --json
```

期望：至少包含 CR/STD 步骤；M2 起含 CD/STD 1 步（`CHANGE_MANAGER`，W6）。

### 5.5 授权边界

- v1 不做 `AUTHORITY-CHECK`，依赖 SAP 登录 + 应用角色（A8）；不创建自定义 AUTH 对象（CLI 不支持，需 basis 人工配置）。
- 数据范围：请求人仅自己的请求；开发 / 测试按指派；变更经理 / 发布管理员 / 管理员全量；观察者按组件 / 周期。
- 审批额外校验：非当前步骤审批人 → `APPROVER_MISMATCH`；请求人审批自己 → `SELF_APPROVAL`。

---

## 6. 号段

### 6.1 对象与区间

| 号段对象 | 区间 | 范围 | 用途 |
|---|---|---|---|
| `ZCRW_REQ` | `01` | 1 – 9999999999 | CR 编号 |
| `ZCRW_CD` | `01` | 1 – 9999999999 | CD 编号 |
| `ZCRW_TASK` | `01` | 1 – 9999999999 | Task / SubTask 编号 |

- 年度无关（`TOYEAR = 0000`）、内部编号（`PROCIND = 'I'`）、无本地缓存（`NUMBER_GET_NEXT`）。
- 区间由 `ZCL_CRW_BOOTSTRAP` 幂等创建；号段**对象**由 §2 S3 创建。

### 6.2 只读检查

```bash
abap select --table TNRO --where "OBJECT LIKE 'ZCRW%'" --count-only --json
abap select --table NRIV --where "OBJECT LIKE 'ZCRW%'" \
  --fields OBJECT,NRRANGENR,FROMNUMBER,TONUMBER,NRLEVEL,PROCIND --json
```

期望：`TNRO` `data.count=3`；`NRIV` 3 行，`NRRANGENR='01'`、`PROCIND='I'`。

### 6.3 规则

- **不要手工重置 / 修改 `NRIV`**；区间缺失时重跑 `abap run ZCL_CRW_BOOTSTRAP --json`。
- **号段空洞正常**：回滚、取消、撤销的取号同样消耗号码，`NRLEVEL` 只增不减；报表不假设连续编号。
- 取号失败（`NUMBER_RANGE_ERROR`）先看 §11，再核对 bootstrap 与 `NRIV` 只读结果。

---

## 7. 断电 / 数据重置

### 7.1 原则

- 重置只清业务表、保留种子：清 `ZCRW_REQ` / `_CD` / `_TASK` / `_TR` / `_SCHED` / `_APPR` / `_HIST` / `_NOTE` / `_LOG`；保留 `ZCRW_VERSION` / `ZCRW_APPR_CFG` / `ZCRW_ROLE` / `NRIV` / `T100`。
- v1（当前）用 `ZCL_CRW_M1_SMOKE` 做「写 + 自动清理」端到端验证，仅限开发；M2 交付后用 `ZCL_CRW_TEST_DATA` 统一准备与清理。
- 以下命令**写 SAP（安装 / 开发步骤，非只读）**，不得放进 README 的运行验证清单。

### 7.2 使用 `ZCL_CRW_TEST_DATA`（M2 计划）

```bash
abap run ZCL_CRW_TEST_DATA --json
```

期望：`data.output` 含 `CRW_TEST_DATA_PREPARE_OK`（标记在实现时冻结并回写本节）。
清理入口以实现为准；若用 `--method clean` 且返回 `WRAPPER_INPUT_UNAVAILABLE`（本系统 ADT classrun 不支持参数注入），改用独立清理入口类并回写本节。

### 7.3 重置后验证（连续两次一致）

```bash
abap run ZCL_CRW_BOOTSTRAP --json
abap run ZCL_CRW_SELFCHECK --json
abap run ZCL_CRW_M1_SMOKE --json      # 写数据并自动清理
abap run ZCL_CRW_SELFCHECK --json
```

期望：两次 selfcheck 的 `tables=13 / intervals=3 / messages=8 / version` 一致（`rows` 与 `NRIV.NRLEVEL` 因取号推进而变化属正常）；smoke 输出 `CRW_M1_SMOKE_OK req=<n> cd=<n> task=<n> sub=<n>`，执行后业务表 0 行：

```bash
abap select --table ZCRW_REQ  --count-only --json   # 期望 count=0
abap select --table ZCRW_CD   --count-only --json
abap select --table ZCRW_TASK --count-only --json
abap select --table ZCRW_HIST --count-only --json
```

### 7.4 断电 / 异常中断恢复

- 每个写请求一个 LUW（`COMMIT WORK AND WAIT`），未提交事务由 SAP 回滚；**不需要手工清理事务**。
- 恢复后先只读核对：`abap run ZCL_CRW_SELFCHECK --json` → `abap select` 关键表 → `abap dumps --json` → `abap select --table ZCRW_LOG --json`（按 `CORRELATION_ID` 定位用户报错）。
- 若出现「状态已变但历史缺失」等半状态：保留现场（§8.1 只读导出），上报维护者；**不要手工改业务表**。

---

## 8. 回滚

### 8.1 回滚前备份（只读导出）

```bash
mkdir -p tmp/backup
for t in ZCRW_REQ ZCRW_CD ZCRW_TASK ZCRW_TR ZCRW_SCHED ZCRW_APPR ZCRW_APPR_CFG \
         ZCRW_HIST ZCRW_NOTE ZCRW_VERSION ZCRW_ROLE; do
  abap select --table "$t" --json > "tmp/backup/$t.json"
done
```

注意：备份文件含真实业务数据，只放 `tmp/`（gitignored），不入库、不提交、不截图，用完删除。

### 8.2 回滚步骤

1. **停止写入**：通知使用方暂停动作（v1 无后台作业，无队列需要停）。
2. **备份现场**：按 §8.1 导出关键表。
3. **回推上一版本代码**：从 git 取上一版本 `src/`（AFF 是唯一来源）→ §3 静态校验 → 按依赖序 `push` → `inspect --activation`。
4. **表结构**：CLI 2.0.0 没有 `ALTER`，**不支持回滚表结构**；如新版本改过表，只能删除表后按旧 AFF 重建（数据丢失，必须人工确认）。
5. **迁移只前进**：不执行 down migration；`ZCRW_VERSION` 保留已应用版本，回滚后的旧代码必须兼容新数据。
6. **重新初始化与验证**：`abap run ZCL_CRW_BOOTSTRAP --json` → `abap run ZCL_CRW_SELFCHECK --json` → `abap test ZCL_CRW_UTIL --json`；页面刷新确认版本与 `/health` 一致。

### 8.3 不可回滚项

- 业务数据（回滚不还原数据，回滚前自行备份）。
- 已释放 transport 状态（CTS 只读，不回滚、不 release）。
- 审计历史（`ZCRW_HIST` 只追加）与日志（`ZCRW_LOG` 只追加）。
- 已消耗的号段（`NRIV.NRLEVEL` 不回退）。

---

## 9. 运维边界

| 边界 | v1 行为 | 说明 |
|---|---|---|
| CTS | 只读 `E070` / `E071` / `E07T` / `TMSBUFFER`；**不 release、不执行 TMS、不创建 transport** | ToC 只记录与计划；读取失败降级为未知（D4 / D8 / W21） |
| 后台作业 | 无 | 导入计划到点 / 逾期在读取时计算（D9） |
| 邮件通知 | 无 | 站内待办 / 通知 P2 |
| 审计 | `ZCRW_HIST` 只追加、无删除入口、导出只读 | **非合规级不可篡改**：管理员仍可直接改表 |
| 日志 | `ZCRW_LOG` 只追加；带 `CORRELATION_ID` | 不记录凭证、URL、真实业务数据 |
| dump 检查 | 定期 `abap dumps --json`（只读） | 确认无 CRW 相关 ST22 dump |
| 数据保留 | v1 不删除业务行 | 归档 / 清理策略 P2；回滚前手工导出（§8.1） |
| 本地包 | `$CRW` 不可跨系统部署 | 产品化需迁移到可传输包（P2） |
| 索引 | v1 不建二级索引（CLI 无入口） | 压测后 GUI / DB02 按需建（D20） |
| 会话 | 由 SAP 控制超时 | CLI `SESSION_STORE_FALLBACK` / `SESSION_REUSE_UNSTABLE` 不影响结果 |

---

## 10. 验证清单（只读）

> 以下命令全部只读；写数据的 bootstrap / migration / smoke / test-data 属安装 / 开发步骤（§2、§7），不在此列。

| 检查项 | 命令 | 期望 |
|---|---|---|
| 自检 | `abap run ZCL_CRW_SELFCHECK --json` | `data.output` 含 `CRW_SELFCHECK_OK tables=13 rows=<n> intervals=3 version=<v> messages=8`（M2 起含 `icf=` / `cts=`） |
| 单元测试 | `abap test ZCL_CRW_UTIL --json` | 无失败（当前 4 个用例通过） |
| 表 | `abap select --table DD02L --where "TABNAME LIKE 'ZCRW%'" --count-only --json` | `data.count=13` |
| 号段对象 | `abap select --table TNRO --where "OBJECT LIKE 'ZCRW%'" --count-only --json` | `data.count=3` |
| 号段区间 | `abap select --table NRIV --where "OBJECT LIKE 'ZCRW%'" --fields OBJECT,NRRANGENR,FROMNUMBER,TONUMBER,NRLEVEL --json` | 3 行、区间 `01` |
| 消息类 | `abap select --table T100 --where "ARBGB = 'ZCRW_MSG'" --count-only --json` | `data.count=8` |
| 锁对象 | `abap select --table DD25L --where "VIEWNAME LIKE 'EZCRW%'" --count-only --json` | `data.count=2` |
| 版本 | `abap select --table ZCRW_VERSION --fields COMPONENT,VERSION_NO,APPLIED_AT --json` | 版本与 `/health` 一致 |
| ICF 节点 | `abap select --table ICFSERVICE --where "ICF_NAME = 'ZCRW_APP'" --count-only --json` | `data.count=1` |
| 事务码 | `abap tcode ZCRW --json` | 解析到入口程序 `ZCRW_START` |
| 健康端点 | 浏览器登录后 GET 相对路径 `/sap/bc/zcrw/api/v1/health` | JSON 200；返回 `status` 与 `components`（A10 枚举） |
| 页面 / hash 路由 | 浏览器打开 `/sap/bc/zcrw/`、`/sap/bc/zcrw/#/<route>`（如 `#/requests`）并刷新 | 页面正常渲染、刷新不 404（SPA fallback） |
| dump | `abap dumps --json` | 近期无 CRW 相关 dump（人工判断） |

补充：`abap run` / `abap test` 的只读性取决于被执行对象；`ZCL_CRW_M1_SMOKE` / `ZCL_CRW_TEST_DATA` / `ZCL_CRW_BOOTSTRAP` / `ZCL_CRW_MIGRATION` 会写数据，只能出现在安装 / 开发步骤。

---

## 11. 排障

| `error.code` | 处理 |
|---|---|
| `NO_TRANSPORT` | `$CRW` 应作为本地包免 transport。检查：包名是否写为 `'$CRW'`（单引号）、是否误传 `--tr`、CLI 是否 ≥ 2.0.0、`abap deploy status --json` 是否 current；仍失败按 `.agents/skills/abap-cli-setup/SKILL.md` 排查。 |
| `OBJECT_NOT_ACTIVE` | `run` / `push` 返回该码：`abap inspect <对象> --activation --json` 看 `data.activation.ok`，`abap activate <对象> --yes --json` 后重试；`inspect --activation` 本身不返回该码，用 `data.activation.ok=false` 表示未激活。 |
| `WRAPPER_NOT_DEPLOYED` | 内置 ICF 服务缺失 / 过期：`abap deploy --yes --json`，确认 `deploy status` current 后重跑原命令。 |
| `TABLE_NOT_FOUND` | 表未建或名字拼错：核对 §2 S2 的 13 张表；用 `abap select --table DD02L --where "TABNAME = '<表>'" --count-only --json` 只读确认。 |
| `NUMBER_RANGE_ERROR` | `NRIV` 区间缺失：重跑 `abap run ZCL_CRW_BOOTSTRAP --json`；再核对 §6.2；**不要手工改 `NRIV`**。 |
| `OBJECT_LOCKED` | 其他会话 / 进程持有 SAP 锁：`abap inspect <对象> --locks --json` 只读确认归属，等锁释放或联系持锁人；不要强杀进程。 |
| `CTS_READ_ERROR` | CTS 读取失败 / 无只读权限：确认 `E070` / `E071` / `E07T` / `TMSBUFFER` 只读权限；页面按降级显示（`SYNC_STATE=ERROR` / `UNKNOWN`），不阻塞 CR / CD / 任务流程；`POST /transports/sync` 返回 502。 |
| `SESSION_STORE_FALLBACK` | CLI 会话存储回退提示（WARN），**不影响命令结果**，无需处理；若同时出现 400 session timeout → 重跑原命令或 `abap session info --json` 后重试。 |

补充（非 CLI 错误码）：

- `WRAPPER_INPUT_UNAVAILABLE`：`abap run --method` 在本系统 ADT classrun 不支持参数注入 → 改用 `if_oo_adt_classrun~main` 的 `abap run <类>` 入口，或独立清理入口类。
- `SESSION_REUSE_UNSTABLE`：同 `SESSION_STORE_FALLBACK`，属会话层提示，不影响业务结果。

---

> 维护约定：architecture / workflow 冻结契约变更时同步更新本文；M1 实测后回写所有 `<...>` 占位符与本手册标注“实测后回写”的命令。
