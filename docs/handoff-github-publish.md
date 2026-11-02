# Handoff：GitHub 项目创建与提交规则（下一个会话）

> **状态：✅ 已完成（2026-11-02）。本文是 GitHub 发布任务的存档记录，仅用于追溯；请勿按 §5 重新执行。**
> 当前下一阶段入口：[`docs/handoff-next-session.md`](handoff-next-session.md)；发布决策与完成记录见 [`docs/github-workflow.md`](github-workflow.md)。

> 用途：把当前**本地**仓库 `abap_cli_demo` 发布到 GitHub，并规划/落地后续的提交、分支、PR、发布规则。
> 上一个任务（CRW 应用 M1–M4）已交付完成，摘要见 §11；应用级交接见 [`apps/change-request-workbench/docs/handoff.md`](../apps/change-request-workbench/docs/handoff.md)。
> 本文件是下一个任务的唯一入口。执行前先读仓库根 [`AGENTS.md`](../AGENTS.md)（仓库合约，不可协商项优先）。

## 1. 目标

1. 在 GitHub 创建远端仓库，把本地 `main` 历史（15 个提交、工作区干净、无 remote）推送上去。
2. 规划并落地 GitHub 协作规则：提交信息与粒度、分支策略、PR、tag/release、敏感信息扫描、README/索引回写、Issues/Projects、CI（可后置）。
3. 产出：根 `CONTRIBUTING.md`、`.github/` 模板（PR/issue）、`AGENTS.md` §11 回写、根 README 状态更新；首次 push/PR 流程验证。
4. 全程先冻结 §3 的决策；**未确认前不 push、不改历史**。

## 2. 当前仓库基线（2026-11-02 实测）

| 项 | 现状 |
|---|---|
| 路径 | `/Users/lei/Desktop/ai_abap/abap_cli_demo` |
| 分支 / HEAD | `main` / `bf6daea`（`docs(crw): document ENQU active flag requirement in runbook`） |
| 提交数 / 跟踪文件 | 15 / 191（`apps/` 128、`demos/` 9） |
| 工作区 | clean；无 tag；**无 remote** |
| 目录 | `AGENTS.md`、`README.md`、`docs/`、`demos/01-icf-mime-stats/`、`apps/change-request-workbench/`、`.agents/`、`.gitignore`、`.abapignore` |
| 身份 | 已配置（个人邮箱；public 仓库需用户决定是否隐藏，见 §3） |
| GitHub CLI | `gh 2.103.3` 已安装并登录（`repo`/`workflow` scope，HTTPS 协议） |
| 体积 | `.git` 1.9 MB；最大 blob 222 KB（截图），push 无压力 |
| 历史安全扫描 | 未命中内网 IP / SAP 用户名 / 凭证 / transport 号；历史仅含 `.agents` 的 `.abap.json.template`（占位值，保留） |
| 启动校验 | `abap run ZCL_CRW_SELFCHECK` → `icf=OK cts=OK`；CLI 2.0.1、ICF current（与 GitHub 任务无关，供环境健康判断） |

## 3. 必须先问用户并冻结的决策

| # | 决策 | 选项 | 建议 | 影响 |
|---|---|---|---|---|
| D1 | 仓库名 | `abap_cli_demo` / `abap-cli-demo` / 其它 | 与目录一致 `abap_cli_demo` | 影响 URL 与 README 徽章 |
| D2 | 可见性 | private / public | **先 private**，确认无敏感后再决定是否转 public | public 需通过 §6 扫描 + 处理 §8 的第三方内容许可 |
| D3 | 历史 | 保留现有 15 提交直推 / 重写 | **保留直推**（提交信息已规范、历史干净） | 重写需 `git filter-repo` + force push，高风险 |
| D4 | 默认分支 | `main`（现状） | 保持不变 | 远端默认分支需一致 |
| D5 | 远程协议 | HTTPS（gh 默认）/ SSH | HTTPS | 影响 `origin` URL |
| D6 | License | 暂不添加 / MIT / 其它 | private 暂缓；public 前必须定 | 无 LICENSE 时 public 默认保留所有权利 |
| D7 | Issues / Projects / Discussions | 开/关 | Issues 开；Projects 可选；Discussions 暂关 | 影响下一阶段里程碑管理 |
| D8 | 分支保护 | 开/关 | 开启“PR 才能进 main + 禁止 force push” | 免费私有仓库可能不支持经典保护，见 §5 S5 降级方案 |
| D9 | CI | 现在做 / 后置 | **后置**（本任务只留规划；无根 `package.json`，Dependabot 不适用） | 影响 PR 必过检查 |
| D10 | README 索引 | 补 GitHub 链接/徽章 | 应用行状态**已在本 handoff 提交时更新为 M4**；建库后只需补 GitHub 链接/徽章 | 与提交同一 commit |
| D11 | 提交身份 | 保留现状 / 改为 GitHub noreply | 由用户决定；若 public 且不想暴露邮箱再改 | 改历史需重写，见 D3 |
| D12 | 第三方内容 | `.agents/` 生成物与 `abap-style`（来自 chunrichi/abap-coding v1.0.7）在 public 仓库的许可/署名 | private 可先不动；public 前确认许可并补 NOTICE/说明 | 合规风险 |
| D13 | 远端归属 | 个人账号 / org | 按用户 | 影响 `gh repo create` 参数与权限 |

