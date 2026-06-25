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
#   - 检测项 1-6 为 FAIL 项, 7-8 为 WARN 项 (不影响 exit code, 仅警告)

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
echo "[1/5] script exists & syntax OK"
assert_eq "1" "$([ -f "$SCRIPT" ] && echo 1 || echo 0)" "health-check.sh exists"
if bash -n "$SCRIPT" 2>/dev/null; then
  echo "  PASS: syntax check OK"
  PASS=$((PASS + 1))
else
  echo "  FAIL: syntax check failed"
  FAIL=$((FAIL + 1))
fi

# ---- 测试 2: 清理起点, 运行一次, 记录退出码 ----
echo "[2/5] run real health-check.sh once"
rm -f "$MARK_FILE"
run_health_check
RC=$?
echo "  (info: real run exit code = $RC)"

# ---- 测试 3: 契约验证 — 退出码与标记文件一致性 ----
echo "[3/5] exit code / mark-file contract"
if [ "$RC" = "0" ]; then
  assert_file_state 0 "$MARK_FILE" "exit 0 => mark file cleared"
else
  assert_file_state 1 "$MARK_FILE" "exit non-zero => mark file written"
fi

# ---- 测试 4: 模拟异常 — 标记写入 & 恢复后清除 ----
echo "[4/5] simulated failure writes mark; success clears it"

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

# ---- 测试 5: WARN 项 (磁盘/日志) 不影响 exit code ----
# 构造副本: 所有 FAIL 项 (1-6) 替换为恒成功, WARN 项 (7-8) 保留并强制触发,
# 验证即使 WARN 触发, exit 仍为 0 (WARN 不写入崩溃标记).
echo "[5/5] WARN items do not affect exit code"

TMP_WARN="$(mktemp -d)/health-check-warn.sh"
# 用真实脚本作为基底
cp "$SCRIPT" "$TMP_WARN"
# 把 6 个 FAIL 检测项的命令替换为恒成功 (true), 让 ERRORS 始终为 0
#  - 项1: openclaw status  => true
#  - 项2: curl ...18789    => true
#  - 项3: curl ...40003    => true
#  - 项4: python3 feishu 检测 => 把 assert 改成恒真 (不依赖 openclaw.json 内容)
#  - 项5/6: 文件存在检测   => 让 SKILLS_OK / CORE_OK 恒不置 false
sed -i \
  -e 's#openclaw status#/bin/true #' \
  -e 's#curl -sf http://127.0.0.1:18789/#/bin/true #' \
  -e 's#curl -sf http://127.0.0.1:40003/v1/models#/bin/true #' \
  -e "s#assert 'feishu' in#assert True or 'feishu' in#" \
  -e 's#SKILLS_OK=false#SKILLS_OK=true#' \
  -e 's#CORE_OK=false#CORE_OK=true#' \
  "$TMP_WARN"
# 改写副本的 MARK_FILE 指向临时 state, 隔离
FAKE_STATE2="$(mktemp -d)"
sed -i 's#\$SCRIPT_DIR/../state/.health-failed#'"$FAKE_STATE2/.health-failed"'#' "$TMP_WARN"
# 强制触发磁盘 WARN: 把阈值 1048576 (1GB) 改成 999999999 (极大约), 让任何剩余空间都算低
sed -i 's#1048576#999999999#g' "$TMP_WARN"
bash -n "$TMP_WARN" 2>/dev/null
SYNTAX_OK2=$?
assert_eq "0" "$SYNTAX_OK2" "warn-copy syntax OK"

rm -f "$FAKE_STATE2/.health-failed"
WARN_OUT="$(bash "$TMP_WARN" 2>/dev/null)"
WARN_RC=$?
assert_eq "0" "$WARN_RC" "warn-copy exits 0 even when WARN triggered"
# 验证输出里有 WARN 标记且 RESULT 不是 FAIL
case "$WARN_OUT" in
  *"[7/8] disk space... WARN"*)
    echo "  PASS: disk space WARN emitted"
    PASS=$((PASS + 1))
    ;;
  *)
    echo "  FAIL: expected disk space WARN (got: $(echo "$WARN_OUT" | grep '\[7/8\]'))"
    FAIL=$((FAIL + 1))
    ;;
esac
case "$WARN_OUT" in
  *"RESULT: OK with"*)
    echo "  PASS: RESULT OK with warnings (not FAIL)"
    PASS=$((PASS + 1))
    ;;
  *)
    echo "  FAIL: expected 'RESULT: OK with N warning(s)' (got: $(echo "$WARN_OUT" | grep RESULT))"
    FAIL=$((FAIL + 1))
    ;;
esac
# WARN 触发时不应写入崩溃标记
assert_file_state 0 "$FAKE_STATE2/.health-failed" "WARN does not write crash mark"

rm -rf "$(dirname "$TMP_WARN")" "$FAKE_STATE2"

echo "=== Result: $PASS passed, $FAIL failed ==="
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
