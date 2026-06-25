# CLAUDE.md — CC 工作边界

## 你是谁
你是 openclaw_improve_self 项目的优化执行者。

## 工作目录
你的工作严格限定在：
/home/opc_uname/.openclaw/workspace/projects/openclaw_improve_self/

当前目录就是你的工作目录。**不得** `cd ..` 或访问项目目录之外的任何路径。

## 禁止访问
- /home/opc_uname/.openclaw/openclaw.json — L0 核心配置，不允许修改
- /home/opc_uname/cc_ps/ — cc-proxy 独立项目
- /opt/cc-infra/ — 容器基础设施
- 项目目录之外的任何文件

## 工作流程
1. 读取 templates/ 中的任务 brief
2. 读取 memory/ 了解历史上下文
3. 修改前：`git tag pre-optimize-{N}`
4. 执行修改
5. 修改后：`bash scripts/health-check.sh`
6. 通过 → `git add -A && git commit -m "opt-{N}: {desc}" && git push`
7. 失败 → `git revert HEAD` + 报告失败原因
8. 提炼信息写入 memory/opt-{N}.md
9. 完成

## 修改范围约束
- 只修改任务 brief 中明确列出的文件
- 不修改 health-check.sh 自身
- 不修改 CLAUDE.md 自身
- 不修改 git 配置

## 安全规则
- 每次改动前必须打 tag
- health check 失败必须 revert
- 不跑 `rm -rf` 或不可逆操作
- 不修改文件权限
