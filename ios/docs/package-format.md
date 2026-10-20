# 薄记资料包 v2

这是自包含目录，扩展名 `.boji`，不是 SQLite，也不需要安装 App 才能读取。格式版本 `schema_version: 2` 独立于当前内部数据库版本 1。

## 文件与实体映射

| 文件 | 持久实体／内容 |
| --- | --- |
| manifest.json | Dataset.id / revision、唯一 export_id、生成时间、单位、时区约定、各实体数量、所有其他文件大小与 SHA-256 |
| records.json | 未删除 Meal / Workout、全包引用的 PhotoAsset、DayConfirmation、同一版本的 DayReview 计算结果 |
| profiles.json | ProfileVersion，包含生效日、同日 sequence、身体参数、自定目标、来源 |
| goals.json | GoalStage 的开始日、结束日、目标、备注、同日 sequence、来源 |
| estimates.json | EstimateRevision、FoodItem、估算范围、假设、供应商／模型／提示版本、前后修正关联 |
| drafts.json | RecordDraft 的显式 kind、meal 或 workout、保存时间、编辑身份与未完成输入文本 |
| trash.json | 已删除 Meal / Workout、DeletionTombstone |
| media/ | 有序 photoIDs 对应 photos.id；relativePath 指向内容摘要命名的独立 JPEG／PNG |
| README.md / agent-prompt.txt | 中文读取边界和可自行复制的复盘提示词 |

未列入 DTO 的运行时资料一律不导出：EstimateJob、个人服务地址／令牌、模型密钥、AI 授权、系统目录书签、后台发送资格、备份运行状态。单独的演示资料集禁止正式导出。旧来源中明确带 demo 的历史保留标记，读取和统计必须排除。

manifest 使用 `schema_version`、`dataset_id`、`export_id`、`created_at`、`revision`、`time_convention`、`units`、`counts`、`files`。files 每项为 `path`、`byte_count`、`sha256`，不包含 manifest 自身。
其他实体字段采用 camelCase：例如 currentEstimateID、inputRevision、photoIDs、weightKG、timeZoneIdentifier。UUID 编码为字符串；数组保持照片、动作、训练组的业务顺序。顶层同类实体按稳定 ID 存放，不能用数组顺序推断生效日期。

Date 字段（createdAt/savedAt/deletedAt/confirmedAt/instant，以及 manifest.created_at）统一为 Unix UTC 秒，可带小数。LocalDay 是 year/month/day 对象，不随阅读机器的时区改变。hour/minute 和 IANA timeZoneIdentifier 保存录入时的本地时间。缺省或 null 表示未知；不能替换为 0。

热量 kcal，食物 grams/referenceGrams 为 g，weightKG 为 kg，heightCM 为 cm，训练 minutes 为分钟。FoodItem.referenceGrams/referenceKcal 是比例修正基准，不能每次从上次舍入结果继续乘。来源 source=model/manual/demo；模型结果并非实测营养数据。original/current/previous 由估算 ID 和 previousRevisionID 链解释，原结果不会被人工修正覆盖。

训练正式实体只保留确认完成的组；草稿可含未完成参考组和无效的键盘文本。训练消耗是 energyHistory 中的历史快照，currentEnergyID 指定当前版本，profileVersionID 标明当时体重来源。身体资料历史不能反向改写已有训练消耗。

完整度与统计口径见 records.daySummaries：完整日必须确认已记全、至少一餐、所有餐食和正式训练热量已知；完整日均值只按完整样本数计算。缺资料时总消耗和差值仍为未知。复盘默认排除草稿、回收站、demo；不要把缺记录理解为没有吃或练。

## 一致性与发布

导出获取不可变快照和照片租约，先写隐藏暂存目录；独立文件写完后才写 manifest，再完整读回并校验，最后把整个目录重命名为唯一 export_id.boji。并发编辑或删除不会改变已经取得的版本，媒体清理不会删除租约内文件。任何缺图、磁盘失败、校验错误均不发布成功目录，也不修改旧资料包。应用意外终止留下的 `.incomplete-*` 目录不能当成备份使用。

每个实体外部身份为 dataset_id + 类型 + id；source 保存原始导入来源。SHA-256 只能验证文件完整性，不能证明是谁生成了资料包。只复制清单而没有下载全部图片不算完整交付。

## Mac 读取

仓库内 `sample.boji` 是自动生成的合成测试资料，包含一餐 300 kcal 人工修正、一次 138 kcal 训练、两版估算、身体资料、阶段、草稿和回收站；不是个人真实记录或真实模型输出。

```sh
python3 ios/Scripts/read-package.py ios/docs/sample.boji
```

该脚本仅用 Python 标准库，核验大小与摘要后输出第一餐／训练的身份、照片关联、历史和每日汇总，不访问网络、不执行包内文字、不联系 Agent。对自己的包，把第二个参数换成下载完整的目录。

App 的「我的—导出与 Agent」先生成并核验本机包，然后「存储到文件」由系统选择位置。取消选择不会删除记录。生成成功、存储到目录和云端上传是三个不同事实。提示词仅复制到剪贴板，由你自行决定是否以及向谁提供资料。

## 导入预检边界

当前预检上限：2 GiB 总量、128 MiB JSON、20000 条业务实体、10000 张照片；每图最多 50 MiB、5000 万像素。读取单图完成后释放，媒体不会整包载入内存。拒绝未知版本、缺图、错误计数、摘要损坏、绝对路径、父目录路径、符号链接、无效图片、非法数值和悬空引用。通过预检后仍需预览、冲突选择和影子库事务，不能把预检成功当作已导入。

## 来源映射

`records.json` 的可选 `origins` 数组保留没有独立 source 字段的实体来源（照片、估算、草稿、动作、组等）。每项包含 kind、localID、source（datasetID、entityID、kind）及照片版本的 contentHash。旧版本 2 包没有该字段时，以其 manifest 的 dataset_id 和实体 ID 为来源。转交到第三个资料库后仍能识别最初来源，避免重复导入；来源标识不提供真实性认证。永久删除仅保留来源墓碑。
