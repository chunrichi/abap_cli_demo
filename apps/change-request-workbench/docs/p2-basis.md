# 变更请求工作台（CRW）· P2 Basis 类项设计

> 状态：设计稿（2026-11-02，P2「站内通知与提醒」轮次）。本轮**只交付设计与可执行清单，不实施**；邮件通道同样仅预留。
> 事实源：[CRW 规划](../../../docs/change-request-workbench-plan.md) §3 / §9 / §12；[architecture.md](architecture.md) §10。
> 使用约定：owner 取值 `Agent` / `Basis` / `User`；所有 `abap` 命令在 `apps/change-request-workbench/` 下执行；不写系统地址、账号、transport 号与真实业务数据。
> 关联：[runbook.md](runbook.md) §2 安装、§10 只读验证；[workflow.md](workflow.md) §8 导入计划、§9 通知。

---

## 1. 范围与结论摘要

本文覆盖 5 个 basis 类项的设计与可执行清单，外加通知/提醒落地所依赖的 SMTP 与 SM36 前置。**本轮均不实施**：站内通知、提醒报表已交付，basis 类项按试点与跨系统部署需求再启动。

| # | 项 | 长期编号 | 本轮工作项 | 本轮结论 | owner | 前置 |
|---|---|---|---|---|---|---|
| 1 | 可传输包迁移 | A19 | A3 | **暂不做**，保持 `$CRW` 本地包（不可跨系统部署） | Basis + Agent | 跨系统部署需求确认 |
| 2 | 二级索引 | A20 / D20 | D2 | **后置**（abap-cli 无索引入口，需 SAP GUI / DB02） | Agent + Basis | 包迁移完成 + 慢查询证据 |
| 3 | 数据归档 | A18 | — | **只出设计**（HIST / LOG / NOTIFY 按年） | Basis + Agent | SARA / AOBJ 与存储、保留期确认 |
| 4 | 权限对象 | A8 | — | **只出设计**（`Z_CRW_ACT` + 角色映射） | Basis | SU21 / PFCG 权限 |
| 5 | Fiori / FLP | D22 | — | **不采用**，保留事务码 `ZCRW`；FLP 走 URL tile 为可选项 | Basis（可选） | FLP 已启用 |
| 6 | SMTP / SM36 | — | — | 只出前置清单；本轮不配 SMTP、不建作业定义 | Basis | SCOT / SM36 权限 |

编号说明：`A19` / `A20` / `A18` / `A8` 是 [architecture.md](architecture.md) §10 的架构决议编号；`D20` / `D22` 是规划 §12 的决策编号；`A3` / `D2` 是本轮 P2 工作分派的工作项标记。同一项可能同时出现多个编号，**执行以本文各节结论为准**。

---

## 2. 可传输包迁移（A19；本轮工作项 A3）

| 项 | 内容 |
|---|---|
| owner | Basis 主导（SE21/SE80 + SE03）；Agent 配合复核与回归 |
| 前置 | 目标 landscape 与 transport layer 由 Basis 确认；对象与数据已备份；本轮不 release transport |
| 事务码 | `SE21` / `SE80`（建包）、`SE03`（重指派）、`SE09` / `SE10`（只查看，不释放） |
| 验收 | 对象 `TADIR.DEVCLASS` 指向 `ZCRW_PKG`，`abap transport check` 抽样 recording 非空，selfcheck / 单测 / smoke 通过 |
| 风险 | 误 release transport、对象锁、MIME/ICF 重指派后需重新激活；本地包短暂不可用 |

### 2.1 现状（2026-11-02）

| 检查项 | 现状 | 只读核对 |
|---|---|---|
| 应用包 | `$CRW`：`PARENTCL = $TMP`、`DLVUNIT = LOCAL`、`KORRFLAG` 空（本地包，无传输） | `abap select --table TDEVC --where "DEVCLASS = '\$CRW'" --json` |
| 包内对象 | `TADIR` **113** 项（M5 后实测；M5 前基线 108） | `abap select --table TADIR --where "DEVCLASS = '\$CRW'" --count-only --json` |
| transport 记录 | `abap transport check` 的 `data.recording` 为空（本地包不记录对象变更） | `abap transport check ZCL_CRW_NOTIFY --json` |
| 部署边界 | 不可通过 CTS 部署到 QA / 生产；换系统需按 runbook §2 重装 | [runbook.md](runbook.md) §1.2 |

