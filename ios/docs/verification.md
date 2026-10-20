# 原生验证记录

本文件只记录实际运行结果，不以模拟服务替代真实模型、iCloud 或真机验收。

## 3.1—3.3、3.5 资料与目标（19:49 更新）

`profile-scroll-verification` 单项 UI 测试 108.79 秒通过，整个所选测试集通过：填写性别公式、年龄 28、身高 175、体重 70、活动 1.2，留空摄入目标并保存；首次阶段目标为空且保存不可用，选择保持状态后保存；终止／重启后阶段与体重保留，摄入目标仍为空。保存截图 `screenshots/profile-fields.png`。字段及阶段当前值有明确的可访问标签与值，小幅滚动可以定位所有输入。

35 项领域／存储测试通过，覆盖缺参数、范围上下界、NaN、不适用年龄、同日版本顺序、回溯影响区间、昨天资料不变、训练历史快照不变、阶段同日切换、倒置日期拒绝及只改备注不新增阶段。资料生效及估算口径说明见 `profile-and-energy.md`。回归中发现一个用例错误依赖无序数据库查询的第一条记录，改为按稳定 ID 选取后通过；生产统计行为没有因此改变。

## 5.1—5.7 训练完整流程（19:46 更新）

`menu-profile-verification` 的训练 UI 用例 130.71 秒通过：选择常用自重动作，填写并确认一组，收起后终止／重启恢复，结束训练，保留未知消耗，编辑训练名称，再复制为全部未完成的新草稿，放弃复制草稿，删除原训练并从回收站恢复，正式列表保持一条。菜单完整行现在都能点击，键盘通过 SwiftUI 焦点正确收起。

领域与原生模型测试覆盖负重／次数上下界、六组仅两组确认、零完成组阻止、复制新身份且清空旧消耗、1—30 组批量生成、八／八／七实际组、无效输入原样恢复、缺体重或时长保留未知、明确重估 138 kcal 并保留旧历史，以及草稿唯一性和存储失败不改变正式记录。操作说明见 `recording.md`、`profile-and-energy.md`。

同一测试集的个人资料流程已完成保存与重启，最后在定位目标输入框时失败；该用例已改为小幅滚动及稳定字段标识后单独复测。

## 7.1—7.9 私有识别服务（19:44 更新）

`cd services/food-estimation && npm test`：TypeScript 构建通过，12 项服务测试通过。测试覆盖未配置不返回热量、鉴权与 owner 隔离、三阶段政策检查、图片实际格式／尺寸／方向／过期校验、提交幂等与正文冲突、24 小时首发边界、持久重启、有界执行、超时与取消、每日额度事务、分钟限流、十进制合计与异常输出、恶意备注作为素材、24 小时／7 天清理及日志凭据扫描。

另一个测试实际启动编译后的 Node 服务子进程，通过临时证书且验证证书的本地 HTTPS 代理提交与查询，模型端使用本地 HTTPS 协议 fixture。真实停止和重启进程后同一任务仍能查询；重发同 ID 后协议 fixture 调用数仍为 1。没有连接外部模型或正式域名，没有关闭 TLS 验证。完整部署、持久磁盘、预算、政策、令牌撤销及回退说明位于 `services/food-estimation/README.md`，提供 systemd 与 Caddy 配置范本。真实供应商联调任务 8.7 仍未完成。

## 4.2、6.1—6.3、6.5 图片与回顾（19:40 更新）

`focus-review-verification` 中七项原生单元测试均通过，新增相机无硬件、拒绝、受限及首次授权决策用例。真实 PhotosPicker 手动选择两个合成测试文件成功，包含有方向标记的 HEIC 与 PNG，显示 2/9 及正确方向，截图 `screenshots/photos-imported.png`。照片模型用例覆盖九张限制、部分读取失败、放弃修改保留原照片；ImageIO 测试实际解码 JPEG／PNG／HEIC。没有将模拟器结果当作真机相机验收。

饮食 UI 用例在原有闭环后增加首页汇总、确认已记全、7／30 天平均及饮食搜索，111.97 秒通过：同一 200 kcal 在详情、首页与平均值一致，样本数均为 1。35 项领域／存储测试覆盖 500 kcal 加未知餐食、缺时长或资料的未知总消耗、两个完整日期的七天平均 600、DTO 编解码、正式记录筛选、稳定时间线及跨日修改失效。回顾说明见 `review.md`。

该测试集仍有两项 UI 失败：阶段 Picker 未输出可访问值，训练 Menu 的外层可访问区域大于实际点击区域。正在修复；没有把整个测试集记为通过。最大字号导航和 44 点触控区验证再次通过。

## 4.3、4.5 饮食详情与人工热量

