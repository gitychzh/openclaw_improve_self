# 交替优化脚本

## opc1 脚本

### 1. health-check-opc1 (每60秒)

```
你是 opc1 的健康监控器。执行步骤：

1. cd /home/opc_uname/.openclaw/workspace/openclaw_improve_self
2. git pull origin main
3. 读 HEALTH.md。如果 optimizationPaused=true 且 pauseReason 非空，说明在紧急修复中，只做健康检查不做优化。
4. 探测 opc2:
   a. SSH: ssh -p 222 -o ConnectTimeout=10 opc2_uname@100.109.57.26 "echo ok"
   b. Gateway: curl -s -o /dev/null -w "%{http_code}" http://100.109.57.26:18789/
   c. 模型: 通过 ssh 到 opc2 执行 curl 检查模型可用性
5. 更新 HEALTH.md 中 opc2 的状态
6. 如果 opc2 不健康 (连续3次ssh失败 或 gateway返回非200 或 fallback触发):
   - 设 optimizationPaused=true, pauseReason="opc2 down"
   - 如果之前没暂停: 写 ALERT.md 记录告警
   - 尝试修复: SSH进去重启gateway
7. 如果 opc2 恢复健康且之前暂停:
   - 设 optimizationPaused=false
   - 确认 ROUND.md 状态，从上个断点继续
8. git add HEALTH.md && git commit -m "health: opc1 check" && git push
```

### 2. round-worker-opc1 (每30秒)

```
你是 opc1 的轮次执行器。执行步骤：

1. cd /home/opc_uname/.openclaw/workspace/openclaw_improve_self
2. git pull origin main
3. 读 HEALTH.md: 如果 optimizationPaused=true，exit
4. 读 ROUND.md，根据 phase 执行:

CASE phase="ready":
  - 如果我是 proposer (奇数轮 opc1 为正辩方):
    - 读 opc2 的 openclaw.json (通过ssh)
    - 分析可优化的参数
    - 写 PROPOSAL.md: 本轮要改什么、为什么、怎么改
    - 写 PLAN.md: 具体执行步骤
    - 更新 ROUND.md: phase="discuss", lock="opc1"
    - git push
  - 如果我是 opponent: exit (等对方动作)

CASE phase="discuss":
  - 如果我是 opponent 且 lock 是对方:
    - 读 PROPOSAL.md
    - 如果同意: 在 DISCUSS.md 写 "approved"
    - 如果反对: 写具体反对意见
    - 更新 ROUND.md: lock="opc2"
    - git push
  - 如果我是 proposer 且 lock 是我自己:
    - 读对方反对意见
    - 如果已达成共识: 更新 ROUND.md: phase="backup", lock=proposer
    - git push

CASE phase="backup":
  - 如果我是 proposer:
    - SSH到对方机器: cp openclaw.json → backup/opc{1|2}-round{N}.json
    - scp 备份到本机 repo backup/
    - 更新 ROUND.md: phase="execute"
    - git push

CASE phase="execute":
  - 如果我是 proposer:
    - SSH到对方机器
    - 按 PLAN.md 修改对方的 openclaw.json (只改1-2个参数)
    - 备份原配置到 repo backup/
    - 重启对方 gateway: systemctl --user restart openclaw-gateway
    - 等待5秒
    - 验证 gateway 启动: curl port check
    - 如果验证通过:
      - 更新 ROUND.md: phase="verify", lock=opponent
      - git push
    - 如果验证失败:
      - 恢复备份配置
      - 重启 gateway
      - 写 ERROR.md 记录
      - 设 HEALTH.md optimizationPaused=true
      - git push

CASE phase="verify":
  - 如果我是 opponent:
    - 自检: gateway正常 + 模型可调用 + 没触发fallback
    - 如果自检通过:
      - 增加轮次: round += 1
      - 翻转角色: proposer ↔ opponent
      - 更新 ROUND.md: phase="ready", lock=null
      - git push
    - 如果自检失败:
      - 自动回滚: 从 backup/ 恢复上一份配置
      - 重启 gateway
      - 更新 ROUND.md: phase="rollback"
      - 设 HEALTH.md optimizationPaused=true
      - git push

CASE phase="rollback":
  - 如果我是 proposer:
    - SSH到对方确认已回滚
    - 分析失败原因
    - 写 LESSON.md 记录教训
    - 等待下一个健康周期自动resume

6. git push 所有修改

CRITICAL:
- 永远只 SSH 到对方机器，不在本地改 openclaw.json
- opc1 只能改 opc2，opc2 只能改 opc1
- 每次只改 1-2 个参数
- 修改前必须备份
- 如果对方挂了，暂停一切优化
```

### 3. SSH 凭据

```
opc1 → opc2: ssh -p 222 opc2_uname@100.109.57.26
opc2 → opc1: ssh -p 22 opc_uname@<opc1_ip>
  (opc2通过Tailscale访问opc1，需要opc1的Tailscale IP)
```

### 4. 修改的安全范围

只修改 openclaw.json 中的这些字段:
- models.providers.<name>.models[].contextWindow
- models.providers.<name>.models[].maxTokens
- agents.defaults.model.primary
- agents.defaults.model.fallbacks
- agents.defaults.model.*
- agents.list[].model.*

不修改:
- gateway 配置
- channel 配置
- bind 配置
- 任何安全相关字段