# Chatwoot 本地前端修改、构建与 Docker 回填

## 目录和容器

- 完整源码：`/Users/arthur/Documents/Codex/2026-07-25/ni/work/chatwoot-build-src`
- Docker Compose：`/Users/arthur/Documents/Codex/2026-07-25/ni/outputs/chatwoot-local/compose.yml`
- Rails 容器：`chatwoot-local-rails-1`
- Chatwoot 地址：`http://127.0.0.1:3000`

先进入完整源码目录：

```bash
cd /Users/arthur/Documents/Codex/2026-07-25/ni/work/chatwoot-build-src
```

## 修改过的前端文件

```text
app/javascript/shared/constants/conversationPriorityStyles.js
app/javascript/dashboard/components/widgets/conversation/ConversationCard.vue
app/javascript/dashboard/components-next/Conversation/ConversationCard/ConversationCard.vue
app/javascript/dashboard/components-next/Conversation/ConversationCard/CardMessagePreview.vue
app/javascript/dashboard/components-next/Conversation/ConversationCard/CardMessagePreviewWithMeta.vue
app/javascript/dashboard/components-next/Conversation/ConversationCard/CardPriorityIcon.vue
app/javascript/dashboard/routes/dashboard/conversation/ConversationAction.vue
app/javascript/shared/components/ui/MultiselectDropdown.vue
app/javascript/shared/components/ui/MultiselectDropdownItems.vue
```

## 重新构建前端

使用临时 Node 容器构建，不依赖 Chatwoot Rails 镜像内是否安装了 pnpm：

```bash
docker run --rm \
  -v /Users/arthur/Documents/Codex/2026-07-25/ni/work/chatwoot-build-src:/app \
  -w /app \
  -e NODE_OPTIONS=--max-old-space-size=8192 \
  node:24-bookworm \
  sh -lc 'corepack enable && pnpm exec vite build'
```

构建产物位于：

```text
/Users/arthur/Documents/Codex/2026-07-25/ni/work/chatwoot-build-src/public/vite
```

## 回填到正在运行的 Chatwoot

使用 tar 流可以确保 `.vite/manifest.json` 等隐藏文件一并复制：

```bash
tar -cf - \
  public/vite \
  app/javascript/shared/constants/conversationPriorityStyles.js \
  app/javascript/dashboard/components/widgets/conversation/ConversationCard.vue \
  app/javascript/dashboard/components-next/Conversation/ConversationCard/ConversationCard.vue \
  app/javascript/dashboard/components-next/Conversation/ConversationCard/CardMessagePreview.vue \
  app/javascript/dashboard/components-next/Conversation/ConversationCard/CardMessagePreviewWithMeta.vue \
  app/javascript/dashboard/components-next/Conversation/ConversationCard/CardPriorityIcon.vue \
  app/javascript/dashboard/routes/dashboard/conversation/ConversationAction.vue \
  app/javascript/shared/components/ui/MultiselectDropdown.vue \
  app/javascript/shared/components/ui/MultiselectDropdownItems.vue \
  | docker exec -i chatwoot-local-rails-1 tar -xf - -C /app
```

确认 manifest 和源码已经进入容器：

```bash
docker exec chatwoot-local-rails-1 sh -lc "
  test -f /app/public/vite/.vite/manifest.json &&
  grep -q 'getConversationCardStyle' \
    /app/app/javascript/dashboard/components/widgets/conversation/ConversationCard.vue &&
  echo 'assets-and-source-synced'
"
```

## 重启 Rails

```bash
docker restart chatwoot-local-rails-1
```

查看启动日志：

```bash
docker logs --tail 100 -f chatwoot-local-rails-1
```

日志稳定后按 `Ctrl+C` 退出日志查看，不会停止容器。

## 验证部署结果

检查首页：

```bash
curl -sS -o /dev/null \
  -w 'page_http=%{http_code}\n' \
  http://127.0.0.1:3000
```

