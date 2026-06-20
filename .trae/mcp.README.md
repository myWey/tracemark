# MCP 配置说明

`.trae/mcp.json` 是项目级 MCP（Model Context Protocol）server 配置，Trae v1.3.0+ 会自动读取。

## 当前配置

默认情况下 `.trae/mcp.json` 不启用任何 MCP server（仅保留 `_comment` 说明）。如需启用：

1. 复制 `mcp.json.template`（或自行创建）为 `.trae/mcp.json`。
2. 在 `mcpServers` 数组中添加需要的 server。
3. 确保所有 secret 通过 `env` 注入，严禁硬编码。

## 如何扩展

在 `mcpServers` 数组中追加对象即可：

```json
{
  "name": "github",
  "command": ["npx", "-y", "@modelcontextprotocol/server-github"],
  "env": {
    "GITHUB_PERSONAL_ACCESS_TOKEN": "${GITHUB_TOKEN}"
  }
}
```

## Secret 注入规范

- 严禁在 `.trae/mcp.json` 中硬编码 token、密码、API key。
- 通过 `env` 字段引用环境变量，由 Trae secret 管理或本地 shell 注入。
- 如需浏览器自动化，可使用 `@modelcontextprotocol/server-puppeteer`。
