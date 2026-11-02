# AGENTS.md — abap-cli DMA Demo 示例库

> 本文件是仓库级合约，DSH / Copilot 等 coding agent 启动时自动加载。
> CLI 领域知识不在这里：先读 [`abap-cli` 路由 skill](.agents/skills/abap-cli/SKILL.md)，命中唯一目标后再加载对应领域 skill。
> 库结构、示例清单、路线图见 [`docs/demo-library-plan.md`](docs/demo-library-plan.md)。

## TL;DR（给 agent 的 9 条）

1. 一个 demo = `src/`（ABAP/AFF 代码）+ `README.md`（含原始 Prompt 与运行验证）；前端页面 demo 可加 `screenshots/`，目录里不放其它文件。
2. 对象名以 `Z` 开头、包含 `DMA`（Demo ABAP），默认 `$TMP` 包。
3. 所有 `abap` 命令 `--json`：成功读 stdout 的 `status`/`data`，失败读 stderr 的 `error.code`。
4. 非交互：写命令带 `--yes`；shell 里 `'$TMP'` 必须单引号。
5. 写 SAP 顺序：`check syntax` → `push` → `inspect --activation` / `run` / `test`；README 里的验证命令只读。
6. 不提交 `.abap.json`、凭证、内网地址、真实业务数据；截图必须脱敏。
7. Prompt 写在 README 的"原始 Prompt"章节，必须可复制执行；实际执行与 prompt 不一致时先改 README。
8. 不碰生产、不 `push --all`、不包级批量删除、不 release transport。
9. 应用型项目在 `apps/`，按 §4A 契约：产品前缀命名（如 `ZCRW_*`），不用 `DMA`/编号；包与写路径限制见 §4A.3。

## 原则

1.删掉多余的标语、说明文字和次要标签。如果删完界面就看不懂，说明布局本身就有问题，直接重新设计。 
2.每次修改都要兼顾用户体验， 开发体验和 AI Agent 的使用体验。三个都要变好，而且不能破坏现有功能。

## 1. 项目定位

本仓库是 **prompt-first 的 ABAP demo 示例库**：每个 demo 用 README 中的 prompt 驱动 agent 调用 `abap` CLI，在 SAP 系统里落地 ABAP 对象，并把可运行代码与说明留在同一个目录。

仓库同时容纳**应用型项目**（`apps/`，真实应用，见 §4A）；应用不是 demo，不参与 demo 编号，也不套用 demo 的目录最小化与 `DMA` 命名。

三句话：

- **prompt 是事实源**：能跑通的是 README 里的 prompt，不是某次对话。
- **目录最小化**：demo 目录只放 ABAP 代码、README，以及前端页面 demo 的截图。
- **README 是唯一入口**：人读说明、agent 执行 prompt、运行验证命令都在 README。

非目标：不做 abap-cli 工具本身的开发；不做 ABAP 教程全集；不覆盖生产发布流程。

## 2. 不可协商的规则

