# 薄记 · Boji

轻一点，记久一点。

饮食与训练记录应用。根目录提供 **v0.6 网页交互原型**，原生 iPhone 工程位于 `ios/`。界面采用单色灰阶、柔和圆角和 Fusion Pixel 字体；以图像、数字和明确的操作建立层级。

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

- 本说明的浏览器版本是设计原型；原生 iPhone 工程的构建和运行见 `ios/README.md`。
- **食物 AI 识别是明确标注的模拟演示，未调用真实模型接口。** 真实上传照片不会获得伪造的识别结果。
- 未连接 iCloud 或其他同步服务。记录存储在当前浏览器的 `localStorage` 中，不适合作为正式健康资料存储方案。
- 仓库不包含用户浏览器中的记录、个人资料、导出数据或 API 密钥。导出文件可能包含身体信息与照片，分享前请自行检查。
- 热量与代谢数值仅为估算，非医学测量或医疗建议。公式来源和限制见 `energy-spec.html`。

## 素材许可

- 当前字体 Fusion Pixel：来自作者官方站点，采用 SIL Open Font License 1.1。许可见 `assets/OFL-Fusion-Pixel.txt`；来源 <https://github.com/TakWolf/fusion-pixel-font>。
- ZCOOL KuaiLe / 站酷快乐体：`assets/OFL-ZCOOL-KuaiLe.txt`。
- Patrick Hand：`assets/OFL-Patrick-Hand.txt`。
- 上述两种早期字体文件来自 Google Fonts 官方仓库，以 SIL Open Font License 1.1 分发。
- 两张早期 Unsplash 照片保留作为示例／上传测试素材，来源见 `design-spec.html`。当前演示餐食使用下列照片；早期手绘字体与像素 SVG 插画保留作历史设计资源。
- 未为项目代码另行授予开源许可证；第三方素材仍遵循各自许可。

## 真实状态样例来源

- 餐食照片来自 Unsplash：[Olya P](https://unsplash.com/photos/fried-egg-with-avocado-toast-breakfast-orMrxgkA4EA)、[joe boshra](https://unsplash.com/photos/healthy-chicken-and-rice-bowl-with-fresh-vegetables-tB2MPTiSrsg)、[sunorwind](https://unsplash.com/photos/salmon-sashimi-bowl-with-rice-and-garnishes-cwqI5PcUsqQ)、[Matilda Jarl](https://unsplash.com/photos/a-bowl-of-granola-with-yogurt-and-blueberries-9Uphjae3YnU)、[Mantra Media](https://unsplash.com/photos/steak-with-vegetables-on-plate-XPvhzVIeETM)、[You Le](https://unsplash.com/photos/a-bowl-of-delicious-laksa-soup-with-noodles-and-shrimp-2h-BQpdUmYo) 与 [Thanti Riess](https://unsplash.com/photos/meat-and-vegetables-YPMdhn9gEp0)。
- 默认状态包含 2026-10-03 至 2026-10-09 的 21 条饮食、3 次训练和一份个人资料，用于观察完整一周的首页、回顾、照片墙与热量趋势。
- 餐食文字、份量、热量、训练组数与个人资料均为虚构样例，不代表照片作者或当前用户；照片无法证明实际份量，热量仍是原型中的演示估算。

## UI 简化原则

这次改造保留像素字体和图标的辨识度，将全项目的界面统一为轻量的单色手账。

1. **先确定当前任务。** 记录页用于识别和打开记录，表单用于完成录入，回顾页用于理解变化，设置页用于找到选项。同一屏不让次要说明与主任务竞争。
2. **用布局处理留白。** 内容少时调整尺寸、比例和排列；首页使用等大的双列视觉卡片，只显示照片或训练部位图标与热量，不补装饰性文案。
3. **按需展开细节。** 时间、分类、标签、公式、估算明细、历史版本和技术说明进入详情或折叠区。输入标签、单位、错误、关键状态和执行前必要提示仍然可见。
4. **让相同内容落在相同位置。** 热量数字与单位统一层级；同类记录、控件和设置行使用相同间距、圆角和对齐。信息密度来自结构，不依赖多层框体。
5. **用克制的视觉层级。** 白色画布、灰色表面、黑色主操作；去掉硬阴影和重复粗描边。列表与表单优先轻分隔，避免卡片套卡片。
6. **简化呈现，保留事实和能力。** 不把未知热量显示成零，不把未完成组计入训练，不把示例当真实识别。保存、编辑、导入导出、授权与恢复等能力继续可用，并保留键盘、屏幕阅读器及系统字号支持。

### 视觉约定

- 色彩：网页浅色画布 `#fff`、正文 `#191919`、次要文字 `#666`、灰色表面 `#f3f3f3`；深色使用对应的语义颜色。原生遵循系统明暗模式。
- 间距：以 4px / 4pt 为基准；页面通常 16–24，控件间距 8–16，分区间距 20–24。
- 容器：记录卡圆角 16，按钮和表面圆角 12；图片圆角 10–12。依靠背景区分层级，少用边框和阴影。
- 字体：Fusion Pixel；网页正文与控件 12px，核心数字 24/36px；原生保持可缩放的语义字号。
- 操作：训练卡片直接进入编辑，详情与历史按需打开。每个任务保留一个明确的主动作，主要操作的点击区域至少 44px / 44pt；紧凑选择控件保留清晰间距。折叠内容仍可通过键盘与辅助功能访问。
- 图像：用户照片保持原图；原创像素图标表达训练部位。示例素材不进入真实记录的推断。
- 验证：饮食/训练录入和编辑、个人资料、7/30 天回顾、未知/空白/失败状态、浅色/深色、320/393px 网页，以及原生小屏与大字号。
