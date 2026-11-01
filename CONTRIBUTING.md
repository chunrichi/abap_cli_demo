# 贡献指南

本仓库是 prompt-first 的 ABAP demo 示例库：`demos/` 放可复制执行的最小 demo，`apps/` 放应用型项目；demo 由 [abap-cli](https://github.com/chunrichi/abap-cli) 在 SAP 中落地（远程：<https://github.com/chunrichi/abap_cli_demo>，public，MIT）。

开始前先读仓库合约 [`AGENTS.md`](AGENTS.md)：§2（不可协商规则 / 安全红线）、§4.2（README 文档结构与风格）、§4.5（截图脱敏）、§9（文档与语言）、§11（Git 与提交）是硬约束，本文件不得与其冲突；demo 契约在 §4，应用契约在 §4A。

## 快速开始

1. 读 [`AGENTS.md`](AGENTS.md) §2（不可协商规则）、§4（demo 契约）、§4A（应用契约）、§7（验证）、§11（Git 与提交）。
2. 本地前置：Node.js 22+、[abap-cli](https://github.com/chunrichi/abap-cli) 2.0.0+（当前验证 2.0.1）、可连接的 dev / sandbox / trial SAP 系统（`.abap.json` 不入库）。
3. `abap init && abap doctor --json`，从根 [`README.md`](README.md) 的索引选一个 demo 或应用开始。
4. CLI 命令细节与错误码按 AGENTS §12 路由到 [`.agents/skills/`](.agents/skills/)，本文件不复制命令速查。

动手前确认工作区从最新 `main` 切出；提交前必须通过"验证与敏感扫描"一节。

## 决策记录（已冻结）

D1–D13 于 2026-11-02 冻结。变更决策需维护者确认，并在同一 PR 更新本表与 [`docs/github-workflow.md`](docs/github-workflow.md)。

| # | 决策 | 结论 |
|---|---|---|
| D1 | 仓库名 / URL | `abap_cli_demo`；<https://github.com/chunrichi/abap_cli_demo> |
| D2 | 可见性 | public（直接公开） |
| D3 | 提交历史 | 保留发布前的现有历史直推，不重写（决策基线 16 个提交） |
| D4 | 默认分支 / 远程协议 | `main`；HTTPS |
| D5 | License | MIT；版权人 `chunrichi (旧事)`，年份 2026（见 [`LICENSE`](LICENSE)） |
| D6 | Issues / Projects / Discussions | Issues 开；Projects 关；Discussions 关 |
| D7 | `main` 分支保护 | PR 才能进 `main`、禁止 force push、禁止删除 `main`；public 仓库预期可用经典保护，API 不支持时降级为约定 + 可选 `.githooks`（见 docs/github-workflow.md §4） |
| D8 | CI | 后置：本阶段只做本地静态检查（`git status` / `scripts/check-secrets.sh` / 目录与命名校验），未来可接 GitHub Actions |
| D9 | 根 README 元数据 | 补仓库链接 + 徽章；徽章只放仓库级事实（如 License），CI 落地前不放构建徽章 |
| D10 | 提交身份 | 保留现状 `旧事 <545049148@qq.com>`；已确认 public 下邮箱公开 |
| D11 | 第三方内容 | 根 [`NOTICE`](NOTICE) 记录来源与许可；`.agents/skills/abap-cli*`、`.agents/agents/*` 为 abap-cli 生成物（MIT）；`.agents/skills/abap-style` 来自 `chunrichi/abap-coding` v1.0.7，版权人与本仓库同一人；详见 docs/github-workflow.md §6 |
| D12 | 远端归属 | `chunrichi` 个人账号 |
| D13 | Tag / Release | 本阶段不打 tag/Release；规则采用 `v0.x.y` 语义化版本，里程碑或首个公开版本再打 |

补充约定：仓库 About 描述留空、topics 不设置；根 README 徽章不放未验证的 CI 状态。

## 提交信息规范

格式与历史前缀等价（两种写法都接受，同一 PR 内保持一致）：

| 历史写法（保留） | 等价 `<type>(<scope>)` | 用于 |
|---|---|---|
| `demo(<NN>-<slug>): <summary>` | `feat(demo-<NN>): <summary>` / `fix(demo-<NN>): <summary>` | 新增或修复一个 demo |
| `app(crw): <summary>` | `feat(crw)` / `fix(crw)` / `refactor(crw)` / `test(crw)` | `apps/` 应用线 |
| `docs: <summary>` / `docs(crw): <summary>` | `docs(repo): <summary>` / `docs(crw): <summary>` | 只改文档 |
| `chore(repo): <summary>` | `chore(repo): <summary>` | 仓库元数据、依赖、脚本 |

- `type`：`feat` / `fix` / `docs` / `chore` / `refactor` / `test`；`scope`：`crw` / `demo-<NN>` / `docs` / `repo`。
- 一个里程碑、一个 demo、一个可独立回滚的变更 = 一个 commit。`README.md` + `src/`（+ `screenshots/`）必须在同一 commit，保证 demo 可单独回滚（AGENTS §11）；根 README 索引变更也在同一 commit。
- 提交正文（可选）写"做了什么 + 为什么 + 验证命令"，不写过程性流水账；不把 WIP 提交到 `main`，个人分支可 amend / rebase。
- 示例：`feat(demo-02): add ALV report demo`、`fix(crw): reject empty approval comment`、`docs: update GitHub workflow decision record`、`chore(repo): add MIT license and notice`。

## 分支策略

- `main` 受保护：只接受 PR 合入，禁止 force push、禁止删除（管理员同样受限）。
- 短生命周期分支：`feat/<topic>`、`fix/<topic>`、`docs/<topic>`、`chore/<topic>`；`topic` 用 kebab-case ASCII，例如 `docs/github-workflow`、`feat/demo-02-alv-report`。
- 合并后删分支；不长期维护 `develop`（demo 库规模不需要）。
- 分支保护未生效时的降级约定见 [`docs/github-workflow.md`](docs/github-workflow.md) §4；PR 仍是唯一合入方式。

## PR 流程

1. 从最新 `main` 切短分支，本地按上述规范提交。
2. PR 标题同 commit 格式；正文必须使用 [`.github/PULL_REQUEST_TEMPLATE.md`](.github/PULL_REQUEST_TEMPLATE.md)，逐项勾选。
3. 单 PR 尽量小：一个 demo / 一个应用里程碑 / 一个主题；避免夹杂无关重构。
4. SAP 侧改动附**只读**验证命令与输出摘要：`abap run` / `abap test` / `abap select` 等 `--json` 的 `status`、`data.activation` / `data.output` / `data.exitCode` 等关键字段；不附真实地址、账号、client、transport 号。
5. 必须实际跑通再写"已验证"；没有跑通就如实写"未验证"（AGENTS §7.1）。
6. 合并方式（squash 或 merge）由维护者按 PR 情况选择；合并后删除分支。
7. 禁止 force push 已评审提交；固定评审点后需要改动时，说明原因并重新请求 review。
8. 分支保护启用时，`main` 的直推会被拒绝；不要用管理员绕过或 `--no-verify` 规避规则。

## 验证与敏感扫描（提交 / 推送前必做）

```bash
git status --short
bash scripts/check-secrets.sh
```

- `git status --short`：确认无意外新增（`.abap.json`、`tmp/`、日志、原始截图、本地配置、编辑器产物）。
- `bash scripts/check-secrets.sh`：只读、无网络，检查已跟踪敏感文件名、私网地址、凭证赋值形态、transport 号形态、历史提交（`git log -G` / `-S`）、最大 blob（< 500 KB）与截图体积；有阻断项时非零退出。凭证关键词的文档性提及、`.agents/skills/**` 生成物与占位 transport 号只提示、不阻断。
- SAP 侧改动按 AGENTS §7 跑只读验证（白名单命令），结果写进 demo README / 应用 README 或 PR 描述；UI 变更重拍脱敏截图，单张 ≤ 500 KB（AGENTS §4.5）。
- 扫描白名单：`.agents/skills/**`（abap-cli 生成物，含 CLI 文档占位示例）与文档中的占位 transport 号 `DEVK900001` / `QASK900123` / `NDK123456` 不阻断；未跟踪文件只报告、不判定。白名单之外任何命中都先停并问维护者。

## Tag / Release

- 语义化版本 `v0.x.y`；0.x 阶段允许不兼容变更，但要在 Release notes 标明。
- 本阶段（首次公开）不打 tag / Release；里程碑或首个公开版本再打，且只从已合入 `main` 的 commit 打。
- Release notes 必含：范围（demo / 应用 / 文档）、验证命令与结果摘要、已知限制；不 attach 敏感证据（截图原始文件、凭证、地址、日志）。
- 已发布 tag 不 force push、不移动；需要修正时打新版本。

## CI 规划（后置）

本阶段不接 GitHub Actions，本地静态检查兜底：

```bash
git status --short
bash scripts/check-secrets.sh
# 目录 / 命名 / README 结构：新增 demo 按 AGENTS §4.3、§10 自查
# 可选：node scripts/check-demos.mjs（M2 落地后再接）
```

未来接入 Actions 时，PR 必过：敏感扫描（复用本脚本）、Markdown / 链接检查、目录与命名校验；SAP 相关验证不上 GitHub 托管 runner，凭证不进 workflow。CI 落地前不在根 README 放构建徽章（D9）。

## 安全红线

不可协商项以 [`AGENTS.md`](AGENTS.md) §2、§4（含 §4.5 截图脱敏）、§8（安全边界）为准；GitHub 侧补充：

- 不提交 `.abap.json`、`tmp/`、`.env`、cookie、凭证、内网地址 / RFC1918 私网 IP、SAP 用户名、transport 号、真实业务数据；截图必须脱敏。
- 不把 secret、token 写进提交、PR、Issue、Release 或日志；不把 `gh` token、keychain 内容写入任何文件或命令输出。
- 不 force push `main`、不删除 `main`；历史重写必须维护者明确批准并先备份。
- 不把真实系统地址、client、账号写进 README、示例、截图、Issue 或 PR。
- 发现误提交敏感内容：立即停止推送并告知维护者，不要先公开讨论细节。

## 报告问题

- Bug / 功能建议使用 [`.github/ISSUE_TEMPLATE/`](.github/ISSUE_TEMPLATE/) 下模板；标签使用 `bug` / `enhancement`（GitHub 默认）与领域标签 `app/crw` / `demo` / `docs` / `chore`（仓库已创建）。
- 安全问题私下联系维护者，不在公开 Issue 贴敏感细节。
