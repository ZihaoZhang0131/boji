# 规格与验证覆盖

当前 77/80 个实施任务已完成。下表逐项对应八份规格的要求，区分核心测试、已执行的 UI 测试和仍待外部条件的验收。具体执行结果及失败记录见 `verification.md`；6.6、12.3 和 12.5 保持未完成。

## native-app-shell

| 要求 | 证据 | 当前边界 |
|---|---|---|
| 原生导航覆盖全部核心入口 | LaunchTests + RootView + ExportPhotoTests | 模拟器系统导出与目录选择器已可视复测；真机待测 |
| 首次使用与演示资料隔离 | DemoTests + LaunchTests | 个人库／演示隔离已测 |
| 日期时间遵循实际使用情境 | TimeTests | 跨日、旅行与补记已测 |
| 像素风适配原生系统交互 | ProfileTests.testSmallScreenLargeTextNavigationHasAccessibleButtons + screenshots/dark.png | 模拟器已测；实际设备与 VoiceOver 待测 |
| 系统权限失败允许继续核心记录 | CameraAccessTests + BackupTests.directoryFailureKeepsLocalWritesAndLimitsAutomaticRetryUntilResume | 权限分支已测；真实系统拒绝权限待测 |

## local-record-storage

| 要求 | 证据 | 当前边界 |
|---|---|---|
| 本地提交结果真实可见 | RepositoryTests.failedSaveRollsBackAndRetryCommitsOnlyOnceAcrossRestart | 保存失败／重试已测 |
| 核心资料离线可用 | RepositoryTests.persistentRoundTripPreservesIdentityOrderNilAndHistories + LifecycleTests | 磁盘重启已测；飞行模式整体流程待测 |
| 草稿隔离与恢复 | LifecycleTests + MealEditorTests + WorkoutEditorTests | 草稿恢复／隔离已测 |
| 照片引用与资料生命周期一致 | MediaTests | 独立照片、租约与失败回收已测 |
| 删除记录提供三十天恢复期 | LifecycleTests.trashBoundaryRestoresIdentityInvalidatesJobsAndCreatesTombstone + ImportTests.deletedBackupRecordsRequireSeparateRestoreChoiceAndSamePackageNeverDuplicates | 30 天边界／恢复／墓碑已测 |
| 数据升级失败保护原资料 | MigrationTests + WorkspacePortabilityTests | 各激活边界／回退已测 |
| 外部读取仅包含已提交的一致版本 | PortabilityTests.exportLeaseKeepsOneRevisionWhileRecordsAreEditedAndPurged | 一致快照已测 |

## profile-and-goals

| 要求 | 证据 | 当前边界 |
|---|---|---|
| 身体资料提供明确的校验与缺失状态 | EnergyTests.profileBoundariesAndHistoryDates + ProfileTests | 边界／未知目标已测 |
| 个人资料按生效日期保留版本 | ProfilePersistenceTests.backdatedProfileRequiresConfirmationAndDoesNotRewriteTraining | 版本选择已测 |
| 回溯资料变更需要明确说明影响 | ProfilePersistenceTests.backdatedProfileRequiresConfirmationAndDoesNotRewriteTraining | 显式回溯确认已测 |
| 阶段目标保留连续历史 | ProfilePersistenceTests.goalChangesPreservePersonalTargetAndReopenWithoutDuplicateStages | 目标／备注与历史已测 |
| 估算参数与目标不冒充事实结论 | EnergyTests + docs/profile-and-energy.md | 未从目标生成未经输入的摄入事实 |

## meal-recording

| 要求 | 证据 | 当前边界 |
|---|---|---|
| 照片或文字满足最低保存条件 | MealTests.textOnlyMealReopensWithSelectedTimeAndClassification + MealEditorTests | 文字／空记录已测 |
| 系统拍照和相册导入保留真实内容 | MediaTests + MealEditorTests.testPhotoPartialFailureLimitAndDiscardProtectFormalCopy + ExportPhotoTests.testOfflineMultiPhotoDraftManualEditDeleteAndRestore | JPEG／PNG／HEIC 内核、模拟器多图完整 UI 流程已测；真机拍照成功，相册首次未显示，修复后用户复测缩略图出现；HEIC 和权限拒绝仍待实测 |
| 补记和编辑保留记录身份 | MealTests + LaunchTests.testMealDraftRestartManualEditAndTrash | 编辑身份与取消已测 |
| 识别输入变化使旧结果过期 | MealTests.mealFactsAndRecognitionInputsHaveSeparateRevisions + EstimationTests | 输入失效已测 |
| 详情和删除恢复闭环 | LaunchTests.testMealDraftRestartManualEditAndTrash + ExportPhotoTests.testOfflineMultiPhotoDraftManualEditDeleteAndRestore + LifecycleTests | 文字与离线多图餐食 UI 均通过 |
| 原始饮食保存不依赖识别结果 | EstimationTests.draftEstimateKeepsIdentityWhenSavedBeforeOrAfterResult | 识别与保存竞争已测 |

## workout-recording

