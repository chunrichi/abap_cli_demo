# abap-cli DMA Demo 示例库 · 规划

> 状态：规划稿（2026-10-31）。
> 仓库合约（必须遵守的规则）在 [`AGENTS.md`](../AGENTS.md)；本文档负责"为什么、做什么、按什么顺序做"。
> 示例清单是路线图，不代表 demo 已创建。

## 1. 摘要

- **目标**：把"用 prompt + abap-cli 完成一个 ABAP 任务"沉淀成 12 个可复现、可阅读的 demo。
- **形态**：每个 demo 一个目录，只包含 `src/`（ABAP/AFF 代码）+ `README.md`（含原始 Prompt 与运行验证）；前端页面 demo 可加 `screenshots/`。
- **命名**：所有 SAP 对象以 `Z` 开头且包含 `DMA`（Demo ABAP），例如 `ZCL_DMA_02_HELLO`、`ZDMA_03_REPORT`。
- **不做证据体系**：不保存 `evidence/`、`meta.json`、`prompt.md`、`verify.sh`；验证结果写进 README，索引记录"最近验证"日期。
- **本期交付**：仓库合约 `AGENTS.md` + 本规划。目录骨架与 demo 实现按第 9 节路线图分期落地。
- **首个 demo**：01 icf-mime-stats（ICF + MIME 统计看板）于 2026-10-31 落地、2026-11-01 live 验证（见 `demos/01-icf-mime-stats/`）。
- **应用线（独立于 demo 编号）**：第二个旗舰项目是真实应用「变更请求工作台（CRW）」，位于 `apps/change-request-workbench/`，按 `AGENTS.md` §4A 管理；规划见 [`docs/change-request-workbench-plan.md`](change-request-workbench-plan.md)。demo 02–12 路线图保留，不受影响（D7）。
- **已完成的验证**：D02 的命令协议已于 2026-10-31 在 dev 环境 `$TMP` 实跑通过并清理（见第 11 节）。

## 2. 目标与非目标

### 2.1 目标

1. **学会**：读者/agent 能通过 README 中的 prompt 理解"一个 ABAP 任务如何用 abap-cli 端到端完成"。
2. **复现**：同一 prompt 在满足前置条件的 dev 系统上可重复执行，结果由 README 中的只读命令判定。
3. **最小目录**：每个 demo 只有 ABAP 代码与 README，降低维护成本、便于浏览与复制。
4. **可读**：README 同时服务人和 agent：场景、原始 prompt、实现说明、运行验证、截图、清理。
5. **可视化**：有前端页面的 demo 用截图证明效果。

### 2.2 非目标

- 不开发 abap-cli 工具本身（工具仓库是 `vibe_with_abap`）。
- 不做 ABAP 语言教程全集；demo 只覆盖"用 CLI 落地"的主路径。
- 不覆盖生产发布、权限设计、性能压测等真实工程全流程。
- **不建立证据/审计体系**：不记录原始 JSON 日志、不做状态机、不做新鲜度巡检。

## 3. 设计原则

| 原则 | 含义 | 落地方式 |
|---|---|---|
| prompt-first | 能跑通的是 README 里的 prompt，不是对话 | Prompt 作为 README 章节，可复制执行；偏差必须回写 |
| 目录最小化 | demo 只放代码与说明 | `README.md` + `src/` + 可选 `screenshots/`，禁止其它文件 |
| 行为契约 | prompt 定义"做什么/怎么算成功"，不贴完整实现 | `src/` 是参考实现；验收看行为断言 |
| 可重跑 | demo 必须能复位后重跑 | README 清理章节 + 连续两次验证 |
| 最小爆炸半径 | 只动自己声明的对象 | README 对象清单 + 默认 `$TMP` |
| 单一说明源 | 说明、prompt、验证命令只在 README | 不拆分 prompt/verify 文件 |
| 截图即视觉验证 | 前端页面 demo 用截图证明效果 | `screenshots/` + README 嵌入 |
| 渐进加载 | agent 不预加载全部知识 | 读 demo README → 根索引 → 目标 skill |

## 4. 库结构（规划）