> shell 中 `$` 是变量前缀：查 `$CRW` 时把 where 值写成 `'\$CRW'`（双引号内转义），或改用单引号拼接，避免被 shell 展开成空串。

### 2.2 目标形态

- 新建**顶层可传输包** `ZCRW_PKG`（命名沿用 `ZCRW_` 前缀；≤30 字符），super package 为与目标组件匹配的顶层包（如客户命名空间的顶层包），`KORRFLAG = X`。
- 原 `$CRW` 下全部对象重指派到 `ZCRW_PKG`；之后的对象变更都由传输请求记录，可经 CTS 部署到 QA / 生产。
- 包迁移不改变对象名与对象内容；AFF 仍是代码唯一来源，迁移后继续按 runbook 的 `check syntax` → `push` → `inspect --activation` 维护。

### 2.3 执行路径（Basis 主导，按序）

| 步 | 动作 | 说明 |
|---|---|---|
| M1 | 确认目标包命名与 transport layer | 由 Basis 按目标组件/命名空间确定；写入《迁移记录》，不入库真实系统信息 |
| M2 | `SE21`（或 `SE80`）创建顶层可传输包 `ZCRW_PKG` | 选择 transport layer 与 software component；记录到一个请求，**只记录不释放** |
| M3 | `SE03` → Transport Organizer Tools → 对象重指派 | 按对象组分批（DDIC → 类/接口 → 程序 → 号段/锁/消息类 → ICF/MIME → 事务码），每批后核对 `TADIR`；避免一次全包选中 |
| M4 | 重激活对象 | ICF 节点与 MIME 资产按 runbook §2.8 / §2.10 重新激活/重推；类用 `abap inspect --activation` 确认 |
| M5 | 回归 | 按 §2.6 执行；通过后由 Basis 决定何时 release / 走哪个传输链 |
| M6 | 回写文档 | 包名变化要同步 `AGENTS.md` §4A.3、规划 §10.3、runbook §1.1 / §2、README 的包与部署边界表述（本轮不实施，故本轮不改） |

### 2.4 abap-cli 限制（决定了迁移不能全自动）

| 限制 | 影响 | 处理 |
|---|---|---|
| `abap create DEVC` 必须指定父包，且只能建在 HOME 组件的可传输包下 | 不能在 CLI 一步建「顶层」`ZCRW_PKG` | 顶层包由 Basis 用 SE21/SE80 建 |
| `abap push` 无 `--package` 参数 | 推送不能改对象归属包 | 归属变更只走 SE03 |
| `abap transport assign` 只把对象挂到请求，不改 `TADIR.DEVCLASS` | 不能替代包重指派 | 迁移期间不用它「顺便迁移」；assign 仅用于请求归集 |
| CLI 无批量包重指派命令 | 100+ 个对象需人工分组执行 | 按 §2.3 M3 分批，批次间只读核对 |

### 2.5 风险与回滚

- **禁止 release transport**：迁移期间只记录对象变更；release / 导入由 Basis 按发布流程单独执行。
- **对象锁**：重指派前用 `abap inspect <对象> --locks --json` 只读确认；有编辑锁时等释放，不强杀。
- **MIME / ICF**：MIME 资产与 ICF 节点重指派后可能出现「类运行时缓存过期」，按 runbook §2.8 再 `abap activate ZCL_CRW_HTTP_HANDLER --yes --json`；MIME 按 §2.10 重推一层并验证 200。
- **回滚**：把对象从 `ZCRW_PKG` 重指派回 `$CRW`（同样 SE03），已记录未释放的请求保留；AFF 重推上一版本代码；业务数据不动。回滚后按 §2.6 复验。
- **不可回滚项**：已释放的传输、已导入的目标系统对象（与 CTS 边界一致，见 workflow §7）。

