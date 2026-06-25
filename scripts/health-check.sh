#!/bin/bash
# health-check.sh — OpenClaw agent 健康探测
# 用法: bash scripts/health-check.sh
# 返回: exit 0 = 健康, exit 1 = 异常
#
# 检测项 1-6 为 FAIL 项 (任一失败 => exit 1)
# 检测项 7-8 为 WARN 项 (仅警告, 不影响 exit code)

ERRORS=0
WARNINGS=0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MARK_FILE="$SCRIPT_DIR/../state/.health-failed"

echo "=== Health Check Start ==="

# 1. openclaw 进程
echo -n "[1/8] openclaw status... "
if openclaw status >/dev/null 2>&1; then
  echo "OK"
else
  echo "FAIL"
  ERRORS=$((ERRORS + 1))
fi

# 2. gateway 端口 18789
echo -n "[2/8] gateway port 18789... "
if curl -sf http://127.0.0.1:18789/ >/dev/null 2>&1; then
  echo "OK"
else
  echo "FAIL"
  ERRORS=$((ERRORS + 1))
fi

# 3. LiteLLM proxy 端口 40003
echo -n "[3/8] LiteLLM proxy port 40003... "
if curl -sf http://127.0.0.1:40003/v1/models >/dev/null 2>&1; then
  echo "OK"
else
  echo "FAIL"
  ERRORS=$((ERRORS + 1))
fi

# 4. feishu 配置存在
echo -n "[4/8] feishu channel config... "
if python3 -c "
import json
with open('/home/opc_uname/.openclaw/openclaw.json') as f:
    d = json.load(f)
    assert 'feishu' in d.get('channels', {})
" 2>/dev/null; then
  echo "OK"
else
  echo "FAIL"
  ERRORS=$((ERRORS + 1))
fi

# 5. 关键 skill 文件
echo -n "[5/8] critical skills... "
SKILLS_OK=true
for skill in lark-im lark-doc lark-calendar lark-contact; do
  if [ ! -f "/home/opc_uname/.agents/skills/$skill/SKILL.md" ]; then
    echo -n "$skill:MISSING "
    SKILLS_OK=false
  fi
done
if [ "$SKILLS_OK" = true ]; then
  echo "OK"
else
  echo ""
  ERRORS=$((ERRORS + 1))
fi

# 6. workspace 核心文件
echo -n "[6/8] workspace core files... "
CORE_OK=true
for f in AGENTS.md SOUL.md; do
  if [ ! -f "/home/opc_uname/.openclaw/workspace/$f" ]; then
    echo -n "$f:MISSING "
    CORE_OK=false
  fi
done
if [ "$CORE_OK" = true ]; then
  echo "OK"
else
  echo ""
  ERRORS=$((ERRORS + 1))
fi

# 7. 磁盘空间 (WARN) — workspace 所在分区剩余 < 1GB 告警
echo -n "[7/8] disk space... "
WORKSPACE_DIR="/home/opc_uname/.openclaw/workspace"
# df 输出第 4 列 Available (KB), 取挂载在 workspace 路径上的分区
AVAIL_KB=$(df -P "$WORKSPACE_DIR" 2>/dev/null | awk 'NR==2 {print $4}')
if [ -z "$AVAIL_KB" ]; then
  echo "WARN (unable to query disk space)"
  WARNINGS=$((WARNINGS + 1))
else
  # 1GB = 1048576 KB
  if [ "$AVAIL_KB" -lt 1048576 ]; then
    AVAIL_GB=$(awk -v k="$AVAIL_KB" 'BEGIN{printf "%.1f", k/1048576}')
    echo "WARN (${AVAIL_GB}G free)"
    WARNINGS=$((WARNINGS + 1))
  else
    AVAIL_GB=$(awk -v k="$AVAIL_KB" 'BEGIN{printf "%.1f", k/1048576}')
    echo "OK (${AVAIL_GB}G free)"
  fi
fi

# 8. 日志 ERROR 检查 (WARN) — 最近 5 分钟内 openclaw 日志是否出现 ERROR
echo -n "[8/8] recent log errors... "
LOG_DIR="/home/opc_uname/.openclaw/logs"
LOG_ERROR_COUNT=0
if [ -d "$LOG_DIR" ]; then
  # 取最近 5 分钟内修改过的日志文件 (*.log / *.jsonl), grep ERROR (大小写敏感, 排除注释里的 error)
  # find -mmin -5: 修改时间在 5 分钟内; -print0 / xargs -0 安全处理空格路径
  RECENT_LOGS=$(find "$LOG_DIR" -type f \( -name '*.log' -o -name '*.jsonl' \) -mmin -5 2>/dev/null)
  if [ -n "$RECENT_LOGS" ]; then
    # 用 xargs 安全传参; grep -c 返回匹配行数
    LOG_ERROR_COUNT=$(printf '%s\n' "$RECENT_LOGS" | xargs -r grep -c 'ERROR' 2>/dev/null | awk -F: '{s+=$NF} END{print s+0}')
  fi
  if [ "${LOG_ERROR_COUNT:-0}" -gt 0 ]; then
    echo "WARN ($LOG_ERROR_COUNT ERROR line(s) in last 5m)"
    WARNINGS=$((WARNINGS + 1))
  else
    echo "OK (no ERROR in recent logs)"
  fi
else
  echo "OK (log dir absent, skipped)"
fi

echo "=== Health Check Result ==="
if [ $ERRORS -gt 0 ]; then
  echo "RESULT: FAIL ($ERRORS error(s), $WARNINGS warning(s))"
  # 写入崩溃标记，供 safe-mode.sh 检测
  mkdir -p "$(dirname "$MARK_FILE")"
  echo "{\"failed_at\":\"$(date -Iseconds)\",\"errors\":$ERRORS}" > "$MARK_FILE"
  exit 1
fi

# 健康则清除标记
rm -f "$MARK_FILE"
if [ $WARNINGS -gt 0 ]; then
  echo "RESULT: OK with $WARNINGS warning(s)"
else
  echo "RESULT: OK"
fi
exit 0
