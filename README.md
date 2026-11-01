# abap-cli DMA Demo 示例库

用 prompt 驱动 agent 调用 `abap` CLI，在 SAP 里落地可复现的 ABAP demo；每个 demo 只有 `README.md` + `src/`（前端页面 demo 另加 `screenshots/`）。另有应用型项目放在 [`apps/`](apps/)（见 [`AGENTS.md`](AGENTS.md) §4A）。

## 快速开始

前置：Node.js 22+、[abap-cli](https://github.com/chunrichi/abap-cli) 1.1.0+、可连接的 dev/trial SAP 系统。

```bash
abap init
abap doctor --json
```

然后从下方索引选一个 demo，按它的 README 执行“原始 Prompt”。

## Demo 索引

| 编号 | 标题 | 层级 | 对象 | 关键命令 | 最近验证 |
|---|---|---|---|---|---|
| [01](demos/01-icf-mime-stats/README.md) | ICF + MIME 统计看板 | intermediate | `ZCL_DMA_01_STATS` / `ZCL_DMA_01_STATS_CLEANUP` (CLAS)、`ZDMA_01_STATS` (HTTP)、MIME `/zdma_01_stats` | doctor, create, check, push, mime create/push, run, select, delete | 2026-11-01 |

## 应用项目

真实应用（非 demo），按 [`AGENTS.md`](AGENTS.md) §4A 契约管理。

| 项目 | 状态 | 说明 |
|---|---|---|
| [变更请求工作台（CRW）](apps/change-request-workbench/README.md) | M4（M1–M4 已交付） | 变更请求全流程工作台；产品前缀 `ZCRW_`，包 `$CRW`；状态与验证见 [应用 README](apps/change-request-workbench/README.md)，安装见 [runbook](apps/change-request-workbench/docs/runbook.md)，规划见 [docs/change-request-workbench-plan.md](docs/change-request-workbench-plan.md) |

## 仓库结构

- [`AGENTS.md`](AGENTS.md)：仓库合约（命名、目录、验证、安全边界）
- [`docs/demo-library-plan.md`](docs/demo-library-plan.md)：示例清单与路线图
- [`docs/change-request-workbench-plan.md`](docs/change-request-workbench-plan.md)：变更请求工作台（应用型项目）规划
- [`docs/handoff-next-session.md`](docs/handoff-next-session.md)：下一任务交接（GitHub 发布与提交/分支/PR 规则）
- [`demos/`](demos/)：每个 demo 一个目录
- [`apps/`](apps/)：应用型项目（非 demo），当前为变更请求工作台（CRW）
- [`.agents/skills/`](.agents/skills/)：abap-cli 技能（DSH 项目级技能根）

## 约定

- demo 对象名以 `Z` 开头且包含 `DMA`，默认 `$TMP` 包，可删除重建。
- 所有命令 `--json`；写命令带 `--yes`；`$TMP` 必须写成 `'$TMP'`。
- 验证命令只读；验证结果写进 demo README，不保存证据文件。
- 应用型项目在 [`apps/`](apps/)（契约见 [`AGENTS.md`](AGENTS.md) §4A），不使用 `DMA` 命名与 `$TMP` 包；当前项目为变更请求工作台（CRW）。