### 2.6 验收命令（只读，迁移后执行）

```bash
cd apps/change-request-workbench

# 1) 包属性：KORRFLAG=X、DLVUNIT 不再为 LOCAL
abap select --table TDEVC --where "DEVCLASS = 'ZCRW_PKG'" --json

# 2) 归属：ZCRW_PKG 对象数 ≈ 迁移前基线（TADIR 113 项（M5 后实测），+ 包对象本身），$CRW 只剩包对象
abap select --table TADIR --where "DEVCLASS = 'ZCRW_PKG'" --count-only --json
abap select --table TADIR --where "DEVCLASS = '\$CRW'" --count-only --json

# 3) 抽样 transport 记录：data.recording 非空（全量按 TADIR 清单逐对象执行）
abap transport check ZCRW_NOTIFY --json
abap transport check ZCL_CRW_NOTIFY --json
abap transport check ZCRW_REMIND_JOB --json

# 4) 回归
abap run ZCL_CRW_SELFCHECK --json
abap test ZCL_CRW_NOTIFY --json
abap run ZCL_CRW_M1_SMOKE --json
```

期望：包属性与对象归属符合 §2.2；`abap transport check` 的三条抽样 `data.recording` 均为非空 transport 号（**具体值不写入文档**）；selfcheck `CRW_SELFCHECK_OK tables=14 … icf=OK cts=OK`；单测与 smoke 通过。本轮决策 A3 暂不做（保持 `$CRW` 本地包），迁移命令未执行；基线只读核对：`$CRW` DLVUNIT=LOCAL、KORRFLAG 空、`abap transport check` 返回 `recording=""`。

### 2.7 决策与重启条件

- **本轮决策（工作项 A3）：暂不做**。当前只服务 test 环境试点，`$CRW` 本地包免 transport、写路径稳定；迁移会引入 SE03 批量重指派与 ICF/MIME 重激活的回归面，收益不足以覆盖本轮风险。
- **重启条件**（满足任一）：① 需要部署到 QA / 生产；② 试点扩展到其他 client / 系统；③ 需要以 CTS 管理版本与回退；④ 需要 basis 按发布流程审计对象变更。
- 重启时先做灰度：选 1 个类 + 1 张表 + 1 条 MIME 资产试迁移，按 §2.6 复验后再全量。迁移完成后，本文 §3 的索引也应在新包内创建（索引是 DDIC 对象，随包传输）。

---

## 3. 二级索引（A20 / D20；本轮工作项 D2）

| 项 | 内容 |
|---|---|
| owner | Agent 给出清单与验证；Basis 执行 SE11 / DB02（需 DDIC 权限） |
| 前置 | 包迁移完成（索引随包传输）；有慢查询 / 压测证据，不凭猜测建索引 |
| 事务码 | `SE11`（建索引）、`DB02` / `ST04` / `SQLM`（验证）、`SE14`（必要时重建） |
| 验收 | 索引在 `DD12L` 可见且激活；典型查询不因索引变慢；表行数 / 存储可接受 |
| 风险 | 写放大与存储增长；无效索引不加速；DDIC 变更需传输 |

### 3.1 建议索引清单（按查询路径）

