# openclaw_improve_self

> Agent 自我优化的安全方案设计
> Status: 设计阶段（未部署）
> Created: 2026-06-25

## 目标

让 OpenClaw agent 能持续优化自身的配置、skill、prompt、工具链路，同时保证：
- 改崩了能恢复
- 改动有版本可追溯
- 不需要人工干预也能回滚

## 核心风险

| 风险 | 说明 |
|------|------|
| 自我锁死 | 改了配置导致 agent 无法启动或无法响应 |
| 记忆丢失 | 改了 MEMORY/skill 导致上下文断裂 |
| 循环依赖 | 优化逻辑本身有问题，越改越差 |
| 无回滚点 | 没有快照，改坏了无法恢复 |

---

## 方案一：外部 Agent 修改（Claude Code / ACP 模式）

**思路：** 自己不改自己，让外部 coding agent（Claude Code、Cursor 等）通过 ACP 协议来改。

```
OpenClaw Agent (被改方)
    ↑
    │ ACP session
    │
Claude Code / Cursor (修改方)
    ↓
  读取 → 分析 → 修改 → 测试 → 提交
```

**流程：**
1. Agent 发现需要优化的点（heartbeat 或手动触发）
2. Agent 把优化需求 + 当前配置打包成 task brief
3. 通过 `sessions_spawn(runtime="acp")` 启动 Claude Code
4. Claude Code 读取配置文件 → 做修改 → 跑测试 → git commit
5. Agent 验证修改，如果不通过则 git revert

**优点：**
- 实现简单，单机即可
- 改方和被改方隔离，改崩了不影响修改方
- Claude Code 本身擅长代码修改

**缺点：**
- 单点：如果 OpenClaw 崩了，无法启动新的 ACP session 来修复
- 依赖 Claude Code 可用性
- 被改方完全被动，无法自救

**恢复机制：** git revert + 手动重启

---

## 方案二：双机互修（Mutual Repair）

**思路：** 两台机器各跑一个 OpenClaw，A 改 B，B 改 A。一个崩了另一个能修。

```
Machine A (OpenClaw-A)          Machine B (OpenClaw-B)
  ├─ config-A                    ├─ config-B
  ├─ skills-a                    ├─ skills-b
  └─ workspace-a                 └─ workspace-b
         ↕ SSH / API ↕
    A 修改 B 的文件            B 修改 A 的文件
    A 健康检查 B               B 健康检查 A
    B 崩了 → A 修复            A 崩了 → B 修复
```

**流程：**
1. 两台机器通过 SSH 互相访问对方 workspace
2. 各自独立运行，定期 heartbeat 检查对方健康状态
3. 发现对方异常 → SSH 过去 git revert → 重启
4. 主动优化时，A 通过 SSH 修改 B 的配置，B 验证后生效

**优点：**
- 真正的容灾：一边崩了另一边能救
- 完全对等，无单点
- 可以做 A/B 测试（A 用新配置，B 用旧配置，对比效果）

**缺点：**
- 需要两台机器，成本高
- SSH 互访需要配好权限
- 两边同时改同一个东西会冲突（需要协调机制）
- 如果改了共同依赖（如同一个 git repo）可能同时崩

**恢复机制：** 对方 SSH 进来 git revert + 重启

**协调机制建议：**
- 用一个共享的 lock file（放在两机都能访问的地方）防止同时改
- 或者用主从模式：平时 A 是主改方，B 是备；定期切换

---

## 方案三：Git 检查点 + 健康探测 + 自动回滚（单机自修）

**思路：** 自己改自己，但每次改动前 git commit，改完跑健康检查，不通过自动 revert。

```
┌─────────────────────────────────────┐
│         OpenClaw Agent              │
│                                     │
│  1. git commit (checkpoint)         │
│  2. 修改配置/skill/prompt           │
│  3. 健康探测:                       │
│     - openclaw status               │
│     - 发一条测试消息给自己          │
│     - 检查关键 skill 是否可用       │
│  4. 通过 → 保留改动                 │
│     失败 → git revert + restart     │
│  5. 如果 restart 后仍异常:          │
│     → 进入安全模式（用默认配置）     │
└─────────────────────────────────────┘
```

**关键设计：**

### 3.1 安全模式 (Safe Mode)
- 在 `openclaw` 启动脚本中加一个检查
- 如果检测到上次启动后 health check 失败过，自动用 git 上一个 stable tag 的配置启动
- 类似 Windows 的"上次正确配置"

### 3.2 健康探测脚本
```bash
#!/bin/bash
# health-check.sh
openclaw status || exit 1
# 发测试消息
echo "ping" | openclaw chat --session health-check --timeout 30
# 检查关键 skill
openclaw skill list --json | jq '.[] | select(.name=="lark-im") | .enabled'
```

