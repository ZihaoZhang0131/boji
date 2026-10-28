# 原生验证记录

## 2026-10-25 训练动作卡片与自动粗估

网页与原生「记训练／编辑训练」采用浅灰动作卡片、白色输入区、组数加减和底部放弃／保存；添加动作在当前页展开。移除名称、时间、时长、强度和热量预览输入。新记录自动记录首页日期及当前当地时间。自动估算 `sets-met-net-v1` 保留参数和体重来源，旧记录原样保存不重算。

验证：

- `BASE_URL=http://127.0.0.1:8766 npm test` 的七组网页回归通过，包括新增 `verify-workout.cjs`。覆盖 320／393px、明暗外观、大字号、44px 操作区、DOM 与输入保留、同页选择、保存失败、重启、旧快照和未知热量；浏览器控制台无错误。日志 `/tmp/boji-workout-web-final.log`；单位标题微调后补跑表单回归 `/tmp/boji-workout-editors-final.log`。
- `swift test --package-path ios/BojiCore`：75 项通过。新增分段能耗、真实零值、缺体重、支持范围、旧快照保留、导出往返、参数篡改拒绝及网页小数时长导入验证，日志 `/tmp/boji-workout-core-final.log`。
- iPhone SE / iOS 26.5：4 项 `WorkoutEditorTests` 通过。UI 覆盖同页加动作、组数加减、保存重启、修改放弃、复制、删除恢复，以及最大辅助字号下的布局与底部按钮。浅色日志 `/tmp/boji-workout-ui-final.log`，深色日志 `/tmp/boji-workout-dark-final.log`，最终深色卡片、加减图标与 44pt 操作区校验 `/tmp/boji-workout-layout-final.log`；最终模型回归 `/tmp/boji-workout-app-final.log`。测试完成后模拟器已恢复浅色。
- 网页实际截图：[训练录入](../../editor-screenshots/new-workout-393.png)；原生实际截图：[深色训练卡片](screenshots/workout-simple-dark.png)。截图为隔离测试资料。

本轮没有安装到真实 iPhone；模拟器的键盘、字号和界面验证不等同于真机 VoiceOver 或实体键盘专项验收。


本文件只记录实际运行结果，不以模拟服务替代真实模型、iCloud 或真机验收。

## 2026-10-21 我的功能网格

网页和原生「我的」均直接平铺各自原有的全部 8 项功能，每行三个图标＋文字，点击即打开对应功能。原生个人资料、阶段目标、AI 估算、导出与 Agent、导入与恢复、目录备份、回收站及演示切换均保留原入口与权限，分类中间页已移除。

原生 `testMineAllFunctionsGridAndDirectNavigation` 与演示隔离烟测通过：8 个入口首页可见、按三列对齐且等宽、点击区域至少 44pt，个人资料／AI／导出直接打开与返回均可用；演示空间的禁用规则与退出隔离也保留。结果 `/tmp/boji-mine-all-functions.xcresult`。网页三组回归通过，覆盖直接入口、目标历史、资料导出及 320／393px 布局；另外实际查看了阶段历史、Agent 复盘与 iCloud 直达页面。未进行真机安装。

[原生全部功能效果](screenshots/ui-mine-all-functions.png)。

## 2026-10-20 全项目 UI 简化