| 表 | 建议索引字段 | 支撑查询（API / 页面） | 优先级 |
|---|---|---|---|
| `ZCRW_REQ` | `STATUS` | 请求列表按状态筛选、报表分布 | 高 |
| `ZCRW_REQ` | `OWNER` | 我的工作 / 负责人筛选 | 高 |
| `ZCRW_REQ` | `REQUESTER` | 我的请求 | 高 |
| `ZCRW_REQ` | `CYCLE_ID` | 按周期筛选、导入清单 | 中 |
| `ZCRW_REQ` | `CREATED_AT` | 列表默认 `createdAt desc`、趋势报表 | 高 |
| `ZCRW_CD` | `REQ_ID` | CR 详情下 CD 列表 | 高 |
| `ZCRW_TASK` | `ASSIGNEE` | 我的任务、逾期扫描 | 高 |
| `ZCRW_TASK` | `STATUS` | 任务列表 / 看板 | 中 |
| `ZCRW_TASK` | `DUE_DATE` | 逾期任务扫描（`ZCRW_REMIND_JOB`） | 高 |
| `ZCRW_SCHED` | `STATUS` | 计划列表、逾期扫描 | 高 |
| `ZCRW_SCHED` | `SCHEDULED_AT` | 按日期视图、逾期扫描 | 高 |
| `ZCRW_HIST` | `OBJECT_TYPE` + `OBJECT_ID` | 对象历史 / 审计查询 | 高 |
| `ZCRW_NOTIFY` | `USER_ID` + `STATUS` + `CREATED_AT` | 通知列表、未读数、扫描去重（P2 新增表，建议同一批评估） | 中 |

说明：

- 单字段索引与复合索引按实际执行计划取舍；上表是候选，不是一次性全部创建。
- `ZCRW_NOTIFY` 的 `DEDUP_KEY` 去重查询按 `USER_ID + DEDUP_KEY`，量级判断后再决定是否加复合索引（通知表按年归档，见 §4）。
- `ZCRW_HIST` 的 `OBJECT_ID` 已按对象编号回查，`OBJECT_TYPE + OBJECT_ID` 复合索引优先于两个单列索引。

### 3.2 SE11 步骤

1. `SE11` 打开目标表 → 菜单/按钮进入索引维护，新建二级索引（命名 `ZCRW_<表>~Z01`、`Z02`…）。
2. 选择索引字段与顺序（区分度高的列在前；范围查询列放最后）；保存到传输请求（只记录，不释放）。
3. 激活索引；`DB02` / `SE14` 确认数据库层索引已建。
4. 每个索引单独创建、单独验证，避免一次批量改动无法定位问题。

### 3.3 验证方式（只读）

```bash
cd apps/change-request-workbench

# 索引元数据（DD12L：二级索引头）
abap select --table DD12L --where "SQLTAB LIKE 'ZCRW%'" --json

# 受影响的典型查询（确认结果与性能可接受）
abap select --table ZCRW_REQ --where "STATUS = 'PENDING_APPROVAL'" --count-only --json
abap select --table ZCRW_TASK --where "ASSIGNEE <> '' AND STATUS <> 'DONE'" --count-only --json
abap select --table ZCRW_SCHED --where "STATUS = 'PLANNED'" --count-only --json
```

期望：`DD12L` 中能看到新建索引且状态为激活；查询结果与建索引前一致（`count` 一致）；用 `DB02` / `SQLM` 或压测脚本确认执行计划使用索引，本轮决策 D2 后置（CLI 无索引入口），未建索引、未采集执行计划；后续由人工在 SE11 执行后回填。

### 3.4 决策与风险

- **本轮决策（工作项 D2）：后置**。abap-cli 2.0.1 无建索引入口；当前 test 环境数据量小（业务表为演示 / 试点量级），先建索引没有收益，还会增加写路径与迁移面。
- **触发条件**：试点数据达到 1 万 CR / 5 万任务 / 2 万传输关联规模，或报表 / 列表出现秒级慢查询；先在 §3.3 采集证据，再按 §3.1 顺序逐批建。
- **回滚**：`SE11` 删除索引并激活（会删除数据库索引）；未 release 的请求可直接丢弃。

---

## 4. 数据归档（A18）

| 项 | 内容 |
|---|---|
| owner | Basis 主导（SARA / 归档存储 / 权限）；Agent 提供归档程序与在线窗口查询改造 |
| 前置 | 归档对象（AOBJ）已定义、归档存储可用、保留期经合规确认；在线查询按时间窗改造 |
| 事务码 | `AOBJ`（定义归档对象）、`SARA`（归档运行）、`SARI`（归档信息）、`SOST` / `SM37`（作业） |
| 验收 | 归档运行生成归档文件；在线表行数下降；历史 / 日志页面仍可查询在线窗口；还原（`SARA` reload）可用 |
| 风险 | 归档数据不可在线查询；删除不可恢复；与审计边界冲突 |

