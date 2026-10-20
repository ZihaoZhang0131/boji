# 原生代码边界

`App` 保存 SwiftUI 视图、相机／相册与文件选择器、Keychain 和装配入口。`BojiCore` 是支持 iOS 17／macOS 14 以上的本地 Swift package：

- `BojiDomain` 保存值类型、时间、资料和目标规则、热量计算、估算资格以及统计口径。金额类数值使用 Decimal，未知值保留 nil。
- `BojiPersistence` 用 SwiftData 显式提交和回滚，照片独立落盘。`ManagedStore` 使用完整影子库和原子活动指针处理导入／升级；旧库保留供回退。成功提交递增资料修订并标记待备份。
- `BojiEstimation` 包含私有 HTTPS 协议和持久任务调度器。提交幂等、轮询恢复、取消与有限重试都依赖保存的任务身份；应用结果之前重新核对资料集、输入、生命周期、授权与人工修订。
- `BojiPortability` 定义版本 2 资料包、完整性预检、来源映射与冲突计划、原型 JSON 转换、独立导出和单向目录备份。备份操作元数据单独持久化，不产生新的资料修订或无限备份循环。

`WorkspaceModel` 装配当前资料库、估算队列和目录备份，在导入或回退后同时切换这些依赖并刷新值快照。旧库被冻结，仍持有旧引用的任务无法覆盖新版本。目录不可用和 AI 失败不会让已保存的记录变成保存失败。

AI 请求发送至独立的 `services/food-estimation` TypeScript 服务；供应商密钥只在服务环境中。客户端 Keychain 保存个人服务令牌。正式装配未配置时显示不可用，不使用演示结果。服务用 SQLite 持久化幂等任务和配额，执行结果未知的请求不自动重复调用供应商。

时钟、文件操作、照片写入与关键发布边界可注入测试替身或故障。测试使用独立临时目录和合成图片；原生装配支持显式存储根供 XCTest 隔离，UI 测试使用仅 Debug 可识别的 UUID 目录。模拟器临时签名用于 Keychain 验证，不等同于真实设备签名。

```sh
swift test --package-path ios/BojiCore
npm test --prefix services/food-estimation
BOJI_RUN_SERVICE_INTEGRATION=1 swift test --package-path ios/BojiCore
```

最后一项在 macOS 使用临时证书和 localhost HTTPS 协议夹具验证真实 Swift／TypeScript 传输、幂等及恢复；夹具不是供应商真实识别。真实 AI、iCloud 跨设备交付和真机权限验收分别记录，不能以协议测试代替。
