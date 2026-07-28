# Chatwoot BG v4.16.1 BM 部署指引

本文用于部署 `bg/4.16.1-bm` 分支。该分支基于 `bg/v4.16.1`，包含现有 BG 定制、会话列表定制、Agent Bot 测试能力，以及每轮 resolved 独立发送 CSAT 的改动。

## 1. 发布原则

- 生产镜像必须由仓库中的 `docker/Dockerfile` 构建。
- 不要部署本地测试镜像 `chatwoot-bg:v4.16.1-local`。该镜像只用于本机验证。
- 镜像标签必须包含 Git commit SHA，不要使用可变的 `latest` 标签。
- Rails 和 Sidekiq 必须使用完全相同的镜像。
- 正式环境必须执行数据库 migration。本版本相对 v4.14.2 包含 21 个 migration。
- migration 前必须备份 PostgreSQL 和附件存储，并保留当前生产镜像标签。
- 生产 Agent Bot 地址必须是容器可访问的内部服务或 HTTPS 地址，不能使用 `host.docker.internal`。

## 2. 发布内容确认

从目标分支获取源码：

```bash
git fetch origin
git switch bg/4.16.1-bm
git pull --ff-only origin bg/4.16.1-bm
```

确认工作区和提交：

```bash
git status --short
git log -7 --oneline
```

`git status --short` 应无输出。记录将要发布的 commit：

```bash
SOURCE_COMMIT="$(git rev-parse HEAD)"
echo "$SOURCE_COMMIT"
```

## 3. 构建生产镜像

先设置你们实际使用的 Registry。以下仅为示例：

```bash
IMAGE_REPOSITORY="<registry>/bluegame-studio/chatwoot-bg"
IMAGE_TAG="v4.16.1-bm-${SOURCE_COMMIT:0:8}"
IMAGE="${IMAGE_REPOSITORY}:${IMAGE_TAG}"
```

使用正式 Dockerfile 构建：

```bash
docker build \
  --pull \
  --build-arg SOURCE_COMMIT="$SOURCE_COMMIT" \
  --tag "$IMAGE" \
  --file docker/Dockerfile \
  .
```

推送镜像：

```bash
docker push "$IMAGE"
```

构建完成后记录以下信息：

- Git branch：`bg/4.16.1-bm`
- Git commit：`$SOURCE_COMMIT`
- 镜像：`$IMAGE`
- 镜像 digest：`docker image inspect "$IMAGE" --format '{{index .RepoDigests 0}}'`

建议在与生产相同架构的 CI/Jenkins 构建节点上完成构建。不要把开发机 ARM64 镜像直接部署到 AMD64 服务器。

## 4. 上线前检查

上线前确认：

- 当前生产镜像标签和 digest 已记录，可用于回滚。
- PostgreSQL 备份可恢复，不只是备份命令返回成功。
- S3、对象存储或 Docker volume 中的附件已备份。
- Redis 不作为唯一业务数据来源；重要队列已处理或允许重放。
- 新镜像已成功启动过，并能连接与生产相同版本的 PostgreSQL、Redis。
- `FRONTEND_URL`、数据库、Redis、邮件、对象存储等环境变量仍完整。
- Agent Bot webhook URL 已改为正式环境可访问地址。
- 已安排维护窗口，migration 期间停止用户写入和 Sidekiq 消费。

## 5. 备份

### PostgreSQL

以下是标准 PostgreSQL 自定义格式备份示例，连接参数按正式环境调整：

```bash
pg_dump \
  --format=custom \
  --no-owner \
  --file="chatwoot-before-v4.16.1-bm-${SOURCE_COMMIT:0:8}.dump" \
  "$DATABASE_URL"
```

验证备份可读取：

```bash
pg_restore --list "chatwoot-before-v4.16.1-bm-${SOURCE_COMMIT:0:8}.dump" >/dev/null
```

### 附件存储

- S3 或兼容对象存储：确认 Bucket versioning、快照或跨 Bucket 备份有效。
- Docker volume：创建 volume 快照或使用基础设施备份工具导出。
- 不要执行 `docker compose down -v`。

## 6. Docker Compose 部署

先把生产 Compose 或环境变量中的 Rails、Sidekiq 镜像改为同一个 `$IMAGE`，但暂时不要启动应用进程。

停止产生写入的应用服务：

```bash
docker compose stop rails sidekiq
```

拉取新镜像：

```bash
docker compose pull rails sidekiq
```

