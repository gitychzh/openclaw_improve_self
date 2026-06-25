# ACP 优化任务

## 任务编号
opt-001

## 优化目标
第一轮优化，低风险验证全流程。三个子任务：

1. **写 tests/health-check.test.sh** — 对 health-check.sh 的单元测试
2. **写 scripts/pre-commit-hook.sh** — git pre-commit 钩子，提交前自动跑 health check
3. **审查现有脚本** — 检查 health-check.sh / snapshot.sh / safe-mode.sh 是否有 bug 或可改进点

## 当前状态
- git tag: stable-v1
- health check: 通过 (6/6)
- 最近报错: 无

## 约束
1. **只在** /home/opc_uname/.openclaw/workspace/projects/openclaw_improve_self/ 内工作
2. **不碰** 以下路径（L0 核心配置，禁止访问）：
   - /home/opc_uname/.openclaw/openclaw.json
   - /home/opc_uname/cc_ps/
   - /opt/cc-infra/
3. 修改前先 `bash scripts/snapshot.sh pre-optimize-001-rev1`
4. 修改后跑 `bash scripts/health-check.sh`
5. health check 失败则 `git revert HEAD` 并报告原因
6. 提炼有用信息写入 memory/opt-001.md
7. 完成后 `git push`

## 修改范围
- 新建: tests/health-check.test.sh
- 新建: scripts/pre-commit-hook.sh
- 可修改: scripts/health-check.sh, scripts/snapshot.sh, scripts/safe-mode.sh（如果有 bug）
- 可修改: CLAUDE.md, PLAN.md（如果审查发现需要更新）
- 不得修改: .gitignore, state/ 下的文件

## 验证标准
- health-check.sh 通过（exit 0）
- tests/health-check.test.sh 能跑通
- pre-commit-hook.sh 语法正确
- 改动的文件符合预期（git diff 检查，无无关改动）
- 无项目目录外的文件被改动

## 上下文
这是项目第一轮正式优化。目标是补齐待办项 + 验证 ACP 优化全流程能跑通。
稳定优先，不做大改。

## 详细要求

### tests/health-check.test.sh
- 测试 health-check.sh 在正常状态下返回 exit 0
- 测试 health-check.sh 在异常状态下（模拟）返回 exit 1
- 测试失败时 .health-failed 标记文件是否生成
- 测试成功时 .health-failed 标记文件是否清除
- 用 bash assert 模式，不需要额外依赖

### scripts/pre-commit-hook.sh
- 提交前自动跑 health-check.sh
- 失败则阻止提交（exit 1）
- 提示用户如何安装: `ln -s ../../scripts/pre-commit-hook.sh .git/hooks/pre-commit`

### 脚本审查要点
- snapshot.sh: 是否处理了 git commit 没有改动的情况
- safe-mode.sh: stable tag 查找逻辑是否健壮
- health-check.sh: 检测项是否充分
