# GitHub 发布与协作流程

> 状态：决策已于 2026-11-02 冻结。本文件记录 D1–D13 决策、发布流程 S1–S8、分支保护与降级方案、CI 规划与第三方内容许可；协作规则速查见 [`CONTRIBUTING.md`](../CONTRIBUTING.md)。
> "完成记录"（§9）由发布执行人用实测值回填，未验证前保持占位，不要填计划值。

## 1. 目标与范围

把本地 `abap_cli_demo` 仓库发布到 GitHub，并固化可执行的协作规则：仓库元数据与许可、提交 / 分支 / PR / tag 规则、敏感信息扫描、README 与索引回写、CI（后置）。

发布基线（决策时实测）：`main` 分支、16 个提交、工作区 clean、无 remote、无 tag；最大 blob 约 218 KB（截图），低于 500 KB 上限。发布执行时以实际值回填 §9。

工作区约定：只连接 dev / sandbox / trial 系统；发布流程本身不连 SAP，不把 `.abap.json`、地址、账号带进仓库。

## 2. 决策记录 D1–D13（已冻结）

| # | 决策 | 结论 | 影响 / 依据 |
|---|---|---|---|
| D1 | 仓库名 | `abap_cli_demo`；<https://github.com/chunrichi/abap_cli_demo> | 与本地目录一致，README 徽章与链接据此 |
| D2 | 可见性 | public（直接公开） | 公开前必须通过 S1 扫描与第三方许可确认（§6） |
| D3 | 提交历史 | 保留发布时的现有历史直推，不重写 | 决策基线 16 个提交；重写需 `git filter-repo` + force push，风险高，不做 |
| D4 | 默认分支 / 远程协议 | `main`；HTTPS | 远端默认分支与本地一致；`origin` 用 HTTPS |
| D5 | License | MIT；版权人 `chunrichi (旧事)`，年份 2026 | 见根 [`LICENSE`](../LICENSE)；无 License 的 public 仓库默认保留所有权利 |
| D6 | Issues / Projects / Discussions | Issues 开；Projects 关；Discussions 关 | Issue 模板见 `.github/ISSUE_TEMPLATE/` |
| D7 | `main` 分支保护 | PR 才能进 `main`、禁止 force push、禁止删除 `main`；public 仓库预期可用经典保护，API 不支持时降级为约定 + 可选 `.githooks` | 两种状态见 §4；管理员同样受限（enforce admins） |
| D8 | CI | 后置：本阶段只做本地静态检查（`git status` / `scripts/check-secrets.sh` / 目录与命名校验），未来可接 GitHub Actions | 本阶段不写 workflow 文件，规划见 §7 |
| D9 | 根 README 元数据 | 补仓库链接 + 徽章 | 徽章只放仓库级事实；CI 落地前不放构建徽章 |
| D10 | 提交身份 | 保留现状 `旧事 <545049148@qq.com>` | 已确认 public 下邮箱公开；不改历史 |
| D11 | 第三方内容 | 根 [`NOTICE`](../NOTICE) 记录来源与许可；`.agents/skills/abap-cli*`、`.agents/agents/*` 为 abap-cli 生成物（MIT）；`.agents/skills/abap-style` 来自 `chunrichi/abap-coding` v1.0.7 | 合规风险已处理，明细见 §6 |
| D12 | 远端归属 | `chunrichi` 个人账号 | 影响 `gh repo create` 参数与权限 |
| D13 | Tag / Release | 本阶段不打 tag / Release；规则采用 `v0.x.y` 语义化版本，里程碑或首个公开版本再打 | 规则见 CONTRIBUTING；不 attach 敏感证据 |

补充约定：仓库 About 描述留空；topics 不设置；不放置未经验证的 CI 徽章。

## 3. 发布流程 S1–S8

每步先读"期望"，失败即停，不跳过、不 force、不改历史。

### S1 预检（只读）

```bash
git status --short
git log --oneline -5
git remote -v
bash scripts/check-secrets.sh
git rev-list --objects --all | git cat-file --batch-check='%(objecttype) %(objectsize) %(rest)' \
  | awk '$1 == "blob"' | sort -k2 -rn | head -5
gh auth status
```

期望：工作区 clean、`main` 本地历史完整、首次发布前无 remote、扫描退出码 0、最大 blob < 500 KB、`gh` 已登录且协议为 HTTPS。
敏感词历史扫描（内网地址、SAP 用户名、transport 号）只在本机 shell 用实际值执行，**不写入仓库**；命中即停，先处理再进入 S3。

