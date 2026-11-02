# Handoff：下一阶段（CRW M6 审批增强 + 产品化 + basis 落地）

> 状态：**当前任务入口**（2026-11-03 更新）。
> 上一阶段（GitHub 发布）已完成，存档见 [`docs/handoff-github-publish.md`](handoff-github-publish.md)；发布决策与完成记录见 [`docs/github-workflow.md`](github-workflow.md)。
> 应用级交接见 [`apps/change-request-workbench/docs/handoff.md`](../apps/change-request-workbench/docs/handoff.md)；P2 basis 设计见 [`apps/change-request-workbench/docs/p2-basis.md`](../apps/change-request-workbench/docs/p2-basis.md)。
> 开始前先读仓库根 [`AGENTS.md`](../AGENTS.md)（仓库合约，不可协商项优先）。

## 0. 新会话启动清单

```bash
cd /Users/lei/Desktop/ai_abap/abap_cli_demo
git log --oneline -5 && git status --short
cd apps/change-request-workbench
abap doctor --json
abap deploy status --json
abap run ZCL_CRW_SELFCHECK --json
abap test ZCL_CRW_NOTIFY --json
abap run ZCL_CRW_NOTIFY --json
```

期望：工作区 clean；`deploy status` current；selfcheck `tables=14 version=1.2.0 icf=OK cts=OK`；单测 0 failed；`CRW_NOTIFY_OK rows=<n> unread=<n>`（复位后 0/0）。
再读：根 README 应用索引、应用 `docs/handoff.md` §0/§14、`docs/p2-basis.md`、`docs/architecture.md` §4.2/§6、`docs/workflow.md` §9。

## 1. 当前基线（2026-11-03）

| 项 | 状态 |
|---|---|
| GitHub | <https://github.com/chunrichi/abap_cli_demo>（public）；`main` 受保护（PR 必需、禁 force push/删除、`enforce_admins=true`）；PR #1–#4 已合并 |
| 仓库规则 | [`CONTRIBUTING.md`](../CONTRIBUTING.md)、`.github/` 模板、`scripts/check-secrets.sh`；提交/分支/PR/tag 规则已生效 |
| CRW 应用 | M1–M5 已交付：14 表、v1.2.0、`/api/v1` + 16 页 SPA、审批/锁/CTS/计划/报表/通知；`ZCRW_REMIND_JOB` 报表就绪 |
| 截图 | 9 张 1440×1000 M5 实拍（含通知中心/铃铛），已脱敏 |
| 未启用 | CI（D8 后置）、tag/Release（D13 暂缓）、SMTP/SM36（basis）、包迁移/索引/归档/权限/Fiori（设计已就绪） |

## 2. 下一阶段任务（已确认范围）

### M6a 审批增强（优先，纯应用内）

1. **ALL 通过规则**：审批矩阵支持“任一人（ANY）/ 全部（ALL）”；需先确认 `ZCRW_APPR_CFG` 加字段的可行路径（abap-cli 对已有表加字段的能力需实测；不可行则改用独立规则表），含迁移、单测、审批页展示与推进逻辑。
2. **审批改派**：`POST /approvals/{id}/reassign`（当前审批人或 `CHANGE_MANAGER`/`ADMIN` 可改派；写审计；通知新审批人；页面动作）。
3. **URG 事后补审**：URG 变更的事后补审模型（状态/清单/提醒）、待补审报表与通知；与 workflow W20 对齐并补契约文档。

### M6b 产品化小项

1. 配置编辑：周期 / 角色 / 审批矩阵的 PATCH API + ADMIN 页表单 + 审计（写保护头、乐观锁）。
2. 报表日期范围参数化（`from/to` + 页面日期控件）。
3. ADM 检查清单（W28 模型：不建表或最小表，关闭校验；先定模型再实现）。

### F. basis 类项落地（需 user/basis 配合）

按 [`p2-basis.md`](../apps/change-request-workbench/docs/p2-basis.md) 执行：SM36 作业 `ZCRW_REMIND`（runbook §2.13）→ 包迁移 A3（SE21/SE80 + SE03，只记录不 release）→ 索引 D2（SE11）→ 归档/权限对象/Fiori（按需）。Agent 负责清单、验证命令、执行后复核与文档回写。

### 待用户确认的工程化项

- CI（D8 后置 → 现在做最小 CI：敏感扫描 + Markdown 链接 + 目录/命名 + AFF 校验；public 仓库免费）。
- 首个 tag `v0.1.0` + Release notes（D13）。
- About 描述 / topics（D9 原为留空）。

## 3. 约束与流程（不可协商）

- 走 `feat/<topic>` / `docs/<topic>` 分支 + PR；`main` 只能经 PR 合入；不 force push、不删 `main`。
- 提交前：`git status` → `bash scripts/check-secrets.sh` → `AGENTS.md` §7 只读验证；README/索引与代码同 PR。
- SAP 写路径：`check content` / `validate:aff` → `check syntax` → `push` → `inspect --activation` / `run` / `test`；一次只写 CRW 对象；不 release transport、不碰生产、不 `push --all`。
- 截图：UI 变更后重拍、脱敏（`DEMO_*`、无 URL/client）、单张 ≤ 500 KB；本次截图流水线见 `tmp/`（gitignored，不入库）。
- 文档语言：中文正文、命令/对象名 ASCII；不写实测未通过的值。

## 4. 完成标准（每个 PR）

- 应用 DoD（`AGENTS.md` §4A.4）：目录/命名、自检/单测/只读断言、截图、runbook、无 URL/凭证/真实数据。
- 新增/变更行为：selfcheck、`abap test`、只读 `select` 断言、必要的 smoke/演示数据验证；连续两次（含复位）一致。
- 文档：architecture / workflow / runbook / README / handoff 同步；`p2-basis.md` 状态更新。
- PR 按 `.github/PULL_REQUEST_TEMPLATE.md` 逐项填写，合并后删分支。

## 5. 参考

- 仓库合约：[`AGENTS.md`](../AGENTS.md)（§2/§4A/§7/§8/§11/§13）
- 协作规则：[`CONTRIBUTING.md`](../CONTRIBUTING.md)
- 发布与决策：[`docs/github-workflow.md`](github-workflow.md)
- 应用规划：[`docs/change-request-workbench-plan.md`](change-request-workbench-plan.md)
- 应用交接：[`apps/change-request-workbench/docs/handoff.md`](../apps/change-request-workbench/docs/handoff.md)
- 架构/流程：[`architecture.md`](../apps/change-request-workbench/docs/architecture.md)、[`workflow.md`](../apps/change-request-workbench/docs/workflow.md)
- 安装/运维：[`runbook.md`](../apps/change-request-workbench/docs/runbook.md)
- P2 basis：[`p2-basis.md`](../apps/change-request-workbench/docs/p2-basis.md)