`recording-keyboard-verification` 中 `testMealDraftRestartManualEditAndTrash` 全部通过（130.5 秒）：文字草稿重启恢复、正式保存、详情、人工填写 200 kcal、放弃历史修改、删除、回收站恢复、列表只保留一条、再次重启仍显示 200 kcal。模型测试另验证删除草稿中的照片后放弃，正式照片集合与副本均保留。

领域与存储共 35 项通过：跨日移动清除两个已有确认且旧日不再显示，新日仅增加同一身份；比例修改 100 g／200 kcal 至 150 g 得 300，来回修改不累计舍入误差；未知克数不换算，负值、NaN 和超限拒绝。模拟模型输出仅用于历史规则测试，明确标为 `fixture-only`，验证原始模型版本、两次人工版本和前序关系都保留，不代表真实模型联调通过。

## 4.1 最低保存条件与补记

33 项领域／存储测试通过。文字餐食带补记日期、时区、餐次和标签写入后，重新打开磁盘库与原记录完全相等；重发同提交 ID 后仍只有一条。模拟器模型测试阻止空表单，并验证纯文字与分类字段保存；原生 UI 已走通纯文字草稿终止／重启恢复、正式保存及详情打开。图片模型测试另验证九张限制、混合成功与失败及放弃编辑后原照片仍可读。后续人工保存、删除恢复的完整 UI 用例仍单独记录。

## 4.4 识别输入与事实版本

领域与存储 32 项测试通过。新增用例区分照片顺序／备注修订和日期／餐次／标签修订：前者清除当前热量引用，保留旧估算历史；后者保留有效估算。已改变再改回的输入也保持更高输入版本，不能让在途旧结果重新有效；旧事实版本提交被拒绝。回顾仅采纳当前输入版本且结构校验通过的估算，未知和失效不会计为零值。原生详情显示待重估原因并提供历史入口。

## 2.4 草稿与录入模型

模拟器原生单元测试五项通过，包含饮食空表单阻止、文字／餐次／标签草稿恢复、正式保存同身份、历史修改放弃、训练无效次数字符串恢复及仅完成组提交。`recording-ui-verification` 的饮食流程已实际执行终止 App 后重新启动，再次打开表单并断言草稿原文一致，随后成功保存并打开详情；该完整 UI 用例稍后在键盘遮挡人工保存按钮处失败，不能据此声称整个饮食闭环通过。基础仓储测试另外覆盖保存失败状态与重试、重新打开磁盘库恢复、唯一训练草稿冲突、迟到写入及放弃墓碑。

当前领域与存储测试扩展为 31 项通过，增加训练边界、复制／重估历史及回顾缺失规则。仍需继续原生界面闭环验收。

## 1.3 原生入口与日期

`meal-verification.xcresult` 中 `testAppLaunches` 和 `testEmptyNavigationAndHistorySelection` 通过：隔离空库启动、三页切换、前一天、回到今天、重启后今天日期、个人资料待填写及阶段未设置。纯时钟测试验证跨午夜、编辑中不跳日、历史选择保持、上海／洛杉矶切换及旧记录时区保留。系统当前时间由生产时钟读取，页面每分钟刷新。该次测试集中的饮食入口测试因父级可访问标识覆盖按钮标识失败，已修正并待单独复跑，未用整个失败测试集宣称全部通过。

## 2.8 存储故障组合（19:13 更新）

`cd ios/BojiCore && swift test`：26 项通过，包含各参数场景。组合测试使用临时磁盘库，注入保存前错误，确认旧正式值不变；同提交 ID 重试、重新打开及重复提交只保留一条记录；草稿失败状态可见，重试后重新打开可恢复最后版本；迁移失败后的完整旧代恢复另有四个边界验证。没有改动用户原型资料。

此次并发运行首次发现 Core Data 在多个容器同时建表时崩溃（`NSSQLEntity_DerivedAttributesExtension`）。已将容器创建及迁移串行化，修复后整套测试通过。旧失败结果不计作通过。模拟器字体加载与最低系统版本两项测试也已通过；导航 UI 的组合控件查询正在修正，尚未记为整体 UI 通过。

## 2026-10-17 环境

- Xcode 26.6（17F113），iOS／iOS Simulator SDK 26.5。
- Swift 6.3.3，XcodeGen 2.45.3；工程最低系统版本 iOS 17.0。
- 开始时没有安装模拟器运行时，后通过 `xcodebuild -downloadPlatform iOS -architectureVariant arm64` 下载并安装 iOS 26.5（23F77）。
- 已创建 Boji iPhone SE（第三代）模拟器，ID 为 `16F94325-E1DA-4CA0-A0C7-540404563642`。

## 1.1 工程构建与启动

已创建 `Boji.xcodeproj`、共享 `Boji` scheme、应用、单元测试和 UI 测试 target。已执行：

