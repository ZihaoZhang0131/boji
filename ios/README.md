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

如果设备已经启动，可跳过 `boot`。当前已接入本机资料、饮食、训练、草稿和回收站，功能验收仍按 OpenSpec 清单逐项进行。

## 导航与演示

当前已有「记录／回顾／我的」导航、真实日期、前后一天和日历选择，身体资料初始为空。「我的 → 体验演示」打开独立的内存资料空间；「退出演示」返回个人库。每次进入演示都会重建例子，不写入个人记录或草稿，识别服务和正式资料包导出均禁止使用演示空间。

个人资料保存在 App 容器的 `Application Support/Boji/Personal/`。打开库失败会停留在错误和重试页面，不自动删除或重建已有资料。演示隔离已通过临时磁盘库测试，原生界面验收结果单独记录。

录入与恢复操作见 `docs/recording.md`，资料生效及计算口径见 `docs/profile-and-energy.md`，存储失败与恢复见 `docs/storage.md`，千问直连和授权见 `docs/ai.md`。个人版无需自建服务器；既有私有服务代码位于 `services/food-estimation/`，仅为可选路径。版本 2 资料包、原型 JSON 迁移和单向目录备份已接入，验证状态见清单及 `docs/verification.md`。流转操作见 `docs/import-and-backup.md`，格式与 Mac 校验见 `docs/package-format.md`。真实模型仍需用户在 iPhone 本机配置密钥并指定图片后验收；真机签名与 iCloud 跨设备交付已实测。未配置的识别不会生成样例结果。

领域与临时磁盘故障测试：`cd BojiCore && swift test`。UI 测试在 Debug 构建使用每次独立的 UUID 资料目录，重启同一测试时保留该目录；Release 构建不识别这个测试参数。
