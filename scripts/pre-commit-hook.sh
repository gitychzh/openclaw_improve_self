#!/bin/bash
# pre-commit-hook.sh — git pre-commit 钩子
# 提交前自动跑 health-check.sh, 失败则阻止提交
#
# 安装方法:
#   ln -sf ../../scripts/pre-commit-hook.sh .git/hooks/pre-commit
#   chmod +x scripts/pre-commit-hook.sh
#
# 用法 (手动测试):
#   bash scripts/pre-commit-hook.sh
#
# 退出码:
#   0 = 健康检查通过, 允许提交
#   1 = 健康检查失败, 阻止提交

set -u

# 解析脚本真实物理路径 (跟随 symlink), 这样经 .git/hooks/pre-commit 软链调用时
# 也能正确定位到 scripts/ 目录, 而非误判为 .git/hooks/.
# BASH_SOURCE[0] 可能是相对路径或 symlink, readlink -f 统一解析为绝对物理路径.
SELF="${BASH_SOURCE[0]}"
if command -v readlink >/dev/null 2>&1; then
  SELF_REAL="$(readlink -f "$SELF" 2>/dev/null || printf '%s' "$SELF")"
else
  # 无 readlink 的兜底: 退回原路径 (BSD/老系统)
  SELF_REAL="$SELF"
fi
SCRIPT_DIR="$(cd "$(dirname "$SELF_REAL")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
HEALTH_CHECK="$SCRIPT_DIR/health-check.sh"

# 防御: 确认在项目仓库内运行
if [ ! -d "$PROJECT_DIR/.git" ] && [ ! -f "$PROJECT_DIR/.git" ]; then
  echo "pre-commit: WARNING: 未在 git 仓库内, 跳过 health check" >&2
  exit 0
fi

echo "pre-commit: running health-check.sh..."
if bash "$HEALTH_CHECK"; then
  echo "pre-commit: health check OK, 允许提交"
  exit 0
fi

echo "" >&2
echo "pre-commit: ❌ health check 失败, 提交已阻止" >&2
echo "pre-commit: 修复后重新提交, 或用 'git commit --no-verify' 跳过(不推荐)" >&2
exit 1