```sh
cd ios
xcodegen generate
xcodebuild -project Boji.xcodeproj -alltargets -configuration Debug \
  -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO \
  SYMROOT=/tmp/boji-native-products OBJROOT=/tmp/boji-native-intermediates build
```

结果：`BUILD SUCCEEDED`，应用及两个测试 target 均完成 arm64／x86_64 模拟器编译和链接；这是构建结果，测试尚未执行。产物 `Boji.app/Info.plist` 中 `MinimumOSVersion` 为 `17.0`。`plutil -lint` 工程文件通过，`openspec validate native-iphone-core --strict` 通过。

安装运行时前，共享 scheme 构建因缺平台退出码 70；安装后使用以下命令完成构建、安装和启动，`TEST BUILD SUCCEEDED`，启动返回 PID 89926，随后通过 Simulator 画面确认应用已显示导航、当前日期和空记录。截图：`screenshots/initial-launch.png`。UI 测试结果另记，不以启动成功代替后续流程验收。

```sh
xcodebuild -project Boji.xcodeproj -scheme Boji -configuration Debug \
  -destination 'platform=iOS Simulator,id=16F94325-E1DA-4CA0-A0C7-540404563642' \
  -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO build-for-testing
xcrun simctl install 16F94325-E1DA-4CA0-A0C7-540404563642 .build/DerivedData/Build/Products/Debug-iphonesimulator/Boji.app
xcrun simctl launch 16F94325-E1DA-4CA0-A0C7-540404563642 com.boji.personal
```

初次工程验收使用空记录应用。此次未执行原有网页截图测试，因为原型代码没有修改。

## 1.2 模块边界

`swift build --target BojiDomain` 通过；`swift test` 的 4 个 Swift Testing 测试通过，覆盖跨午夜、历史编辑保护、跨时区记录与往返编码、补记时间，以及未配置识别服务不返回模拟结果。应用装配使用 `UnconfiguredEstimationService`，测试时钟只位于测试 target。

接入本地 package 后再次执行上述全 target 模拟器 SDK 编译通过。具体模块说明见 `architecture.md`。这不替代 1.3 的原生 UI 验收。

## 1.5、2.1、2.2 独立验证

`swift test` 9 项通过。演示使用不同资料集及内存库，往返两次后个人记录和草稿快照完全一致；演示识别与导出策略均拒绝操作。SwiftData 临时磁盘往返保留稳定 ID、照片／组顺序、资料／估算／训练历史、删除时间、墓碑与空热量。注入保存前空间不足后无新记录或虚假成功；对已有餐食的失败修改保持原值，重新打开仍成立；重试和成功后重新提交均只生成一条记录。预期修订冲突与第二份活动训练草稿被拒绝。

模型使用显式 `cloudKitDatabase: .none`，未连接任何 iCloud 数据库。App 与两个测试 target SDK 构建通过，尚未把模拟器 UI 测试记为通过。

## 2.3 照片文件

`swift test` 13 项通过（图片中断测试含两个参数场景）。使用生成的 JPEG 测试图验证旋转方向、GPS 去除、缩略图及删除原文件后的副本读取。在暂存后、发布后和数据库提交前注入中断／磁盘错误，均没有产生悬空成功记录；准备图片可重试，启动清理可移除无引用文件。缺失图片阻止提交。导出值快照期间删除记录并清理，租约仍保护照片，释放后才允许回收。

## 2.6、2.7 升级与快照

升级四个注入点（读取旧快照后、影子库完成后、激活前、激活后）均在重新打开后读到一套完整旧／新资料，照片可读且原提交收据保持幂等。未知版本 99 在改写前失败，指针字节不变；显式恢复回到同一资料集的旧修订。以上与基础测试共 18 项通过（含参数场景）。1.1 的共享 scheme `build-for-testing` 已通过，运行测试仍单独记录。

快照测试在租约持有期间提交删除及执行清理，取得的快照仍保留原记录，图片可读；释放后才能清理。这验证了并发操作发生在导出读取期间时的一致性与文件保护。

## 3.4 计算基础

`swift test` 现有 21 项通过。规格数值 1659（静息）、1991（日常）、138（45 分钟力量净消耗）一致；计算以整次训练输入为参数，没有按动作重复累加入口。体重／时长未知返回 nil，越界时长被拒绝；训练快照保存体重、时间、MET 类型、来源资料 ID 与 `met-net-v1`，更改当前资料不改写历史值。附加测试覆盖资料边界、同日提交顺序、回溯影响区间和阶段同日归属，相关表单任务仍未勾选。

## 1.4 像素组件与小屏外观

