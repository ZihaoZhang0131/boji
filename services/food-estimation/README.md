# 薄记私有食物识别服务

Node 24.14.0（LTS 分支）＋TypeScript＋Node SQLite＋Sharp。只运行一个进程／实例，使用本机持久目录；API 和并发为 1 的 worker 同进程。所有测试使用合成数据和明确的协议 fixture，不表示任何真实供应商已联通。

## 本地运行

```sh
cd services/food-estimation
nvm use
npm ci --ignore-scripts
npm run build
npm test
```

按 `.env.example` 在进程环境中设置 `DATA_DIR`、`PORT`、`BOJI_OWNERS_JSON`。令牌应从密码管理器生成 32 字节以上的随机值，安全交付给自己的 App；服务仅配置该值的 SHA-256 十六进制摘要。owner 名保持稳定，更换对应摘要即可撤销旧令牌。不要把真实令牌或供应商密钥放进命令行参数、仓库、截图、导出包或普通日志。环境文件权限设为 600，采用部署平台的密钥环境更合适。

四项供应商配置全部留空时仍能启动，`GET /v1/config` 返回 `available:false`，上传和新识别返回 `not_configured`，不会返回样例热量。部分填写会拒绝启动。

配置完成后使用 `npm start`。默认只监听 `127.0.0.1:8787`，`GET /health` 可检查进程；本地 HTTP 仅供回环调试或同机反向代理。App 的正式连接地址必须使用可信 HTTPS。

## 供应商和授权政策

`PROVIDER_URL` 是完整的 HTTPS chat-completions 端点；`PROVIDER_NAME`、`PROVIDER_MODEL`、`PROVIDER_KEY` 都必须配置，模型需要支持图片和 `json_schema` 输出。适配器不猜测其他供应商协议，不重定向、不工具调用、不读取用户给出的远程图片 URL，也不会自动用第二次调用修复输出。模型密钥仅供服务进程使用。

`POLICY_VERSION` 和 `PROVIDER_RETENTION` 描述实际处理政策。对外政策 ID 还包含供应商、模型、地址、保留规则和提示版本的摘要，即使忘记手改版本也会发现这些内容的变化。上传、提交、执行三个阶段都检查政策。旧的相同请求查询仍可取得原任务；已有幂等记录不会因此再调用。

服务清理不等于供应商删除。应阅读并准确填写供应商保留政策，在模型账户另外设置金额预算；每天 50 次请求不是金额上限。新政策必须在 App 中重新明确授权。

## HTTP 契约

除 `/health` 外都需 `Authorization: Bearer <personal token>`。JSON 错误为 `{"error":{"code":"..."}}`，不含上游原始错误正文。所有响应禁止缓存。

| 路径 | 请求／结果 |
|---|---|
| `GET /v1/config` | 实际供应商／模型、政策版本、资料范围、保留规则、费用和上限；无凭据 |
| `POST /v1/uploads` | 二进制 JPEG／PNG／WebP，实际 MIME 与解码必须匹配；头 `X-Boji-Policy-Version`；201 返回 `image_ref/sha256/bytes/mime_type/expires_at` |
| `POST /v1/food-estimates` | `Content-Type: application/json`；202 返回稳定任务身份及状态 |
| `GET /v1/food-estimates/{job_id}` | 状态、来源关联和校验后的 `result`；过期结果只返回 `expired` |
| `DELETE /v1/food-estimates/{job_id}` | 幂等取消，立即删除服务输入；无法保证撤回已发送给上游的资料 |

提交字段：`request_id`、UTC `request_created_at`（首次真实发送前持久化）、`record_id`、非负整数 `input_revision/lifecycle_epoch`、`image_refs[]`、`note`、`locale`、`policy_version`；显式重试可带原服务任务 `retry_of`，必须使用新 `request_id`。图片引用属于同一 owner，一次绑定一个任务；重试重新上传本地图片。相同 ID／相同规范化正文返回原任务，不同正文返回 `conflict`。先查询原任务，再检查 24 小时首发期限；即使输入已清理也不重放。

上传最多 9 张，每张最多 2 MiB、合计 18 MiB；真实解码最多 5000 万像素，拒绝动画，重新编码为去元数据的 JPEG。照片引用 24 小时过期；每 owner 同时最多暂存 100 张，超限返回可识别限流。备注最多 8000 字符，JSON 请求最多 64 KiB。模型响应最多 256 KiB。

