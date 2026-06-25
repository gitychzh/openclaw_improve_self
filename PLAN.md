# openclaw_improve_self — 方案五实施规划

> 状态：规划中（未部署）
> 远程仓库：https://github.com/gitychzh/openclaw_improve_self
> 创建时间：2026-06-25

## 1. 项目边界

### 1.1 本项目管理什么
OpenClaw agent (h1) 的自我优化体系，包括：
- workspace 下的配置文件（AGENTS.md, SOUL.md, TOOLS.md, IDENTITY.md, USER.md, HEARTBEAT.md）
- memory 文件（MEMORY.md, memory/*.md）
- 项目级文件（projects/openclaw_improve_self/）
- health-check 脚本
- 自动回滚逻辑
- ACP 优化任务模板

### 1.2 本项目不管什么（不碰）
- `/home/opc_uname/.openclaw/openclaw.json`（L0 核心配置，只通过 ACP agent 改）
- `~/cc_ps/` 目录（cc-proxy 自优化项目，独立运行）
- `/opt/cc-infra/` 容器基础设施
- 其他 projects/ 下的项目

### 1.3 Claude Code 工作目录
**严格限定在** `/home/opc_uname/.openclaw/workspace/projects/openclaw_improve_self/`

CC 的 cwd 设为此目录，CLAUDE.md 放在此目录作为 CC 的指令边界。
CC 不得访问此目录之外的任何文件。

---

## 2. 分层策略

| 层级 | 内容 | 路径 | 风险 | 修改方式 |
|------|------|------|------|----------|
| L0 核心 | openclaw.json, model 路由, 容器配置 | ~/.openclaw/openclaw.json, /opt/cc-infra/ | 🔴高 | 仅 ACP agent 改 + health check + git |
| L1 skill | ~/.agents/skills/, ~/.openclaw/plugin-skills/ | 同左 | 🟡中 | ACP agent 改 + health check |
| L2 prompt | AGENTS.md, SOUL.md, TOOLS.md, IDENTITY.md, USER.md | workspace/ | 🟡中 | h1 自改 + git commit |
| L3 记忆 | MEMORY.md, memory/*.md | workspace/ | 🟢低 | h1 自由修改 |
| L4 项目 | projects/openclaw_improve_self/ | workspace/projects/ | 🟢低 | h1 + CC 均可改 |

---

## 3. Git 仓库结构

### 3.1 仓库初始化
```
远程: https://github.com/gitychzh/openclaw_improve_self.git
本地: /home/opc_uname/.openclaw/workspace/projects/openclaw_improve_self/
```

**不把整个 workspace 纳入此 repo。** 只把 `projects/openclaw_improve_self/` 作为独立 git repo。

workspace 根目录已有的 git（master branch, no commits）保持不动，另建独立 repo。

### 3.2 目录结构
```
projects/openclaw_improve_self/
├── README.md                 # 项目说明
├── DESIGN.md                 # 方案设计文档（已完成）
├── PLAN.md                   # 本实施规划
├── CLAUDE.md                 # CC 的指令边界文件
├── .gitignore
├── scripts/
│   ├── health-check.sh       # 健康探测脚本
│   ├── pre-commit-hook.sh    # git pre-commit 钩子
│   ├── safe-mode.sh          # 安全模式启动逻辑
│   └── snapshot.sh           # 快照（git tag）脚本
├── templates/
│   └── acp-optimize-task.md  # ACP 优化任务 brief 模板
├── memory/                   # CC 每轮优化的记忆传承
│   └── README.md
├── state/                    # 运行状态
│   ├── optimization-log.json # 优化历史
│   └── stable-tags.json      # stable tag 记录
└── tests/
    └── health-check.test.sh  # health check 自测
```

### 3.3 .gitignore
```
state/optimization-log.json.bak
*.tmp
*.log
```

---

## 4. 核心组件设计

### 4.1 health-check.sh

**作用：** 修改后自动检测 agent 是否正常工作。

**检测项：**
1. `openclaw status` 返回正常
2. gateway 端口 18789 可达
3. LiteLLM proxy 端口 40003 可达
4. 飞书 channel 连接正常（检查 openclaw.json 中 feishu 配置存在）
5. 关键 skill 文件存在（lark-im, lark-doc 等）
6. workspace 核心文件存在（AGENTS.md, SOUL.md）

**返回：** exit 0 = 健康，exit 1 = 异常

```bash
#!/bin/bash
# scripts/health-check.sh
set -e

ERRORS=0

# 1. openclaw 进程
if ! openclaw status >/dev/null 2>&1; then
  echo "FAIL: openclaw status"
  ERRORS=$((ERRORS + 1))
fi

# 2. gateway 端口
if ! curl -sf http://127.0.0.1:18789/ >/dev/null 2>&1; then
  echo "FAIL: gateway port 18789"
  ERRORS=$((ERRORS + 1))
fi

# 3. LiteLLM proxy
if ! curl -sf http://127.0.0.1:40003/v1/models >/dev/null 2>&1; then
  echo "FAIL: LiteLLM proxy port 40003"
  ERRORS=$((ERRORS + 1))
fi

# 5. 关键 skill 文件
for skill in lark-im lark-doc lark-calendar lark-contact; do
  if [ ! -f "/home/opc_uname/.agents/skills/$skill/SKILL.md" ]; then
    echo "FAIL: skill $skill missing"
    ERRORS=$((ERRORS + 1))
  fi
done

# 6. workspace 核心文件
for f in AGENTS.md SOUL.md; do
  if [ ! -f "/home/opc_uname/.openclaw/workspace/$f" ]; then
    echo "FAIL: workspace file $f missing"
    ERRORS=$((ERRORS + 1))
  fi
done

if [ $ERRORS -gt 0 ]; then
  echo "Health check: $ERRORS error(s)"
  exit 1
fi

echo "Health check: OK"
exit 0
```

### 4.2 快照与回滚机制

**快照：** 每次修改前打 git tag
```
stable-20260625-2130    # 人工标记的稳定点
pre-optimize-001         # 第 1 次优化前
pre-optimize-002         # 第 2 次优化前
```

**回滚流程：**
```
修改后 health check 失败
  → git revert HEAD（撤销最近一次改动）
  → 再次 health check
  → 如果仍失败 → git reset --hard stable-XXXX
  → 重启 openclaw
```

### 4.3 安全模式

**触发条件：** openclaw 启动时检测到上次 health check 失败标记文件存在。

**逻辑：**
1. 修改后写标记文件 `state/.health-failed`
2. 下次 openclaw 启动时，h1 检查此标记
3. 如果存在 → 用 `git reset --hard` 回到最近 stable tag
4. 删除标记文件
5. 通知 Boss 张

### 4.4 ACP 优化任务模板

`templates/acp-optimize-task.md`：

```markdown
# ACP 优化任务

## 任务编号
opt-{N}

## 优化目标
{描述要优化什么}

## 当前状态
- git tag: {当前 stable tag}
- health check: {通过/失败}
- 最近报错: {如果有}

## 约束
1. **只在** /home/opc_uname/.openclaw/workspace/projects/openclaw_improve_self/ 内工作
2. **不碰** ~/.openclaw/openclaw.json（L0 核心配置）
3. **不碰** ~/cc_ps/ 和 /opt/cc-infra/
4. 修改前先 `git tag pre-optimize-{N}`
5. 修改后跑 `bash scripts/health-check.sh`
6. health check 失败则 `git revert` 并报告
7. 提炼有用信息写入 memory/opt-{N}.md
8. 完成后 `git push`

## 修改范围
{具体要改哪些文件}

## 验证标准
- health-check.sh 通过
- 改动的文件符合预期（git diff 检查）
- 无无关文件被改动
```

### 4.5 CLAUDE.md（CC 指令边界）

放在项目目录，CC 启动时自动读取。

```markdown
# CLAUDE.md — CC 工作边界

## 你是谁
你是 openclaw_improve_self 项目的优化执行者。

## 工作目录
你的工作严格限定在：
/home/opc_uname/.openclaw/workspace/projects/openclaw_improve_self/

## 禁止访问
- /home/opc_uname/.openclaw/openclaw.json
- /home/opc_uname/cc_ps/
- /opt/cc-infra/
- 项目目录之外的任何文件

## 工作流程
1. 读取 templates/ 中的任务 brief
2. 读取 memory/ 了解历史
3. git tag pre-optimize-{N}
4. 执行修改
5. bash scripts/health-check.sh
6. 通过 → git commit + git push
   失败 → git revert + 报告原因
7. 提炼信息写入 memory/opt-{N}.md
```

---

## 5. 执行流程

### 5.1 h1 自主修改流程（L2/L3）

```
h1 发现可优化项
  → git add -A && git commit -m "pre-optimize: {desc}"  # 快照
  → 修改文件（AGENTS.md, MEMORY.md 等）
  → bash scripts/health-check.sh
  → 通过 → git commit -m "opt: {desc}" → git push
  → 失败 → git revert HEAD → 通知 Boss 张
```

### 5.2 ACP 修改流程（L0/L1）

```
h1 发现需要改 L0/L1
  → 填写 templates/acp-optimize-task.md
  → sessions_spawn(
      runtime: "acp",
      agentId: "claude",
      mode: "run",
      cwd: "/home/opc_uname/.openclaw/workspace/projects/openclaw_improve_self",
      task: "读取 templates/acp-optimize-task.md，按约束执行"
    )
  → CC 执行修改 + health check
  → h1 审核 git diff
  → 通过 → git push
  → 失败 → CC 自动 revert，报告原因
```

### 5.3 灾难恢复流程

```
h1 完全无法启动
  → 人工 ssh 到机器
  → cd 项目目录
  → git log --oneline  # 查看历史
  → git reset --hard stable-XXXX  # 回到最近的稳定点
  → openclaw restart
  → 或：在新机器上 git clone + 恢复 workspace
```

---

## 6. 部署步骤（待批准后执行）

### Phase 1: 基础设施 ✅
1. ✅ `cd projects/openclaw_improve_self/`
2. ✅ `git init && git remote add origin git@github.com:gitychzh/openclaw_improve_self.git`
3. ✅ 创建所有目录和文件（scripts/, templates/, memory/, state/）
4. ✅ 写 .gitignore
5. ✅ 首次 commit + push

### Phase 2: 健康检查 ✅
1. ✅ 写 scripts/health-check.sh
2. ⬜ 写 tests/health-check.test.sh（后续补充）
3. ✅ 手动跑一次 health check 确认基线通过
4. ✅ git tag stable-baseline

### Phase 3: CC 边界 ✅
1. ✅ 写 CLAUDE.md
2. ✅ 写 templates/acp-optimize-task.md
3. ✅ 用 ACP spawn 一次 CC 做空跑测试（只读不改，验证边界）
4. ✅ CC 发现 gap：health check 失败不写标记 → 已修复

### Phase 4: 回滚机制 ✅
1. ✅ 写 scripts/snapshot.sh（打 tag）
2. ✅ 写 scripts/safe-mode.sh（安全模式）
3. ⬜ 配置 git pre-commit hook（可选，后续补充）
4. ✅ 测试回滚流程：模拟 skill 缺失 → health check 失败 → .health-failed 写入 → safe-mode 回滚到 stable tag → 标记清除

### Phase 5: 集成测试 ✅
1. ✅ 模拟 health check 失败 → 验证自动回滚（Phase 4 已覆盖）
2. ✅ git 状态一致性验证
3. ✅ 远程仓库同步验证
4. ⬜ 通过 ACP 让 CC 做一次真实小优化（待启动正式优化轮次）

---

## 7. 与 cc-proxy 自优化项目的关系

cc-proxy 自优化（`~/cc_ps/cc_repair_self/`）是独立项目，优化的是容器层面的 proxy 代码。
本项目优化的是 OpenClaw agent 自身的配置/skill/prompt/记忆。

两者独立运行，互不干扰：
- cc-proxy 项目改 /opt/cc-infra/ 下的容器代码
- openclaw_improve_self 改 workspace 下的 agent 配置
- 都用 ACP + Claude Code，但 cwd 不同，互不交叉

---

## 8. 待确认

- [x] Boss 张批准本规划
- [x] 远程仓库已创建（gitychzh/openclaw_improve_self）
- [x] 开始执行 Phase 1
- [x] Phase 1-4 完成
- [x] Phase 5 集成测试完成
- [ ] 启动正式优化轮次