> 用 ask_user_question 一次性把 D1–D13（可合并）问清，答案写进 `CONTRIBUTING.md` 的决策表或 `docs/github-workflow.md`。

## 4. 安全红线（不可协商）

- 禁止提交：`.abap.json`、`tmp/`、`.env`、日志、cookie、凭证、内网地址/IP、transport 号、SAP 用户名、真实业务数据。
- 截图必须脱敏（现有 7 张已脱敏：无系统地址，用户显示 `DEMO_USER`）。
- 禁止 `git push --force` 到 `main`；历史重写/强推必须用户明确批准并先备份。
- 不把 `gh` token、keychain 密码写入任何文件或命令输出。
- push 前必须完成 §6 扫描；扫描有任何命中先停止并问用户。
- 不把本地 `.abap.json`、`.abap-cli/`、`tmp/` 加入 Git 跟踪（`.gitignore` 已覆盖）。

## 5. 执行步骤草案（S1–S8，每步可验证）

### S1 预检（只读，先于任何写操作）

```bash
git status --short && git log --oneline -5 && git remote -v
gh auth status
# 用本机环境值逐个跑（值不写入仓库）：内网地址、SAP 用户名、transport 号
git log --all -S "<内网地址或主机名>" --oneline
git log --all -S "<SAP 用户名>" --oneline
git log --all --name-only --pretty=format: | sort -u | grep -Ei "abap\.json|\.env$|cookie|password|secret" || echo ok
git rev-list --objects --all | git cat-file --batch-check='%(objecttype) %(objectsize) %(rest)' \
  | awk '$1=="blob"{print $2, $3}' | sort -rn | head -5
```

期望：clean、无 remote、历史扫描无命中、最大 blob < 500 KB。

### S2 冻结决策

向用户确认 §3；把答案落到 `CONTRIBUTING.md`（或 `docs/github-workflow.md`）。未确认不进入 S4。

### S3 仓库元数据准备

- 根 `README.md`：应用行状态已更新为 M4（M1–M4 已交付；本 handoff 提交包含）；建库后补 GitHub 仓库链接/徽章，保持 demo 索引“最近验证”为实际日期。
- `.gitattributes`（建议新增）：

```gitattributes
* text=auto eol=lf
*.png binary
*.jpg binary
*.abap linguist-language=ABAP
```

- `LICENSE`：按 D6；public 前必须确定。
- 如 D12 需要：`NOTICE` 或 README 第三方内容说明（`.agents/skills/` 为 abap-cli 生成物；`abap-style` 来自 chunrichi/abap-coding v1.0.7）。

### S4 创建远端并首次推送

```bash
# 前提：S1–S3 完成、决策已冻结
gh repo create <owner>/<name> --<private|public> --source=. --remote=origin --push
# 或用户已手动建库：
# git remote add origin <url> && git push -u origin main
```

期望：`origin` 出现，`main` 推送成功；**失败即停**（大文件/敏感/权限/已存在 remote），不 force、不改历史。

### S5 仓库设置与保护

```bash
git remote -v
git fetch origin && git branch -u origin/main main
gh repo view --json name,visibility,defaultBranchRef,url
gh repo edit --default-branch main   # 确认默认分支
```

- 启用 Issues（D7）；Projects 按 D7。
- 分支保护（D8）：public 仓库可用经典保护；免费 private 仓库可能不可用，则降级为“约定 + 本地 hook”（如 `.githooks/pre-push` 禁止直推 main，需用户确认是否落地）。保护目标：PR 才能进 main、禁止 force push、禁止删除 main。