### S2 决策冻结

D1–D13 已冻结（§2）。执行人确认仓库名、可见性、License、Issues 设置与分支保护策略；未确认不进入 S4。

### S3 仓库元数据准备

- 已有：[`LICENSE`](../LICENSE)（MIT）、[`NOTICE`](../NOTICE)（第三方内容）、[`.gitattributes`](../.gitattributes)（`* text=auto eol=lf`、图片按二进制、`*.abap linguist-language=ABAP`）。
- 根 [`README.md`](../README.md)：补仓库链接与徽章（D9），保持 demo 索引"最近验证"为实际日期。
- 提交身份保持 D10（`旧事 <545049148@qq.com>`）；用 `git log -1 --format='%an <%ae>'` 核对，不改历史。
- 期望：`git status` clean；元数据与文档变更同 commit / 同 PR。

### S4 创建远端并首次推送

```bash
gh repo create chunrichi/abap_cli_demo --public --source=. --remote=origin --push
# 若仓库已手动创建：
# git remote add origin https://github.com/chunrichi/abap_cli_demo.git
# git push -u origin main
```

前提：本地 `main` 已含全部待发布提交且工作区 clean。
期望：`git remote -v` 出现 `origin`；`main` 推送成功；`gh repo view --json name,visibility,defaultBranchRef,url` 返回 public / `main`。
失败（大文件、权限、remote 已存在、分支名不符）即停；不 force、不重试推送。

### S5 仓库设置与保护

```bash
gh repo edit chunrichi/abap_cli_demo --default-branch main
gh repo edit chunrichi/abap_cli_demo --enable-issues=true --enable-projects=false --enable-discussions=false
gh repo edit chunrichi/abap_cli_demo --enable-squash-merge=true --enable-merge-commit=true \
  --enable-rebase-merge=false --delete-branch-on-merge=true
gh api repos/chunrichi/abap_cli_demo \
  --jq '{visibility: .visibility, default_branch: .default_branch, has_issues: .has_issues, has_projects: .has_projects, has_discussions: .has_discussions}'
```

期望：`visibility=public`、`default_branch=main`、`has_issues=true`、`has_projects=false`、`has_discussions=false`。
About 描述留空、topics 不设置（不执行 `--add-topic`；`--description` 不传或置空）。
标签：保留 GitHub 默认 `bug` / `enhancement`；领域标签 `app/crw` / `demo` / `docs` / `chore` 用 `gh label create` 创建（见 §5）。
分支保护按 §4 执行，并回填 §9。

### S6 协作规则文件

本批文件：`CONTRIBUTING.md`、`.github/PULL_REQUEST_TEMPLATE.md`、`.github/ISSUE_TEMPLATE/bug.md`、`.github/ISSUE_TEMPLATE/feature.md`、`scripts/check-secrets.sh`、`docs/github-workflow.md`（本文件）。
期望：`bash scripts/check-secrets.sh` 退出码 0（告警人工确认）；PR / Issue 模板 front matter 可被 GitHub 解析；相对链接可解析。

### S7 回写仓库合约与索引

- [`AGENTS.md`](../AGENTS.md) §11：补远端 / 默认分支 / PR / 扫描 / tag 规则。
- 根 [`README.md`](../README.md)：补 GitHub 链接、徽章与仓库结构条目。
- 期望：AGENTS §11、README、CONTRIBUTING、本文件互链一致，无失效链接；回写与规则文件同 PR。

### S8 验证与首次 PR 演练

```bash
git ls-remote --heads origin
gh repo view --json name,visibility,defaultBranchRef,url
gh pr list
```

首次 PR 演练（保护启用后）：

```bash
git switch -c docs/pr-drill
# 做一处小文档改动并提交
git commit -am "docs: verify protected-branch PR flow"
git push -u origin docs/pr-drill
gh pr create --title "docs: verify protected-branch PR flow" \
  --body-file .github/PULL_REQUEST_TEMPLATE.md   # 按模板逐项填写（CLI 创建需显式传 body）
gh pr view --json state,mergeable
gh pr merge --squash --delete-branch
```

期望：PR 创建成功、模板可填、合并成功、远端分支被删除；`main` 只能经该 PR 更新。
保护验证（可选，仅在保护已启用时）：

