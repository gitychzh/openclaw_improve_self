# OpenClaw 模型链路代码

本目录包含从 OpenClaw 提取的模型路由与链路核心代码，
用于 h1 与 opc2 交替优化。

## 代码结构

| 文件 | 行数 | 功能 |
|------|------|------|
| `resolve-route.js` | 482 | 核心路由解析：agent 匹配、binding 优先级、缓存策略 |
| `route-cli.js` | 497 | CLI 路由处理：命令解析、route-first 执行优化 |
| `route-matrix.js` | 165 | Matrix 协议路由：DM session、thread routing |
| `models.js` | 42 | 模型定义：Cloudflare AI Gateway model builder |
| `provider-fireworks.js` | 71 | Fireworks 提供商目录 |
| `model-auth-env.js` | 98 | 环境变量 API Key 解析 |

## 优化方向

- **路由效率**: reduce O(n) lookups, optimize cache hit rates
- **错误处理**: missing edge cases, null safety
- **可维护性**: deduplicate logic, improve naming
- **性能**: reduce allocations, optimize hot paths
- **配置灵活性**: model fallback chains, dynamic provider selection