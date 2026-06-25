# ACP 优化任务模板

## 任务编号
opt-{N}

## 优化目标
{描述要优化什么，比如：优化 SOUL.md 的 prompt 让回复更简洁}

## 当前状态
- git tag: {当前 stable tag，CC 读取 state/stable-tags.json}
- health check: {通过/失败}
- 最近报错: {如果有，描述最近的问题}

## 约束
1. **只在** /home/opc_uname/.openclaw/workspace/projects/openclaw_improve_self/ 内工作
2. **不碰** 以下路径（L0 核心配置，禁止访问）：
   - /home/opc_uname/.openclaw/openclaw.json
   - /home/opc_uname/cc_ps/
   - /opt/cc-infra/
3. 修改前先 `bash scripts/snapshot.sh pre-optimize-{N}`
4. 修改后跑 `bash scripts/health-check.sh`
5. health check 失败则 `git revert HEAD` 并报告原因
6. 提炼有用信息写入 memory/opt-{N}.md
7. 完成后 `git push`

## 修改范围
{具体要改哪些文件，明确列出}

## 验证标准
- health-check.sh 通过（exit 0）
- 改动的文件符合预期（git diff 检查，无无关改动）
- 无项目目录外的文件被改动

## 上下文
{h1 提供的背景信息，比如为什么要优化、期望的效果}
