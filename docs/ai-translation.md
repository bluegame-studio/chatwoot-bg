# AI 翻译服务配置

回复编辑器中的 AI 翻译功能通过 Chatwoot 后端代理调用外部翻译服务。浏览器不会接触 OAuth client secret 或 access token。

## 必需环境变量

必须同时配置以下三个运行时环境变量：

| 变量 | 值 | 说明 |
| --- | --- | --- |
| `AI_TRANSLATE_API_BASE_URL` | `https://ai-chat-dev.yamie.eu.cc` | 翻译服务地址，不要在末尾添加 `/` |
| `AI_TRANSLATE_CLIENT_ID` | OAuth 服务签发的 client ID | 当前服务对应的客户端账号 |
| `AI_TRANSLATE_CLIENT_SECRET` | OAuth 服务签发的 client secret | 敏感信息，不要提交到 Git |

示例 `.env`：

```env
AI_TRANSLATE_API_BASE_URL=https://ai-chat-dev.yamie.eu.cc
AI_TRANSLATE_CLIENT_ID=<your-client-id>
AI_TRANSLATE_CLIENT_SECRET=<your-client-secret>
```

client ID 和 client secret 必须使用授权服务实际签发的值，不能使用变量名、scope 或示例占位符代替。固定 OAuth scope 为 `ai.translate`，由 Chatwoot 后端自动传递，不需要额外环境变量。

## Docker Compose

推荐通过 `env_file` 注入变量：

```yaml
services:
  rails:
    env_file:
      - .env
```

也可以直接映射部署平台中的 Secret：

```yaml
services:
  rails:
    environment:
      AI_TRANSLATE_API_BASE_URL: ${AI_TRANSLATE_API_BASE_URL}
      AI_TRANSLATE_CLIENT_ID: ${AI_TRANSLATE_CLIENT_ID}
      AI_TRANSLATE_CLIENT_SECRET: ${AI_TRANSLATE_CLIENT_SECRET}
```

修改 `.env` 后必须重新创建 Rails 容器，单独执行 `docker restart` 不会更新容器环境变量：

```bash
docker compose up -d --force-recreate rails
```

如果 Compose 服务名不是 `rails`，请替换为实际承载 Chatwoot Web/Rails 的服务名。多副本部署需要为所有 Rails Web 副本配置相同变量。Sidekiq 不执行翻译请求，不强制要求配置这些变量。

## Docker Run

```bash
docker run --env-file .env <other-options> chatwoot/chatwoot:latest
```

也可以分别传入变量：

```bash
docker run \
  -e AI_TRANSLATE_API_BASE_URL=https://ai-chat-dev.yamie.eu.cc \
  -e AI_TRANSLATE_CLIENT_ID=<your-client-id> \
  -e AI_TRANSLATE_CLIENT_SECRET=<your-client-secret> \
  <other-options> \
  chatwoot/chatwoot:latest
```

这些变量是运行时配置，不需要也不应该写入 Dockerfile。

## 启用状态

Chatwoot 只有在三个变量都为非空值时才启用回复框中的翻译按钮。缺少任意变量时：

- 翻译按钮保持显示但处于禁用状态。
- Hover 按钮会提示需要配置的环境变量。
- 客服登录时不会请求翻译服务授权。

配置完成并重新创建 Rails 容器后，刷新 Chatwoot 页面即可启用按钮。access token 由 Rails 获取并缓存在 Redis 中，到期前会自动刷新。

## 验证

确认容器已经收到全部变量：

```bash
docker compose exec rails bundle exec rails runner \
  "puts Integrations::AiTranslate::AccessTokenService.configured?"
```

输出 `true` 表示配置完整。不要使用会打印 `ENV` 全部内容的命令，以免泄露 client secret。
