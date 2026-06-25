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

    # hard reset 前先 stash 保护未提交改动 (额外保险)
    # 统计已跟踪文件的改动数 (不含未跟踪文件, stash -u 才包含未跟踪)
    STASH_FILES=$(git diff --name-only 2>/dev/null | wc -l | tr -d ' ')
    STAGED_FILES=$(git diff --cached --name-only 2>/dev/null | wc -l | tr -d ' ')
    DIRTY_COUNT=$((STASH_FILES + STAGED_FILES))
    if [ "$DIRTY_COUNT" -gt 0 ]; then
      # stash 已跟踪改动 (不包含未跟踪文件, 保持最小侵入); 失败不阻断回滚
      if git stash push -m "safe-mode: pre-reset stash ($STABLE_TAG)" >/dev/null 2>&1; then
        echo "stashed $DIRTY_COUNT files before reset"
      else
        echo "WARNING: stash 失败, 继续硬回滚 (改动可能丢失)"
      fi
    else
      echo "no uncommitted changes to stash"
    fi
    # 注意: reset 后 stash 不自动恢复 (安全模式下不信任当前改动)
    # 如需找回: git stash list / git stash pop

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