```
abap_cli_demo/
├── AGENTS.md                     # 仓库合约（权威）
├── README.md                     # 库入口 + demo 索引（编号/标题/层级/对象/关键命令/最近验证）
├── docs/
│   └── demo-library-plan.md      # 本文件
├── demos/
│   ├── 01-icf-mime-stats/
│   │   ├── README.md             # 场景 + 原始 Prompt + 实现说明 + 运行验证 + 清理（+ 截图）
│   │   ├── src/                  # AFF 代码（.abap / .json）；MIME 前端资产放 src/mime/
│   │   └── screenshots/          # 可选：仅前端页面 demo
│   ├── 02-hello-class/
│   └── ...
├── scripts/
│   └── check-demos.mjs           # 可选：目录/命名/README 结构校验（M2）
├── .agents/
│   ├── skills/                   # abap-cli 生成物 + 手工同步的 abap-style（DSH 项目级技能根）
│   └── agents/abap-developer.agent.md
├── .abap.json                    # 本地连接绑定（gitignored）
├── .abapignore                   # push 扫描忽略规则
└── tmp/                          # 临时物（gitignored）
```

分层职责：

- `AGENTS.md`：规则（做什么/禁止什么/DoD）。
- `docs/`：设计与路线图（为什么/清单/计划）。
- `demos/<id>/`：可执行单元（README + 代码 + 可选截图）。
- `scripts/`：可选门禁（目录结构校验）。
- `.agents/`：CLI 领域知识生成物（随 abap-cli 升级重新生成）+ 手工同步的 `abap-style`（来自 chunrichi/abap-coding）。

## 5. Demo 契约

### 5.1 目录（严格）

```
demos/01-icf-mime-stats/
├── README.md
├── src/            # 只放 AFF 代码文件，扁平布局；MIME 前端资产放 src/mime/
└── screenshots/    # 可选，仅前端页面 demo
```

- `src/` 命名遵循 AFF：`<name>.<type>[.<sub_type>][.<content_type>].<ext>`；DDIC/CDS 的 sidecar 与主文件同目录、一并提交（`.tabl.ddic`、`.tabl.settings.json`、`.ddls.acds`、`.xslt.xml` 等）。
- MIME/ICF 前端 demo 的静态资产（HTML/CSS/JS）放 `src/mime/`，与 AFF 源码分开；`abap mime push src/mime --root <path>` 直接上传。
- HTTP/TRAN 的 AFF JSON 在 `abap create` 时需要顶层 CLI 信封字段 `name`；仓库内保留规范 AFF 文件（不含 `name`），执行时生成带 `name` 的临时副本（见 01 demo 的 S7）。
- 禁止出现 `meta.json`、`prompt.md`、`verify.sh`、`evidence/`、日志、临时文件。

### 5.2 README 章节（唯一入口）

1. 标题 + 一句话目标
2. 场景与目标
3. 原始 Prompt（可复制）
4. 实现说明（对象清单/关键设计/`src/` 文件）
5. 运行与验证（只读命令 + 期望输出）
6. 截图（可选，仅前端页面）
7. 清理（复位/删除命令）
8. 常见错误（可选）

### 5.3 命名

- 目录：`demos/<NN>-<slug>/`，`NN` 两位、不复用。
- 对象：`Z` 开头 + 含 `DMA` + 全大写 + ≤30 字符：

| 类型 | 模式 | 示例 |
|---|---|---|
| `CLAS` | `ZCL_DMA_<NN>_<ROLE>` | `ZCL_DMA_02_HELLO` |
| `INTF` | `ZIF_DMA_<NN>_<ROLE>` | `ZIF_DMA_08_GREETER` |
| `PROG` / `DDLS` | `ZDMA_<NN>_<ROLE>` | `ZDMA_03_REPORT` |
| `TABL` / `STRU` / `DOMA` / `DTEL` / `HTTP` / `TRAN` | `ZDMA_<NN>_<ROLE>` | `ZDMA_06_ORDERS` |

### 5.4 包与传输

| 层级 | package | transport | 复位方式 |
|---|---|---|---|
| basic / intermediate | `$TMP` | `none` | 删除对象后重建，可反复跑 |
| advanced | 专用包（如 `ZDMA_PKG`，需人确认） | `required` | 尽量幂等；不可复位时 README 写明 |

### 5.5 截图（仅前端页面 demo）

