# 薄记资料包 v2

本包含身体资料与照片，请仅交给你信任的接收方。无需薄记 App；JSON 使用 UTF-8，照片使用包内相对路径。
阅读前核验 manifest.json 内所有文件的 byte_count 与 SHA-256。清单本身到达不代表图片已下载；SHA-256 只验证完整性，不证明来源真实性。先把完整目录下载到本机再读取。

- records.json：未在回收站的餐食 meals、训练 workouts、全包照片 photos、确认完整度 confirmations、同一快照计算出的 daySummaries。
- profiles.json：身体资料生效日历史；同一天 sequence 大者后生效。
- goals.json：阶段历史；startDay 含当天，endDay 不含当天。阶段不是摄入目标。
- estimates.json：全部人工／模型／演示估算历史；当前结果由餐食 currentEstimateID 指向，还须 inputRevision 相符。previousRevisionID 连接原估算和修正。source=model/manual/demo；demo 不计真实摄入。
- drafts.json：明确 kind 的草稿，meal 或 workout 二者之一；不计正式统计。编辑草稿不会提前修改正式记录。weightText/repsText 保留未完成键盘输入，不能用作完成组。
- trash.json：回收站餐食、训练及永久删除墓碑；不计正常查询。重新导入旧记录不等于撤销墓碑，需用户明确恢复。
- media/：照片按内容 SHA-256 命名；photos 中 id 与餐食有序 photoIDs 关联，relativePath 为包内路径。

UUID 是稳定身份。外部身份为 dataset_id + 实体类型 + id；source 记录从别的资料集导入的原身份。修订号只在相应身份内比较，不能仅凭文件修改时间覆盖记录。
Date 类字段均为 UTC Unix 秒（可带小数）；localDay/hour/minute 与 timeZoneIdentifier 保留录入时的本地日期、时间和 IANA 时区，不能按读取机器时区重新分日。
热量单位 kcal、食物 grams 为 g、weightKG 为 kg、heightCM 为 cm、minutes 为分钟。JSON 缺省或 null 表示未知，不是零。
日常基线和 MET 均为估算，训练 energyHistory 保留当时体重、时长、算法版本；不要拿最新体重改写旧消耗。只计算 completed=true 的正式训练组。
缺记录不是没有吃、没有练。完整日须确认记全、至少一餐且餐食与训练热量有效。日均值只按完整样本日数计算，并显示样本数；日常基线未知时总消耗与差值未知。daySummaries 是导出时计算结果，事实仍以记录为准。
包中不含模型密钥、个人令牌、目录书签、联网授权或待执行任务。导入不会自动识别照片。正式导出禁止整个演示空间；旧迁移保留的 demo 来源也须排除真实统计。
agent-prompt.txt 可复制后自行配合完整资料包交给 Agent；App 不会代你发送任何内容。