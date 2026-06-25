#!/bin/bash
# snapshot.sh — 修改前打快照 tag
# 用法: bash scripts/snapshot.sh [-f] <tag-name>
# 示例: bash scripts/snapshot.sh pre-optimize-001
#        bash scripts/snapshot.sh -f pre-optimize-001   # 覆盖同名 tag
#
# 选项:
#   -f  覆盖同名 tag (先删除再建)
# 无 -f 时若 tag 已���在: 打印提示并跳过创建, 正常退出 0

set -e

FORCE=0
TAG_NAME=""

# 解���参数: -f 选项 + 位置参数 tag-name
while [ $# -gt 0 ]; do
  case "$1" in
    -f|--force)
      FORCE=1
      shift
      ;;
    -h|--help)
      sed -n '2,9p' "$0"
      exit 0
      ;;
    *)
      if [ -z "$TAG_NAME" ]; then
        TAG_NAME="$1"
      else
        echo "snapshot: 未知参数: $1 (用法: snapshot.sh [-f] <tag-name>)" >&2
        exit 1
      fi
      shift
      ;;
  esac
done

TAG_NAME="${TAG_NAME:-pre-optimize-unknown}"
PROJECT_DIR="/home/opc_uname/.openclaw/workspace/projects/openclaw_improve_self"

cd "$PROJECT_DIR"

# 确保所有改动已提交
git add -A
git commit -m "snapshot: $TAG_NAME" 2>/dev/null || true

# 同名 tag 处理
if git rev-parse "$TAG_NAME" >/dev/null 2>&1; then
  if [ "$FORCE" = "1" ]; then
    echo "snapshot: tag $TAG_NAME 已存在, -f 覆盖中..."
    git tag -d "$TAG_NAME"
  else
    echo "snapshot: tag $TAG_NAME already exists, use -f to overwrite"
    exit 0
  fi
fi

# 打 tag
git tag "$TAG_NAME"
echo "Snapshot tagged: $TAG_NAME"

# 记录到 state
python3 -c "
import json, os, datetime
state_file = 'state/stable-tags.json'
tags = []
if os.path.exists(state_file):
    with open(state_file) as f:
        tags = json.load(f)
tags.append({
    'tag': '$TAG_NAME',
    'timestamp': datetime.datetime.now().isoformat(),
    'commit': os.popen('git rev-parse HEAD').read().strip()
})
os.makedirs('state', exist_ok=True)
with open(state_file, 'w') as f:
    json.dump(tags, f, indent=2, ensure_ascii=False)
"

echo "Done."
