# 薄记 · Boji

轻一点，记久一点。

饮食与训练记录应用的可交互 UI / UX 原型，当前版本 **v0.6**。采用黑白像素风与 Fusion Pixel 字体；中文、小字、英文和数字统一像素化。

![薄记界面总览](energy-overview.png)

## 当前功能

- 饮食照片、文字、餐次与时间记录，以及编辑、删除和撤销。
- 训练动作、重量、次数和完成组记录，支持草稿恢复与批量补记。
- 个人信息录入、静息代谢与日常消耗估算。
- 基于体重、时长和训练类型估算运动净消耗。
- 食物 AI 识别的交互演示、逐项份量与热量修正。
- 7 / 30 天热量图表，区分完整记录、漏记与待估算数据。
- 本地记录与图片 JSON 导出。

## 运行

这是静态网页原型，无需构建。进入仓库目录启动服务：

```sh
python3 -m http.server 8765 --bind 127.0.0.1
```

打开 <http://127.0.0.1:8765/>。请通过本地 HTTP 服务访问，以保证图片导出等功能正常工作。

## 文件入口

- `index.html`：可交互原型。
- `gallery.html`：主要界面总览。
- `energy-spec.html`：热量功能、计算口径、AI 接口约定、v0.6 视觉与产品边界。
- `design-spec.html`：早期记录功能设计。
- `app.js` / `redesign.js` / `energy.js`：基础交互、简化视觉层和热量功能层。
- `style.css` / `mono.css` / `typography.css` / `energy.css`：样式与字体。
- `pixel-font.css` / `pixel.css` / `pixel.js`：v0.6 像素字体、视觉层、原创像素图标与示例插画的展示替换。
- `assets/`：字体、许可证、示例照片和 SVG 插画。

## 浏览器验证

需要 Node.js 和本机安装的 Google Chrome。启动上述预览服务后：

```sh
npm install
npm test
```

`npm run capture` 重新生成最新热量功能截图。测试使用独立浏览器上下文，不读取用户日常浏览器的数据。截图中的个人信息、照片和记录均为示例。

## 产品边界与隐私

- 当前是浏览器设计原型，不是原生 iOS 应用，也未上线 App Store。
- **食物 AI 识别是明确标注的模拟演示，未调用真实模型接口。** 真实上传照片不会获得伪造的识别结果。
- 未连接 iCloud 或其他同步服务。记录存储在当前浏览器的 `localStorage` 中，不适合作为正式健康资料存储方案。
- 仓库不包含用户浏览器中的记录、个人资料、导出数据或 API 密钥。导出文件可能包含身体信息与照片，分享前请自行检查。
- 热量与代谢数值仅为估算，非医学测量或医疗建议。公式来源和限制见 `energy-spec.html`。

## 素材许可

- 当前字体 Fusion Pixel：来自作者官方站点，采用 SIL Open Font License 1.1。许可见 `assets/OFL-Fusion-Pixel.txt`；来源 <https://github.com/TakWolf/fusion-pixel-font>。
- ZCOOL KuaiLe / 站酷快乐体：`assets/OFL-ZCOOL-KuaiLe.txt`。
- Patrick Hand：`assets/OFL-Patrick-Hand.txt`。
- 上述两种早期字体文件来自 Google Fonts 官方仓库，以 SIL Open Font License 1.1 分发。
- 两张早期 Unsplash 照片保留作为示例／上传测试素材，默认界面使用项目绘制的像素 SVG。来源见 `design-spec.html`。早期手绘字体与插画保留作历史设计资源，不用于当前 App 界面。
- 未为项目代码另行授予开源许可证；第三方素材仍遵循各自许可。

## 真实状态样例来源

- 餐食照片来自 Unsplash：[Olya P](https://unsplash.com/photos/fried-egg-with-avocado-toast-breakfast-orMrxgkA4EA)、[joe boshra](https://unsplash.com/photos/healthy-chicken-and-rice-bowl-with-fresh-vegetables-tB2MPTiSrsg)、[sunorwind](https://unsplash.com/photos/salmon-sashimi-bowl-with-rice-and-garnishes-cwqI5PcUsqQ)、[Matilda Jarl](https://unsplash.com/photos/a-bowl-of-granola-with-yogurt-and-blueberries-9Uphjae3YnU)、[Mantra Media](https://unsplash.com/photos/steak-with-vegetables-on-plate-XPvhzVIeETM)、[You Le](https://unsplash.com/photos/a-bowl-of-delicious-laksa-soup-with-noodles-and-shrimp-2h-BQpdUmYo) 与 [Thanti Riess](https://unsplash.com/photos/meat-and-vegetables-YPMdhn9gEp0)。
- 默认状态包含 2026-10-03 至 2026-10-09 的 21 条饮食、3 次训练和一份个人资料，用于观察完整一周的首页、回顾、照片墙与热量趋势。
- 餐食文字、份量、热量、训练组数与个人资料均为虚构样例，不代表照片作者或当前用户；照片无法证明实际份量，热量仍是原型中的演示估算。

## v0.6 设计约定

- 目标：保留饮食、训练、热量估算的全部交互，改为克制的黑白像素手账。借鉴《星露谷物语》的物品栏和像素框，不使用游戏的角色、贴图、标志或界面素材。
- 结构：记录、回顾、我的三项导航不变；既有 Sheet 与统计口径不变；手机端固定记录入口，窄屏滚动展示长表单。
- 字体：Fusion Pixel 12px 简体中文版，中文和 Latin 使用同一字体。正文、小字与控件优先 12px，标题 24/36px，品牌 36/48px；密集数值少量 18px。真实设备放大与 Dynamic Type 待原生验证。
- 材质：黑白与中性灰；2px 主边框、1px 信息分隔、无模糊的 3px 硬阴影、方形选中点。留白建立层级，不铺满像素纹理。
- 图像：原创 16×16 像素图标和 48×48 餐食示例；用户上传的照片仍显示原图。纯展示层映射不改照片 URL 或持久化数据。
- 图表：柱形和数据点方角化；数值、缺失处理与交互仍使用原逻辑，像素风不改变数据。
- 验收：旧录入流程、新热量流程、字体加载、真实照片保护、320/393px、浅色/深色、空白/离线/识别失败均能运行并完成视觉核验。