| 要求 | 证据 | 当前边界 |
|---|---|---|
| 动作和组支持负重与自重 | WorkoutTests.workoutValidationReferenceAndBatchBoundaries + WorkoutEditorTests | 负重／自重边界已测 |
| 参考组和完成组严格区分 | WorkoutTests + WorkoutFlowTests | 只提交已完成组已测 |
| 复制训练生成新的当次记录 | WorkoutTests.workoutFinishCopyAndReestimateKeepHistoryAndIdentity + WorkoutFlowTests | 新身份／清空时长及完成状态已测 |
| 批量补记创建用户确认完成的组 | WorkoutTests.workoutValidationReferenceAndBatchBoundaries | 批量边界与实际组数已测 |
| 训练暂停和历史修改不制造重复记录 | WorkoutEditorTests + WorkoutFlowTests | 退出恢复／编辑／去重已测 |
| 运动消耗关联当次计算输入 | WorkoutTests.completeTrainingLifecycleSurvivesRestartWeightChangeCopyAndTrashWithoutDoubleCounting + WorkoutFlowTests.testWorkoutRestartsFinishesEditsCopiesAndRestores | 改体重不漂移、复制清空完成状态与完整 UI 串联已测 |
| 已完成训练可删除与恢复 | WorkoutFlowTests + LifecycleTests | 删除恢复与计数已测 |

## energy-and-review

| 要求 | 证据 | 当前边界 |
|---|---|---|
| 日常代谢计算遵循固定口径 | EnergyTests.specifiedEnergyExamplesAndUnknowns | 固定公式已测 |
| 训练按整次净消耗计算 | EnergyTests + WorkoutTests | 净消耗与快照已测 |
| 摄入保留已知量和缺口 | ReviewTests.incompleteIntakeAndUnknownBurnAreNotZero | 已知摄入与缺口已测 |
| 完整度由用户确认且随事实修改失效 | ReviewTests.confirmationsSurviveEstimatesButNotMovedFacts | 事实失效、估算保留确认已测 |
| 总消耗和差值遵循缺失规则 | ReviewTests.incompleteIntakeAndUnknownBurnAreNotZero | 总消耗／差值缺失规则已测 |
| 时间线及三种记录回顾读取正式资料 | ReviewTests.twoCompleteDaysAverageAndSearchUseOnlyFormalFacts + LaunchTests | 正式事实与搜索已测 |
| 自定义日期区间与图表完整性 | ReviewAITests.testReviewDateEditingCommitsOnlyOnConfirm + ReviewPresentationTests + ReviewTests.customReviewRangesIncludeBothEndpointsAndRejectInvalidSpans | 默认近 7 天、确认／取消、单日及 90／91 天边界、跨年闰日与缺失值已测 |
| 历史训练重估必须显式触发 | WorkoutTests.workoutFinishCopyAndReestimateKeepHistoryAndIdentity | 重估显式快照历史已测 |

## food-estimation