2026-10-17：iPhone SE（第三代）模拟器，iOS 26.5。`LaunchTests` 的最大辅助字号与主要触控区检查已通过；所有主要按钮至少 44 pt。另将模拟器切为深色，实际查看首页日期、空状态、操作和三项导航均可读，截图为 `screenshots/dark.png`，检查后恢复浅色。大字号截图为 `screenshots/large-text.png`。字体注册测试通过，OFL 与转换来源随 App 资源保留。基础语义由原生控件、明确 label/value 提供；真实设备 VoiceOver 连续操作仍属于 12.3，未代替该项实测。

## 8.2—8.5 原生识别队列与结果竞争

2026-10-17：`BOJI_RUN_SERVICE_INTEGRATION=1 swift test --package-path ios/BojiCore`，44 项测试通过。补充了连续三版离线输入只提交最后一版、重开磁盘库后按 remote ID 轮询、取消远端任务、网络／限流最多七次发送和额度／供应商超时终止状态。已覆盖离线三天首发、响应丢失后的请求正文与 ID 不变，以及备注修改、删除恢复、撤权、政策变更、资料集切换、放弃草稿、人工先填 600 kcal 的竞争保护。草稿在结果前／后保存均保留 meal ID；迟到的自动保存不会清掉估算，历史表单不能覆盖其间正式人工修正。

新增跨语言测试从真实 Swift `ServiceClient` 通过 HTTPS 访问 TypeScript 服务和 SQLite。测试生成一次性 SHA-256 / serverAuth 证书，仅向该测试 URLSession 提供 CA 锚点并执行系统信任及主机名校验，未修改系统信任或生产 TLS。第一次提交被服务接收后代理主动断开响应，重发和重启后的查询仍只有一次固定协议结果调用；未授权请求零上传、上传一次、取消后查询为 cancelled，输出扫描无测试令牌或备注。初次测试证书缺少适当用途，系统拒绝连接；补充用途后通过。模型为固定的 `protocol-only`，不代表 8.7 的真实模型验收。

## 9.1—9.3、9.5 资料包与独立读取

2026-10-17：启用真实 HTTPS 协议联调的全部核心测试 49 项通过（`BOJI_RUN_SERVICE_INTEGRATION=1 swift test --package-path ios/BojiCore`）。新增资料包往返、运行时资料排除、并发编辑删除快照、四处磁盘中断、缺图、未知版本、坏摘要、越界路径、符号链接、超大稀疏文件、无效图片和非法数值测试。Date 使用 Unix 秒，发布结果返回读回校验后的 manifest，避免内存 Date 与持久化表示的细微精度差异；测试按稳定实体身份比较顶层记录，业务内部照片／动作／组仍逐项比较顺序。

`ios/docs/sample.boji` 由测试生成，只有合成资料。独立执行 `python3 ios/Scripts/read-package.py ios/docs/sample.boji` 验证 9 个文件，读出一餐、一次训练和一张照片；餐食人工 300 kcal、两版历史，训练 138 kcal、一个完成组，完整度为 true。未连接任何外部 Agent。格式及逐字段边界见 `docs/package-format.md`。

## Keychain 与客户端构建

无签名模拟器构建不能访问 Keychain，第一次检查失败；改为模拟器本地 ad-hoc 签名后，`KeychainTests.testDeviceOnlyCredentialRoundTripAndEndpointIsolation` 通过（0.070 秒）。构建使用 `CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES`，不需要用户开发者证书，也不代表真机签名安装验收。正式代码不包含测试 CA 或模型密钥，资料包使用 allowlist DTO 排除 AI 设置、任务和目录授权。

### 6.4 小屏回顾

`ReviewAITests.testEveryChartDayCanBeSelectedOnSmallScreen` 在 iPhone SE（第三代）iOS 26.5 模拟器通过（58.814 秒）。逐一点击 7 天和 30 天共 37 个日期，每个目标宽度至少 44 pt，选择日期与详情一致。范围切换重置横向位置；未知日期不画成零值。核心测试 `twoCompleteDaysAverageAndSearchUseOnlyFormalFacts` 验证七天中仅两天完整时按两天平均。结果见 `.build/signed-export-verification.xcresult`。

### 导入内核与原型迁移（任务 2.5、10.1、10.3、10.4）

`swift test --package-path ios/BojiCore` 最新 60 个测试通过（`/tmp/boji-prototype-tests-v2.log`；未设置真实协议夹具开关的该次运行不包含 HTTPS 集成执行）。原生包预检覆盖未知版本、缺图、摘要错误、路径越界、符号链接、超大包、无效数值及图片损坏；所有校验先于活动库提交。四个影子库激活边界注入空间不足，重开只得到完整旧库或完整新库。