- 位置 `screenshots/`，PNG/JPEG，单张 ≤500KB。
- 命名 `<NN>-<slug>-<desc>.png`，如 `11-http-service-home.png`。
- 脱敏：不出现系统 URL、client、用户名、真实业务数据。
- README 相对路径嵌入；实现变更后重截。

## 6. Prompt 设计与示例

### 6.1 README 骨架模板

````markdown
# <NN> <标题>

一句话目标。

## 场景与目标

<1–3 句：把什么业务/技术逻辑落地成什么>

## 原始 Prompt

```text
<可直接复制给 agent 的完整 prompt>
```

## 实现说明

| 对象 | 类型 | 包 | 说明 |
|---|---|---|---|
| `ZCL_DMA_<NN>_<ROLE>` | CLAS | `$TMP` | <...> |

`src/` 文件：
- `src/zcl_dma_<NN>_<role>.clas.abap`

## 运行与验证

```bash
abap run ZCL_DMA_<NN>_<ROLE> --json
```

期望：`status=success`、`data.exitCode=0`、`data.output` 包含 `<标记>`。

## 截图

（仅前端页面 demo）![<说明>](screenshots/<NN>-<slug>-<desc>.png)

## 清理

```bash
abap delete ZCL_DMA_<NN>_<ROLE> --type CLAS --yes --json
abap search ZCL_DMA_<NN>_<ROLE> --type CLAS --exact --json
```

## 常见错误

| error.code | 处理 |
|---|---|
| `...` | `...` |
````

### 6.2 完整示例：D02 hello-class

> 该 README 的命令序列已于 2026-10-31 实跑验证（对象名当时为临时探针名，见第 11 节）；demo 目录尚未创建。

````markdown
# 01 Hello Class

创建并运行第一个 ABAP 类。

## 场景与目标

把一个最小业务逻辑（返回问候语）落地成全局类，并证明它在 SAP 上可执行。

## 原始 Prompt

```text
目标：在 SAP 中创建全局类 ZCL_DMA_02_HELLO，实现 if_oo_adt_classrun，
      main 输出一行包含 DMA_OK 的文本，并运行验证。

前置条件：
- 已完成 abap init，.abap.json 绑定 dev/trial profile
- abap doctor --json 全部 ok
- 不依赖 ICF、不需要 transport

实现契约：
- 对象：ZCL_DMA_02_HELLO（CLAS），包 '$TMP'
- 实现接口 if_oo_adt_classrun
- if_oo_adt_classrun~main 向 out 输出文本，必须包含 DMA_OK
- 不使用数据库、不写 transport、不修改其他对象

执行步骤：

S1 预检
- 命令：abap doctor --json
- 期望：status=success，data.environment[].status 均为 ok
- 失败：CONFIG_ERROR/AUTH_ERROR → 读 .agents/skills/abap-cli-setup/SKILL.md

S2 复位
- 命令：abap search ZCL_DMA_02_HELLO --type CLAS --exact --json
- 期望：status=success；无匹配时存在 data.hint
- 若已存在：abap delete ZCL_DMA_02_HELLO --type CLAS --yes --json

S3 创建对象
- 命令：abap create CLAS ZCL_DMA_02_HELLO --package '$TMP' --description 'DMA demo 02 hello class' --yes --json
- 期望：status=success，data.localFile=src/zcl_dma_02_hello.clas.abap
- 失败：OBJECT_EXISTS → 回 S2；VALIDATION_ERROR → 检查 --yes 是否缺失

S4 实现
- 动作：编辑 src/zcl_dma_02_hello.clas.abap，实现 if_oo_adt_classrun~main；遵循 .agents/skills/abap-style/SKILL.md 的命名/注释/格式
- 约束：非 FINAL 全局类必须有 PRIVATE SECTION 或 PROTECTED SECTION，否则 S5 出现 warning

S5 语法检查
- 命令：abap check syntax src/zcl_dma_02_hello.clas.abap --json
- 期望：status=success 且 data.failure=false
- 失败：SYNTAX_ERROR → 读 error.details.issues[] 修复后重跑 S5

S6 推送并激活
- 命令：abap push src/zcl_dma_02_hello.clas.abap --yes --json
- 期望：status=success、data.failed=0、data.results[0].activated=true
- 失败：ACTIVATION_FAILED → 读 error.details.results[0].messages[] 修复后回 S5；OBJECT_NOT_FOUND → 回 S3

S7 激活复核
- 命令：abap inspect ZCL_DMA_02_HELLO --activation --json
- 期望：data.activation.ok=true
- 失败：data.activation.ok=false → abap activate ZCL_DMA_02_HELLO --yes --json；OBJECT_NOT_FOUND → 回 S3

S8 运行验收
- 命令：abap run ZCL_DMA_02_HELLO --json
- 期望：status=success、data.exitCode=0、data.output 包含 DMA_OK

验收标准：
- S5–S8 期望全部满足
- S2–S8 连续执行两次（含复位）结果一致
- data.output 包含 DMA_OK

清理：
- abap delete ZCL_DMA_02_HELLO --type CLAS --yes --json，期望 data.deleted=true
- abap search ZCL_DMA_02_HELLO --type CLAS --exact --json，期望无匹配
- 本地 src/ 保留为参考实现，不删除
```

