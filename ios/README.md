# 薄记 iPhone

原生工程支持 iOS 17 及以上。现有网页继续用于设计参考与旧资料导出。

## 构建

需要 Xcode 与 iOS SDK；安装模拟器运行时后可运行。工程由 XcodeGen 2.45.3 生成，`project.yml` 是工程配置来源，生成的共享 scheme 和工程一起保存。

```sh
cd ios
xcodegen generate
xcodebuild -project Boji.xcodeproj -scheme Boji -configuration Debug \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath .build/DerivedData CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES build
```

运行测试时将 `<SIMULATOR_ID>` 替换为 `xcrun simctl list devices available` 中的设备 ID：

```sh
xcodebuild -project Boji.xcodeproj -scheme Boji \
  -destination 'platform=iOS Simulator,id=<SIMULATOR_ID>' \
  -derivedDataPath .build/DerivedData CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES test
```

模拟器使用临时签名以验证 Keychain；这不提供真机安装签名。

当前默认 Bundle ID 为开发用 `com.boji.personal`；真机签名时填写自己的团队和可用标识，不在仓库保存签名凭据。

各阶段验证结果见 `docs/verification.md`。构建通过不等同于模拟器启动、真机功能或整个变更交付完成。

## 尚未安装模拟器时

```sh
xcodebuild -downloadPlatform iOS -architectureVariant arm64
xcrun simctl list runtimes
xcrun simctl list devices available
```

运行时下载完成后，在 Xcode 的 Devices and Simulators 中创建 iPhone 模拟器。下载期间可以只编译应用与测试 target：

```sh
xcodebuild -project Boji.xcodeproj -alltargets -configuration Debug \
  -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO \
  SYMROOT=/tmp/boji-native-products OBJROOT=/tmp/boji-native-intermediates build
```

这条命令验证编译和链接，不运行测试。设备可用后，先执行上方共享 scheme 的构建和测试命令，再安装并启动：

```sh
xcrun simctl boot '<SIMULATOR_ID>'
xcrun simctl bootstatus '<SIMULATOR_ID>' -b
xcrun simctl install '<SIMULATOR_ID>' .build/DerivedData/Build/Products/Debug-iphonesimulator/Boji.app
xcrun simctl launch '<SIMULATOR_ID>' com.boji.personal
```

如果设备已经启动，可跳过 `boot`。当前已接入本机资料、饮食、训练和回收站，功能验收仍按 OpenSpec 清单逐项进行。

## 当前 MVP 导航

保留「记录／回顾／我的」三页。「我的」只保留身体资料、AI 估算、数据管理；iCloud 备份、导出、导入与恢复、回收站集中在数据管理。阶段目标与 Agent 复盘已退出产品导航。目录授权后可前台自动备份，也可停止自动运行或立即备份；不新增后台周期任务。已有历史与资料包兼容性保留。

回顾默认展示饮食／训练两张 13 周记录日历，已记录格分别带餐具／哑铃图标；摄入曲线与训练消耗柱状图位于「趋势」，默认近一周，可选择 1—90 天日期区间，1—7 天完整显示每日日期。系统字体随 Dynamic Type 缩放；日历内密集标注限制字号，趋势图的大字号保留首尾日期并在必要时分行，完整数据仍可读屏。原生控件遵循系统导航习惯。界面只使用黑白灰，用户照片保持原色。

正式界面无演示入口。Debug 构建显式带 `--ui-test-demo-controls` 启动时才显示测试用演示开关；演示仍使用独立内存空间，不联网、不导出。

个人资料保存在 App 容器的 `Application Support/Boji/Personal/`。打开库失败会停留在错误和重试页面，不自动删除或重建已有资料。演示隔离已通过临时磁盘库测试，原生界面验收结果单独记录。

录入与恢复操作见 `docs/recording.md`，资料生效及计算口径见 `docs/profile-and-energy.md`，存储失败与恢复见 `docs/storage.md`，千问直连和授权见 `docs/ai.md`。个人版无需自建服务器；既有私有服务代码位于 `services/food-estimation/`，仅为可选路径。版本 2 资料包与原型 JSON 迁移继续可用；目录自动备份已接回数据管理，验证状态见清单及 `docs/verification.md`。流转操作见 `docs/import-and-backup.md`，格式与 Mac 校验见 `docs/package-format.md`。真实模型仍需用户在 iPhone 本机配置密钥并指定图片后验收；历史版本的真机签名与 iCloud 跨设备交付曾实测；本次重新接入后的真机 iCloud 验收按用户选择留待稍后，不以模拟状态替代。未配置的识别不会生成样例结果。

领域与临时磁盘故障测试：`cd BojiCore && swift test`。UI 测试在 Debug 构建使用每次独立的 UUID 资料目录，重启同一测试时保留该目录；Release 构建不识别这个测试参数。


## 记录首页

首页日期横条固定显示设备当地今天前后各 15 天，切换日期不重建范围。更早的历史在回顾中查看，回到首页时超出窗口的选择会重置为今天，已保存记录保持不变。

`Home/HomeComponents.swift` 独立承载日期、热量总览和单列记录；回顾使用独立的记录日历和趋势组件。餐次与训练部位分类只影响展示，不写入数据库。未知热量显示待估算／横杠，草稿不计入汇总，数值不使用千位分隔符。辅助字号下，热量总览纵向排列，记录内容自动增高。

首页顶部不再显示 App 名，完整日期直接作为标题；日期按钮改为纯数字圆形，随辅助字号同比增大。首页移除当天汇总／记全入口，记录横条使用画布底色与细描边，与灰底热量总览区分。

训练改为一次录入保存：没有进行中卡片、逐组确认或结束训练按钮。未保存输入仅存在于本次表单内，不生成草稿；放弃、关闭或重启后不恢复，没有暂存／冲突弹窗。保存前列表显示原记录，保存修改更新同一身份。规则详见 `docs/recording.md`。

四个新建／编辑表单统一为内容区、时间／热量信息和底部固定保存。饮食移除标签、照片排序与恢复输入；训练移除批量录入、排序及冗余估算说明。返回或放弃不提交修改，保存后才影响正式记录，旧照片、标签与历史保留。已有饮食直接打开编辑表单，底部固定并排「保存／删除／返回」；新建饮食保留顶部放弃和底部保存。辅助字号使用两列餐次和纵向组输入。

回顾仅显示两张 13 周记录日历或 自定义日期区间的摄入曲线与训练柱状图，不再包含当天明细。日历按已保存记录着色并显示类型图标，趋势在缺失日期留空，日历独立翻页，趋势选择起止日期且不改变首页日期。旧数据及统计模型保留兼容，详见 `docs/review.md`。
