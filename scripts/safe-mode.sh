#!/bin/bash
# safe-mode.sh — 安全模式：检测上次是否崩溃，自动回滚
# 用法: bash scripts/safe-mode.sh
# 应在 openclaw 启动前或 heartbeat 中调用

PROJECT_DIR="/home/opc_uname/.openclaw/workspace/projects/openclaw_improve_self"
MARK_FILE="$PROJECT_DIR/state/.health-failed"

# 检查崩溃标记
if [ -f "$MARK_FILE" ]; then
  echo "WARNING: 检测到上次 health check 失败标记，进入安全模式"

  # 读取最近的 stable tag
  STABLE_TAG=$(python3 -c "
import json
with open('$PROJECT_DIR/state/stable-tags.json') as f:
    tags = json.load(f)
    # 找最近的人工标记的 stable tag
    for t in reversed(tags):
        if t['tag'].startswith('stable-'):
            print(t['tag'])
            break
" 2>/dev/null)

  if [ -n "$STABLE_TAG" ]; then
    echo "回滚到 stable tag: $STABLE_TAG"
    cd "$PROJECT_DIR"
    git reset --hard "$STABLE_TAG"
    echo "已回滚到 $STABLE_TAG"
  else
    echo "ERROR: 未找到 stable tag，无法自动回滚，需要人工干预"
    exit 2
  fi

  # 删除标记文件
  rm -f "$MARK_FILE"
  echo "安全模式处理完毕，可以正常启动"
  exit 0
fi

echo "无崩溃标记，正常模式"
exit 0