## 实现说明

| 对象 | 类型 | 包 | 说明 |
|---|---|---|---|
| `ZCL_DMA_02_HELLO` | CLAS | `$TMP` | 实现 `if_oo_adt_classrun`，输出问候语 |

`src/` 文件：
- `src/zcl_dma_02_hello.clas.abap`

## 运行与验证

```bash
abap run ZCL_DMA_02_HELLO --json
abap inspect ZCL_DMA_02_HELLO --activation --json
```

期望：
- `abap run`：`status=success`、`data.exitCode=0`、`data.output` 包含 `DMA_OK`
- `abap inspect`：`data.activation.ok=true`

## 截图

本 demo 无前端页面，省略。

## 清理

```bash
abap delete ZCL_DMA_02_HELLO --type CLAS --yes --json
abap search ZCL_DMA_02_HELLO --type CLAS --exact --json
```

期望：`data.deleted=true`；search 无匹配。

## 常见错误

| error.code | 处理 |
|---|---|
| `VALIDATION_ERROR` | 写命令缺 `--yes`；`$TMP` 未加单引号 |
| `OBJECT_EXISTS` | 回 S2 删除后重建 |
| `SYNTAX_ERROR` | 读 `error.details.issues[]` 修复 |
| `OBJECT_NOT_ACTIVE`（run/push） | `abap activate ... --yes` |
````

### 6.3 参考实现（D02）

`demos/02-hello-class/src/zcl_dma_02_hello.clas.abap`：

```abap
CLASS ZCL_DMA_02_HELLO DEFINITION PUBLIC.
  PUBLIC SECTION.
    INTERFACES if_oo_adt_classrun.
  PRIVATE SECTION.
ENDCLASS.

CLASS ZCL_DMA_02_HELLO IMPLEMENTATION.
  METHOD if_oo_adt_classrun~main.
    out->write( |DMA_OK: hello from abap-cli| ).
  ENDMETHOD.
ENDCLASS.
```

### 6.4 Prompt 写作反例

| 反例 | 问题 | 改法 |
|---|---|---|
| "把类改好并推上去" | 无对象名、无验收 | 写清对象、命令、`status`/字段断言 |
| 内嵌 200 行 ABAP | prompt 与实现耦合、难维护 | 行为契约 + `src/` 参考实现 |
| 用 `sleep 5` 等激活 | 不确定、不可重跑 | 用 `inspect --activation` 断言 |
| 写死 transport 号/系统 URL | 不可移植、泄密 | 运行时 `transport list/create` 获取 |
| 用 SE16 手工准备数据 | 非自动化、不可复现 | ABAP fixture classrun 准备/清理 |
| 验收写"输出正常" | 无法机器判定 | `data.output` 包含明确标记 |
| 把 prompt/验证拆成单独文件 | 目录膨胀、易漂移 | 都写进 README 对应章节 |

## 7. 示例清单（12 个）

图例：`规划` = 待实现；`协议已验证` = 命令序列实跑过，demo 未建；`已落地` = demo 已创建并 live 验证。

### 7.1 M1 · 基础闭环（`$TMP`；02/04/05 走 ADT，03 走 ICF）

> 03 的 `abap run-report` 走内置 ICF `/run/report`，不是 ADT；ICF 过期时先 `abap deploy --yes --json`。