使用新镜像执行 migration：

```bash
docker compose run --rm rails bundle exec rails db:chatwoot_prepare
```

只有 migration 成功后才启动应用：

```bash
docker compose up -d rails sidekiq
```

检查状态和启动日志：

```bash
docker compose ps
docker compose logs --tail=200 rails sidekiq
```

## 7. Kubernetes 部署

如果正式环境使用 Kubernetes：

1. 创建只运行一次的 migration Job，镜像必须是本次 `$IMAGE`。
2. Job command 使用 `bundle exec rails db:chatwoot_prepare`。
3. 等待 Job 成功完成，不允许 Rails/Sidekiq deployment 抢先更新。
4. 更新 Rails deployment。
5. Rails readiness probe 正常后更新 Sidekiq deployment。
6. 确认所有 Pod 使用同一个 image digest。

不要在每个 Rails Pod 启动时并发执行 migration。

## 8. 发布后验证

### 版本和 migration

在 Rails 容器内确认 commit：

```bash
cat /app/.git_sha
```

输出必须等于构建时的 `$SOURCE_COMMIT`。

确认 Chatwoot 版本：

```bash
sed -n '1,6p' /app/package.json
```

应显示 `"version": "4.16.1"`。

确认无待执行 migration：

```bash
bundle exec rails db:abort_if_pending_migrations
```

### 服务检查

- Chatwoot 首页和登录页返回 HTTP 200。
- Rails 日志无持续 5xx、数据库字段不存在或 migration pending 错误。
- Sidekiq 成功连接 Redis，并开始消费队列。
- 原有账号、联系人、会话、消息和附件可访问。
- 新建 incoming 消息后，坐席端能实时收到。
- 会话卡片的优先级、未读样式、联系人标识和复制按钮正常。

### CSAT 回归流程

使用一个专门测试联系人完成以下流程：

1. 发送消息并由坐席回复。
2. 第一次 resolved，确认收到第一条 CSAT，打开链接并提交评分。
3. Reopen 同一个会话并再次发送消息。
4. 第二次 resolved，确认收到第二条 CSAT。
5. 确认两条 CSAT 链接中的 UUID 不同。
6. 分别提交评分，确认报表中存在两条 response，且各自绑定不同的 CSAT message。

不要把临时 `csat-tester.html` 部署到生产环境。

## 9. Agent Bot 配置

仓库中的 `scripts/simple-agent-bot.js` 主要用于流程验证。正式环境如继续使用它，必须作为独立、受监控的服务运行，并满足：

- 使用进程管理器、容器或 Kubernetes deployment 保持常驻。
- webhook 使用容器可访问的内部 DNS 或 HTTPS URL。
- 配置健康检查、日志采集和自动重启。
- 不要把 `scripts/simple-agent-bot.env` 提交到 Git。
- 不要在正式环境配置 `http://host.docker.internal:4000/webhook`。

发布后从 Rails 容器主动检查 Bot webhook 是否可达。Bot 不可达时，Chatwoot 会记录 Agent Bot 错误，并可能把会话自动标记为 open。

## 10. 回滚

本次 migration 包含新表、新字段、索引、数据回填和已有配置字段语义复用。不要仅把应用镜像切回 v4.14.2 后继续使用已经迁移的数据库。

推荐回滚流程：

1. 停止新版本 Rails 和 Sidekiq。
2. 保存故障现场日志和当前数据库副本。
3. 恢复上线前 PostgreSQL 备份。
4. 如有附件写入，按备份策略恢复或核对对象存储增量。
5. 把 Rails 和 Sidekiq 镜像切回已记录的旧版本 digest。
6. 启动旧版本服务并执行基础验证。

PostgreSQL 恢复示例：

```bash
pg_restore \
  --clean \
  --if-exists \
  --no-owner \
  --dbname="$DATABASE_URL" \
  "chatwoot-before-v4.16.1-bm-${SOURCE_COMMIT:0:8}.dump"
```

恢复操作会覆盖数据库，必须在确认目标数据库和备份文件后执行。

## 11. 发布记录

每次正式发布至少保存：

- 发布时间和操作人
- Git branch、commit SHA
- 镜像标签和 digest
- migration Job 或命令执行结果
- 数据库和附件备份位置
- Rails、Sidekiq 启动验证结果
- CSAT 两轮回归结果
- Agent Bot 可达性结果
- 回滚镜像和回滚负责人
