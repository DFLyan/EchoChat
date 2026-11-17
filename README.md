# 回声 EchoChat

把你和 TA 的微信聊天记录，变成一个会像 TA 一样说话的 AI。

运行在 HarmonyOS（鸿蒙）上的纯本地应用：导入微信聊天导出文件，AI 归纳 TA 的说话风格生成人设卡，然后在微信风格的聊天界面里与"TA"流式对话。

## 功能

- **导入聊天记录**
  - 支持 Moect 导出的 `c*.js` 分片（多选 / zip 压缩包）
  - 兼容留痕（MemoTrace）等工具导出的 txt
  - zip 自动解压解析，GBK/UTF-8 编码自动识别
  - 微信里收到 zip 可直接「其他应用打开 → 回声」自动进入导入流程
- **自动识别双方**：按消息发送方自动区分"我"与"TA"，可手动确认与改名
- **AI 人设卡**：归纳 TA 的性格、语气特点、口头禅、常聊话题、关系；精选对话示例经过**原文逐字校验**，杜绝模型编造
- **分析深度可选**：1.5 万 / 3 万 / 6 万字采样三档，记录多时可提高还原度
- **微信风格聊天**：气泡消息、双方头像、时间分隔线、emoji 面板、长按复制、流式逐字回复、失败重试
- **聊天复盘（聊天分析）**：AI 以聊天教练视角通读全部原始记录，指出你的沟通问题（话题终结、不接情绪、回复敷衍等）并给出可直接照做的建议
- **模型灵活**：默认 DeepSeek，兼容任何 OpenAI 风格接口（Moonshot / GLM / Qwen / 硅基流动等），支持从 `/models` 动态拉取可用模型列表，模型名可自由输入
- **数据全本地**：聊天记录、人设、API Key 仅保存在本机（RDB + Preferences），不经过任何中间服务器

## 技术栈

- HarmonyOS ArkTS / ArkUI（声明式），API 23
- Navigation + 系统路由表（router_map）页面路由
- relationalStore（RDB）存储角色 / 消息 / 原始记录，Preferences 存设置
- `http.requestInStream` + SSE 逐行解析实现流式输出
- zlib 解压、DocumentViewPicker 文件选择、文件打开方式关联（skills）

## 目录结构

```
entry/src/main/ets/
├── entryability/        # 入口 UIAbility（处理文件打开 Want）
├── pages/               # Index 首页 / ImportPage 导入 / ChatPage 对话
│                        # CoachPage 聊天分析 / SettingsPage 设置
├── services/
│   ├── LlmClient.ets         # OpenAI 兼容客户端（chat + SSE 流式）
│   ├── ChatParser.ets        # 留痕 txt 解析
│   ├── WeChatExportParser.ets# Moect window.__wxChunk 解析
│   ├── PersonaAnalyzer.ets   # 人设卡生成 + 示例原文校验
│   ├── PromptBuilder.ets     # 角色扮演 system prompt
│   └── ChatCoach.ets         # 聊天复盘分析
├── database/            # PersonaDb(RDB) / SettingsStore(Preferences)
├── model/               # 数据模型
└── common/              # UiUtil 工具
```

## 快速开始

1. 使用 DevEco Studio 打开工程（需 HarmonyOS SDK，API 23）
2. 配置签名后运行到真机或模拟器
3. 命令行方式：

```bash
devecocli build
devecocli run
```

## 使用流程

1. 电脑上用 [Moect](https://github.com/mofan6/Moect) 导出微信 PC 聊天记录（`c000001.js` 等分片），打包成 zip
2. 把 zip 发送到手机（如微信文件传输助手）
3. 在微信里「其他应用打开 → 回声」，或打开 app 在导入页选择文件
4. 确认"我 / TA"、选择分析深度，生成人设卡（可编辑后保存）
5. 开始和 TA 聊天；聊天页右上角菜单可进入「聊天分析」做全局复盘

## 设置说明

- **API Key / API 地址 / 模型**：在设置页填写；点击「获取可用模型列表」可从接口拉取当前可用的模型并点选
- 兼容任何 OpenAI 风格的 `/chat/completions` 接口

## 隐私与限制

- 手机端无法直接读取微信数据库（系统沙箱限制），聊天记录需在 PC 端用 Moect 等工具导出
- 所有数据仅保存在本机；对话时聊天内容会发送给你配置的模型服务方
