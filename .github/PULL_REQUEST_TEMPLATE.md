## 变更点

<!-- 做了什么、为什么；涉及 demo 编号 / 应用 / 文档路径 -->

## 验证命令与结果

<!-- 只读命令 + 关键 JSON 字段摘要；不粘贴真实系统地址、账号、transport 号 -->

```bash
git status --short
bash scripts/check-secrets.sh
```

- [ ] `git status --short` 无意外新增（无 `.abap.json`、`tmp/`、日志、原始截图）
- [ ] `bash scripts/check-secrets.sh` 退出码 0（告警已人工确认）
- [ ] SAP 侧只读验证（如有）：`abap search|inspect|run|test|select ... --json` 的 `status` / `data.*` / `error.code` 摘要：
- [ ] 静态检查（如有）：`abap check content` / `abap validate:aff`；可选 `node scripts/check-demos.mjs`

## 截图影响（如有）

- [ ] 无 UI 变更
- [ ] UI 变更已重拍并替换 `screenshots/`，与当前 `src/` 行为一致
- [ ] 截图已脱敏（无系统地址、client、用户名、真实业务数据），单张 ≤ 500 KB

## 敏感信息与脱敏 checklist

- [ ] 未包含 `.abap.json`、`.env`、cookie、凭证、`tmp/`、日志
- [ ] 未包含内网地址 / RFC1918 私网 IP、SAP 用户名、真实 transport 号
- [ ] 未包含真实业务数据；截图与示例已脱敏
- [ ] `README.md`、`src/`、`screenshots/` 与根索引变更在同一 PR 内
- [ ] 提交信息符合 `CONTRIBUTING.md`；未 force push 已评审提交

## 关联 Issue

Closes #