### 3.3 改动分层
| 层级 | 内容 | 风险等级 | 修改方式 |
|------|------|----------|----------|
| L0 核心 | gateway config, model 路由 | 🔴 高 | 只能方案二/一改 |
| L1 skill | SKILL.md, 脚本 | 🟡 中 | 可自改，需 health check |
| L2 记忆 | MEMORY.md, daily notes | 🟢 低 | 可自改，随时 |
| L3 prompt | SOUL.md, AGENTS.md | 🟡 中 | 可自改，需验证 |

**优点：**
- 单机即可，无额外成本
- 自动化程度高
- 分层控制风险

**缺点：**
- 如果改了启动脚本本身，可能无法进入安全模式
- 健康探测可能不够全面
- 自我认知盲区：agent 可能不知道某个改动会崩

**恢复机制：** git revert + 安全模式启动

---

## 方案四：影子克隆 (Shadow Clone)

**思路：** 维护一个 staging 克隆，先在克隆上改和测试，通过后 promote 到生产。

```
┌──────────────┐     ┌──────────────┐
│  Production   │     │   Shadow     │
│  (live)       │────→│  (staging)   │
│  对外服务     │     │  测试改动     │
│               │←────│  验证通过     │
│               │     │  promote     │
└──────────────┘     └──────────────┘
```

**流程：**
1. 定期把 production 配置 clone 到 shadow 目录
2. 在 shadow 上做修改 + 测试
3. 测试通过 → rsync/git merge 到 production
4. production 出问题 → 从 shadow 的上一个 stable 版本回滚

**实现方式：**
- 同一台机器两个 openclaw 实例（不同端口）
- 或用 docker，shadow 是一个 container

**优点：**
- 生产零停机
- 测试充分才 promote
- 可以做金丝雀发布

**缺点：**
- 资源消耗大（跑两份）
- 配置同步复杂
- shadow 和 production 环境差异可能导致测试不准

---

## 方案五：混合方案（推荐）

**组合：方案三（Git 检查点）+ 方案一（ACP 外部修改）+ 方案二的精神（远程备援）**

```
┌──────────────────────────────────────────────┐
│              日常运行                         │
│                                              │
│  ┌─ L2 记忆层: 自由修改 (MEMORY, daily)      │
│  ├─ L1 Skill层: 自改 + health check + git    │
│  └─ L0 核心层: 不自改，委托 ACP agent 改     │
│                                              │
│           ↓ 发现需要改 L0                    │
│                                              │
│  ┌─ ACP Agent (Claude Code)                  │
│  │  1. 读取当前配置                          │
│  │  2. 修改 + git commit                     │
│  │  3. health check                          │
│  │  4. 失败 → git revert                     │
│  └─                                         │
│                                              │
│  ┌─ 远程备援 (可选)                          │
│  │  定期 git push 到远程 repo                │
│  │  崩溃时任何机器 clone → 恢复              │
│  └─                                         │
└──────────────────────────────────────────────┘
```

**分层策略：**
- **L2（记忆）**: agent 自己随时改，低风险
- **L1（skill/prompt）**: agent 自己改，但每次 git commit + health check
- **L0（核心配置）**: 不自改，委托 ACP agent（Claude Code）来改，改完也 health check
- **灾难恢复**: 所有配置 git push 到远程 repo，任何机器都能 clone 恢复

**为什么推荐这个方案：**
1. 成本低——不需要两台机器，单机就能跑
2. 风险可控——分层 + git + health check 三重保险
3. 有外部援助——ACP agent 处理高风险改动
4. 可扩展——以后加第二台机器直接升级到方案二
5. 灾备——git remote 是最简单可靠的备份

---

## 后续步骤（待确认方案后）

1. 初始化 git repo 在 workspace
2. 写 health-check.sh
3. 配置安全模式启动逻辑
4. 设置 ACP agent 的 task brief 模板
5. 配置远程 git repo 做灾备
6. 写自动优化触发逻辑（heartbeat 检测到可优化项时触发）

---

## 方案对比总结

| 维度 | 方案一 (ACP) | 方案二 (双机) | 方案三 (Git+Health) | 方案四 (影子) | 方案五 (混合) |
|------|-------------|--------------|--------------------|--------------|--------------|
| 成本 | 低 | 高（两台机器） | 低 | 中 | 低 |
| 复杂度 | 低 | 高 | 中 | 高 | 中 |
| 容灾能力 | 弱 | 强 | 中 | 中 | 中+可扩展 |
| 自主性 | 被动 | 对等 | 主动 | 主动 | 分层自主 |
| 恢复速度 | 慢（手动） | 快（自动） | 快（自动） | 快 | 快 |
| 推荐度 | ⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ |
