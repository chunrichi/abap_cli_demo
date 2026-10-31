# abap-cli DMA Demo 示例库

用 prompt 驱动 agent 调用 `abap` CLI，在 SAP 里落地可复现的 ABAP demo；每个 demo 只有 `README.md` + `src/`（前端页面 demo 另加 `screenshots/`）。

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

## 仓库结构

- [`AGENTS.md`](AGENTS.md)：仓库合约（命名、目录、验证、安全边界）
- [`docs/demo-library-plan.md`](docs/demo-library-plan.md)：示例清单与路线图
- [`demos/`](demos/)：每个 demo 一个目录
- [`.agents/skills/`](.agents/skills/)：abap-cli 技能（DSH 项目级技能根）

## 约定

- 对象名以 `Z` 开头且包含 `DMA`，默认 `$TMP` 包，可删除重建。
- 所有命令 `--json`；写命令带 `--yes`；`$TMP` 必须写成 `'$TMP'`。
- 验证命令只读；验证结果写进 demo README，不保存证据文件。