| 编号 | 主题 | 对象 | 主要命令 | README 验收要点 | 状态 |
|---|---|---|---|---|---|
| 01 | icf-mime-stats | `ZCL_DMA_01_STATS` (CLAS) + `ZDMA_01_STATS` (HTTP) + MIME `/zdma_01_stats` + 临时清理类 `ZCL_DMA_01_STATS_CLEANUP` (CLAS) | doctor, search, create, check, push, mime create/push, run, select, delete | `abap run` 输出含 `DMA_STATS_OK`/`DMA_MIME_OK`；ICFSERVICE/ICFHANDLER 各 1 行；清理类输出 `DMA_CLEANUP_OK` | 已落地 |
| 02 | hello-class | `ZCL_DMA_02_HELLO` (CLAS) | doctor, search, create, check, push, run, inspect, delete | `abap run` 输出含 `DMA_OK`；`activation.ok=true` | 协议已验证 |
| 03 | report-list | `ZDMA_03_REPORT` (PROG) | create `--template report`, check, push, run-report, inspect, delete | `abap run-report` 的 `data.output` 含 `DMA_OK`；报表已激活 | 规划 |
| 04 | unit-test-loop | `ZCL_DMA_04_CALC` (CLAS + testclasses) | create, check, push, test, run, delete | 先红后绿：首轮 `abap test` 有失败；修复实现后全绿 | 规划 |
| 05 | syntax-fix-loop | `ZCL_DMA_05_FIX` (CLAS) | create, check syntax, push, run, delete | 首轮 `check syntax` 返回 `SYNTAX_ERROR` 且 `error.details.issues[]` 非空；修复后 `data.failure=false` + run 成功 | 规划 |

### 7.2 M2 · 数据与写路径（`$TMP`，部分依赖 ICF）

> 06/09 依赖内置 ICF 服务（TABL/DDIC 写入；`select` 也走 ICF）；M1 的 03 同样依赖 ICF。当前 dev 环境 ICF 版本落后（见第 11 节环境观察），执行前先 `abap deploy --yes --json`。

| 编号 | 主题 | 对象 | 主要命令 | README 验收要点 | 状态 |
|---|---|---|---|---|---|
| 06 | table-query | `ZDMA_06_ORDERS` (TABL) + `ZCL_DMA_06_FIXTURE` (CLAS) | deploy status, create TABL `--file`, check, push, run, select, delete | `abap select` 返回预期行数/字段；清理后 `--count-only` 为 0 | 规划 |
| 07 | pull-modify-push | `ZCL_DMA_07_GREET` (CLAS) | create, pull `--overwrite`, diff, status, check, push, run, delete | pull 后 `diff` 无差异；改实现后 `diff` 有差异；push 后 run 输出新标记 | 规划 |
| 08 | interface-impl | `ZIF_DMA_08_GREETER` (INTF) + `ZCL_DMA_08_EN` / `ZCL_DMA_08_ZH` (CLAS) | create ×3, push `--atomic`, run, test, delete | `push --atomic` 的 `data.failed=0`；运行输出两种语言 | 规划 |
| 09 | cds-view | `ZDMA_09_ORDERS` (TABL) + `ZDMA_09_CDS` (DDLS，`src/` 含 `.ddls.json` + `.ddls.acds`) + `ZCL_DMA_09_READER` (CLAS) | create TABL `--file`, push, create DDLS `--file`, push, create CLAS, check, push, run, delete（Prompt 共 10 步：S1 预检含 release 检查，S10 清理） | classrun 从 CDS 读取并输出预期行标记；**不要用 `abap select` 查 CDS**（会 `TABLE_NOT_FOUND`）；S1 捕获 `DDLS_NOT_SUPPORTED_ON_ECC`（exit 64）→ 以退出码 2 拒绝执行 | 规划 |

> 09 的 DDLS 需要 `src/` 同目录 `.ddls.json` + `.ddls.acds`；S1 捕获 `DDLS_NOT_SUPPORTED_ON_ECC`（exit 64）→ 退出码 2。

### 7.3 M3 · 真实工程与治理（advanced）