原生包连续导入以及跨第三个资料库的再次导入不增加实体；永久删除和已放弃草稿需要单独恢复选择。已记全状态单独变化也进入预览，混合日期不自动沿用确认。回收站保留时长、照片租约和墓碑测试与旧备份恢复测试共同验证任务 2.5。

原型样例来自 `app.js` 和 `energy.js` 的已知导出结构，迁移覆盖饮食、嵌入 PNG、训练完成组、活动草稿、资料、目标、完整度以及人工修正的原始示例历史。重复转换身份一致，导入第二次不增量；`demo-ai` 不产生真实摄入。未确认单位／时区／不确定历史身份会拒绝转换，路径图片和非法 data URL 失败后不发布资料包。实际用户原型文件尚未提供，因此此处验证使用合成样例。

### 全量核心、目录备份与原生装配复测

- `BOJI_RUN_SERVICE_INTEGRATION=1 swift test --package-path ios/BojiCore`：**68 个测试通过**，包含真实 localhost HTTPS Swift—TypeScript 协议夹具（`/tmp/boji-all-core-tests.log`）。训练完整生命周期新增验证 70 kg 旧快照不随 80 kg 新资料漂移、复制时清空消耗与完成状态、编辑和恢复后只计数一次。
- `npm test --prefix services/food-estimation`：**12 个服务测试通过**，无跳过（`/tmp/boji-final-service-tests.log`）。
- Xcode `build-for-testing`：当前导入、原型迁移、目录备份页面与测试 target 编译通过（`/tmp/boji-portability-unit-build.log`）。
- `BojiTests`：**9 个原生单元测试通过**，包含临时签名下的 Keychain，以及真实 WorkspaceModel 导入刷新、旧仓储拒绝写入和回退刷新（`.build/portability-unit-verification.xcresult`，`/tmp/boji-portability-unit-tests.log`）。
- `ReviewAITests.testUnconfiguredAIAndAutomaticToggleDoNotAuthorizeSending`：原生 UI 通过（31.546 秒），自动开关保存后重启保留，开关不等于联网授权。结合未授权零真实 HTTP 上传、政策变更与撤回的核心／集成测试验证 8.1。

目录备份验证包括实际临时目录书签解析与协调写入、更换和断开、未知文件保护、坏书签失败但本机继续保存、六秒合并编辑、导出时新提交仍待备份、四个发布中断点、指针写后状态保存前中断的恢复、外部并发指针改动及有界自动重试。全部必要文件都有上传证据才允许显示上传确认；临时本机目录的系统属性可能缺失，按实现显示未知，不假设已上传。

Mac 解锁后在 iPhone SE（第三代）iOS 26.5 模拟器完成 `ExportPhotoTests` 两项 UI 测试（`.build/export-photo-retest2.xcresult`）。正式资料包生成后系统文件选择器确实打开，取消后仍能再次导出。离线且未配置 AI 的独立资料库中，系统相册一次选择两张照片，草稿折叠、强制重启后恢复、保存、人工填 420 kcal、编辑备注、删除、回收站恢复、再次重启和照片关联均通过。手动可视核对亦看到相册 `2/9` 与两张缩略图。iOS 26 的 PhotosUI 远程可访问性网格会在反复枚举时失效，UI 测试改用本模拟器固定首行照片位置；该坐标只用于测试，不属于产品实现，也不代表真机相机验收。

在另一个隔离资料库中，模拟器的系统文件夹选择器从「浏览—我的 iPhone」授权本机目录，界面显示已连接与更换／立即备份／断开操作；确认断开后恢复「未连接 · 本机记录正常保存」。结合 `DirectoryBackupTests` 的真实临时目录测试，已覆盖书签、协调写入、更换、撤权、坏书签及非薄记文件保护。此处的 File Provider Storage 是模拟器本机位置，并非真实 iCloud Drive 同步或 Mac 下载验收。

`WorkoutFlowTests.testWorkoutRestartsFinishesEditsCopiesAndRestores` 在完整补入个人资料与实际 30 分钟时长后通过（`.build/workout-estimate-flow2.xcresult`）：训练草稿重启恢复、完成组写入、体重从 70 kg 改为 80 kg 后旧训练 kcal 快照不变、修改旧训练、复制为零完成组草稿、放弃副本、删除和回收站恢复均在同一隔离库验证。第一次测试未填时长，按规则显示「待估算」，随后修正测试输入；这不是产品错误。

`EstimateDisplayTests.testUnknownManualFoodRatioAndRevisionHistory` 在 iPhone SE 模拟器通过（`.build/estimate-history-final.xcresult`）：无结果显示「待估算」而非零，100 g/200 kcal 改为 150 g 时自动得到 300 kcal，两版人工结果均能在历史列表中查看。详情的 `EstimateContents` 逐项显示食物名称、克数未知占位、假设、估算范围、来源和模型名；服务客户端结构化结果及估算规则由 Swift 测试覆盖。此验收确认展示和人工修正能力，不将模拟结果冒充真实供应商识别。