```bash
git switch main
git commit --allow-empty -m "chore(repo): protection probe"
git push origin main    # 期望被拒绝
git reset --hard origin/main
```

期望：直推被拒绝；之后用 `reset` 恢复本地，不留下探针提交。
结果（仓库 URL、可见性、默认分支、已启用功能、扫描结果、演练结果）回填 §9。

## 4. 分支保护与降级方案

目标（D7）：PR 才能进 `main`、禁止 force push、禁止删除 `main`；管理员同样受限（`enforce_admins=true`）。

### 4.1 状态 A：经典保护已启用（预期）

public 仓库预期支持经典分支保护。用 API 一次性写入（单维护者场景 `required_approving_review_count=0`，仍强制走 PR；多人维护时提高到 ≥1）：

```bash
gh api -X PUT repos/chunrichi/abap_cli_demo/branches/main/protection \
  --input - <<'JSON'
{
  "required_status_checks": null,
  "enforce_admins": true,
  "required_pull_request_reviews": {
    "required_approving_review_count": 0
  },
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false
}
JSON
```

验证：

```bash
gh api repos/chunrichi/abap_cli_demo/branches/main/protection \
  --jq '{enforce_admins: .enforce_admins.enabled, force_push: .allow_force_pushes.enabled, deletions: .allow_deletions.enabled, pr_reviews: .required_pull_request_reviews.required_approving_review_count}'
```

期望：`enforce_admins=true`、`force_push=false`、`deletions=false`、`pr_reviews=0`。
说明：`required_approving_review_count=1` 在单维护者下会卡住自己的 PR（不能给自己 approve），多人协作时再提高。

### 4.2 状态 B：降级（API 不支持时）

触发：`gh api` 返回 403 / 404 / 422，或提示经典保护不可用（免费 plan / 权限限制）。
处理：

1. 不反复重试；在 §9 完成记录标注"服务端保护未启用（降级）"。
2. 保持约定级保护：`main` 只经 PR、禁止 force push、禁止删除；规则已写入 [`CONTRIBUTING.md`](../CONTRIBUTING.md) 与 AGENTS §11。
3. 可选本地兜底：`.githooks/pre-push` 阻止直推 `main`（本地配置，需每人自行启用；不替代服务端保护）：

```bash
#!/bin/sh
# .githooks/pre-push — 阻止直推受保护分支（本地兜底）
branch=$(git symbolic-ref --short HEAD 2>/dev/null || true)
if [ "$branch" = "main" ]; then
  echo "禁止直推 main：请走 PR（见 CONTRIBUTING.md）" >&2
  exit 1
fi
```

```bash
chmod +x .githooks/pre-push
git config core.hooksPath .githooks
```

4. 降级期间合并 / 发版由维护者在 PR 中显式确认；管理员仍可绕过本地 hook，不得作为常规操作。
5. 仓库升级（转组织账号或提升 plan）后重试状态 A，并更新 §9。

### 4.3 保护验证要点

- 直推 `main` 被拒绝；force push 被拒绝；删除 `main` 被拒绝（API 返回 422 / 403）。
- PR 合并前满足 PR 要求（即使 approving count 为 0，也不允许直推）。
- 管理员同样受限（`enforce_admins=true`）；如非预期，回到 §4.1 修正 payload。

## 5. 元数据与徽章约定

- 仓库名 / URL：见 D1；About 描述留空；topics 不设置。
- Issues 标签：GitHub 默认 `bug` / `enhancement` 保留；领域标签 `app/crw` / `demo` / `docs` / `chore` 已创建，issue 模板 front matter 与 PR/Issue 按范围使用。
- License：MIT（根 `LICENSE`），版权人 `chunrichi (旧事)`，年份 2026；`NOTICE` 记录第三方内容（D11）。
- `.gitattributes`：统一 LF、图片按二进制、`*.abap` 计入 ABAP 语言统计，保证 diff 与 GitHub 语言识别稳定。
- README 徽章：只放可验证事实（如 License）；构建 /覆盖率徽章等 CI 真实产出后再放，不放占位状态。
- 合并方式未冻结：squash 或 merge 由维护者按 PR 情况选择并记录；建议 squash，保持 `main` 线性、一个 PR 一个提交。

## 6. 第三方内容与许可（D11）

