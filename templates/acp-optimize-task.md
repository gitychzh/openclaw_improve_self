# ACP 优化任务

## 任务编号
opt-002

## 优化目标
第二轮优化，工具链实质改进。四个子任务：

1. **snapshot.sh 增强** — 加 `-f` 选项支持覆盖同名 tag；同名 tag 已存在时默认跳过并提示
2. **写 tests/run-all-tests.sh** — 聚合测试脚本，跑完所有 tests/ 下的测试并汇总结果
3. **health-check.sh 检测项增强** — 加 2 项检测：磁盘空间（剩余 < 1GB 时告警）+ openclaw 日志最近 5 分钟无 ERROR
4. **safe-mode.sh 改进** — `git reset --hard` 前先 `git stash` 保护未提交改动（安全模式场景下 hard reset 是预期行为，但 stash 作为额外保险）

## 当前状态
- git tag: stable-v2
- health check: 通过 (6/6)
- 单元测试: 8/8 通过
- pre-commit hook: 已安装并生效

## 约束
1. **只在** /home/opc_uname/.openclaw/workspace/projects/openclaw_improve_self/ 内工作
2. **不碰** 以下路径：
   - /home/opc_uname/.openclaw/openclaw.json
   - /home/opc_uname/cc_ps/
   - /opt/cc-infra/
3. 修改前先 `bash scripts/snapshot.sh pre-optimize-002-rev1`
4. 修改后跑 `bash scripts/health-check.sh`
5. health check 失败则 `git revert HEAD` 并报告原因
6. 提炼有用信息写入 memory/opt-002.md
7. 完成后 `git push`

## 修改范围
- 可修改: scripts/snapshot.sh, scripts/health-check.sh, scripts/safe-mode.sh
- 新建: tests/run-all-tests.sh
- 可修改: tests/health-check.test.sh（如果 health-check.sh 改了需要同步更新测试）
- 不得修改: .gitignore, CLAUDE.md, state/ 下的文件

## 验证标准
- health-check.sh 通过（exit 0），新增检测项也正常工作
- tests/run-all-tests.sh 跑通，所有测试通过
- snapshot.sh -f 选项测试通过
- safe-mode.sh stash 逻辑测试通过
- 改动的文件符合预期（git diff 检查，无无关改动）

## 上下文
opt-001 已完成，项目基础设施健全。本轮开始做实质改进。
opt-001 建议方向：snapshot.sh 加 -f 选项、run-all-tests.sh、health check 检测项增强。

## 详细要求

### snapshot.sh 增强
- `bash scripts/snapshot.sh <tag-name>` 现有行为不变
- 加 `-f` 选项: `bash scripts/snapshot.sh -f <tag-name>` 覆盖同名 tag
- 无 `-f` 时如果 tag 已存在：打印提示 "tag XXX already exists, use -f to overwrite" 并跳过 tag 创建（不 exit 1，正常退出 0）
- 保持 `set -e` 语义合理

### tests/run-all-tests.sh
- 遍历 tests/ 下所有 *.test.sh 并执行
- 汇总通过/失败数量
- 任何失败则 exit 1

### health-check.sh 检测项增强
- 新增 [7] 磁盘空间: 检查 workspace 所在分区剩余空间，< 1GB 时 WARN（不 FAIL，只是警告）
- 新增 [8] 日志检查: 检查 ~/.openclaw/logs/ 下最新的日志文件，最近 5 分钟内是否有 "ERROR" 关键字。有则 WARN
- 这两项是 WARN 不是 FAIL，不影响 exit code
- 输出格式: `[7/8] disk space... OK (12.3G free)` 或 `[7/8] disk space... WARN (0.8G free)`

### safe-mode.sh 改进
- `git reset --hard` 前先 `git stash`（如果有未提交改动）
- stash 后打印 "stashed N files before reset"
- reset 后 stash 不自动恢复（安全模式下不信任当前改动）