1. **对象边界**：只操作本 demo 使用的对象；其他 SAP 对象只读。
2. **命名**：对象名以 `Z` 开头且包含 `DMA`，按 §4.3 的模式；demo 编号不复用。
3. **目录最小化**：demo 目录只允许 `README.md`、`src/`、可选 `screenshots/`；禁止 `meta.json`、`prompt.md`、`verify.sh`、`evidence/`、日志等额外文件。
4. **默认 `$TMP`**：basic / intermediate demo 一律 `$TMP`，免 transport、可删除重建；非 `$TMP` 写操作必须先获得人确认。
5. **JSON 契约**：所有命令 `--json`；成功解析 stdout 的 `status` 与 `data`，失败解析 stderr 的 `error.code`；stderr 里的 `WARN` 行不代表失败。
6. **非交互**：写命令必须 `--yes`；`$TMP` 必须写成 `'$TMP'`；README 中不得出现需要 TTY 输入的命令。
7. **写路径顺序**：`check syntax` → `push` → `inspect --activation`（或 `run`/`test` 验证）；不允许跳过检查直接 push。
8. **验证只读**：README 的"运行与验证"只允许只读命令（白名单见 §7.2）；出现写命令视为违规。
9. **脱敏**：不提交 `.abap.json`、`.env`、凭证、内网地址、SAP 用户名、transport 号、真实业务数据；截图按 §4.5 处理。
10. **不碰生产**：只连接 dev / sandbox / trial 环境；无法确认环境时先问人。
11. **禁止批量操作**：不 `push --all` / `check --all`，不按包批量删除，不 release transport。
12. **不静默偏差**：实际执行与 README 的 prompt 不一致时，回写 README（必要时 `src/`），重新验证。
13. **应用单元例外**：`apps/` 项目按 §4A 执行；本节规则 2/3/4 中关于 `DMA` 命名、demo 目录最小化、`$TMP` 默认包的条款不适用，但脱敏、不碰生产、禁止批量/release、JSON 契约、写路径顺序仍然适用。

## 3. 仓库布局

```
abap_cli_demo/
├── AGENTS.md                  # 本文件：仓库合约（手写，权威）
├── README.md                  # 库入口 + demo 索引（编号/标题/层级/对象/最近验证）
├── CONTRIBUTING.md            # 协作规则：提交/分支/PR/tag/敏感扫描
├── LICENSE                    # MIT
├── NOTICE                     # 第三方内容与生成物署名
├── .gitattributes             # 换行与 linguist 规则
├── .github/                   # PR / issue 模板
├── docs/
│   ├── demo-library-plan.md   # demo 线：结构、示例清单、路线图
│   ├── change-request-workbench-plan.md  # 应用线：CRW 规划
│   ├── github-workflow.md     # GitHub 决策记录（D1–D13）与发布流程
│   ├── handoff-github-publish.md  # 已完成：GitHub 发布任务存档
│   └── handoff-next-session.md    # 下一阶段交接（M6 审批/产品化 + basis 落地）
├── demos/
│   ├── 01-icf-mime-stats/
│   │   ├── README.md          # 场景 + 原始 Prompt + 实现说明 + 运行验证（+ 截图）
│   │   ├── src/               # AFF 代码，扁平布局；MIME 前端资产放 src/mime/
│   │   └── screenshots/       # 可选：仅前端页面 demo
│   └── <NN>-<slug>/
├── apps/
│   └── change-request-workbench/  # 应用型项目（非 demo）：README + docs + src + src/mime + screenshots
├── scripts/
│   ├── check-demos.mjs        # 可选：目录/命名/README 结构校验（M2）
│   └── check-secrets.sh       # push/PR 前本地敏感扫描
├── .agents/
│   ├── skills/                # abap-cli 生成物 + 手工同步的 abap-style（DSH 项目级技能根）
│   └── agents/abap-developer.agent.md
├── .abap.json                 # 本地连接绑定（gitignored，不入库）
├── .abapignore                # push 扫描忽略规则（入库）
├── .gitignore                 # 本地文件排除（入库）
└── tmp/                       # 临时物（gitignored）
```

