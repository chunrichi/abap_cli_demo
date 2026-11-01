---
name: Bug 报告
about: 报告 demo、应用或文档中的缺陷（可复现、可验证）
title: "[bug] "
labels: ["bug"]
assignees: ""
---

## 现象

<!-- 期望什么、实际什么；有 error.code 或关键 JSON 字段请附上 -->

## 复现步骤

1.
2.
3.

## 环境

- 仓库版本 / commit：
- demo 目录或应用：`demos/...` / `apps/...`
- abap-cli 版本（`abap --version`）：
- SAP 系统类型：dev / sandbox / trial（**不写**地址、client、账号）

## 验证命令与输出摘要

```bash
abap ... --json
```

关键字段（`status` / `error.code` / `data.*`）：

## 敏感信息确认

- [ ] 未包含 `.abap.json`、凭证、内网地址、SAP 用户名、真实 transport 号、真实业务数据
- [ ] 截图（如有）已脱敏

> 标签：本模板声明 `bug`；领域标签 `app/crw`、`demo`、`docs`、`chore` 已在仓库中创建，可按影响范围添加。