### S6 协作规则文件

- `CONTRIBUTING.md`（根）：提交规范、分支、PR、tag/release、敏感扫描清单、README/索引回写、验收命令。
- `.github/PULL_REQUEST_TEMPLATE.md`：变更点 / 验证命令 / 截图影响 / 脱敏与敏感信息 checklist。
- `.github/ISSUE_TEMPLATE/bug.md`、`feature.md`（YAML front matter；标签建议 `app/crw`、`demo`、`docs`、`bug`、`enhancement`、`chore`）。
- 可选：`scripts/check-secrets.sh`（本地扫描：IP 正则、`abap.json`、`tmp/`、`password`、transport 号模式），并在 CONTRIBUTING 中说明用法。

### S7 回写仓库合约与索引

- `AGENTS.md` §11：补“GitHub 远端/分支/PR 规则见 `CONTRIBUTING.md`；push 前做敏感扫描；禁止 force push main”。
- 根 `README.md`：GitHub 链接/徽章、应用行状态更新。
- 若新增 `docs/github-workflow.md`（决策记录），在根 README 仓库结构里补一行。

### S8 验证 + 首次流程演练

```bash
git ls-remote --heads origin
gh repo view --json name,visibility,defaultBranchRef,url
gh pr list
```

- 如有保护规则：建一个 docs 分支 → 提交 → push → `gh pr create` → 按规则合并（squash 或 merge），验证 PR 模板/流程；合并后删分支。
- 汇报：仓库 URL、可见性、默认分支、已启用功能（Issues/Projects/保护）、扫描结果、PR 演练结果。

## 6. push 前敏感信息扫描清单（每次发布/PR 前）

1. `git status --short` 无意外新增（尤其 `tmp/`、`.abap.json`、截图原始文件）。
2. `git grep -n -I -E "<内网地址正则>|<SAP 用户名>|SAPK[A-Z][0-9]+|password|secret"`（具体值只在本地 shell 使用，不写入仓库；排除已知合法文档提及）。
3. `git log --all -S "<敏感词>"`（历史级，至少覆盖内网 IP、SAP 用户、transport 号）。
4. 大文件：`git rev-list --objects --all | ...` 最大 blob < 500 KB。
5. 截图抽检：不出现系统地址/客户端/真实用户名/真实业务数据。
6. 第三方内容许可确认（仅 public 时强制）。

## 7. 建议的提交 / 分支 / PR / 发布规则（写进 CONTRIBUTING.md 的草案）

### 7.1 提交信息

- 格式：`<type>(<scope>): <summary>`；scope 可为 `crw`、`demo-01`、`docs`、`repo`。
- type：`feat` / `fix` / `docs` / `chore` / `refactor` / `test`；现有历史已用 `app(crw):`、`demo(01-...):`、`docs:`，可保留为应用线/演示线专用前缀（在 CONTRIBUTING 中写明等价关系）。
- 一个里程碑 / 一个 demo / 一个可独立回滚的变更 = 一个 commit；README + `src/` + 截图同 commit。
- 正文写“做了什么 + 为什么 + 验证命令”；不写过程性流水账。
- 不提交 WIP 到 main；个人分支可 amend/rebase。

### 7.2 分支

- 保护 `main`；短生命周期分支：`feat/<topic>`、`fix/<topic>`、`docs/<topic>`、`chore/<topic>`。
- 合并后删分支；不长期维护 `develop`（demo 库规模不需要）。

### 7.3 PR

- 标题同 commit 格式；正文用模板：变更点 / 验证命令与输出摘要 / 截图影响 / 敏感信息与脱敏 checklist。
- 单 PR 尽量小；改动 SAP 侧时附 `abap run`/`test` 只读证据；不附真实地址/账号。
- 禁止在 PR 中 force push 已评审提交（固定评审点后改需说明）。

### 7.4 Tag / Release

- 语义化版本：`v0.x.y`；demo 库按里程碑打 tag（如首个公开版本 `v0.1.0`）。
- Release notes 摘要 include：范围、验证命令、已知限制；不 attach 敏感证据。

### 7.5 每次改动前

- `git status` clean；按 AGENTS §7 跑只读验证；UI 变更重拍脱敏截图；README/索引同步（AGENTS §11 要求同一 commit）。

## 8. 已知坑与经验（来自上一个任务/本仓库）