| 编号 | 主题 | 对象 | 主要命令 | README 验收要点 | 状态 |
|---|---|---|---|---|---|
| 10 | transport-workflow | `ZCL_DMA_10_TR` (CLAS) + 专用包 `ZDMA_PKG` | `transport list --open`, `transport create "DMA demo transport" --package ZDMA_PKG --yes`, create `--tr <TR>`, push `--tr <TR>`, `delete --tr <TR> --yes` | transport 创建在 `ZDMA_PKG`（不是 `$TMP`）、对象已绑定、**不 release**；执行前需人确认 | 规划 |
| 11 | atc-performance | `ZCL_DMA_11_PERF` (CLAS) | create, `check atc --variant DEFAULT`, push, run, delete | ATC 无 priority 1/2 问题；固定输入的 `data.output` 含预期标记；S1 预检 `--variant DEFAULT` 不存在 → 退出码 2；耗时对比仅 exploratory，不入验收 | 规划 |
| 12 | cleanup-audit | `ZCL_DMA_12_SCRATCH` (CLAS) | create, `search --exact`, `list --package '$TMP' --type CLAS`（辅助，断言 `truncated=false`）, where-used, delete, search | 主断言：`search ... --exact` 能找到对象、delete 后无匹配；`list` 仅辅助（默认 limit 20，需 `truncated=false`）；`lockReleased=true` | 规划 |

> 原规划 11 http-service 已由 01 icf-mime-stats 覆盖（ICF 节点 + handler + MIME 前端 + 截图），不再单列。
> D11 的耗时对比仅 exploratory，不进入验收/DoD；验收只用 ATC 问题数与固定输出标记。
> 10 的专用包 `ZDMA_PKG` 必须已存在（demo 不创建包）；不存在时由维护者按团队规范创建后再执行。

### 7.4 编号与依赖规则

- 编号按路线图分配：01 为已落地的 ICF+MIME 看板；M1 占 02–05，M2 占 06–09，M3 占 10–12。
- demo 必须自包含，不复用其他 demo 的对象；无法自包含则合并为一个 demo。
- 依赖特定 SAP release/组件的 demo（09 的 DDLS release、11 的 ATC variant）必须在 README 前置条件写明，并在 Prompt 的 S1 预检中拒绝执行（退出码 2）；ICF 节点已由 01 覆盖。

## 8. 验证与索引

### 8.1 验证方式

| 层 | 方式 | 触发 | 允许写 SAP |
|---|---|---|---|
| 静态 | `abap check content`（`.abap`）/ `abap validate:aff`（JSON）；可选 `node scripts/check-demos.mjs` | 提交前 / PR | 否 |
| 运行 | README "运行与验证"中的只读命令 | 合并前 / 变更后 | 否 |
| 视觉 | `screenshots/`（仅前端页面 demo） | 页面变更后 | 否 |

- 不保存证据文件；README 的"运行与验证"就是验证记录。
- 合并前必须实际跑通一次；没有跑通不得写"已验证"。
- 可重跑 demo 连续两次（含复位）结果一致。

### 8.2 根 README 索引

`编号 | 标题 | 层级 | 对象 | 关键命令 | 最近验证`

- 新增/变更 demo 同一 commit 更新；"最近验证"填实际跑通日期。

### 8.3 `scripts/check-demos.mjs`（可选）

检查项：

1. `demos/<NN>-<slug>/` 命名合法、编号唯一。
2. 目录只含 `README.md` / `src/` / `screenshots/`（可选）；发现其它文件报错。
3. `src/` 非空；文件扩展名符合 AFF（`.abap` / `.json` 等）。
4. README 含必需章节（场景与目标 / 原始 Prompt / 实现说明 / 运行与验证 / 清理）。
5. 对象名匹配 `Z` 开头且含 `DMA`（从 README 的"实现说明"表格与 `src/` 文件名提取）。
6. 根 README 索引与 demo 目录一致。
7. 高风险模式扫描：`push --all` / `check --all` / `https?://` / `password` / 凭证字段；`.abap.json` 只扫描其内容是否被提交（文件本身由 `.gitignore` 排除），不因 README 合法提及文件名而报错。
8. 输出 `--json` 摘要，退出码 `0/1`。

### 8.4 CI（可选，M3）

- PR 流水线：只跑静态检查（无需 SAP 凭证）。
- live 验证：需要 SAP 凭证，跑在自托管 runner 上；只跑 `$TMP` demo，不打印连接信息。
- 不做证据归档与新鲜度巡检（按"不要证据文件"的要求）。

## 9. 路线图

