#!/bin/bash
# snapshot.sh — 修改前打快照 tag
# 用法: bash scripts/snapshot.sh <tag-name>
# 示例: bash scripts/snapshot.sh pre-optimize-001

set -e

TAG_NAME="${1:-pre-optimize-unknown}"
PROJECT_DIR="/home/opc_uname/.openclaw/workspace/projects/openclaw_improve_self"

cd "$PROJECT_DIR"

# 确保所有改动已提交
git add -A
git commit -m "snapshot: $TAG_NAME" 2>/dev/null || true

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
