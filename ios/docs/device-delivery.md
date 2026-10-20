# 安装到自己的 iPhone

当前工程已在 iOS 26.5 模拟器编译、启动及执行原生测试。2026-10-18 使用用户的 Personal Team 把 Debug App 安装到 iPhone 14（iOS 26.6）；首次启动因开发者证书未获用户信任而被拒，用户在手机完成信任后，`devicectl device process launch` 成功，Xcode 真机截图显示薄记已运行在「目录备份」页面。以下保留完整的个人安装与更新步骤。

1. 打开 `ios/Boji.xcodeproj`，在 Xcode Settings 的 Apple Accounts 登录自己的 Apple 账号。账号登录和凭据由本人完成，不发到聊天或写入仓库。
2. 选择 Boji target，在 Signing & Capabilities 启用 Automatically manage signing，选择自己的 Team。当前本机 `project.yml` 已记录此 Personal Team ID 供重新生成工程；换用其他账号时同步改 Team ID。若 `com.boji.personal` 对你的团队不可用，改为可用且之后保持不变的 Bundle ID，并同步修改 `project.yml` 的 `PRODUCT_BUNDLE_IDENTIFIER`，避免以后运行 XcodeGen 覆盖。
3. 连接并解锁运行 iOS 17 以上的 iPhone，按系统提示信任开发电脑。开发运行需在设备启用 Developer Mode 并按系统流程重启确认。首次用 Personal Team 安装后，如 iOS 提示未经信任的开发者，到「设置 → 通用 → VPN 与设备管理」信任对应开发者，再在 Xcode 选择该设备运行 Boji。自动签名及开发运行方式见 [Apple 运行文档](https://developer.apple.com/documentation/xcode/running-your-app-on-simulated-or-physical-devices) 和 [Developer Mode](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device)。
4. 首次启动应为空资料库。先在飞行模式填写资料、记录文字餐食和训练，关闭并重开确认保存；再验证相册、相机和拒绝权限后继续文字记录。

免费 Personal Team 的设备安装描述文件自签发起七天到期，届时需要重新通过 Xcode 签名运行；账号能力与其他上限以 [Apple 账号说明](https://developer.apple.com/help/account/basics/about-your-developer-account) 为准。付费团队也须管理实际描述文件有效期，不以模拟器临时签名代替真机签名。

## 更新与资料保护

更新前生成完整资料包，核验照片和 manifest。用同一 Bundle ID／团队在原设备上覆盖运行；不要以卸载再安装作为更新步骤。签名过期时先重新签名，避免卸载丢失容器资料。若更改 Bundle ID，系统会把它当作另一个 App，资料需要从完整资料包显式导入。应用遇到未知 schema 不会清库，恢复路径见 `storage.md` 与 `import-and-backup.md`。

## 配置 AI 与 Mac 备份

个人版无需自建服务器。App「我的 → AI 估算」在 iPhone 本机填写自己的千问 API Key，阅读供应商政策后明确授权；当前端点和模型固定为千问AI平台与 `qwen3-omni-flash`。密钥只留在本机 Keychain，不进入导出包、备份或仓库。初次联调由用户指定可发送的测试图片。已有私有服务代码可选，见 `services/food-estimation/README.md`。

目录备份通过「我的 → 目录备份」选择用户自己的文件夹。真机选择 iCloud Drive 后记录一条测试餐食，在 Mac 下载完整包并运行校验脚本；本机目录写入成功不代表该跨设备步骤已经完成。

## 仍需填写的实测记录

安装设备为 iPhone 14／iOS 26.6，签名团队为用户的 Personal Team，安装日期为 2026-10-18。iCloud 全文件下载和 manifest 校验已完成。仍需验证：相机和 HEIC、拒绝权限、键盘遮挡、小屏／大字号／深色／VoiceOver、飞行模式重启，以及真实千问识别修正后持久化。对应 OpenSpec 任务在实测前保持未勾选。