网页与原生共享[简化原则与视觉约定](../../README.md#ui-简化原则)：记录卡只保留图像／图标与热量，统一灰色表面、圆角、间距和数字层级；详情、公式和历史按需展开，输入标签、单位、错误与必要授权提示保留。原生训练卡片直接进入编辑，顶部「详情」保留历史、复制与回收站入口。

iPhone SE（第三代）／iOS 26.5 模拟器的五项关键 UI 测试通过：人工热量从 100 g／200 kcal 修正至 150 g／300 kcal 并保留历史；演示空间的卡片及分组导航；最大辅助字号下的主要触控区；7／30 天共 37 个日期逐一选择；训练草稿重启、直接编辑、历史体重快照、取消复制保留修改、明确放弃后复制及删除恢复。结果位于 `/tmp/boji-ui-complete.xcresult`。复制初始化失败后的退出处理另经最终模拟器构建检查通过（`/tmp/boji-ui-final-build.log`），未将其称为故障注入测试。

网页三组回归通过（`BASE_URL=http://127.0.0.1:8766`），覆盖记录编辑与恢复、份量修正、个人资料、7／30 天图表、导出、320／393px 布局和字体图标；控制台无错误。另检查浅色／深色及未知热量状态。全部测试使用独立测试资料，未读取个人正式记录。

原生效果：[记录](screenshots/ui-minimal-records.png)、[直接编辑训练](screenshots/ui-minimal-workout.png)、[回顾](screenshots/ui-minimal-review.png)、[我的](screenshots/ui-minimal-settings.png)。本轮未进行真机安装。

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


## 2026-10-24：黑白灰 MVP 精简

- Web 与原生统一系统正文、黑白灰和轻分隔。「我的」收敛为身体资料、AI 估算、数据管理；导出、导入与恢复、回收站继续可达。阶段/Agent/目录备份退出导航，目录备份轮询停用。演示开关仅 Debug 的显式测试参数可见；已有历史和资料包字段保持兼容。
- 回顾默认灰阶月历，热量图表收进趋势。月历按记录与确认状态着色，不把热量高低当作成绩。原生切月时采用日期与占位项各自独立标识，避免月初日期消失。
- `BASE_URL=http://127.0.0.1:8766 npm test`：三套浏览器检查通过，覆盖记录编辑、训练草稿、完成组、导出含照片、灰阶界面、320/393px、深色模式与无页面异常。`npm run capture` 已更新界面总览。
- `swift test`：72 项核心测试通过，包含持久化、估算、导入/导出与恢复规则；2 项原生工程配置测试通过。
- iOS 26.5 / Boji iPhone SE 模拟器：7 个不同 UI 用例通过（分两轮运行）：MVP 导航与月历、空库日期导航、测试演示卡片、系统导出选择器、资料保存重启、饮食草稿/热量修正/删除恢复/趋势、最大辅助字号按钮。编译通过。
- 实际截图已检查：`screenshots/ui-mine-minimal-mvp.png`、`ui-review-monochrome-month.png`、`ui-mvp-largest-text.png`、`ui-mvp-dark.png`。深色截图来自 `simctl` 实际运行，检查后恢复模拟器浅色外观。
- 本轮未安装真机、未调用真实千问、未重新验证 iCloud 交付；旧版本验证记录不代表本轮已重复完成。


## 2026-10-24：记录首页日期横条与单列记录

- 本轮仅改记录首页的展示与导航连接；回顾继续使用原有方形卡片，「我的」保持上轮 MVP 状态。新增 `HomeComponents.swift` 与网页 `home.js` / `home.css`，没有数据库字段、接口或迁移变更。
- 日期范围固定为今天前后各 15 天，首次居中；网页使用 2026-10-09 示例时钟，原生使用设备当地日期。点选保持横向位置，月份随选择更新，回到首页时越界日期重置为今天。
- 总览合并为摄入／训练净消耗，未知显示横杠，部分待估算显示已知数值，草稿不参与统计；首页数值无千位逗号。记录一行一条，按餐次／训练部位显示图标和分类，保留时间、热量与草稿状态；原照片、名称、动作和餐次均保留。
- 浏览器 `BASE_URL=http://127.0.0.1:8766 npm test` 四套检查通过，`verify-home.cjs` 在补入鼠标拖动与英文完整词分类后再次通过。覆盖 31 天、跨月／闰日／夏令时、首次居中、点选位置保持、跨日数据、汇总打开趋势、回顾方形卡不变、草稿不计汇总且重启恢复，以及 320/393px 浅深色。页面异常为 0。
- iPhone SE / iOS 26.5 模拟器：构建通过，4 个 `HomePresentationTests` 通过；6 个不同 UI 用例分轮通过：首页日期／趋势、草稿切日与重启、演示记录直接编辑、空库日期导航、最大字号导航与最大字号记录横条。最大字号记录测试在深色外观下通过，断言横条自动增高、完整滚动到固定操作区上方、点击进入编辑。模拟器外观已恢复浅色。
- 首轮 UI 测试暴露横条的无障碍按钮角色丢失，修复后草稿和演示编辑复测通过。最大字号测试最初在固定按钮区域发起滑动，修正为内容区滑动，并加强完整可见范围断言后通过；未将仅边缘可点作为完整显示验收。
- 截图：网页 `home-list-393.png`、`home-list-320.png` 及对应 dark 文件；原生 `screenshots/ui-home-date-strip.png`、`ui-home-draft.png`、`ui-home-dark.png`、`ui-home-largest-text-row.png`。实际查看并核对过。
- 本轮未安装到真实 iPhone、未调用真实模型、未重新验证 iCloud；旧核心测试与真机记录不表示本轮再次运行。


### 同日：首页圆形日期与模块层次细化

- 删除首页 App 标题，以所选完整日期为标题；星期按当地日历计算。日期按钮仅显示数字，使用至少 44pt 的圆形，保留完整无障碍标签。首页删除当天汇总及记全入口，未改动历史字段与回顾页统计。
- 日期区无整体底板，热量总览保留灰底；记录横条改为画布底色与 1pt 细描边。网页对应 44px 圆形与 1px 描边，支持深色。
- `BASE_URL=http://127.0.0.1:8766 npm test` 四套浏览器检查全部通过，覆盖完整日期文案、纯数字圆形、无首页记全入口、三块表面区别、31 天范围与切日位置、草稿恢复、320/393px 与深色模式。截图与 gallery 已刷新。
- iPhone SE / iOS 26.5 模拟器构建通过，三个首页 UI 用例分轮通过：切日与趋势、草稿切日重启、最大辅助字号。日期测试最初错误地要求 SwiftUI 按钮内暴露文字子节点，改为验证按钮完整可访问名称、圆形尺寸和无星期子文本后通过；产品按钮自身行为正常。
- 已检查实际网页与原生截图，最新原生图仍位于 `screenshots/ui-home-draft.png`、`ui-home-largest-text-row.png` 和 `ui-home-dark.png`。本轮没有安装到真实 iPhone。


### 同日：训练改为一次录入与保存

- 网页与原生训练均直接打开录入表单；删除逐组确认、进行中／编辑中状态与结束训练操作，以“保存训练／保存修改”提交整条记录。每组数据统一校验，未通过时保留输入，已保存事实不变。内部历史字段和净消耗计算口径保留，无数据迁移。
- 首页只显示已保存训练；取消或中断的输入在编辑器私下恢复，不参与记录列表和热量汇总。点击已保存横条继续修改，保存更新同一条记录；切换到另一条训练前明确处理未保存输入，避免覆盖。
- 浏览器 `BASE_URL=http://127.0.0.1:8766 npm test` 四套检查通过。随后 `verify.cjs` 补充无效组数值与未保存输入冲突后再次通过，覆盖直接录入、一次保存、原记录修改、批量输入、取消与重启恢复、320/393px，页面异常为 0。截图与 gallery 已刷新，查看过最终 `training-393.png`。
- iPhone SE / iOS 26.5 模拟器构建通过；6 项单元测试（`WorkoutEditorTests` 2 项、`HomePresentationTests` 4 项）及 2 项首页 UI 测试通过。UI 实际完成保存、取消修改、恢复修改、保存后重启，以及最大辅助字号下记录完整可见并可点击。日志 `/tmp/boji-workout-form-native.log`，结果为 `Test-Boji-2026.10.24_23-04-11-+0800.xcresult`。其余原生 UI 用例仅同步了操作名称，本轮未全量执行。
- 已查看本轮实际截图 `screenshots/ui-workout-saved-home.png` 与 `screenshots/ui-home-largest-text-row.png`。未安装到真实 iPhone、未调用真实模型。

### 同日：训练仅保存或放弃，移除输入恢复

- 根据后续反馈，移除训练自动暂存、重启恢复、未保存输入冲突弹窗与额外清空输入操作。顶部统一为“放弃”，直接退出；未保存数据仅存在本次表单，关闭即放弃，编辑已有记录时原保存版本不变。旧版训练草稿不再恢复，打开训练表单时清除，饮食草稿规则未在本轮改动。
- 原生训练直接使用事务保存接口，不再先生成草稿；全部组校验通过后一次提交，继续保留原记录身份、热量历史与并发版本检查。网页保存失败会回滚内存记录并留在表单显示错误，不报保存成功。
- `BASE_URL=http://127.0.0.1:8766 npm test` 四套浏览器检查通过；增加存储空间不足失败分支后，`verify.cjs` 再次通过。覆盖放弃新建／修改、Escape 退出、刷新不恢复、遗留草稿不阻塞编辑、保存失败无部分写入，以及 320/393px 与浅深色。无页面异常。
- `swift test` 72 项核心测试通过。iPhone SE / iOS 26.5 模拟器构建通过；7 项单元测试与 `HomeTests/testWorkoutSaveOrDiscardHasNoRecoveryOrConflict` UI 用例通过，实际验证放弃后为空、原记录不变、保存修改与重启不恢复未保存输入。日志 `/tmp/boji-save-discard-native.log`。
- 已刷新当前网页并观察到训练卡片直接进入编辑、顶部“放弃”、底部“保存修改”；已查看本轮原生截图 `screenshots/ui-workout-save-or-discard.png`。本轮未安装到真实 iPhone。
- 补充 `WorkoutFlowTests/testWorkoutSavesRestartsEditsCopiesAndRestores` 通过，覆盖保存后重启、修改原记录、复制直接进入新表单、放弃复制、删除与恢复；历史体重快照保持不变。首轮脚本仍从“数据管理”寻找“身体资料”，修正为当前“我的”首页入口后复测通过；该失败不是训练产品逻辑错误。日志 `/tmp/boji-save-discard-copy-retest.log`，本轮合计两个原生 UI 用例通过。

### 同日：饮食与训练的四个表单精简

- 四个表单统一为内容、时间／热量信息和底部固定保存；去掉照片排序、标签输入、折叠信息、批量组录入、动作排序及重复说明。新建／编辑共用同一布局。保留添加照片与动作、修改组数值、餐次、时间、热量和历史事实。
- 饮食也改为保存或放弃，不再按输入自动暂存或恢复旧草稿；人工热量与照片处理仍使用内部临时事务，放弃不修改正式记录。旧标签和照片顺序未删，保存后的 AI 请求沿用既有授权规则。
- 五套网页检查分轮通过：`verify.cjs`、`verify-energy.cjs`、`verify-pixel.cjs`、`verify-home.cjs`、`verify-editors.cjs`。包括照片及文字保存、放弃后原记录不变、训练完整校验、未知热量、320/393px 和浅深色，页面异常为 0。`editor-screenshots/` 中的 16 张新建／编辑截图已更新并抽查。
- iPhone SE / iOS 26.5 模拟器：6 项表单模型测试通过（饮食 3、训练 3），覆盖照片临时引用、人工热量、旧记录身份、输入不恢复与保存校验。首轮 Swift 编译器在绑定 actor 方法引用时崩溃，换为显式闭包后编译通过。
- 两项 UI 用例最终在深色下通过：四个新建／编辑表单、350 kcal 人工值保存、放弃饮食修改保留原文、训练 8 次修改为 9 次后重新打开，以及最大辅助字号下的边界和完整可见范围。大字号截图检查曾发现系统日期控件撑宽页面，现改为日期／时间分行并限制紧凑控件字号；加强边界断言后通过。详情返回后的虚拟列表定位、输入光标位置也已修正测试操作，未将首轮失败计为通过。
- 最终 UI 日志 `/tmp/boji-minimal-editors-native-layout.log`，结果 `Test-Boji-2026.10.24_23-33-05-+0800.xcresult`。本轮未安装到真实 iPhone，未调用真实 AI 服务；其他原生 UI 用例只同步了控件名称，未全量执行。
- 已检查并保存四个表单及大字号内容／元数据截图：`screenshots/ui-minimal-*.png`。模拟器已恢复浅色外观，浏览器停留在新版饮食表单。

### 同日：回顾精简为日历与趋势

- 删除独立照片墙、饮食／训练分类页、搜索筛选、记全确认、日均／盈亏分析和多层说明。日历与趋势共用当日摄入、训练净消耗及单列记录；训练从回顾也直接进入编辑器。日历选中态使用圆形、小点标记有记录，翻月同时更新所选日期，短月取最后一天。
- 趋势仅展示连续 7／30 日的已记录摄入和训练净消耗。每一天均可选择，未知与真实零值区分；无有效值显示横杠，部分未知时标为「已知」。旧确认字段和统计模型保留兼容，没有迁移或改写历史记录。
- 六套网页检查分轮通过：基础录入、热量、灰阶视觉、首页、四个表单、回顾专项。覆盖跨月／跨年／闰年、44px 日期点击区、7／30 天范围和选择、已知／未知数值、原记录编辑与放弃、浏览不写入数据、320/393px 浅深色。首轮热量脚本沿用了错误的样例摄入预期，核对现有样例后更正为 2060 kcal 并通过。页面异常为 0。
- `review-screenshots/` 的日历、7 天与 30 天趋势截图已更新并核对；`npm run capture` 完成，界面总览同步使用新版月历。首页与四个表单回归检查通过。
- iPhone SE / iOS 26.5 模拟器构建通过；三个不同 UI 用例通过：7／30 天逐日点击与对应数据、日历跨月及饮食详情／训练直接编辑、最大辅助字号。复测在深色外观下完成。首次发现图表日期丢失按钮角色，补充无障碍按钮标记；最大字号菜单测试按实际可访问名称修正。截图检查再发现日期标签被固定高度截成省略号，改为随字号增宽／增高后，最大字号单项复测通过并确认数字可读。
- 日志 `/tmp/boji-minimal-review-native-final.log` 和 `/tmp/boji-minimal-review-large-final.log`；结果分别为 `Test-Boji-2026.10.24_23-46-14-+0800.xcresult` 与 `Test-Boji-2026.10.24_23-49-37-+0800.xcresult`。实际截图保存在 `screenshots/ui-minimal-review-calendar.png`、`ui-minimal-review-trend.png` 及对应 `-largest` 文件，已逐张检查。模拟器恢复浅色。本轮未安装真实 iPhone、未调用真实 AI；没有重复执行未改动的核心数据单元测试。


## 2026-10-25 饮食详情精简

网页与 iPhone 饮食详情只展示图片、文字和热量，底部固定并排编辑、删除、返回。网页 `BASE_URL=http://127.0.0.1:8765 npm test` 六个脚本通过，另检查 320／393 宽度的深浅色、纯文字／纯图片／多图／长文字／未知热量、固定操作栏、Escape 与返回焦点。截图位于仓库根目录 `meal-detail-screenshots/`。

iPhone SE 模拟器编译通过，3 项 MealEditorTests 与 6 项相关 UI 用例均通过：热量经编辑表单修改、多图保存与删除恢复、编辑保存／放弃、回顾入口、重启与回收站恢复、最大辅助字号。初次运行中的滚动位置和空输入框可访问性断言已调整；LaunchTests 与最大字号用例随后分别定向复测通过。记录数据及估算历史的存储格式不变。

详情截图：`screenshots/ui-meal-detail-text.png`、`screenshots/ui-meal-detail-photos.png`、`screenshots/ui-meal-detail-largest.png`。测试结果包保存在本机 `/tmp/boji-meal-detail-tests-20261024.xcresult`、`/tmp/boji-meal-detail-retest-20261024.xcresult`、`/tmp/boji-meal-detail-largest-verified.xcresult`，后两包用于上述定向复测。

## 2026-10-25 双记录日历与双趋势曲线

- 回顾不再渲染当天汇总、记录列表或编辑入口。网页和原生均使用两张 13 周记录日历，以及两张 7／30 天摄入／训练净消耗曲线；没有有效值的日期断线，保存但待估算的记录仍在日历着色。
- `BASE_URL=http://127.0.0.1:8766 npm test` 六套网页脚本通过（日志 `/tmp/boji-review-curves-all-web.log`）。月份标注调整后定向重跑 `verify-review.cjs` 通过（`/tmp/boji-review-curves-web-final.log`），覆盖历史／未来边界、独立翻页状态、有效零值、部分估算、数据更新与 320／393px 深浅色；控制台错误为 0。`npm run capture` 已更新展示截图。
- 新增 `ReviewPresentationTests` 六个原生单元／渲染测试，覆盖日历跨年、闰日与 DST、草稿／回收站、训练净消耗当前快照、PCHIP 无过冲、缺失断线与零值。两个已知数据曲线的真实 SwiftUI 渲染图位于 `screenshots/ui-review-curves-fixture-light.png`、`ui-review-curves-fixture-dark.png`，均已目视检查；这些是明确的测试样本，并非用户记录。
- 原生小屏 iPhone SE 的空数据、44pt 实际点击区域、最大辅助字号测试通过；月份开头不足两列时省略重复月份，图内月份／星期字号限制到 XXXL，完整日期可读屏。最终修正结果：`Test-Boji-2026.10.25_00-13-03-+0800.xcresult`，日志 `/tmp/boji-review-curves-verified.log`，`TEST SUCCEEDED`。大字号深色截图 `ui-review-dual-calendar-largest.png`、`ui-review-dual-trend-largest.png` 已检查，无月份重叠。
- 保存与重启恢复 UI 测试在浅色、深色均通过；草稿不会显示为记录，已有数据未迁移、未改写。模拟器已恢复浅色。本轮未安装真实 iPhone，未调用真实 AI。

- 最终浅色保存／重启复测通过：`Test-Boji-2026.10.25_00-15-59-+0800.xcresult`，日志 `/tmp/boji-review-curves-light-final.log`。最终截图 `ui-review-dual-calendar.png`、`ui-review-dual-trend.png`；全年旧数据与首页日期均未因回顾浏览而改写。


## 2026-10-25 点击饮食记录直接编辑

- 网页与 iPhone 首页点击已有饮食直接进入预填的「编辑饮食」，移除独立详情与工程引用。底部固定等宽「保存／删除／返回」，新建饮食仍是顶部放弃、底部保存。进入不自动弹出键盘；返回不提交或触发估算。
- 删除使用已保存原记录，忽略表单中未保存的文字、热量与照片修改。网页保留撤销，原生保留确认与 30 天回收站；失败保留输入，可重试。保存、删除和照片导入的重复操作受到保护，关闭后的迟到图片结果不会写回。
- `BASE_URL=http://127.0.0.1:8765 npm test` 六套网页回归通过，日志 `/tmp/boji-direct-editor-web.log`。覆盖直接编辑、保存、返回、键盘退出与焦点恢复、删除失败与撤销、320／393px 深浅色。另检查纯文字、多图、长文字、未知热量、导入中禁用保存／删除、退出后忽略迟到图片，以及固定操作栏与内容滚动。
- iPhone SE / iOS 26.5 模拟器构建通过，4 项 `MealEditorTests` 与 5 个不同 UI 用例分轮通过。覆盖热量修改、保存更新同一记录、返回放弃、未保存修改后删除、失败重试、原照片保留、回收站恢复、重启和最大辅助字号。首轮多图测试将部分可见的热量行判为可点击，误点固定删除按钮；改为先滚动到操作栏上方完整可见，再等待热量表单，定向复测通过。
- 最终模型重新编译并复跑 4 项单元测试，多图 UI 复测也通过。结果包为 `/tmp/boji-direct-editor-tests.xcresult` 和 `/tmp/boji-direct-editor-final-model.xcresult`；后者是最终模型与多图复测结果，前者其余 4 个 UI 用例通过。
- 已查看网页 `editor-screenshots/direct-meal-393.png`、`direct-meal-320-dark.png`，及原生 `screenshots/ui-direct-meal-editor.png`、`ui-direct-meal-editor-largest.png`、`ui-direct-meal-editor-photos.png`。未安装到真实 iPhone，未调用真实 AI；数据结构、估算规则与历史格式未变。

### 趋势日期区间选择器（2026-10-25）

网页与原生趋势改为起止日期面板，默认截至设备当地今天的近 7 天，支持包含首尾的 1—90 天。确认后才更新两图，取消保留原范围；日历仍独立翻页。网页移除固定示例时钟，历史示例日期不平移。日期状态不写入记录或导出格式。

验证完成：`BASE_URL=http://127.0.0.1:8766 npm test` 七组网页回归通过，无页面错误；日期专项另覆盖单日、2／6／8／90 天、91 天拒绝、空日期、未来日期、倒置区间、取消／外部关闭／Escape、焦点恢复、真实本地日期、上海／洛杉矶时区、跨日、历史首页入口和刷新重置。320／393px 浅深色截图位于 `review-screenshots/range-panel-*.png` 及 `trend-1-*`、`trend-90-*`。

`swift test --package-path ios/BojiCore`：76 项通过；原生 `ReviewPresentationTests`：7 项通过，覆盖 1／2／7／30／90 天与小屏、浅深色、大字号图表。iPhone SE / iOS 26.5 模拟器验证首页入口、空状态、保存及重启、实际起止日期选择、取消与确定、单日、浏览位置、辅助字号。截图复查发现并修复了紧凑日期控件的大字号横向溢出、确认／取消按钮触控高度和深色确认按钮文字对比度。日期值沿用系统完整读屏内容；可视日期字号上限 XXXL，其他文本继续随辅助字号缩放。

最终深色模拟器复测 `ReviewAITests.testReviewDateEditingCommitsOnlyOnConfirm` 与 `testReviewLargestText` 均通过（85.493 秒），结果：`.build/DerivedData/Logs/Test/Test-Boji-2026.10.25_14-45-51-+0800.xcresult`。原生截图：`docs/screenshots/review-range-compact.png`、`review-range-single-day.png`、`review-range-largest.png`、`review-range-largest-dark.png`。模拟器外观已恢复为测试前的浅色。


### 2026-10-25：趋势图一体化排版

网页与原生的标题／单位紧凑成组，纵轴右对齐并绑定三条水平参考线，横轴短刻度与逐日数据共用坐标，两图按最宽数值共用纵轴占位。沿用独立纵轴、缺失断线、真实零值、待估算标题及已确认日期区间。原生大字号保留首尾日期；文字实际宽度不足时分行，不缩小文字。

- 网页回顾回归通过：320／393px、浅深色，覆盖单日、7／30／90 天、跨年、缺失、零值、空状态及合法多餐合计 123456 的六位数刻度；直接测量 DOM 验证纵轴文字中心／参考线、横轴标签／短刻度／数据点、两图绘图区边界一致，且日期无重叠或裁切。日期确认／取消、页面保留、首页重置、跨日和持久化不变回归通过。其余网页记录、热量、样式、首页、编辑器及训练回归全部通过。
- 原生 `swift test` 的 76 项核心测试通过。`ReviewPresentationTests` 9 项通过，渲染覆盖 320／393pt、浅深色、Large／XXXL／最大辅助字号及长数值／空状态。最终渲染结果：`/tmp/boji-chart-layout-delivery.xcresult`。
- 模拟器的回顾空状态、日期确认／取消、保存／重启、最大辅助字号四项 UI 场景通过；布局调整后的保存／读屏标签与最大字号复测通过，结果在 `/tmp/boji-chart-layout-tests.xcresult` 与 `/tmp/boji-chart-layout-verified.xcresult`。
- 已目视检查同一跨年数据的修改前后截图，以及单日、长区间、六位数、空状态和最大辅助字号的最终截图。网页截图位于 `review-screenshots/`；原生代表截图为 `screenshots/review-charts-unified-*.png`。这些均为固定测试数据，非用户真实记录。本次未执行真机回归。

## 2026-10-25 我的与设置子页简洁化

- 网页 `mine.js` / `mine.css` 和原生 `MineComponents.swift` 将「我的」、资料、AI 与数据管理统一为纯色单列、细分隔线和紧凑分组。首页状态取当前有效资料及既有授权数据；网页 AI 始终标明演示，不增加同步或备份状态。
- 资料保留校验、有效日期与回溯确认；单位贴近输入，目标单独分组，说明和历史折叠。原生普通字号字段行收紧，辅助字号上下排列，输入提示提高对比度。保存与错误提示固定在底部。
- 原生导出按生成／存储阶段突出操作，导入结果与错误紧邻对应操作，恢复旧版本独立折叠。回收站保留删除日期、恢复、永久删除确认和 30 天保留规则。网页导出错误重试及资料格式保持不变。
- 新密钥已撤回旧授权、随后政策请求失败时，补充刷新内存快照，防止首页显示过期授权。测试使用临时目录、内存凭据和模拟政策服务，没有读取真实 Keychain 或发送模型请求。
- 网页全量 `BASE_URL=http://127.0.0.1:8766 npm test` 通过；`verify-mine.cjs` 覆盖按今天判定状态、历史日期隔离、保存／取消、开关即时持久化、导出失败重试、嵌套返回焦点、键盘循环、错误提示位置，及 320／393 px 浅深色和 200% 重排。日志 `/tmp/boji-mine-full-web.log`、`/tmp/boji-mine-final-web.log`。
- 核心 76 项、应用单元测试 33 项通过。应用结果 `/tmp/boji-mine-final.xcresult` 的 BojiTests 部分；最终设置专项与截图见 `/tmp/boji-mine-verified.xcresult`。AI 多状态和最大字号回收站截图使用真实 UIHostingController 布局；直接 ImageRenderer 不能绘制 ScrollView 和系统输入控件，不能使用其空白结果作视觉验收。
- 原生相关 UI 基线 8 项通过，结果 `/tmp/boji-mine-ui.xcresult`。之后的资料紧凑排版与保存通过 `/tmp/boji-mine-delivery.xcresult` 的 ProfileTests；回收站计数、永久删除取消、恢复及记录／回顾闭环通过 `/tmp/boji-mine-final.xcresult` 的 LaunchTests。最大字号恢复确认浮层缺少可用取消路径，现改为带取消的系统 alert，并在最终 MineSettingsTests 复测。
- 浏览器截图位于 `mine-screenshots/`；原生首页与子页为 `screenshots/mine-*`。自动化检查了入口状态、辅助功能标签及主要控件至少 44 pt，小屏和最大辅助字号截图经人工查看。本轮没有真机安装或 VoiceOver 实际朗读，云端文件提供者上传状态也未据模拟器结果推断。
- 最终页面截图在导航动画结束后重新采集，`/tmp/boji-mine-screens.xcresult` 的普通与最大辅助字号 2 项 UI 测试通过；`screenshots/mine-profile-small.png`、`mine-profile-largest.png`、`mine-home-small.png` 等已更新为稳定画面。

## 2026-10-25 接回 iCloud 自动备份

已在现有未提交 UI 改动上增量接回「我的 → 数据管理 → iCloud 备份」。旧授权明确启用，停止保留目录和历史；自动运行独立于 AI，仅在前台检查，导入/恢复先排空旧发布，再使用切换当下的本机配置。最近完整写入时间与系统上传证据分开显示，资料包版本不变。

- 核心 `swift test`：83 项通过，日志 `/tmp/boji-backup-core.log`。包含三次重试与退避、取消、串行发布、已停止手动备份、完整包全部文件状态及 30 秒节流。
- 应用首次全量单元测试：37 项通过，`/tmp/boji-backup-app.xcresult`。新增的备份状态截图使用隔离资料与明确的模拟证据；不代表真实云端上传。
- 网页八组全量回归通过，`BASE_URL=http://127.0.0.1:8766 npm test`，日志 `/tmp/boji-backup-web.log`；覆盖 320／393px 浅深色、键盘和焦点、记录与回顾。
- 第一轮 UI 中记录编辑/回收站与设置导航通过；两个备份选择器取消测试仅按 Button 类型查找控件失败。后续定位和复测结果另记，不将这轮视为全部 UI 通过。
- 用户明确选择稍后真机验收；当前连接的 iPhone 不可用。本轮没有向真实 iCloud 测试目录发布，没有验证 Mac 下载，也没有声称执行真机 VoiceOver。

最终复测：

- `/tmp/boji-backup-delivery.xcresult` 全部通过：应用单元 38 项、备份专项 UI 2 项。包含首次选择、停止后手动备份、错误提示保留及导入/恢复后的本机设置保留。
- 文件提供者的取消占位元素虽可出现在读屏树中，但不一定可点击，且打开时有异步空白加载阶段。专项 UI 等待系统控制器就绪后，通过系统面板下拉关闭验证放弃选择，再检查返回、重启仍未设置；普通字号与最大辅助字号均通过。
- 其他已通过 UI：`/tmp/boji-backup-ui.xcresult` 中记录编辑/回收站、我的导航、设置普通/最大字号 4 项；`/tmp/boji-backup-verified.xcresult` 中演示隔离和回顾日期编辑/重启 3 项。两次中间结果包包含已修复的选择器测试失败，不能把整个中间包标为通过。
- 最后核心回归 83 项通过；追加确认停止后的状态核对不会重建已移除的目录，选择器返回与在途发布相遇不会丢失目录选择，较晚的停止操作优先于首次自动发布。
- `docs/screenshots/backup-*` 是六种代表状态的 320/393pt 浅深色和最大字号夹具；`mine-backup-unconfigured-*`、`mine-backup-actions-*` 是模拟器中的实际页面。共归档 22 张备份截图，并更新数据管理截图。已检查文字、操作区、错误就近呈现及滚动后的可达性。
- `git diff --check` 通过。未提交、推送或安装到真实 iPhone；既有未提交改动保留。真实 iCloud / Mac 和真机 VoiceOver 边界不变。
