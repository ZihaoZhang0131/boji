# 薄记 · Boji

轻一点，记久一点。

饮食与训练记录应用的可交互 UI / UX 原型，当前版本 **v0.5**。采用黑白简笔画、站酷快乐体与 Patrick Hand 字体。

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
- `energy-spec.html`：v0.5 热量功能、计算口径、AI 接口约定与产品边界。
- `design-spec.html`：早期记录功能设计。
- `app.js` / `redesign.js` / `energy.js`：基础交互、简化视觉层和热量功能层。
- `style.css` / `mono.css` / `typography.css` / `energy.css`：样式与字体。
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

- ZCOOL KuaiLe / 站酷快乐体：`assets/OFL-ZCOOL-KuaiLe.txt`。
- Patrick Hand：`assets/OFL-Patrick-Hand.txt`。
- 字体文件来自 Google Fonts 官方仓库，以 SIL Open Font License 1.1 分发。
- 两张早期 Unsplash 照片保留作为示例／上传测试素材，默认界面使用项目绘制的 SVG 简笔画。来源见 `design-spec.html`。
- 未为项目代码另行授予开源许可证；第三方素材仍遵循各自许可。