### M1 · 骨架与基础闭环

- [x] 仓库初始化：`git init` + `.gitignore` + `.abapignore`
- [x] 根 `README.md`（库入口 + 索引表 + 快速开始）
- [x] demo 01：ICF + MIME 统计看板（2026-10-31 落地、2026-11-01 验证，`demos/01-icf-mime-stats/`）
- [ ] demo 02–05（`$TMP`，README 含 Prompt 与运行验证）
- [ ] 可选：`scripts/check-demos.mjs` 初版

**DoD**：01–05 目录合规（README + src）、live 跑通、根索引更新、连续两次重跑一致。

### M2 · 数据与写路径

- [ ] demo 06–09（含 TABL/DDLS/ICF 依赖）
- [ ] `scripts/check-demos.mjs` 完整检查项
- [ ] PR 静态检查流水线（可选）

**DoD**：06–09 live 跑通；ICF 前置检查写进 README Prompt；静态检查通过。

### M3 · 真实工程与治理

- [ ] demo 10–12（transport / ATC / cleanup）
- [x] 前端页面 demo 截图（01 已落地，`screenshots/`）
- [ ] 可选 live 流水线

**DoD**：10–12 live 跑通；截图脱敏且与实现一致；根索引完整。

## 10. 风险与对策

| 风险 | 影响 | 对策 |
|---|---|---|
| README 的 Prompt 与实际实现漂移 | 不可复现 | 执行偏差回写 README；连续两次验证；`check-demos` 校验章节 |
| 没有证据文件/自动化验证 | 合并时可能漏跑 | 合并前必须 live 跑通；根索引记录"最近验证"日期；DoD checklist |
| 截图过期或含敏感信息 | 误导/泄密 | 实现变更后重截；截图前脱敏；单张 ≤500KB |
| `$TMP` 对象在同一 client 内共享，可能与他人重名 | 冲突/误删 | 强制 `DMA` 命名；复位前 `search` 确认；只删 README 声明对象 |
| SAP release/组件差异（CDS、ATC、textpool） | 部分系统失败 | README 前置条件写明 release；S1 预检拒绝执行 |
| ICF 未部署或版本过期 | DDIC/select/run-report 失败 | S1 `abap deploy status --json`；过期则 `abap deploy --yes --json` |
| 网络/会话抖动导致偶发失败 | 误判 | 单命令 ≤60s；同一失败最多重试 2 次 |
| 演示对象残留污染 dev 系统 | 环境变脏 | README 清理章节 + `search` 复核；D12 审计 |
| agent 上下文膨胀 | 成本高、易跑偏 | 读 README → 根索引 → 按需 skill；不预加载 demo 全集 |
| CI 凭证泄漏 | 安全事故 | 只用自托管 runner + secret；日志禁打印；`.abap.json` 不入库 |

## 11. 协议验证记录（2026-10-31，文档记录，不是证据文件）

环境：`abap --version` = 1.1.0；dev profile（`.abap.json` 绑定）；对象全部在 `$TMP`，验证后已删除。
说明：探针对象当时命名为 `ZCL_DEMO_PROBE`（历史命名，最终约定为 `Z*DMA*`）。

| # | 命令 | 退出码 | 关键结果 |
|---|---|---|---|
| 1 | `abap search ZCL_DEMO_PROBE --type CLAS --exact --json` | 0 | 无匹配，`data.hint` 存在 |
| 2 | `abap create CLAS ZCL_DEMO_PROBE --package '$TMP' --description '...' --json` | 7 | 缺 `--yes` 报 `VALIDATION_ERROR`（错误信封在 stderr） |
| 3 | 同上 + `--yes --json` | 0 | `data.localFile=src/zcl_demo_probe.clas.abap`、`activated=true` |
| 4 | `abap check syntax src/zcl_demo_probe.clas.abap --json` | 0 | `data.failure=false`；非 final 类缺 `PRIVATE SECTION` 时有 warning |
| 5 | `abap push src/zcl_demo_probe.clas.abap --yes --json` | 0 | `data.results[0].status=activated`、`data.failed=0` |
| 6 | `abap run ZCL_DEMO_PROBE --json` | 0 | `data.output="DEMO_OK: hello from abap-cli"`、`data.exitCode=0`、`data.route=classrun` |
| 7 | `abap inspect ZCL_DEMO_PROBE --activation --json` | 0 | `data.activation.ok=true`、`hasPendingInactiveVersion=false` |
| 8 | `abap delete ZCL_DEMO_PROBE --type CLAS --yes --json` | 0 | `data.deleted=true`、`lockReleased=true` |
| 9 | 再次 `abap search ...` | 0 | 无匹配（清理完成） |

