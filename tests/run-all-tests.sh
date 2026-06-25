#!/bin/bash
# run-all-tests.sh — 聚合运行 tests/ 下所有 *.test.sh 并汇总结果
# 用法: bash tests/run-all-tests.sh
# 退出码: 0 = 全部通过, 1 = 有失败
#
# 设计:
#   - 自动发现 tests/ 目录下所有 *.test.sh
#   - 逐个执行, 捕获退出码
#   - 汇总通过/失败数量, 任一失败则 exit 1
#   - 不中断: 即使某个测试失败也继续跑剩余测试 (用 set +e 包裹)

set -u

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PASS=0
FAIL=0
FAILED_TESTS=()

# 发现所有测试脚本, 按文件名排序保证顺序稳定
shopt -s nullglob
TESTS=( "$TEST_DIR"/*.test.sh )
shopt -u nullglob

TOTAL=${#TESTS[@]}
if [ "$TOTAL" = "0" ]; then
  echo "run-all-tests: 未发现任何 *.test.sh 测试文件 (目录: $TEST_DIR)"
  exit 1
fi

echo "=== Run All Tests ($TOTAL suite(s)) ==="
echo

i=0
for t in "${TESTS[@]}"; do
  i=$((i + 1))
  name="$(basename "$t")"
  echo "---- [$i/$TOTAL] $name ----"
  # 子进程跑, 不让 set -e / 当前 shell 受影响
  if bash "$t"; then
    PASS=$((PASS + 1))
    echo "[$i/$TOTAL] $name: SUITE OK"
  else
    rc=$?
    FAIL=$((FAIL + 1))
    FAILED_TESTS+=("$name (exit=$rc)")
    echo "[$i/$TOTAL] $name: SUITE FAIL (exit=$rc)"
  fi
  echo
done

echo "=== Summary ==="
echo "suites passed: $PASS / $TOTAL"
echo "suites failed: $FAIL / $TOTAL"
if [ "$FAIL" -gt 0 ]; then
  echo "failed suites:"
  for ft in "${FAILED_TESTS[@]}"; do
    echo "  - $ft"
  done
  exit 1
fi

echo "ALL TESTS PASSED"
exit 0