`OfflineIntegrationTests.testEmptyStoreProfileMealWorkoutRestartAndReviewWithNetworkForcedOffline` 在独立空库及 `--ui-test-offline` 下通过（`.build/offline-integration.xcresult`）：录入身体资料、文字餐食和已完成训练后强制退出，重启后的正式记录数、资料状态与回顾中的餐食／训练均正确；未进入演示空间。此开关强制 App 判断离线，不是 iOS 系统飞行模式。模拟器设置和控制中心未成功切换到系统飞行模式，因此 6.6 的字面验收仍未完成，不能据此勾选。

相册由系统 PhotosPicker 提供私密选择，不要求开放整个相册；选中后复制到 App 本机媒体库。若照片读取失败或用户取消，原草稿保留，可用文字继续记录。相机权限首次拒绝后可继续文字／相册记录；需要重新授权时到 iPhone「设置—薄记—相机」开启，再返回 App 拍照。模拟器没有真实相机硬件，权限和 HEIC 真机验收仍待设备。

`openspec validate native-iphone-core --strict` 通过；Mac Python 工具再次校验样例包成功。真实供应商、用户 iCloud 目录和签名真机仍未提供，不能将以上测试视为这些外部条件已验收。

## 2026-10-18 真机准备状态

用户连接 iPhone 后，`devicectl` 已识别有线设备 `iPhone14,7`（iPhone 14，iOS 26.6，build 23G71），后续复查显示 `pairingState: paired`。Xcode「Devices」窗口与设备详情明确提示开发者模式未开启，且 Xcode「Apple Accounts」中尚无已登录账号；`security find-identity -v -p codesigning` 显示 0 个有效签名身份。尚未构建、安装或在真机启动 App。等待用户在设备开启开发者模式，并在 Xcode 自行登录 Apple 账号后继续核验。`openspec validate native-iphone-core --strict` 在此状态下再次通过，OpenSpec 仍为 70/77。

用户完成开发者模式与 Xcode 登录后，`ddiServicesAvailable: true`、`pairingState: paired`；Xcode 设备目标可用。为 Boji target 选择 Personal Team 后，Xcode 自动生成 Apple Development 证书和七天有效的本地 provisioning profile，包含此 iPhone 的 UDID。`xcodebuild -destination 'platform=iOS,id=00008110-000225E12E05401E' -allowProvisioningUpdates build` 成功，`codesign --verify --deep --strict` 通过，签名 entitlements、profile 的 Team ID 与 bundle ID 一致。`devicectl device install app` 成功安装 `com.boji.personal`。首次 `devicectl device process launch` 被 iOS 拒绝，系统明确报告证书／profile 未被用户显式信任；等待用户在设备「设置 → 通用 → VPN 与设备管理」信任后复测，不把安装成功记作启动成功。团队 ID 已加入 `project.yml`，重新运行 XcodeGen 后构建设置保持一致。

用户在 iPhone 上信任开发者后，再次运行 `devicectl device process launch` 成功。Xcode Devices 窗口列出「薄记」`com.boji.personal`，真机截图显示 App 正在「目录备份」页面，底部三项导航可见；此时尚未连接 iCloud 目录。签名配置文件到期时间为 2026-10-25 05:15:57 UTC，届时须重新签名安装。实际安装、签名与启动满足任务 12.4；此截图不证明离线、相机、真实 AI 或 iCloud 验收。

随后在用户开启真实飞行模式后，真机 `build-for-testing` 成功，但 `test-without-building` 未执行测试代码：新安装的 `BojiUITests-Runner` 被 iOS 以开发者 App 证书尚未信任为由拒绝启动。运行器的签名、entitlements 与配置文件 Team ID／bundle ID 相符，配置文件包含该设备；这次结果不能计入 6.6。已请用户暂时联网完成运行器的系统信任，再重新进入飞行模式测试。

第二次运行 `BojiUITests-Runner` 仍被 iOS 以相同理由拒绝，测试代码未执行。改用正式 Debug App 的 `--ui-test-store <UUID>` 启动参数隔离资料库，真机截图证实从空白记录页开始；用户在手机录入资料、餐食、训练并拍摄照片。通过 `devicectl device copy from` 仅复制该 UUID 对应的隔离目录，Core Data 记录中有 profile、meal、workout、photo 各一条。强制结束进程并用同一参数重启后再次复制，四类记录数量一致，真机首页截图显示 13:27 的照片餐食及训练。用户从手机图标自行打开 App 时未带测试参数，因此切回正式个人库并误以为测试餐食丢失；重新带相同 UUID 启动后首页又显示该餐食。设备截图在声称飞行模式时仍显示蜂窝信号格，因此不能把这轮计入真正飞行模式的 6.6。

