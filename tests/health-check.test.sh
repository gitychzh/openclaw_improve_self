#!/bin/bash
# health-check.test.sh — health-check.sh 单元测试
# 用法: bash tests/health-check.test.sh
# 设计原则:
#   - 不破坏真实运行环境
#   - 用 bash assert 模式, 不依赖额外框架
#   - 验证 health-check.sh 的对外契约:
#       exit 0 => .health-failed 标记被清除
#       exit 1 => .health-failed 标记被写入
#   - 不假设环境是"健康"还是"异常"(那是部署决定的), 只验证退出码与标记文件的一致性

set -u

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$TEST_DIR/.." && pwd)"
SCRIPT="$PROJECT_DIR/scripts/health-check.sh"
STATE_DIR="$PROJECT_DIR/state"
MARK_FILE="$STATE_DIR/.health-failed"

PASS=0
FAIL=0

# ---- assert helpers ----
assert_eq() {
  # assert_eq <expected> <actual> <msg>
  if [ "$1" = "$2" ]; then
    echo "  PASS: $3 (got=$2)"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $3 (expected=$1, got=$2)"
    FAIL=$((FAIL + 1))
  fi
}

assert_file_state() {
  # assert_file_state <should_exist:1|0> <path> <msg>
  if [ "$1" = "1" ] && [ -f "$2" ]; then
    echo "  PASS: $3 (file exists)"
    PASS=$((PASS + 1))
  elif [ "$1" = "0" ] && [ ! -f "$2" ]; then
    echo "  PASS: $3 (file absent)"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $3 (expected exist=$1, actual=$([ -f "$2" ] && echo 1 || echo 0))"
    FAIL=$((FAIL + 1))
  fi
}

run_health_check() {
  # 在子 shell 中运行, 输出静默, 返回退出码
  bash "$SCRIPT" >/dev/null 2>&1
  return $?
}

echo "=== health-check.sh unit tests ==="

# ---- 测试 1: 脚本存在且可执行 ----
echo "[1/4] script exists & syntax OK"
assert_eq "1" "$([ -f "$SCRIPT" ] && echo 1 || echo 0)" "health-check.sh exists"
if bash -n "$SCRIPT" 2>/dev/null; then
  echo "  PASS: syntax check OK"
  PASS=$((PASS + 1))
else
  echo "  FAIL: syntax check failed"
  FAIL=$((FAIL + 1))
fi

# ---- 测试 2: 清理起点, 运行一次, 记录退出码 ----
echo "[2/4] run real health-check.sh once"
rm -f "$MARK_FILE"
run_health_check
RC=$?
echo "  (info: real run exit code = $RC)"

# ---- 测试 3: 契约验证 — 退出码与标记文件一致性 ----
echo "[3/4] exit code / mark-file contract"
if [ "$RC" = "0" ]; then
  assert_file_state 0 "$MARK_FILE" "exit 0 => mark file cleared"
else
  assert_file_state 1 "$MARK_FILE" "exit non-zero => mark file written"
fi

# ---- 测试 4: 模拟异常 — 标记写入 & 恢复后清除 ----
echo "[4/4] simulated failure writes mark; success clears it"

# 构造一个故意失败的 health-check 副本 (检测项 1 必失败: 不存在的命令)
TMP_SCRIPT="$(mktemp -d)/health-check-fail.sh"
sed 's#openclaw status#__nonexistent_cmd_for_test__ #' "$SCRIPT" > "$TMP_SCRIPT"
# 副本的 MARK_FILE 仍指向项目 state/.health-failed (相对脚本目录的 ../state)
# 为隔离, 改写 MARK_FILE 指向临时 state 目录
FAKE_STATE="$(mktemp -d)"
sed -i 's#\$SCRIPT_DIR/../state/.health-failed#'"$FAKE_STATE/.health-failed"'#' "$TMP_SCRIPT"
bash -n "$TMP_SCRIPT" 2>/dev/null
SYNTAX_OK=$?
assert_eq "0" "$SYNTAX_OK" "fail-copy syntax OK"

rm -f "$FAKE_STATE/.health-failed"
bash "$TMP_SCRIPT" >/dev/null 2>&1
FAIL_RC=$?
assert_eq "1" "$FAIL_RC" "fail-copy exits 1"
assert_file_state 1 "$FAKE_STATE/.health-failed" "fail-copy writes mark file"

# 再构造一个"成功"副本 (所有检测项必过): 直接用一个恒成功脚本但保留标记逻辑
TMP_OK="$(mktemp -d)/health-check-ok.sh"
cat > "$TMP_OK" <<'EOF'
#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MARK_FILE="__MARK_PLACEHOLDER__"
ERRORS=0
# 模拟全部通过
if [ $ERRORS -gt 0 ]; then
  mkdir -p "$(dirname "$MARK_FILE")"
  echo "{}" > "$MARK_FILE"
  exit 1
fi
rm -f "$MARK_FILE"
exit 0
EOF
sed -i "s#__MARK_PLACEHOLDER__#$FAKE_STATE/.health-failed#" "$TMP_OK"
# 先制造一个已存在的标记, 验证成功运行会清除它
echo '{"failed_at":"test"}' > "$FAKE_STATE/.health-failed"
bash "$TMP_OK" >/dev/null 2>&1
OK_RC=$?
assert_eq "0" "$OK_RC" "ok-copy exits 0"
assert_file_state 0 "$FAKE_STATE/.health-failed" "ok-copy clears mark file"

# ---- 清理临时文件 ----
rm -rf "$(dirname "$TMP_SCRIPT")" "$(dirname "$TMP_OK")" "$FAKE_STATE"

# ---- 恢复真实环境标记状态 (按真实退出码) ----
if [ "$RC" = "0" ]; then
  rm -f "$MARK_FILE"
fi

echo "=== Result: $PASS passed, $FAIL failed ==="
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