预期输出：

```text
page_http=200
```

查看首页当前引用的 dashboard 资源：

```bash
curl -sS http://127.0.0.1:3000 \
  | grep -oE 'dashboard-[A-Za-z0-9_-]+\.(js|css)' \
  | sort -u
```

检查 manifest 中的 dashboard bundle：

```bash
docker exec chatwoot-local-rails-1 sh -lc "
  grep -A 4 -B 2 'entrypoints/dashboard.js' \
    /app/public/vite/.vite/manifest.json
"
```

每次构建产生的文件哈希都可能不同，不要固定使用某一次的 bundle 文件名。

## 发送 API Inbox 测试消息

当前 API Inbox 标识符：

```text
NdDD7tkaGFqVPKwJ99cmjQWb
```

下面的命令会创建一个新联系人、新会话并发送一条 incoming 消息：

```bash
CHATWOOT_INBOX_BASE='http://127.0.0.1:3000/public/api/v1/inboxes/NdDD7tkaGFqVPKwJ99cmjQWb'
CHATWOOT_TEST_SOURCE_ID="priority-unread-test-$(date +%s)"

curl -fsS -X POST \
  "$CHATWOOT_INBOX_BASE/contacts" \
  -H 'Accept: application/json' \
  -H 'Content-Type: application/json' \
  --data "{
    \"source_id\":\"$CHATWOOT_TEST_SOURCE_ID\",
    \"identifier\":\"$CHATWOOT_TEST_SOURCE_ID\",
    \"name\":\"优先级未读测试用户\",
    \"email\":\"priority-unread-test@example.com\"
  }" \
  > /tmp/chatwoot-test-contact.json

curl -fsS -X POST \
  "$CHATWOOT_INBOX_BASE/contacts/$CHATWOOT_TEST_SOURCE_ID/conversations" \
  -H 'Accept: application/json' \
  -H 'Content-Type: application/json' \
  --data '{}' \
  > /tmp/chatwoot-test-conversation.json

CHATWOOT_TEST_CONVERSATION_ID="$(
  jq -r '.id' /tmp/chatwoot-test-conversation.json
)"

curl -fsS -X POST \
  "$CHATWOOT_INBOX_BASE/contacts/$CHATWOOT_TEST_SOURCE_ID/conversations/$CHATWOOT_TEST_CONVERSATION_ID/messages" \
  -H 'Accept: application/json' \
  -H 'Content-Type: application/json' \
  --data '{
    "content":"【前端样式测试】请检查左侧卡片的未读文字和优先级背景。",
    "echo_id":"priority-unread-style-test"
  }' \
  | jq
```

测试时先不要进入新会话：

1. 在左侧确认用户名、最新消息为蓝色并加粗。
2. 无优先级时确认卡片背景为浅蓝色。
3. 设置紧急、高、中、低优先级，确认卡片背景分别切换。
4. 确认右侧优先级徽标、未读文字和未读徽标同时存在。
5. 进入会话后，确认未读样式清除，优先级背景继续保留。

## 用编辑器打开源码

Visual Studio Code：

```bash
code /Users/arthur/Documents/Codex/2026-07-25/ni/work/chatwoot-build-src
```

Cursor：

```bash
cursor /Users/arthur/Documents/Codex/2026-07-25/ni/work/chatwoot-build-src
```

如果命令行还没有安装 `code` 或 `cursor` 命令，可以在编辑器中选择：

```text
File → Open Folder...
```

然后打开：

```text
/Users/arthur/Documents/Codex/2026-07-25/ni/work/chatwoot-build-src
```

## 注意事项

当前方式是把构建产物直接写入正在运行的 Rails 容器。如果删除并重新创建 Rails 容器，容器内回填的文件会消失，但宿主机完整源码和构建产物仍会保留。重新创建容器后，再执行“回填到正在运行的 Chatwoot”和“重启 Rails”两节即可。