真机相册第一次选择本地照片后仍显示 `照片 · 0/9`，页面未就近显示错误；拍照入口正常。`MealEditorView` 原先在视图 `onDisappear` 时取消相册导入任务，系统相册呈现／关闭可能触发这个时机。移除该过早取消，并把导入错误显示在照片入口旁后，重新签名覆盖安装；用户在同一真机选择本地照片，确认出现 `照片 · 1/9` 和缩略图。模拟器 `ExportPhotoTests.testOfflineMultiPhotoDraftManualEditDeleteAndRestore` 回归通过（1 项，0 失败，311.810 秒），覆盖多图选择、草稿恢复、人工编辑、删除及恢复。真机单张导入成功不替代 HEIC、权限拒绝等 12.3 剩余项目。

2026-10-18：用户选定并授权 iCloud Drive「薄记测试备份」目录；通过 iPhone 镜像仅操作系统目录选择器及薄记备份页。App 显示目录已写入，随后显示系统确认全部文件上传，且明确提示 Mac 下载状态未知。Mac 对该目录内的 `.boji` 包先观察到数个 `compressed,dataless` 占位文件；执行系统下载后，`python3 ios/Scripts/read-package.py` 完整核验 manifest 和 10 个文件的 SHA-256，通过并读出修订 34、1 次训练、2 张照片及日汇总。当前这份实际包无餐食，不能把另一隔离测试库的餐食算入。手机断开目录后显示「未连接 · 本机记录正常保存」，Mac 原快照仍在；重选同一目录后重新建立连接并写入。此为 11.5 的真机到 Mac、撤权及占位文件实测，不代表真实 AI 或餐食端到端验收。

