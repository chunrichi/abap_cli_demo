#!/usr/bin/env bash
# check-secrets.sh — abap_cli_demo 提交/推送前的本地敏感信息扫描
#
# 特性：只读、无网络、不修改工作区与 Git 索引。
# 用法：bash scripts/check-secrets.sh
#
# 检查项：
#   1. 工作区状态与未跟踪文件 —— 只报告，不参与判定（新文件提交前本该存在）
#   2. 已跟踪文件中的敏感文件名/危险目录 —— 命中即阻断
#   3. 已跟踪文件内容：RFC1918 私网地址、凭证赋值、transport 号形态 —— 命中即阻断；
#      凭证关键词提及 —— 只提示，人工确认
#   4. 历史提交：git log -G 查私网地址/凭证赋值/transport 号形态（命中即阻断）；
#      git log -S 查凭证关键词提及（只提示，人工确认）
#   5. 已跟踪 blob 最大 < 500 KB；截图超过 500 KB 告警
#
# 白名单：
#   - .agents/skills/** 为 abap-cli 生成物（含 CLI 文档里的占位示例与关键词），跳过内容与历史扫描
#   - 文档示例 transport 号 DEVK900001 / QASK900123 / NDK123456 为占位形态，不阻断
#   - 本脚本自身（scripts/check-secrets.sh）不因文件名含 "secret" 被判为敏感文件
#   - 凭证关键词的文档/代码性提及只提示不阻断；只有赋值形态才阻断
#   - 未跟踪文件只报告，避免把待提交的新文件误判为违规
#
# 退出码：0 = 无阻断项；1 = 存在阻断项；2 = 环境错误（不是 Git 仓库等）。

set -u

MAX_BLOB_BYTES=$((500 * 1024))

# RFC1918 私网地址（10/8、172.16/12、192.168/16），前后避免匹配到更长数字
PRIVATE_IP_RE='(^|[^0-9.])(10\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}|192\.168\.[0-9]{1,3}\.[0-9]{1,3}|172\.(1[6-9]|2[0-9]|3[01])\.[0-9]{1,3}\.[0-9]{1,3})([^0-9.]|$)'
# 凭证赋值形态：password = xxx / token: xxx 等；仅提示性词不算
CRED_ASSIGN_RE='(password|passwd|pwd|secret|auth[_-]?token|api[_-]?key|access[_-]?key|private[_-]?key)[[:space:]]*[:=][[:space:]]*[^[:space:]]{6,}'
# transport 号形态：DEVK900001 / NDK123456 等
TRANSPORT_RE='(^|[^A-Z0-9])[A-Z]{2,4}K[0-9]{6,}'
PLACEHOLDER_TRANSPORTS='DEVK900001|QASK900123|NDK123456'
# 凭证关键词：文档/代码中的普通提及只提示，不阻断（赋值形态由 CRED_ASSIGN_RE 阻断）
CRED_KEYWORD_RE='(password|passwd|secret|cookie|credential|token)'
# 已跟踪文件里的敏感文件名与危险目录（.abap.json.template 单独放行）
SENSITIVE_NAME_RE='(^|/)(\.abap\.json|\.env(\.[^/]*)?|\.npmrc|\.netrc|id_rsa[^/]*|[^/]*\.(pem|key|p12|pfx|log)|[^/]*cookie[^/]*|[^/]*password[^/]*|[^/]*secret[^/]*|credentials?(\.[^/]*)?)$|(^|/)(tmp|\.abap-cli|node_modules|logs)/'
SKIP_PATHS=':(exclude).agents/skills/**'

FAIL_COUNT=0
WARN_COUNT=0

section() { printf '\n=== %s ===\n' "$*"; }
ok() { printf '  [通过] %s\n' "$*"; }
note() { printf '  [提示] %s\n' "$*"; }
warn() {
  WARN_COUNT=$((WARN_COUNT + 1))
  printf '  [告警] %s\n' "$*"
}
fail() {
  FAIL_COUNT=$((FAIL_COUNT + 1))
  printf '  [失败] %s\n' "$*"
}
indent() { sed 's/^/    /'; }

