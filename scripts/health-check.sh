#!/bin/bash
# health-check.sh — OpenClaw agent 健康探测
# 用法: bash scripts/health-check.sh
# 返回: exit 0 = 健康, exit 1 = 异常

ERRORS=0
WARNINGS=0

echo "=== Health Check Start ==="

# 1. openclaw 进程
echo -n "[1/6] openclaw status... "
if openclaw status >/dev/null 2>&1; then
  echo "OK"
else
  echo "FAIL"
  ERRORS=$((ERRORS + 1))
fi

# 2. gateway 端口 18789
echo -n "[2/6] gateway port 18789... "
if curl -sf http://127.0.0.1:18789/ >/dev/null 2>&1; then
  echo "OK"
else
  echo "FAIL"
  ERRORS=$((ERRORS + 1))
fi

# 3. LiteLLM proxy 端口 40003
echo -n "[3/6] LiteLLM proxy port 40003... "
if curl -sf http://127.0.0.1:40003/v1/models >/dev/null 2>&1; then
  echo "OK"
else
  echo "FAIL"
  ERRORS=$((ERRORS + 1))
fi

# 4. feishu 配置存在
echo -n "[4/6] feishu channel config... "
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
echo -n "[5/6] critical skills... "
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
echo -n "[6/6] workspace core files... "
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

echo "=== Health Check Result ==="
if [ $ERRORS -gt 0 ]; then
  echo "RESULT: FAIL ($ERRORS error(s))"
  exit 1
fi
echo "RESULT: OK"
exit 0