同日用户决定个人版改为 iPhone 直连千问，不部署私有服务。更新 `native-iphone-core` 的提案、设计、食物估算规格与任务；OpenSpec strict 校验通过。当时新增固定新加坡 `ap-southeast-1.maas.qwencloudapi.com` HTTPS 端点、`qwen3-omni-flash`、本机 Keychain 密钥及直连任务路径。千问官方[视觉模型表](https://docs.qwencloud.com/developer-guides/getting-started/vision-models)将该旧型号列为不支持结构化输出，因此请求不发送 `response_format`，只用提示要求 JSON 并在本机严格校验。`BojiCoreTests` 全部 70 项通过，包括直连格式／错误合计、丢响应不自动重试、每日尝试上限和重启后结果未知；最初新测试预期错误类型与实际领域错误不一致，适配器统一转换后通过。签名的真机构建通过并覆盖安装到 iPhone 14，使用同一隔离测试库启动。尚未配置真实密钥或发送照片，不能把协议 fixture 算作真实识别。

同日后续：用户已在 iPhone 隔离版薄记内直接输入千问 API Key 并完成授权；当时源代码和日志未接收密钥；后续用户误将旧密钥发入聊天，已建议立即撤销并换新，仓库及测试命令未使用该密钥。`xcodebuild -scheme BojiCoreTests ... test` 最新结果为 **71 项通过**（`ios/.build/qwen-direct-tests.log`），新增显式重试验证：直连请求超时后重启不自动调用，用户重新触发后才产生第二次请求。`BojiUITests/LaunchTests/testPersonalAISettingsUseDirectQwenWithoutServerAddress` 通过，确认个人版设置显示千问直连、密钥安全输入框，且无服务器地址输入框（`ios/.build/qwen-direct-ui.log`）。此前两次 UI 断言针对可访问性查询方式失败，已改成准确标识后通过。真实照片尚未发送，8.7 与 12.1 继续保留未完成。

隔离真机资料库复测：复用 iPhone Keychain 中已保存的千问密钥，隔离库「我的—AI 估算」显示供应商、型号、发送范围和政策版本，并在该库单独完成授权。旧相册草稿原有一张摩托车照片，已移除；用户确认左上角带盖饮料为指定测试照，随后隔离草稿显示仅这一张（`照片 · 1/9`）。当前尚未从页面或持久化资料确认餐食保存及真实识别，不能认定已发送或成功。最新签名真机 Debug 构建通过（`ios/.build/direct-qwen-final-device-build.log`），为了不打断手机操作尚未覆盖安装。

真机后续联调：隔离库内出现 4 个失败任务，错误码均为 `unauthorized`，没有成功估算；最新带饮料照片的餐食仍是草稿，尚未发起其真实识别。旧版错误码也用于本机未找到密钥，单凭持久化记录无法区分是否到达供应商；原界面还把格式错误／Keychain 失败合并成“API Key 无效”。已改为分别提示，新增 401 契约测试。待用户撤销已暴露旧密钥、提供非秘密 API Host 并在 iPhone 输入新密钥后，再验证端点与模型权限。

用户随后提供新密钥创建页的非秘密 Base URL `https://maas.qianwenaiapi.com/compatible-mode/v1`。对照千问AI平台官方首调文档，请求路径改为其 `/chat/completions`；旧主机的资料库授权在升级加载时失效、旧本机 Keychain 条目删除，餐食等个人记录保留。71 项核心测试通过（`ios/.build/qwen-new-host-core-tests.log`），单项旧主机迁移测试通过（`ios/.build/qwen-new-host-migration-test.log`），OpenSpec strict 校验通过。签名真机构建成功（`ios/.build/qwen-new-host-device-build.log`），覆盖安装并以同一隔离库 UUID 启动。安装后的该库快照显示 `serviceURL` 与 `acceptedPolicy` 均为空、同一草稿及既有餐食／训练仍在。用户确认旧 Key 已撤销、新 Key 已创建；待其在手机输入新 Key 并重新授权，再执行真实识别。

用户在手机新 Key 授权后，隔离库只保存新平台请求地址与新版授权标识，未在资料库中保存密钥。真机发起的前两次新地址任务均返回 `cannot_recognize`，第三次成功；本机持久化结果显示来源 `model`、供应商 `Qwen`、模型 `qwen3-omni-flash`、710 kcal，且与该餐输入版本及照片 ID 对应。起初该结果只关联草稿；用户随后点「保存饮食」，真机资料库出现正式餐食，其 `currentEstimateID` 指向同一结果，镜像首页显示 710 kcal／AI 估算。尚待人工修正、强制重启后核对；因此 8.7 和 12.1 此刻仍未勾选。镜像画面可读，但点击返回 `noWindowsAvailable`，正在重连后继续。

镜像点击在锁屏重连后仍返回 `noWindowsAvailable`，用户改在手机直接修正。隔离库中该餐先后出现 705 与 700 kcal 两个人工历史版本；700 kcal 是当前有效值，原 710 kcal AI 估算仍在历史中。`devicectl` 强制结束并用同一隔离库 UUID 重启后，再次复制仅该隔离库：正式餐食 ID、1 张照片 ID、当前 700 kcal 人工估算、710 kcal `qwen3-omni-flash` 原始估算及历史均保持一致，断言通过。因此任务 8.7 已完成；没有借这次结果推断完整导出／导入流程或飞行模式验收。

用户在真机「回顾 → 饮食」确认 700 kcal 后，从同一隔离库生成完整 `.boji` 包并保存到 iCloud Drive「薄记测试备份」。Mac 下载后运行 `ios/Scripts/read-package.py` 的只读校验：manifest 与 10 个文件的大小及 SHA-256 全通过；包内 1 条有效餐食、1 次训练、2 张照片，当前餐食 700 kcal 人工值及包含 710 kcal 千问估算的 3 条历史均在。随后以 `--ui-test-store A7646307-BFF4-4CD6-B5B3-C83AC296C2A0` 启动全新空库（导入前实体数为 0），用户在手机通过「导入与恢复」选择该包、预览并确认导入。导入后的 active generation 包含 1 条有效餐食、关联照片、3 条估算历史；内部 UUID 经命名空间映射，但 `origin` 保留原资料集 ID 和源餐食 ID。当前值为 700 kcal，710 kcal `qwen3-omni-flash` 历史仍在；识别任务为 0，授权与服务地址均为空。再强制结束并以同一新隔离库 UUID 重启，当前热量、照片关联和无任务状态保持。任务 12.1 已完成；本轮没有重复发起模型调用，也没有把完整包内容发到聊天。

端点修正后又运行 `BojiUITests/LaunchTests/testPersonalAISettingsUseDirectQwenWithoutServerAddress`，模拟器真 UI 测试 1 项通过（`ios/.build/qwen-new-host-ui-test.log`）：设置页仍显示个人直连、安全输入框及未配置文案，无自建服务器地址框。第三个隔离空库 `412DAD90-A413-4069-BCF7-54280C86462F` 已启动并确认实体数为 0；用户明确确认状态栏是飞机图标且无 Wi-Fi，但尚未在该库录入资料／饮食／训练，所以 6.6 仍未完成。

用户决定暂时保留剩余真机验收未完成。OpenSpec 进度为 77/80，6.6、12.3、12.5 继续未勾选；未把早先有蜂窝信号格的录入或模拟器适配测试替代为真机整体验收。手机 App 已重新以原先含千问识别结果的隔离库 UUID `1865EBA5-48E8-44CB-9BD0-6E7210B45B2D` 启动；用户需自行关闭飞行模式并恢复 Wi-Fi。