- CLI 已从 2.0.0 升到 **2.0.1**：升级后 `abap deploy --yes` 并确认 `abap deploy status` 为 current；否则 DDIC/ICF 读写可能异常。
- 本仓库的 SAP 环境是**本地/开发系统**：GitHub 任务不需要连 SAP；不要把 `.abap.json`、地址、账号带进仓库。
- 截图限制：单张 ≤ 500 KB；现有最大 222 KB；MIME 资源推送与截图流程见 runbook，属本地操作，不需要写进 GitHub 流程。
- 历史提交身份是个人邮箱：若 D2=public 且 D11=隐藏，需 `git filter-repo --mail-map` + force push（高风险，先备份、再用用户批准）。
- `.agents/skills/` 是 abap-cli 生成物，`abap-style` 为第三方（chunrichi/abap-coding v1.0.7）：public 前确认许可/署名。
- 免费 private 仓库的分支保护能力有限：若 API 返回 403/404，别硬试，按 §5 S5 降级并告知用户。

## 9. 完成标准（DoD）

- [ ] GitHub 仓库已创建；`origin` 存在；`main` 已推送且默认分支为 `main`。
- [ ] 可见性/License/Issues/Projects 符合已冻结决策。
- [ ] `CONTRIBUTING.md` + `.github/` 模板已提交；提交/分支/PR/tag 规则可执行。
- [ ] `AGENTS.md` §11、根 `README.md` 已回写；应用行状态为 M4 且链接 runbook。
- [ ] §6 扫描通过；无敏感信息/大文件被推送。
- [ ] 首次 PR（或受保护分支流程）演练通过并汇报。
- [ ] 工作区 clean，提交信息符合新规则。

## 10. 下一个会话可直接复制的启动 Prompt

```text
你是接手 abap_cli_demo 仓库的新会话。先读根目录 AGENTS.md，再读 docs/handoff-next-session.md（下一个任务的唯一入口）。
任务：把本地仓库发布到 GitHub，并落地提交/分支/PR/tag 规则。
要求：
1) 按 handoff §3 先向我确认 D1–D13（仓库名、可见性、历史、License、Issues、分支保护、CI、提交身份等），未确认前不要 push；
2) 按 §5 执行 S1–S8：预检与历史敏感扫描 → 元数据（README/.gitattributes/LICENSE/NOTICE）→ gh repo create + push → 仓库设置与保护 → CONTRIBUTING.md + .github 模板 → AGENTS §11 与根 README 回写 → 首次 PR 演练；
3) 每步给出命令、期望与结果；push 前完成 §6 扫描并汇报；
4) 约束：不提交 .abap.json/tmp/凭证/内网地址/transport 号；不 force push main；历史重写需我批准；无未确认的 public 发布；
5) 结束前跑 §9 DoD 清单并留一份简短完成记录（GitHub URL、可见性、默认分支、启用的功能、演练结果）。
```

## 11. 上一个任务（CRW 应用）完成摘要

M1–M4 已全部交付并提交（`c3a8d19` 冻结 → `fbe659c`/`67d9a37` M1 → `5ceb513` M2 → `09d8d38` M3 → `a66d5a3` M4 → 两个 docs 收尾提交）：

- M1：`$CRW` 本地包 13 表 + 3 号段 + 消息类 + 锁；`/api/v1`（router/handler/控制器）；ICF `ZCRW_APP`；SPA 15 页（MIME `/zcrw`）；事务码 `ZCRW` → `ZCRW_START`；7 张脱敏截图。
- M2：状态机 + 单元测试（22 用例全绿：util 4 / workflow 10 / json 8）；审批矩阵/ANY/驳回意见/自审拦截；ENQUEUE 锁；历史/备注；乐观锁 409。
- M3：CTS 只读适配器 + 传输关联/解绑/标记/同步；导入计划改期/取消/确认/逾期；CD 计划快照。
- M4：报表（分布/趋势/时长/逾期/ToC/CSV）、配置只读、迁移、演示数据；README/architecture/workflow/runbook/handoff 全部更新。
- 最终验证：`CRW_SELFCHECK_OK … icf=OK cts=OK`；业务表 0 行（已复位）；HTTP 200/302/401 实测；工作区 clean。
- 剩余 P2：可传输包迁移、审批 ALL/改派/补审、ADM 清单、配置编辑、索引/归档、通知/作业化、报表日期参数、Fiori tile。详见应用 handoff §14.3。