| 路径 | 来源 | 许可 / 版权 | 同步方式 |
|---|---|---|---|
| `.agents/skills/abap-cli/`、`abap-cli-setup/`、`abap-cli-search/`、`abap-cli-edit/`、`abap-cli-data/`、`abap-cli-performance/`；`.agents/agents/` | [abap-cli](https://github.com/chunrichi/abap-cli)，`abap init --agent generic` 生成物 | MIT License，Copyright (c) 2026 abap-cli contributors | 升级用 `abap init --agent generic --force` 重新生成并单独 review 差异；不手改 |
| `.agents/skills/abap-style/` | [chunrichi/abap-coding](https://github.com/chunrichi/abap-coding)，v1.0.7 | 上游当前未声明单独开源许可证；版权人与本仓库同一人 `chunrichi`，随根 `LICENSE`（MIT）授权 | 手工同步；升级时重新拉取并 review，更新本表与 NOTICE |
| 根 README、`docs/`、`demos/`、`apps/`、`screenshots/` | 本仓库作者 | MIT（根 `LICENSE`） | 截图由作者制作并脱敏，不含第三方素材 |

- 根 [`NOTICE`](../NOTICE) 是署名事实源；第三方内容的版本 / 来源 / 许可变化必须在同一 PR 更新 NOTICE 与本表。
- 新增第三方内容前先确认许可兼容 MIT，并补 NOTICE；无法确认则不带入 public 仓库。

## 7. CI 规划（后置，D8）

- 本阶段不创建 `.github/workflows/`，不写 workflow 文件；PR 由本地检查 + 人工确认兜底。
- 本地静态检查（提交 / PR 前）：

```bash
git status --short
bash scripts/check-secrets.sh
# 目录 / 命名 / README 结构：新增 demo 按 AGENTS §4.3、§10 自查
# 可选（M2 落地后）：node scripts/check-demos.mjs
```

- 未来 GitHub Actions 规划（按落地顺序）：
  1. PR 必过：敏感扫描（复用本脚本）、Markdown / 链接检查、目录与命名校验；
  2. 静态 AFF 校验：`abap check content` / `abap validate:aff`（不连 SAP）；
  3. SAP 只读验证：需要自托管 runner 与 secrets，只跑只读命令；凭证不进 workflow 文件与日志。
- 不启用 Dependabot（当前无根 `package.json`）；不做自动 tag / release；CI 真实产出后再考虑 README 徽章。
- CI 上线本身走独立 PR，先记录在 §9"后续 CI 落地"。

## 8. 维护约定

- push / PR 前先跑 §7 本地检查；任一命中先停并问人，不用 `--no-verify` 或管理员权限绕过。
- 历史不重写（D3）；不 force push 已发布分支与 tag；保护设置变更需在 §9 留痕。
- 根 README 索引、AGENTS §11、CONTRIBUTING、本文件四者同步更新；规则变更走 docs PR。
- 决策变更：新增 D14+ 或标注旧决策"已替代"，不删除历史结论。
- 第三方内容升级（`abap init` / `abap-style`）单独 commit，更新 NOTICE 与本文件 §6。
- 每季度复核：可见性、分支保护状态、协作者权限、第三方许可、扫描脚本自身有效性。
- 安全事件：误推敏感内容 → 立即停止推送 → 告知维护者 → 评估历史重写（需明确批准 + 先备份）。

## 9. 完成记录（由 Lead 回填）

> 发布完成后用实测值替换下表 `<待回填>`；未验证前不要填写计划值或推测结论。

| 项 | 实测值 |
|---|---|
| GitHub URL | `<待回填>` |
| 可见性 | `<待回填>` |
| 默认分支 | `<待回填>` |
| 已推送提交数 / 工作区状态 | `<待回填>` |
| Issues / Projects / Discussions | `<待回填：开 / 关 / 关>` |
| About 描述 / topics | `<待回填：留空 / 未设置>` |
| 分支保护状态 | `<待回填：状态 A 已启用（classic）/ 状态 B 降级（约定 + hook）>` |
| 敏感扫描结果（handoff §6 清单） | `<待回填：运行命令、退出码、告警项>` |
| 首次 push 结果 | `<待回填>` |
| 首次 PR 演练结果 | `<待回填：PR 号、合并方式、分支删除、直推被拒验证>` |
| 后续 CI 落地 | `<待回填：未开始 / 计划中>` |