| 要求 | 证据 | 当前边界 |
|---|---|---|
| 直接调用前明确授权 | EstimationTests.noConsentDemoAndChangedPolicyNeverUploadPhotos + KeychainTests + ReviewAITests；直连设置页 UI 测试及真机联调 | 用户在 iPhone 本机输入新平台密钥并授权；真实千问响应已核验，旧地址授权迁移时失效 |
| 密钥只留在本机 | KeychainTests + PortabilityTests.portablePackageRoundTripsAllEntitiesAndExcludesRuntimeCapabilities + QwenDirectTests | Keychain 不同步、导出排除、固定端点契约已测 |
| 无配置不产生伪造估算 | TimeTests.unconfiguredProductionServiceCannotInventAnEstimate + QwenDirectTests | 未配置不返回演示值；真实千问结果已与本地资料分开验证 |
| 自动和手动识别遵循同一版本规则 | EstimationTests.turningAutomaticOffCancelsOnlyUnsentAutomaticWork + draftEstimateKeepsIdentityWhenSavedBeforeOrAfterResult | 自动／手动与草稿身份已测 |
| 直连调用有明确费用和重试边界 | QwenDirectTests.qwenDirectLostResponseIsNotAutomaticallyRetriedAfterRestart + EstimationTests + 真机任务历史 | 丢响应不自动重发；明确重试和本机每日次数限制已验证；真机前两次无法识别、第三次成功，未由测试工具重复发送 |
| 模型输出必须校验 | QwenDirectTests + services/food-estimation/test/*.test.ts + 真机 710 kcal 结果 | JSON 结构和错误合计已测；真实 `qwen3-omni-flash` 结果经校验后入历史 |
| 迟到结果不能覆盖新事实 | EstimationTests.lateModelResultsNeverOverwriteNewerFacts | 七类竞争已测 |
| 人工修正保留来源和历史 | MealTests.manualCorrectionsKeepOriginalModelRevisionAndEveryConfirmedChange + EstimateDisplayTests.testUnknownManualFoodRatioAndRevisionHistory + 真机重启／导出／导入 | 真机原始 AI 710 kcal、当前人工 700 kcal 与照片关联在重启和跨隔离库导入后均保留 |

## data-portability

| 要求 | 证据 | 当前边界 |
|---|---|---|
| 完整导出使用独立可读资料包 | PortabilityTests.portablePackageRoundTripsAllEntitiesAndExcludesRuntimeCapabilities + Scripts/read-package.py | Mac 已下载并完整核验真机导出的 10 文件资料包 |
| 导出排除凭据和运行时授权 | PortabilityTests + WorkspacePortabilityTests + 真机空库导入 | 排除凭据／授权；真机导入后服务地址、授权和识别任务均为空 |
| 导出完整性可验证 | PortabilityTests.failedExportDoesNotPublishOrDamageLastCompletePackage | 完整校验与发布中断已测 |
| 导入先校验和预览再提交 | PortabilityTests.packagePreflightRejectsUntrustedFilesBeforeAnyDatabaseWrite + ImportTests | 路径／资源上限／影子库已测 |
| 重复导入和冲突处理可预测 | ImportTests | 跨库来源、重复、冲突与恢复选择已测 |
| 原型 JSON 有显式迁移路径 | PrototypeTests | 所有已知实体、嵌图、未知／示例与确认已测 |
| 用户控制 iCloud Drive 目录授权 | BackupTests + BackupView + 真机目录选择／断开／重连 | 真实 iCloud Drive 目录授权、断开、重连及 Mac 下载核验已测 |
| 自动备份不夸大云端可用状态 | BackupTests.backupCoalescesEditsAndOnlyMarksItsActualSnapshotRevisionWritten + uploadStatusRequiresEveryFileAndNeverClaimsMacDelivery + 真机／Mac 核验 | 真机系统确认上传与 Mac 实际下载分开显示；Mac 完整核验真实包 |
| 备份冲突不自动回写本机 | BackupTests.externalPointerEditDuringPublicationRemainsUntouched + backupDetectsExternalModificationAndDoesNotOverwriteUnknownFilesOrReimportData | 外部冲突保护已测 |
| Agent 交付说明表达数据边界 | PackageReadingGuide + PortabilityTests + docs/import-and-backup.md + ExportPhotoTests | 中文提示词、模拟器系统导出选择器及真实 iCloud Drive 到 Mac 的包核验已测 |

## 证据目录

`BojiCore/Tests/BojiCoreTests` 为核心测试，`Tests` 为原生模型／装配测试，`UITests` 为界面测试，`services/food-estimation/test` 为服务验证。Xcode 结果包位于本地 `.build/`，不随源代码提交；关键截图和结论保存在 `docs/`。

用户的 iPhone 14（iOS 26.6）已完成签名安装和启动；用户选定的 iCloud Drive 测试目录已在手机授权，Mac 下载并核验真实快照，断开与重连也已实测。旧密钥误发到聊天后，用户确认已撤销并在手机配置新平台密钥；真机真实识别、人工修正、重启、回顾、完整导出和空库导入均已验证。Mac 已解锁，模拟器可视复测已执行。剩余真机飞行模式整体流程和 12.3 中的 HEIC、拒绝权限、深色、VoiceOver 等矩阵项尚未逐项验收；待办以 OpenSpec tasks.md 未勾选项为准。

## 我的与设置简洁化（2026-10-25）

| 范围 | 验证 | 结论 |
|---|---|---|
| 当前资料状态、授权政策状态和失败刷新 | MinePresentationTests | 今天生效规则、旧政策不算授权、开关不授权、改密钥请求失败、撤回／断开、重新载入已测；内存凭据与模拟服务 |
| 子页排版、导航和阶段主操作 | MineSettingsTests + ProfileTests + ExportPhotoTests | 小屏、最大辅助字号、44 pt 操作、保存返回、导出／系统文件选择器、恢复取消已测 |
| 回收站计数、永久删除确认和恢复 | LaunchTests.testMealDiscardRestartManualEditAndTrash + LifecycleTests | 计数刷新、取消不删除、恢复后重启、保留期限已测 |
| 网页布局与键盘焦点 | verify-mine.cjs + npm test | 320／393 px 浅深色、200% 重排、嵌套返回焦点、即时开关、导出重试及记录／回顾回归已测 |

## 2026-10-25 iCloud 自动备份恢复

- `BackupTests`：旧授权等待明确启用、启停持久化、停止后手动备份、取消不耗费重试、6 秒合并、并发串行发布、切换前排空、15／60／300 秒退避与三次上限、空间错误、外部指针保护、完整文件上传证据和 30 秒刷新限制。
- `BackupSettingsTests`：首次目录选择即备份、后续自动更新、重启与更换目录、导入预览后停止、恢复前更换目录且停止、演示隔离、操作错误不被自动轮询清除；320／393pt 浅深色及最大辅助字号的六种状态截图。
- `MineSettingsTests`：数据管理入口、系统目录选择器加载后下拉关闭、放弃选择后重启仍未配置、系统返回、44pt 操作区及最大字号滚动。
- Web 继续只导出 JSON，`verify-mine.cjs` 检查 iPhone 自动备份提示；记录、回顾与其他设置沿用完整回归。
- 本轮真实 iCloud 验收由用户选择稍后执行：尚未验证本轮真机首次/后续上传、停止以及 Mac 完整下载校验；模拟上传证据和历史验收不能替代。