### 4.1 目标与在线窗口

| 表 | 归档键 | 建议在线窗口 | 说明 |
|---|---|---|---|
| `ZCRW_HIST` | `CHANGED_AT`（按年） | 建议保留 ≥ 3 年在线（最终以合规要求为准） | 业务审计主表；只追加、无删除入口 |
| `ZCRW_LOG` | `TIMESTAMP`（按年） | 12 个月 | 技术日志，面向排障；允许更短 |
| `ZCRW_NOTIFY` | `CREATED_AT`（按年） | 12 个月 | P2 新增；优先做**应用级清理**（已读 / 已忽略且超窗口）再评估归档 |

- 在线窗口内的数据保留在业务表；窗口外数据归档到归档存储并从在线表删除。
- `ZCRW_HIST` 的归档不改变审计边界（应用级审计 ≠ 合规级不可篡改，见 architecture §8.5 / workflow §10.5）。

### 4.2 SARA / AOBJ 前置条件

1. 归档对象：`AOBJ` 为每张表定义归档对象（如 `ZCRW_HIST` / `ZCRW_LOG` / `ZCRW_NOTIFY`），维护表清单、写程序、删除程序、读程序。
2. 归档存储：Basis 提供 ADK 文件存储（文件系统 / 归档存储方案），并确认保留期与存储容量。
3. 权限：执行用户需要 `S_ARCHIVE` / `S_DATASET` 等归档权限；生产执行需变更审批。
4. 作业：归档运行（写 + 删除）通过 `SM36` 后台作业执行，建议每月一次；结果在 `SARI` / `SM37` 核对。
5. 在线改造：历史 / 日志 / 通知页面只查在线表，需在 UI 明确「仅显示在线窗口内数据」，避免用户误以为数据丢失。

### 4.3 程序清单（规划，命名待评审）

| 归档对象 | 写程序 | 删除程序 | 读程序 |
|---|---|---|---|
| `ZCRW_HIST` | `ZCRW_ARCH_WRITE_HIST` | `ZCRW_ARCH_DELETE_HIST` | `ZCRW_ARCH_READ_HIST` |
| `ZCRW_LOG` | `ZCRW_ARCH_WRITE_LOG` | `ZCRW_ARCH_DELETE_LOG` | `ZCRW_ARCH_READ_LOG` |
| `ZCRW_NOTIFY` | `ZCRW_ARCH_WRITE_NOTIFY` | `ZCRW_ARCH_DELETE_NOTIFY` | `ZCRW_ARCH_READ_NOTIFY` |

- 程序类型为 `PROG`，ABAP 按 abap-style 的过程式约定（`REPORT` / `FORM`）；归档程序必须由 Basis 先在 `AOBJ` 注册后才能被 `SARA` 调用。
- 命名、参数（选择屏幕：日期区间 / 测试模式）在实施时冻结；测试模式（不删除）先跑通再开删除。
- 若 `ZCRW_NOTIFY` 先做应用级清理：由 `ZCL_CRW_NOTIFY` 增加「清理超窗口已读通知」的一次性 classrun（写数据，属运维步骤），不进入只读验证清单。

### 4.4 保留期与风险

- 保留期最终由合规 / 审计要求确认；本文给的是工程建议值，不是合规结论。
- 归档删除前必须生成可还原的归档文件；`SARA` 的删除运行不可回滚。
- 归档期间表被业务读写：按对象加锁（`EZCRW_REQ` / `EZCRW_CD` 或归档对象自身的锁定），避免边写边删。
- 与报表冲突：报表默认 90 天窗口（architecture §5.7），归档窗口必须 ≥ 报表窗口。

### 4.5 本轮决策

**只出设计，不实现。** `ZCRW_HIST` / `ZCRW_LOG` 当前数据量小，尚无归档价值；先按 §4.3 完成 AOBJ 注册与测试模式验证，再开删除。触发条件：任一表行数 > 100 万或在线窗口 > 2 年，或 basis 存储告警。