成功 `result` 包含 `items[{name,estimated_grams,kcal,assumptions[]}]`、`total_kcal`、`estimate_range`、`questions`、`source:model_estimate`、`provider/model/prompt_version/created_at`。未知克数为 null；十进制求和严格相等，拒绝负值、非有限值、无项目、合计超过 10000 或范围不包围合计。估算范围不代表置信区间或营养数据库认证。

任务状态为 `queued/running/succeeded/failed/cancelled/expired`。错误包括 `unauthorized/invalid_input/not_configured/policy_changed/conflict/quota_exceeded/rate_limited/provider_timeout/upstream_outcome_unknown/provider_unavailable/invalid_model_output/cannot_recognize/cancelled/expired`。`rate_limited` 有 `Retry-After`；错误不删除 App 的原记录。

## 配额、重启和清理

默认每分钟最多 5 个新任务，每 UTC 日最多 50 次尝试，可用 `MINUTE_JOBS/DAILY_ATTEMPTS` 下调。调用前 SQLite 事务预留配额，失败和显式重试也消耗额度；幂等重发不消耗新额度。单调用 90 秒，执行总期限 120 秒，不自动重试可能已经发生的调用。

进程启动恢复排队任务，把执行中但无法确认上游结果的任务置为 `upstream_outcome_unknown`。SIGTERM 先标记在途状态再退出；突然断电也不会在重启时再次请求在途任务。SQLite 使用事务和 `secure_delete`，数据库升级版本未知时拒绝启动。

终态立即删除照片、备注和请求体；结构化结果在终态 24 小时边界清除，只保留无原文的任务摘要及状态。终态元数据最多 7 天，启动、每分钟及查询时补偿清理；未绑定上传到期删除。不要长期备份任务库、暂存目录或代理请求体。普通日志仅允许事件名、随机任务 ID、固定错误码。

## HTTPS 和持久部署

1. 在持久 Linux 主机安装锁定的 Node 版本，创建无登录权限的 `boji` 用户，将代码放到 `/opt/boji`，执行构建。安装匹配架构的依赖；不要从 Mac 复制 `node_modules`。
2. 使用 `/var/lib/boji-food-estimation` 持久盘及权限 700，环境文件 `/etc/boji-food-estimation.env` 权限 600。只运行一个 systemd unit，禁止多个进程或端口共享此目录；不使用临时函数磁盘。参考 `deploy/boji-food-estimation.service`，按实际 Node 路径调整。
3. 使用自己的域名和可信证书。`deploy/Caddyfile.example` 提供同机反向代理配置；DNS 指向该主机，只公开 HTTPS，Node 端口继续仅监听回环。关闭代理访问日志和正文采集。
4. 配置模型账户金额预算、真实保留政策和 owner 摘要后启动服务，先用无个人信息测试图片验证 `/v1/config → uploads → submit → poll`，再在 App 授权。不要通过关闭证书验证解决 TLS 错误。
5. 用同一个请求 ID 重发并重启服务，确认任务身份保留且供应商调用数没有增加。`npm test` 包含真实子进程重启和本地可信测试证书的 HTTPS 往返；它仍使用模型协议 fixture，不代表正式域名或真实 AI 已验收。

撤销令牌：替换对应 owner 的摘要并重启；不要更换 owner 来伪装撤销。停用模型：移除全部四项供应商配置再重启，本地记录和手工热量继续工作。政策变化时排队旧任务会被拒绝。

回退：先停止服务，保留不含凭据的配置模板和 schema 版本说明，再回退到支持当前 SQLite schema 的程序；未知 schema 不强行降级。恢复的 `running` 任务必须转为结果未知，不能再次调用。不要恢复长期备份的照片／备注。正式发布前重新核对 Node 安全更新，并用相同测试更新 `.nvmrc`、依赖锁和部署版本。

实现参考：[Node SQLite](https://nodejs.org/api/sqlite.html)、[Node 发布支持](https://nodejs.org/en/about/previous-releases)、[Sharp 图片元数据](https://sharp.pixelplumbing.com/api-input/)。
