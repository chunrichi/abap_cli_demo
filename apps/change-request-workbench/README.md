# 变更请求工作台（CRW）

> 状态：M1（数据模型 + 号段 + 消息类已建；服务/页面待做）。
> 这是**真实应用**，不是 demo；不套用 demo 的 `DMA` 命名与编号，契约见仓库 [`AGENTS.md`](../../AGENTS.md) §4A。
> 产品规划与决策记录：[docs/change-request-workbench-plan.md](../../docs/change-request-workbench-plan.md)。

在 SAP 内管理「变更请求 → 变更文档 → 任务/子任务 → 传输（含 ToC）→ 测试 → 计划导入 → 关闭」的全流程工作台，提供工作清单、详情、审批、传输视图、导入计划、仪表盘、报表与审计。

## 范围（D3 已确认）

- CR → CD → Task → SubTask 层级。
- Transport 关联（DEV / ToC），CTS 只读展示（D4：实现但不做 live 验证）。
- 导入计划（计划时间/窗口 + 日程 + 到点/逾期提醒，不执行 TMS 导入）。
- 标准变更 `STD` 一期；紧急 `URG` P1；管理 `ADM` P2。

## 当前状态（2026-11-01）

- 预检：abap-cli 2.0.0；`abap doctor` ok；内置 ICF 2.0.0 current（已 `abap deploy --yes`）；active profile `test`（systemVersion 789）。
- 包：`$CRW` 本地包已创建（super package `$TMP`，DLVUNIT LOCAL，无 transport）；AFF 记录见 `src/$crw.devc.json`。
  重建命令（包不存在时）：`abap create DEVC '$CRW' --package '$TMP' --description 'Change Request Workbench local package' --package-type development --yes --json`。
- **写路径**：abap-cli 2.0.0 原生支持 `$` 前缀本地包免 transport；`$CRW` probe 验证通过：create → check syntax → push → run（`CRW_M0_OK`）→ delete（无 `--tr`）。
- **M0 已验证**：类 probe、DDIC TABL probe、`/ui2/cl_json` + ABAP Unit（testclasses sidecar）、CTS 只读（E070/E071/E07T）。
- **NROB / MSAG 已修复**（本地 CLI 修复，见规划文档 B.4）：`ZCRW_REQ` / `ZCRW_CD` / `ZCRW_TASK` 三个号段已建；`ZCRW_MSG` 消息类已建（T100 8 条）。
- **M1 数据模型**：13 张表（`ZCRW_*`）、3 个号段、消息类、2 个锁对象（`EZCRW_REQ` / `EZCRW_CD`）已在 `$CRW` 建好；AFF 在 `src/`，表均 0 行。
- 尚未创建任何 `ZCRW_*` 业务数据（表均为空）。

## 目录

```
apps/change-request-workbench/
├── README.md
├── docs/            # architecture / workflow / runbook（M1 起）
├── src/             # AFF：DDIC / CLAS / INTF / HTTP / TRAN / NROB / ENQU / MSAG
├── src/mime/        # 前端资产
└── screenshots/     # 主页面截图（脱敏）
```

## 工作约定

- 所有 `abap create/pull` 在本目录执行，避免拉取文件落到仓库根 `src/`。
- 对象前缀 `ZCRW_` / `ZCL_CRW_` / `ZIF_CRW_` / `ZCX_CRW_`；包 `$CRW`。
- 写 SAP 顺序：`check content` / `validate:aff` → `check syntax` → `push` → `inspect --activation` / `run` / `test`。
- 不 release transport；不碰生产；不提交凭证、URL、真实业务数据。

## 下一步

1. 提交/同步本地 CLI 修复（NROB 空 subType、MSAG ADT→ICF fallback）；升级后重新 `abap deploy --yes`。
2. 冻结 v1 API 契约与状态机，写 `docs/architecture.md`、`docs/workflow.md`。
3. 开始 M1 服务与骨架：bootstrap（配置种子 + 号段区间）、selfcheck、CR/CD/Task/SubTask CRUD、API 骨架、ICF 节点 + MIME + 前端首页。
4. 补 M0 剩余：ICF 认证、事务码、MIME/SPA fallback（随 M1 前端一起验证）。