---

## 5. 权限对象（A8）

| 项 | 内容 |
|---|---|
| owner | Basis 主导（SU21 / PFCG / SU01）；Agent 提供服务层 `AUTHORITY-CHECK` 接入设计 |
| 前置 | SU21 权限对象维护权限；PFCG 角色与用户分配；灰度开关（只记录不拦截） |
| 事务码 | `SU21`（定义权限对象）、`PFCG`（角色）、`SU01`（用户）、`SU53`（权限失败分析） |
| 验收 | 授权用户可操作、未授权用户被 `FORBIDDEN`；`SU53` 无意外权限失败；灰度期日志可回放 |
| 风险 | 配置错误导致全员 403；权限对象需传输；与现有应用角色重复 |

### 5.1 建议权限对象与字段

| 权限对象 | 字段 | 取值建议 | 说明 |
|---|---|---|---|
| `Z_CRW_ACT` | `ACTVT` | `01` 创建 / `02` 修改 / `03` 显示 / `16` 执行 / `06` 删除（不复用） | 标准活动字段 |
| `Z_CRW_ACT` | `REQ_TYPE` | `STD` / `URG` / `ADM`（可空 = 任意） | 请求类型维度 |
| `Z_CRW_ACT` | `OBJECT` | `REQ` / `CD` / `TASK` / `TR` / `SCHED` / `NOTIFY` / `CONFIG` | 对象类型维度 |

- 权限对象名 `Z_CRW_ACT`（≤30 字符，命名空间 `Z`）；由 basis 在 `SU21` 创建，Agent 不通过 CLI 创建（abap-cli 不支持 AUTH）。
- 字段组合按实际需要收敛，避免权限矩阵爆炸：v1 建议「活动 + 对象类型」两维，`REQ_TYPE` 仅对 `REQ` 对象生效。

### 5.2 角色映射

| 应用角色 | `ACTVT` | `OBJECT` | 数据范围（沿用应用角色表） |
|---|---|---|---|
| `REQUESTER` | `01` / `03` | `REQ` | 自己的请求 |
| `CHANGE_MANAGER` | `01` / `02` / `03` | `REQ` / `CD` / `TASK` / `SCHED` | 全部 |
| `DEVELOPER` | `02` / `03` | `CD` / `TASK` / `TR` | 指派给本人的任务 / CD |
| `TESTER` | `02` / `03` | `CD` / `TASK` | 指派给本人的测试任务 |
| `RELEASE_MANAGER` | `02` / `03` | `TR` / `SCHED` | 全部 transport 与计划 |
| `ADMIN` | `01` / `02` / `03` / `16` | 全部 | 全部 |
| `VIEWER`（P2） | `03` | 全部 | 按组件 / 周期 |

### 5.3 与现有 `ZCL_CRW_AUTH` 的关系

- **两层判定，后者不取代前者**：SAP 标准权限（`Z_CRW_ACT`）决定「该用户能否操作这类对象」；应用角色表（`ZCRW_ROLE` + `ZCL_CRW_AUTH`）决定「业务角色与数据范围」。
- 服务层顺序建议：`AUTHORITY-CHECK`（权限对象）→ 应用角色 / 数据范围校验 → 状态机与守卫。任一失败返回 `FORBIDDEN` / `APPROVER_MISMATCH` / `SELF_APPROVAL`。
- 未配置权限对象时保持 v1 行为（不做 `AUTHORITY-CHECK`，依赖 SAP 登录 + 应用角色）；启用后必须给所有试点用户配齐角色，否则会被拒绝。
- 通知相关：`NOTIFY` 对象的 `03`（显示）/`02`（标记已读）作用于本人通知，服务层已按 `USER_ID` 过滤，权限对象是外层防线。

### 5.4 SU21 / PFCG / SU01 步骤