- `.agents/skills/` 与 `.agents/agents/` 是 `abap init --agent generic` 的**生成物**：不要手改；升级时用 `abap init --agent generic --force` 重新生成并单独 review 差异。生成物内部的相对链接按上游仓库布局书写，在本库中可能不可解析——以本文件与实际路径为准。
- `.agents/skills/abap-style/` 来自 [`chunrichi/abap-coding`](https://github.com/chunrichi/abap-coding/tree/main/skills/abap-style)（当前 v1.0.7），**手工同步**，不随 `abap init` 更新；升级时重新拉取并 review。
- 入库范围：`AGENTS.md`、`README.md`、`CONTRIBUTING.md`、`LICENSE`、`NOTICE`、`docs/`、`demos/`、`apps/`、`scripts/`、`.github/`、`.agents/`（生成物 + 手工同步的 `abap-style`）、`.abapignore`、`.gitattributes`、`.gitignore`；`.abap.json`、`tmp/`、`.env`、`node_modules/`、日志等按 `.gitignore` 排除。

## 4. Demo 单元契约

### 4.1 目录（严格）

```
demos/01-icf-mime-stats/
├── README.md
├── src/            # 只放 AFF 代码文件（.abap / .json 等），扁平布局
├── src/mime/       # 可选：MIME 前端资产（HTML/CSS/JS）
└── screenshots/    # 可选，仅前端页面 demo
```

- `src/` 采用 abap-file-format 原生扁平布局：`<name>.<type>[.<sub_type>][.<content_type>].<ext>`，例如 `zcl_dma_02_hello.clas.abap`、`zdma_06_orders.tabl.json`。DDIC/CDS 的 sidecar 与主文件同目录、一并提交：`.tabl.ddic`、`.tabl.settings.json`、`.ddls.acds`、`.xslt.xml` 等。
- MIME/ICF 前端 demo 的静态资产（HTML/CSS/JS）放 `src/mime/`，与 AFF 源码分开；`abap mime push src/mime --root <path>` 直接上传。
- HTTP/TRAN 的 AFF JSON 在 `abap create` 时需要顶层 CLI 信封字段 `name`；仓库内保留规范 AFF 文件（不含 `name`），执行时生成带 `name` 的临时副本（见 01 demo 的 S7）。
- demo 目录中不得出现 `meta.json`、`prompt.md`、`verify.sh`、`evidence/`、日志、临时文件；prompt 与验证都写进 README。

### 4.2 README 结构（唯一入口）

按顺序包含：

1. **标题 + 一句话目标**
2. **场景与目标** — 1–3 句：把什么业务/技术逻辑落地成什么
3. **原始 Prompt** — 可直接复制给 agent 的完整 prompt（§5）
4. **实现说明** — 对象清单（名称/类型/包）、关键设计、`src/` 文件说明
5. **运行与验证** — 只读命令 + 期望输出（§7）
6. **截图**（可选）— 仅前端页面 demo，放 `screenshots/`
7. **清理** — 复位/删除命令（可重跑 demo 必填）
8. **常见错误**（可选）— 本 demo 会遇到的 `error.code` 与处理

### 4.3 命名

- **目录**：`demos/<NN>-<slug>/`；`NN` 两位数字、不复用；`slug` 为 kebab-case ASCII。
- **对象名**：以 `Z` 开头、包含 `DMA`、全大写、≤30 字符：

| 类型 | 模式 | 示例 |
|---|---|---|
| `CLAS` | `ZCL_DMA_<NN>_<ROLE>` | `ZCL_DMA_02_HELLO` |
| `INTF` | `ZIF_DMA_<NN>_<ROLE>` | `ZIF_DMA_08_GREETER` |
| `PROG` / `DDLS` | `ZDMA_<NN>_<ROLE>` | `ZDMA_03_REPORT` |
| `TABL` / `STRU` / `DOMA` / `DTEL` / `HTTP` / `TRAN` | `ZDMA_<NN>_<ROLE>` | `ZDMA_06_ORDERS` |

- 编号废弃后保留目录并说明，不复用编号。

### 4.4 包与传输策略

| 层级 | package | transport | 复位方式 |
|---|---|---|---|
| basic / intermediate | `$TMP` | `none` | 删除对象后重建，可反复跑 |
| advanced | 专用包（如 `ZDMA_PKG`，需人确认） | `required` | 尽量幂等；不可复位时在 README 写明 |

- demo 必须**显式传参**（`--package` / `--tr`），不得依赖 `.abap.json` 的默认值。
- transport 号由 `abap transport create/list --json` 运行时取得，不得硬编码到 README。

### 4.5 截图（仅前端页面 demo）

- 位置：`screenshots/`；格式 PNG/JPEG；单张 ≤500KB。
- 命名：`<NN>-<slug>-<desc>.png`，例如 `01-icf-mime-stats-dashboard.png`。
- 必须脱敏：不出现系统 URL、client、用户名、真实业务数据。
- README 用相对路径嵌入，例如：`![看板](screenshots/01-icf-mime-stats-dashboard.png)`。
- 实现变更后重新截图；截图必须与当前 `src/` 行为一致。

## 4A. 应用单元契约（apps/）

> 适用于 `apps/` 下的真实应用（非 demo）。与 §4 的 demo 契约冲突时，以本节为准；§2 的脱敏、不碰生产、禁止批量操作/release、JSON 契约、写路径顺序仍然适用。

### 4A.1 目录

```
apps/<slug>/
├── README.md        # 产品说明、状态、安装、验证、截图索引
├── docs/            # 允许：architecture.md / workflow.md / runbook.md
├── src/             # AFF 扁平布局（DDIC/CLAS/INTF/HTTP/TRAN/NROB/ENQU/MSAG + testclasses sidecar）
├── src/mime/        # 前端资产
└── screenshots/     # 主页面截图（脱敏）
```

- 应用单元允许 `docs/`；demo 不允许。
- 所有 `abap create/pull` 在应用目录内执行，拉取文件落到本应用 `src/`，不得污染仓库根目录。
- 前端零依赖、原生 ES modules；不提交构建产物。

### 4A.2 命名

- 目录：`apps/<kebab-case-slug>/`，无编号、无 demo 字样。
- 对象：产品前缀（当前 `CRW`）：`ZCRW_*` / `ZCL_CRW_*` / `ZIF_CRW_*` / `ZCX_CRW_*`；全大写、≤30 字符、不含 `DMA`。

### 4A.3 包与写路径

- 包：`$CRW`（本地包；super package `$TMP`，无 transport）。
- **本地包写路径**：abap-cli 2.0.0 起原生支持 `$` 前缀本地包免 transport（create / push / delete / deploy + ICF 服务端，见规划文档附录 B.3）。升级 CLI 后先 `abap deploy --yes` 并确认 `deploy status` current；ICF 未匹配时 DDIC/ICF 写路径可能失败。
- 本地包不可跨系统部署；应用 README/runbook 必须写明。
- 写 SAP 顺序：`check content` / `validate:aff` → `check syntax` → `push` → `inspect --activation` / `run` / `test`；一次只写本应用对象。

### 4A.4 验证与 DoD

- 静态：`abap check content` / `abap validate:aff`。
- 单元测试：`abap test`。
- 运行自检：`abap run <SELFCHECK> --json`，输出含固定标记。
- 数据断言：只读 `abap select`。
- UI：`screenshots/` 主页面截图，脱敏且与实现一致。
- 文档：README + `docs/architecture.md` + `docs/workflow.md` + `docs/runbook.md`。
- 可重跑：数据 reset classrun；连续两次一致。

DoD checklist：

- [ ] 目录符合 §4A.1
- [ ] 命名符合 §4A.2
- [ ] 自检/单测/只读断言通过
- [ ] 截图脱敏
- [ ] runbook 可安装/升级
- [ ] 无 URL/凭证/真实业务数据

## 5. Prompt 规范

### 5.1 位置与形态

Prompt 是 README 的"原始 Prompt"章节中的一段可复制文本（建议用 fenced code block），**不是单独文件**；目录里不允许 `prompt.md`。

### 5.2 必需内容

1. **目标**
2. **前置条件** — profile、包、ICF 部署状态、依赖 demo
3. **实现契约** — 对象名/类型、接口/方法签名、输出标记、行为要求
4. **执行步骤** — `S1..Sn`，每步四要素（§5.3）
5. **验收标准** — 只读、可机器判定
6. **清理** — 可重跑 demo 必填

### 5.3 每步四要素

```markdown
### S6 推送并激活
- 目的：把本地实现写到 SAP 并激活
- 命令：`abap push src/zcl_dma_02_hello.clas.abap --yes --json`
- 期望：`status=success`、`data.failed=0`、`data.results[0].activated=true`
- 失败：`ACTIVATION_FAILED` → 读 `error.details.results[0].messages[]` 修复后重跑 S5
```

### 5.4 质量门槛（缺一不可）

- **自包含**：新 agent 只读本文件 + demo README + 路由到的 skill 即可执行。
- **确定性**：不依赖时间、随机数、手工 GUI；需要数据时用 ABAP 代码准备（`if_oo_adt_classrun~main` 或 `abap run --method`，后者需 wrapper 已部署），不用 SE16 手工录入。
- **有界**：≤10 步、≤5 个对象、≤10 分钟；超出则拆成多个 demo。
- **可重跑**：先复位再执行；连续两次（含复位）结果一致。
- **非交互**：无 TTY 提示、无 `read`/`sleep`/`vi`。
- **安全**：不含 URL、账号、密码、transport 号。
- **语言**：正文中文；命令、对象名、字段名、ABAP 源码保持 ASCII。

### 5.5 prompt 不做什么

- 不内嵌完整 ABAP 实现（`src/` 是参考实现，prompt 只定义行为契约）。
- 不写"视情况而定""可选"步骤；分支必须由明确的 `error.code` 或 JSON 字段触发。
- 不复制 skill 里的大段命令速查；用链接指向 `.agents/skills/`。

## 6. Agent 执行协议

```
[0 读取] 读 demo README（场景 + 原始 Prompt + 运行验证）；需要时读根 README 索引与目标 skill
[1 预检] abap doctor --json；abap init --show-config --json；确认 system=dev/trial
         依赖 ICF 的 demo：abap deploy status --json（过期则 abap deploy --yes --json）
[2 复位] abap search <obj> --type <type> --exact --json；存在则 abap delete <obj> --type <type> --yes --json
[3 执行] 按 README 的 Prompt 步骤 S1..Sn；写/改 ABAP 源码前先加载 `.agents/skills/abap-style/SKILL.md`；每步校验 status 与关键 data 字段
[4 纠错] 按 error.code 路由到对应 skill；同一命令最多重试 2 次
[5 验证] 按 README "运行与验证"执行只读命令；前端页面 demo 核对截图
[6 回写] 有偏差 → 更新 README（prompt / 验证命令）；实现变更 → 更新 src 与截图
[7 清理] 按 README 清理；search 确认对象不存在
[8 汇报] 命令清单 + 验证结果 + 与 README 的偏差
```

- **偏差处理**：任何偏离 README prompt 的有效做法，必须在同一次改动中回写 README（必要时同步 `src/`），否则下次执行不可复现。
- **卡死处理**：同一错误重试 2 次仍无进展 → 停止，执行 `abap report-stuck --goal ... --tried ... --where ... --json` 留痕并汇报，不反复试错。
- **失败恢复**：`push` 失败会留下未激活版本（`error.details.results[].written=true, activated=false`）；先 `inspect --activation` 确认，修复后重推；无法修复时 `delete` 重建。
- **demo 独立性**：demo 必须自包含，不复用其他 demo 的对象；无法自包含则合并为一个 demo。

### 常见错误路由（先看，再按 skill 修复）

| `error.code` | 先看 | 动作 |
|---|---|---|
| `NO_TRANSPORT` | `abap-cli-setup` | `transport list` → `transport create` → `--tr` 重试 |
| `LOCK_FAILED` | 人工 | `inspect --locks` 只查 transport 归属，不是编辑器锁；用 SM12/SE11 查并释放编辑器锁 |
| `OBJECT_EXISTS` | 本文件 §6 复位 | 回 S2 删除重建；或改用 `pull` + `push` |
| `SYNTAX_ERROR` / `ACTIVATION_FAILED` | `abap-cli-edit` | 读 `error.details.issues[]`（check syntax）或 `error.details.results[].messages[]`（push）修复后重跑 |
| `OBJECT_NOT_ACTIVE` | `abap-cli-edit` | `abap activate <obj> --yes --json` |
| `WRAPPER_NOT_DEPLOYED` | `abap-cli-setup` | `abap deploy --yes --json` |
| `TABLE_NOT_FOUND` / `OBJECT_NOT_FOUND` | `abap-cli-search` | `abap search <name> --json` 校对 |
| `AUTH_ERROR` / `TLS_ERROR` / `CONFIG_ERROR` | `abap-cli-setup` | `abap profile test`；`abap init` 重写配置 |

完整错误恢复表见 `.agents/agents/abap-developer.agent.md`，但生成代理的错误字段可能滞后：**字段契约以本文件 §6 表为准**。命令细节见对应 skill 的 `references/`。

补充：`OBJECT_NOT_ACTIVE` 由 `run`/`push` 等命令返回；`inspect --activation` 不报该错误，它用 `data.activation.ok=false` 表示未激活。

## 7. 验证与文档

### 7.1 验证方式

| 层 | 方式 | 时机 | 允许写 SAP |
|---|---|---|---|
| 静态 | `scripts/check-demos.mjs`（可选）+ `abap check content` / `abap validate:aff` | 提交前 / CI | 否 |
| 运行 | README 的"运行与验证"命令（只读） | 合并前 / 变更后 | 否 |
| 视觉 | `screenshots/`（仅前端页面 demo） | 页面变更后 | 否 |
| 应用 | `abap test` + 自检 classrun + 只读 `select` + `screenshots/` | 里程碑 / 发布前 | 否 |

- 本仓库**不保存证据文件**：验证结果体现在 README 的"运行与验证"章节，并在根 README 索引记录"最近验证"日期（可选）。
- 合并前必须实际跑通一次；没有跑通不得写"已验证"。
- 可重跑 demo 连续两次（含复位）结果一致。
- 应用项目按 §4A.4 验证；HTTP URL 不写入仓库。

### 7.2 只读命令白名单

- `search`、`inspect`、`status`、`diff`、`run`、`run-report`、`select`、`test`、`fields`、`list`、`where-used`、`tcode`、`types`。
- 断言基于 `--json` 字段（`status`、`data.*`）；`run` 的 `data.output` 需明确写出预期标记；`run-report` 的机器输出也在 `data.output`，`run` 的业务退出码在 `data.exitCode`。
- `run` / `run-report` / `test` 的"只读"取决于被执行对象：验证步骤**不得**调用 fixture/seed 类（它们会写数据）；需要数据断言时只用 `select`/`fields`。
- `abap select` 只支持透明表/视图（DD02L `TRANSC`/`VIEW`），**不支持 CDS 视图**（会 `TABLE_NOT_FOUND`）；CDS 内容用 `abap run`（classrun 里 `SELECT`）验证。

### 7.3 根 README 索引

`编号 | 标题 | 层级 | 对象 | 关键命令 | 最近验证`

- 新增/变更 demo 必须在同一 commit 更新索引；"最近验证"填实际跑通的日期，不填计划日期。

## 8. 安全边界

| 允许 | 禁止 |
|---|---|
| 在 dev/trial 系统创建/推送/运行本 demo 声明的对象 | 生产系统任何写操作 |
| `$TMP` 对象删除后重建 | 删除/修改非 demo 对象 |
| `abap deploy --yes`（ICF 过期时） | 包级批量删除、`push --all`、release transport |
| 只读查询任意表/对象（不写入仓库） | 把真实业务数据写进仓库、README 或截图 |
| 用 ABAP fixture 代码准备/清理测试数据 | 用 SE16/SE37 等 GUI 手工步骤替代 prompt |

- **爆炸半径**：一次 demo 运行只允许影响本 demo 的对象。
- **数据夹具**：abap-cli 没有 insert 命令；测试数据必须由 ABAP 代码（classrun main 或 `run --method`）准备和清理。
- **重试**：同一失败最多 2 次；无进展就停，用 `report-stuck` 留痕。
- **环境识别**：`.abap.json` 的 `system` 字段与 profile 命名共同判断；无法确认时先问人。

## 9. 文档与语言

- **语言**：中文为主；命令、代码、JSON 字段、对象名保持英文/ASCII；ABAP 源码注释用英文（避免 codepage 问题）。
- **README（人读 + agent 执行）**：按 §4.2 章节；Prompt 与验证命令必须可直接复制执行。
- **根 README**：库入口 + 索引表 + 快速开始。
- **截图**：仅前端页面 demo，按 §4.5。
- **ABAP 源码**：遵循 `.agents/skills/abap-style/SKILL.md`（BMW 前缀、注释、格式、实现偏好）；与 demo 既有代码/团队规范冲突时，先匹配既有代码，并在 README 写明例外。
- 文档不写过程性解释（"本次修改了…"）；命令细节用 skill 链接，不复制大段速查。

## 10. 新增 demo 流程（Definition of Done）

1. 选编号：根 README 索引最大编号 +1，**不复用**。
2. 建目录：`README.md` + `src/`（前端页面 demo 另加 `screenshots/`）。
3. 先写**验收标准**，再写执行步骤（验收决定步骤，不是反过来）。
4. 写 ABAP/AFF 代码到 `src/`。
5. 静态校验：`abap check content`（`.abap`）/ `abap validate:aff`（JSON）；可选 `node scripts/check-demos.mjs`。
6. live 实跑：在 `$TMP` 按 README 的 Prompt 执行；README 验证命令通过；连续两次（含复位）结果一致。
7. 清理：`search` 确认对象不存在；`tmp/` 无残留。
8. 前端页面 demo：截图、脱敏、嵌入 README。
9. 更新根 README 索引并提交（一个 demo 一个 commit）。

DoD checklist：

- [ ] 目录只含 `README.md` / `src/` / `screenshots/`（可选；MIME 资产在 `src/mime/`）
- [ ] 对象命名以 `Z` 开头且含 `DMA`（§4.3）
- [ ] README 八章节齐全，含"原始 Prompt"与"运行与验证"
- [ ] Prompt 可复制、每步四要素、验收可机器判定
- [ ] live 跑通、连续两次（含复位）一致
- [ ] 清理后对象不存在
- [ ] 截图（如有）脱敏且与当前实现一致
- [ ] 根 README 索引已更新
- [ ] 无 `.abap.json` / 凭证 / URL / 真实业务数据

应用单元不适用本节的 demo 编号与 `$TMP` live 实跑要求，DoD 见 §4A.4。

## 11. Git 与提交

仓库初始化后，`.gitignore` 至少包含：

```
.abap.json
.env
tmp/
node_modules/
*.log
.DS_Store
```

- 提交信息：`demo(<NN>-<slug>): <做了什么>`、`app(crw): <做了什么>`、`docs: ...`、`chore: ...`；一个 demo/应用里程碑一个 commit。
- `README.md`、`src/`、`screenshots/`、根索引变更必须同一 commit，保证 demo 可独立回滚。
- 不提交构建产物与临时文件；不 force push 主分支。
- **远端与协作（2026-11 起）**：`origin` = <https://github.com/chunrichi/abap_cli_demo>（public），默认分支 `main`；提交/分支/PR/tag 细则见 [`CONTRIBUTING.md`](CONTRIBUTING.md)，决策记录（D1–D13）见 [`docs/github-workflow.md`](docs/github-workflow.md)。
- `main` 受保护：只能经 PR 合入，禁止 force push、禁止删除分支（管理员同样受限）；日常改动走 `feat/`/`fix/`/`docs/`/`chore/` 短分支，合并后删分支。
- push/PR 前必须完成 §7.1 只读验证并运行 `bash scripts/check-secrets.sh`；任一扫描命中先停止并问人。
- tag/release 采用 `v0.x.y` 语义化版本，规则见 CONTRIBUTING.md。

## 12. Agent 上下文与技能路由

- **入口**：[`abap-cli` 路由 skill](.agents/skills/abap-cli/SKILL.md)。先查路由表，命中后只加载**一个**领域 skill，不预加载全部。
- **领域 skill**：`abap-style`（ABAP 编码风格：命名/注释/格式/实现偏好，写 ABAP 前必读）、`abap-cli-setup`（配置/传输/部署）、`abap-cli-search`（元数据/只读探查）、`abap-cli-edit`（pull/push/check/create/delete）、`abap-cli-data`（run/select/test/run-report）、`abap-cli-performance`（性能方法论）。
- **写 ABAP 时**：先 `abap-style`（代码风格），再 `abap-cli-edit`（写路径）；报表类代码按 `abap-style` 的过程式/`FORM` 约定。
- **端到端编排**：[`abap-developer.agent.md`](.agents/agents/abap-developer.agent.md)（7 步工作流 + 错误恢复表）。
- **优先级**：本文件（仓库合约）> skill（CLI 领域知识）；skill 中的通用建议与本文件冲突时，以本文件为准。
- **上下文经济**：读 demo README → 根索引 → 目标 skill；不要预加载全部 demo 或全部 skill；`src/` 只在排错时读。
- **DSH**：本文件自动加载；`.agents/skills/` 是 DSH 项目级技能根，启动时只发现 `name` + `description`，正文按路由表按需读取。本仓库采用 `.agents/` 布局；如需 Copilot，用 `abap init --agent copilot` 生成 `.github/`，两种布局不要同时存在。

## 13. 环境

- 工作区 `.abap.json` 绑定本地 profile（示例值：`{"system":"dev","transport":"","package":""}`），**不入库**；连接参数由 `abap profile` / `abap init` 管理。
- 预检：`abap doctor --json`、`abap init --show-config --json`、`abap profile test`（详见 `abap-cli-setup`）。
- ICF 依赖：DDIC / `select` / `fields` / `run-report` 依赖内置 ICF 服务；`abap deploy status --json` 过期时执行 `abap deploy --yes --json`。
- 环境差异（ECC / S/4、release）写进 demo README 的前置条件，demo 不写死系统信息。
- 当前工作区（2026-11-01）：active profile `test`（systemVersion 789）、abap-cli 2.0.0（Node 24 LTS）、ICF 2.0.0 current；本地包 `$CRW` 已创建，`$` 本地包写路径可用（§4A.3 / 规划文档 B.3）；NROB（空 subType）与 MSAG（ADT→ICF fallback）修复已在 CLI 仓库提交（NROB 含于 `3dd443d` / MSAG 为 `5cf7395`），CLI 仓库工作区干净。

## 14. 参考

- 库结构、示例清单、路线图：[`docs/demo-library-plan.md`](docs/demo-library-plan.md)
- 应用线规划：[`docs/change-request-workbench-plan.md`](docs/change-request-workbench-plan.md)
- 协作规则（提交/分支/PR/tag/敏感扫描）：[`CONTRIBUTING.md`](CONTRIBUTING.md)
- GitHub 决策记录与发布流程：[`docs/github-workflow.md`](docs/github-workflow.md)
- 第三方内容署名：[`NOTICE`](NOTICE)
- 路由层：[`.agents/skills/abap-cli/SKILL.md`](.agents/skills/abap-cli/SKILL.md)
- 端到端代理：[`.agents/agents/abap-developer.agent.md`](.agents/agents/abap-developer.agent.md)
- ABAP 编码风格：[`.agents/skills/abap-style/SKILL.md`](.agents/skills/abap-style/SKILL.md)（来自 `chunrichi/abap-coding`，v1.0.7）
- 命令机器契约：`abap --help`、`abap <cmd> --schema --json`
- 命令速查与错误码：对应 skill 的 `references/commands-quick.md`、`references/errors.md`
