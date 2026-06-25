# openclaw_improve_self

OpenClaw Agent (h1) 自我优化体系 — 方案五（混合方案）。

## 核心思路
分层修改 + git 检查点 + health check + ACP 外部修改 + 远程灾备。

## 文档
- [DESIGN.md](DESIGN.md) — 5 个方案设计与对比
- [PLAN.md](PLAN.md) — 方案五实施规划
- [CLAUDE.md](CLAUDE.md) — Claude Code 工作边界

## 分层
| 层级 | 修改方 | 安全机制 |
|------|--------|----------|
| L0 核心配置 | ACP agent | git + health check + 人工审核 |
| L1 skill | ACP agent | git + health check |
| L2 prompt | h1 自改 | git commit |
| L3 记忆 | h1 自由改 | 无 |
| L4 项目 | h1 + CC | git |

## 灾备
远程仓库: https://github.com/gitychzh/openclaw_improve_self
任何机器都能 clone 恢复。