1. `SU21` 创建权限对象 `Z_CRW_ACT`，维护 `ACTVT` / `REQ_TYPE` / `OBJECT` 字段与取值文档。
2. `PFCG` 按 §5.2 建单角色（如 `Z_CRW_REQUESTER`、`Z_CRW_CHANGE_MANAGER`），在「权限」页签添加 `Z_CRW_ACT` 授权，生成权限参数文件。
3. `SU01` 给试点用户分配角色；用 `SU53` 验证一次越权用例（预期出现 `Z_CRW_ACT` 的授权失败）。
4. 灰度：服务层先「只记录不拦截」（`AUTHORIZATION` 失败写 `ZCRW_LOG`，不返回 403），观察 1–2 周后切为强校验。
5. 权限对象与角色变更随传输请求发布；不 release 前先在 test 环境演练回滚。

### 5.5 灰度与回滚

- 灰度开关建议用 `ZCRW_VERSION` / 迁移里写的配置行或代码常量控制，避免依赖 SAP 参数。
- 回滚：关闭强校验开关，退回 v1 行为；权限对象保留但不拦截；`SU53` 与 `ZCRW_LOG` 留证。
- 不要在生产环境首次启用时直接强校验；先在 test 用 2–3 个真实角色走完整流程。

### 5.6 本轮决策

**只出设计，不实施。** abap-cli 不支持 AUTH 对象；当前试点依赖 SAP 登录 + 应用角色（A8 口径），没有生产级授权要求前不引入权限对象。

---

## 6. Fiori / FLP（D22）

| 项 | 内容 |
|---|---|
| owner | Basis（FLP 配置）；Agent 提供入口 URL 与说明 |
| 前置 | 目标系统已启用 Fiori Launchpad；用户有 FLP 角色；ICF 节点在 FLP 会话下可访问 |
| 事务码 / 工具 | `/UI2/FLPD_CUST`（Launchpad Designer）、`/UI2/FLP`；SAP Fiori 配置由 basis 维护 |
| 验收 | tile 点击打开工作台首页；SSO 生效、无二次登录；URL 不写死在仓库 |
| 风险 | FLP 与 ICF 会话域不一致导致二次登录；URL 写死系统地址；描述符维护成本 |

### 6.1 现状

- 入口是事务码 `ZCRW`（报表事务 → `ZCRW_START`，运行时拼出系统 URL 并打开 ICF 节点 `/sap/bc/zcrw/`），见 architecture §7.5。
- 应用是 ICF + MIME 托管的独立 SPA，不是 Fiori app，没有 `manifest.json` / OData 服务。

### 6.2 可选路径

| 路径 | 成本 | 适用 | 本轮结论 |
|---|---|---|---|
| A. FLP URL tile（tile 直接指向 `/sap/bc/zcrw/`） | 低：basis 在 Launchpad Designer 配一个 URL tile | 用户希望从 FLP 一键进入 | **可选**，仅当 basis 明确要求时做 |
| B. target mapping / intent + 应用描述符 | 高：需描述符、semantic object、FLP 配置 | 需要 intent 导航 / 跨应用跳转 | **不做**，收益低 |
| C. 保持事务码 `ZCRW` | 无 | 当前 SOP | **采用**，作为主入口 |

### 6.3 结论

- **保持事务码作为主入口**，SOP 与文档继续写 `ZCRW`；FLP 仅在 basis 要求时走路径 A（URL tile），不建应用描述符。
- URL tile 的地址由 basis 在目标系统配置，仓库只写相对路径说明，不写主机名 / client。
- 若未来要做 Fiori Elements / intent 导航，属于形态变更（需评估 OData / RAP），不在 P2 范围。

### 6.4 验收与风险

- 验收：FLP 中点击 tile 打开 `/sap/bc/zcrw/` 首页且 SSO 生效；直接访问深链（如 `#/notifications`）仍可用；桌面 / 移动端不承诺。
- 风险：FLP 域与 ICF 域不同会导致二次登录（由 basis 统一 SSO 配置）；tile 配置错误可能指向旧路径，需版本变更时同步。

---

## 7. 通知 / 提醒相关的 basis 前置（SMTP / SM36）

> 本节是 P2 通知交付（站内通知已落地、邮件仅预留）的 basis 前置，不属于上述 5 个长期项；本轮不配置。

