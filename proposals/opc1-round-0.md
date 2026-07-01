# opc1 Proposal: Round 0

**Proposer:** opc1
**Target:** opc2
**Date:** 2026-07-01T21:47+08:00

## 优化点: contextWindow 修正

**当前值:** `contextWindow: 170000`
**建议值:** `contextWindow: 131072`

### 分析

DeepSeek V4 Preview 的实际上下文窗口为 128K tokens。当前配置设为 170000 超过了模型实际能力：

1. **无效值风险**: 当请求接近 170K 时，模型 API 可能拒绝请求或截断，导致不可预期的行为
2. **参考 opc1**: opc1 已验证 `contextWindow: 131072` 在同样模型上稳定运行
3. **131072 = 128 * 1024**: 这是 128K 的精确值，匹配模型规格

### 预期效果
- 避免超出上下文限制的 API 错误
- 确保 opc2 在上下文窗口内正常工作
- 无性能退步（仅降低上限到实际值）