usage() {
  awk 'NR > 1 { if ($0 == "set -u") exit; sub(/^# ?/, ""); print }' "$0"
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || REPO_ROOT=""
if [ -z "$REPO_ROOT" ]; then
  printf '错误：当前目录不在 Git 仓库内，无法扫描。\n' >&2
  exit 2
fi
cd "$REPO_ROOT" || exit 2

BRANCH=$(git branch --show-current 2>/dev/null || true)
[ -n "$BRANCH" ] || BRANCH='(detached HEAD)'
TRACKED_COUNT=$(git ls-files | wc -l | tr -d ' ')

printf 'abap_cli_demo 敏感信息扫描（只读，无网络）\n'
printf '仓库：%s\n分支：%s  已跟踪文件：%s\n' "$REPO_ROOT" "$BRANCH" "$TRACKED_COUNT"

section '1. 工作区状态（只报告）'

STATUS_SHORT=$(git status --short 2>/dev/null || true)
if [ -z "$STATUS_SHORT" ]; then
  note '工作区 clean'
else
  note '存在未提交变更（提交前人工确认范围）：'
  printf '%s\n' "$STATUS_SHORT" | indent
fi

UNTRACKED=$(git ls-files --others --exclude-standard 2>/dev/null || true)
if [ -n "$UNTRACKED" ]; then
  UNTRACKED_TOTAL=$(printf '%s\n' "$UNTRACKED" | wc -l | tr -d ' ')
  note "未跟踪文件 ${UNTRACKED_TOTAL} 个（只报告，不参与敏感判定；提交前确认是否应入库）："
  printf '%s\n' "$UNTRACKED" | head -n 20 | indent
  if [ "$UNTRACKED_TOTAL" -gt 20 ]; then
    note "…其余 $((UNTRACKED_TOTAL - 20)) 个未跟踪文件省略"
  fi
else
  note '无未跟踪文件'
fi

for local_path in .abap.json .env .abap-cli tmp node_modules; do
  [ -e "$local_path" ] || continue
  if git check-ignore -q -- "$local_path" 2>/dev/null; then
    note "本地 ${local_path} 存在且已被 .gitignore 忽略（正常）"
  else
    fail "本地 ${local_path} 存在但未被 .gitignore 忽略，禁止提交"
  fi
done

section '2. 已跟踪敏感文件名'

NAME_HITS=$(git ls-files \
  | grep -E -e "$SENSITIVE_NAME_RE" \
  | grep -v -E -e '(^|/)\.abap\.json\.template$' -e '(^|/)check-secrets\.sh$' \
  || true)
if [ -z "$NAME_HITS" ]; then
  ok '未发现敏感文件名/危险目录'
else
  fail "已跟踪敏感文件名/危险目录 $(printf '%s\n' "$NAME_HITS" | wc -l | tr -d ' ') 处"
  printf '%s\n' "$NAME_HITS" | indent
fi

section '3. 已跟踪文件内容'

PRIVATE_IP_HITS=$(git grep -n -I -E -e "$PRIVATE_IP_RE" -- . "$SKIP_PATHS" 2>/dev/null || true)
if [ -z "$PRIVATE_IP_HITS" ]; then
  ok '私网地址（RFC1918）：未命中'
else
  fail "私网地址（RFC1918）命中 $(printf '%s\n' "$PRIVATE_IP_HITS" | wc -l | tr -d ' ') 处"
  printf '%s\n' "$PRIVATE_IP_HITS" | indent
fi

CRED_HITS=$(git grep -n -I -E -e "$CRED_ASSIGN_RE" -- . "$SKIP_PATHS" 2>/dev/null || true)
if [ -z "$CRED_HITS" ]; then
  ok '凭证赋值形态：未命中'
else
  fail "凭证赋值形态命中 $(printf '%s\n' "$CRED_HITS" | wc -l | tr -d ' ') 处"
  printf '%s\n' "$CRED_HITS" | indent
fi

TRANSPORT_HITS=$(git grep -n -I -E -e "$TRANSPORT_RE" -- . "$SKIP_PATHS" 2>/dev/null || true)
TRANSPORT_REAL=''
if [ -n "$TRANSPORT_HITS" ]; then
  while IFS= read -r hit_line; do
    [ -n "$hit_line" ] || continue
    STRIPPED=$(printf '%s' "$hit_line" | sed -E "s/($PLACEHOLDER_TRANSPORTS)/__PLACEHOLDER__/g")
    if printf '%s' "$STRIPPED" | grep -q -E -e "$TRANSPORT_RE"; then
      TRANSPORT_REAL="${TRANSPORT_REAL}${hit_line}"$'\n'
    fi
  done <<< "$TRANSPORT_HITS"
fi
if [ -z "$TRANSPORT_HITS" ]; then
  ok 'transport 号形态：未命中'
elif [ -z "$TRANSPORT_REAL" ]; then
  note 'transport 号形态：仅命中占位示例（DEVK900001 / QASK900123 / NDK123456），不阻断'
else
  TRANSPORT_REAL_COUNT=$(printf '%s' "$TRANSPORT_REAL" | grep -c -E -e "$TRANSPORT_RE" || true)
  fail "transport 号形态命中 ${TRANSPORT_REAL_COUNT} 处"
  printf '%s' "$TRANSPORT_REAL" | indent
fi

CRED_KEYWORD_HITS=$(git grep -n -I -i -E -e "$CRED_KEYWORD_RE" -- . "$SKIP_PATHS" ':(exclude)scripts/check-secrets.sh' 2>/dev/null \
  | grep -v -e 'check-secrets\.sh' || true)
if [ -z "$CRED_KEYWORD_HITS" ]; then
  ok '凭证关键词提及：未命中'
else
  CRED_KEYWORD_TOTAL=$(printf '%s\n' "$CRED_KEYWORD_HITS" | wc -l | tr -d ' ')
  note "凭证关键词提及 ${CRED_KEYWORD_TOTAL} 处（提示，不阻断；文档/代码性提及由人工确认）："
  printf '%s\n' "$CRED_KEYWORD_HITS" | head -n 20 | indent
  if [ "$CRED_KEYWORD_TOTAL" -gt 20 ]; then
    note "…其余 $((CRED_KEYWORD_TOTAL - 20)) 处省略"
  fi
fi

section '4. 历史提交扫描'

history_scan() {
  local label="$1"
  local regex="$2"
  local entries entry hash subject hits filtered hit_line stripped

  entries=$(git log --all --format='%H %s' -G"$regex" -- . "$SKIP_PATHS" 2>/dev/null || true)
  if [ -z "$entries" ]; then
    ok "${label}：历史未命中"
    return 0
  fi

  local reported=0
  while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    hash=${entry%% *}
    subject=${entry#* }
    hits=$(git grep -n -I -E -e "$regex" "$hash" -- . "$SKIP_PATHS" 2>/dev/null || true)
    [ -n "$hits" ] || continue

    filtered=''
    while IFS= read -r hit_line; do
      [ -n "$hit_line" ] || continue
      stripped=$(printf '%s' "$hit_line" | sed -E "s/($PLACEHOLDER_TRANSPORTS)/__PLACEHOLDER__/g")
      if printf '%s' "$stripped" | grep -q -E -e "$regex"; then
        filtered="${filtered}${hit_line}"$'\n'
      fi
    done <<< "$hits"

    if [ -n "$filtered" ]; then
      reported=$((reported + 1))
      fail "${label}：提交 ${hash}（${subject}）"
      printf '%s' "$filtered" | indent
    fi
  done <<< "$entries"

  if [ "$reported" -eq 0 ]; then
    ok "${label}：历史未命中（仅占位示例）"
  fi
}

history_scan '私网地址（RFC1918）' "$PRIVATE_IP_RE"
history_scan '凭证赋值形态' "$CRED_ASSIGN_RE"
history_scan 'transport 号形态' "$TRANSPORT_RE"

# 关键词提及只提示：文档/注释里正常引用 password、cookie 等词不等同于泄漏。
KEYWORD_NOTED=0
for keyword in password passwd secret cookie token; do
  KEYWORD_COMMITS=$(git log --all --format='%h %s' -S"$keyword" -- . "$SKIP_PATHS" 2>/dev/null || true)
  if [ -n "$KEYWORD_COMMITS" ]; then
    note "历史提交提及关键词 \"${keyword}\"（提示，不阻断；仅为文档/注释性提及）："
    printf '%s\n' "$KEYWORD_COMMITS" | indent
    KEYWORD_NOTED=1
  fi
done
[ "$KEYWORD_NOTED" -eq 1 ] || ok '历史未出现凭证关键词提及'

section '5. 大文件'

BLOB_LIST=$(git rev-list --objects --all 2>/dev/null \
  | git cat-file --batch-check='%(objecttype) %(objectsize) %(rest)' 2>/dev/null \
  | awk '$1 == "blob" { print $2, $3 }' \
  | sort -rn)

if [ -z "$BLOB_LIST" ]; then
  ok '仓库暂无 blob'
else
  MAX_BLOB_LINE=$(printf '%s\n' "$BLOB_LIST" | head -n 1)
  MAX_BLOB_SIZE=${MAX_BLOB_LINE%% *}
  MAX_BLOB_PATH=${MAX_BLOB_LINE#* }
  printf '  最大 blob：%s B  %s\n' "$MAX_BLOB_SIZE" "$MAX_BLOB_PATH"
  printf '  最大的 5 个 blob：\n'
  printf '%s\n' "$BLOB_LIST" | head -n 5 | while IFS=' ' read -r size path; do
    printf '    %8s B  %s\n' "$size" "$path"
  done

  if [ "$MAX_BLOB_SIZE" -ge "$MAX_BLOB_BYTES" ]; then
    fail "存在已跟踪 blob ≥ 500 KB（最大 ${MAX_BLOB_SIZE} B）：${MAX_BLOB_PATH}"
  else
    ok '最大 blob < 500 KB'
  fi

  LARGE_BLOBS=$(printf '%s\n' "$BLOB_LIST" | awk -v max="$MAX_BLOB_BYTES" '$1 >= max')
  if [ -n "$LARGE_BLOBS" ]; then
    fail "已跟踪文件 ≥ 500 KB 的共 $(printf '%s\n' "$LARGE_BLOBS" | wc -l | tr -d ' ') 个"
    printf '%s\n' "$LARGE_BLOBS" | indent
  fi

  BIG_SHOTS=$(printf '%s\n' "$BLOB_LIST" | awk -v max="$MAX_BLOB_BYTES" '$1 >= max && $2 ~ /screenshots\//')
  if [ -z "$BIG_SHOTS" ]; then
    ok '截图均 ≤ 500 KB（AGENTS §4.5）'
  else
    warn '截图超过 500 KB，需压缩或裁剪（AGENTS §4.5）'
    printf '%s\n' "$BIG_SHOTS" | indent
  fi
fi

section '汇总'

if [ "$FAIL_COUNT" -eq 0 ]; then
  ok "无阻断项；告警 ${WARN_COUNT} 项。提交/推送前仍需人工确认未跟踪与本地忽略文件。"
  exit 0
fi

fail "共 ${FAIL_COUNT} 类阻断项、${WARN_COUNT} 类告警；按 CONTRIBUTING.md 处理后再提交/推送。"
exit 1