### 7.1 SMTP（SCOT）——邮件通道预留

| 项 | 内容 |
|---|---|
| 现状 | `ZCL_CRW_NOTIFY=>deliver_email` 已预留；SMTP 未配置，**不发信**，站内通知照常落库 |
| owner | Basis |
| 前置 | `SCOT` 中配置 SMTP 节点（服务器 / 端口 / 认证 / 默认域）；用户 `SU01` 通讯数据有邮箱；出站防火墙放行 |
| 启用步骤 | 1) basis 配好 SMTP 并发送测试邮件；2) Agent 把 `deliver_email` 的占位实现替换为 BCS 发送（`cl_bcs`）；3) 发送失败只写 `ZCRW_LOG`，不阻塞站内通知与业务动作 |
| 验收 | 测试用户收到通知邮件；`SOST` 队列无积压；未配置邮箱的用户降级为仅站内通知 |
| 风险 | 邮件风暴 / 域策略拦截；发送在业务事务内会拖慢接口 → 必须异步 / 队列化 |

### 7.2 后台作业（SM36）——`ZCRW_REMIND_JOB` 定时扫描

| 项 | 内容 |
|---|---|
| 现状 | 报表 `ZCRW_REMIND_JOB` 已交付；**本轮不创建作业定义**，不配 SMTP |
| owner | Basis（建作业）/ Agent（报表维护） |
| 前置 | 报表已激活；执行用户有 `ZCRW_*` 表读 / 写权限与 `ZCRW_NOTIFY` 写权限；作业用户建议用专用批处理用户（用户类型与授权由 basis 确认） |
| 启用步骤 | 按 [runbook.md](runbook.md) §2.13「通知与后台作业（SM36）」创建每日作业（建议 07:00，job 名 `ZCRW_REMIND`） |
| 验收 | `SM37` 中作业 `Finished`；报表输出 `ZCRW_REMIND_JOB_OK approvals=… tasks=… schedules=… total=…`；通知中心出现新通知 |
| 风险 | 夜间扫描与在线请求争用锁；重复执行产生重复通知 → 由 `dedup_key` 去重兜底（见 workflow §9.3） |

---

## 8. 通用启动与回滚约定

| 项 | 约定 |
|---|---|
| 启动顺序 | 包迁移（§2）→ 索引（§3）→ 权限对象（§5）→ 归档（§4）；SMTP / SM36 独立于这四项，可随时启用 |
| 环境 | 只在 dev / test 演练；生产由 basis 按发布流程执行，应用侧不直接连生产 |
| 备份 | 迁移 / 归档前按 runbook §8.1 只读导出；备份文件只放 `tmp/`，不入库 |
| 记录 | 每项实施后回写本文与 runbook 的对应小节；实测值由 Lead 回填，不写未验证结论 |
| 回滚 | 包迁移回退重指派；索引删除并激活；权限对象关闭强校验；归档走 `SARA` 还原，删除不可回滚 |

### 8.1 待剥离依赖（实施时处理）

- 包迁移后需要同步更新：`AGENTS.md` §4A.3（包与写路径）、规划 §10.3、runbook §1.1 / §2、README 的部署边界；这些改动不在本轮文档范围内，迁移实施时统一做。
- 权限对象 / 归档程序 / 邮件发送都涉及 ABAP 代码变更，必须在同一变更内回写 relevant runbook 与 selfcheck / 单测，不静默偏差（AGENTS.md §2.12）。

---

## 9. 参考

- [CRW 规划](../../../docs/change-request-workbench-plan.md)：范围、里程碑、决策记录。
- [architecture.md](architecture.md)：数据模型、API、部署边界、A8/A18–A20 决议。
- [workflow.md](workflow.md)：导入计划（§8）、通知（§9）、审计边界（§10）。
- [runbook.md](runbook.md)：安装 / 升级 / SM36 / 只读验证。
- [`AGENTS.md`](../../../AGENTS.md) §4A：应用单元契约；§8：安全边界。