补充验证（05 syntax-fix-loop 预演）：

| # | 命令 | 退出码 | 关键结果 |
|---|---|---|---|
| 10 | `abap check syntax`（已存在对象 + 本地语法错误） | 7 | `error.code=SYNTAX_ERROR`，问题在 `error.details.issues[]` |
| 11 | `abap push`（同上错误源码） | 7 | `error.code=ACTIVATION_FAILED`，`error.details.results[].written=true, activated=false` |
| 12 | `abap inspect --activation`（失败 push 后） | 0 | `data.activation.ok=false`、`hasPendingInactiveVersion=true` |
| 13 | `abap delete ... --yes` | 0 | `data.deleted=true`、`lockReleased=true` |

得到的协议约束（已写入 `AGENTS.md`）：

1. 写命令在非 TTY 下必须 `--yes`，否则 `VALIDATION_ERROR`（exit 7），错误信封在 **stderr**。
2. shell 中 `$TMP` 必须单引号 `'$TMP'`，否则被展开为空串。
3. `create` 默认自动 `pull` 到 `src/<name>.clas.abap`，随后编辑该文件。
4. `check syntax` 的 warning 不影响 `data.failure`；激活前最好消除（非 final 类需要 `PRIVATE SECTION`）。
5. `check syntax` 失败：exit 7、stdout 为空、问题在 `error.details.issues[]`；对不存在的对象报 `OBJECT_NOT_FOUND`，所以 syntax-fix-loop（05）必须先 `create`。
6. `push` 失败：`error.code=ACTIVATION_FAILED`，问题在 `error.details.results[].messages[]`；源码已写入但未激活。
7. `abap run` 的 `data.output` 是验收 stdout 的稳定字段；`data.exitCode` 是 ABAP 侧退出码。
8. 失败 push 后 `inspect --activation` 返回 `activation.ok=false`、`hasPendingInactiveVersion=true`；修复后重推或 `delete` 重建。
9. 本机 stderr 可能出现 session jar 的 `WARN`（HOME 不可写时回退 TMP）；**只解析 stdout 的 JSON**。

环境观察（2026-10-31，dev 环境）：

- `abap deploy status --json` 返回 `data.status=outdated`（`remoteVersion=1.0.0`，`expectedVersion=1.1.0`，warning `ICF_OUTDATED_DEADLOCK`）。M1 的 03 与 M2 的 06/09 依赖 ICF；01 的 MIME/HTTP 写路径已在 1.0.0 上实测可用，未升级内置服务。依赖 `run-report`/`select` 的 demo 若 `deploy status` 报 outdated，再按需 `abap deploy --yes --json`（会写入 `$TMP`，执行前需确认）。

## 12. 开放问题

1. 是否需要 `scripts/check-demos.mjs`？还是仅靠人工 DoD？
2. 根 README 索引的"最近验证"日期是否维护，还是完全不记录时间？
3. ~~前端页面 demo 用哪种形态~~ 已由 01 落地：MIME 静态资源（HTML/CSS/JS）+ ICF handler 提供 JSON；截图 2 张（30 天 / 7 天视图）。
4. advanced demo 的专用包用哪个（`ZDMA_PKG`？是否已有可用开发包）？transport 演示是否需要真实 release 流程（当前明确不 release）。
5. 是否维护英文版 README（对外分享时）？
6. DSH 与 Copilot 两套 agent 布局：当前采用 `.agents/`（DSH 项目级技能根），是否需要同时支持 `.github/`（Copilot）？
7. 是否需要 README 模板生成器（`scripts/new-demo.mjs`）？
8. D03（report-list）是否升级为带 selection screen / ALV 的报表，还是保持最小可验证？
9. 是否引入"demo 组合"（如 06+09 组成一个业务场景）作为进阶内容？
10. `abap-style` 的同步方式：继续手工复制，还是改为 git submodule / 脚本拉取（避免与上游漂移）？
