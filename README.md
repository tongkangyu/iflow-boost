# iflow-boost

iFlow CLI 增强工具包 - 无代理版，直接使用 iflow 原生功能。

## 功能

| 功能 | 说明 |
|------|------|
| **countTokens 补丁** | 修复第三方 API 无法触发自动压缩的问题 |
| **结构化压缩摘要** | 压缩时生成包含 Scope/Tools/Files/Pending 的摘要 |
| **Git 上下文注入** | 自动注入 Git 分支、状态、最近提交信息 |
| **Skills 系统** | 根据关键词注入技能指令 |
| **成本追踪** | 记录 API 调用次数 |

## 快速开始

```powershell
# 1. 部署
.\deploy.ps1

# 2. 按提示配置 settings.json

# 3. 直接使用 iflow
iflow
```

就这么简单！无需启动代理，无需占用端口。

## 工作原理

```
┌────────────────────────────────────────────────────────────┐
│                    iflow-boost (无代理版)                   │
├────────────────────────────────────────────────────────────┤
│                                                            │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐ │
│  │ patch-iflow  │    │   Hooks      │    │   Skills     │ │
│  │ countTokens  │    │   脚本目录   │    │   JSON 目录  │ │
│  └──────┬───────┘    └──────┬───────┘    └──────┬───────┘ │
│         │                   │                    │         │
│         ▼                   ▼                    ▼         │
│  ┌──────────────────────────────────────────────────────┐ │
│  │                   iflow CLI 原生功能                   │ │
│  │  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐     │ │
│  │  │ Hooks 系统  │ │ 上下文发现  │ │   压缩器    │     │ │
│  │  └─────────────┘ └─────────────┘ └─────────────┘     │ │
│  └──────────────────────────────────────────────────────┘ │
│                                                            │
└────────────────────────────────────────────────────────────┘
```

## countTokens 补丁详解

### 问题背景

iFlow CLI 内置了自动压缩功能，当上下文超过阈值时会自动压缩。但使用第三方 API（如 OpenAI 兼容 API）时，压缩功能无法正常触发。

### 原因分析

iFlow 使用 `countTokens` 方法统计当前上下文的 token 数量：

```javascript
// iflow.js 中的 countTokens 方法
countTokens() {
  const text = this.extractTextFromRequest(this.currentRequest);
  return this.estimateTokens(text);
}
```

问题在于 `extractTextFromRequest` 方法只处理 iflow 原生格式（Claude API 格式），而第三方 API 使用的是 Gemini 格式的 `contents` 结构：

```javascript
// 第三方 API 的请求格式
{
  "contents": [
    { "role": "user", "parts": [{ "text": "Hello" }] },
    { "role": "assistant", "parts": [{ "text": "Hi!" }] }
  ]
}
```

`extractTextFromRequest` 无法识别这种格式，返回空字符串，导致 `countTokens` 返回 0，压缩流程被跳过。

### 补丁方案

补丁修改 `countTokens` 方法，在 `extractTextFromRequest` 返回空时，遍历 `contents` 结构提取文本：

```javascript
// 补丁后的 countTokens 方法
countTokens() {
  let text = this.extractTextFromRequest(this.currentRequest);
  
  // 如果 extractTextFromRequest 返回空，尝试从 contents 提取
  if (!text && this.currentRequest?.contents) {
    for (const content of this.currentRequest.contents) {
      if (content.parts) {
        for (const part of content.parts) {
          if (part.text) text += part.text + ' ';
        }
      }
    }
  }
  
  return this.estimateTokens(text);
}
```

### 支持的 API

补丁后支持所有使用 Gemini 格式的第三方 API：

| API | 兼容性 |
|-----|--------|
| OpenRouter | ✅ |
| DeepSeek | ✅ |
| Qwen (通义千问) | ✅ |
| Kimi (月之暗面) | ✅ |
| 智谱 AI | ✅ |
| 其他 OpenAI 兼容 API | ✅ |

## Hooks 系统

使用 iflow 原生的 Hooks 系统：

| Hook | 触发时机 | 功能 |
|------|---------|------|
| **SetUpEnvironment** | 会话开始时 | 注入 Git 上下文和 Skills 列表 |
| **SessionStart (compress)** | 压缩触发后 | 生成结构化摘要 |
| **PostToolUse** | 工具调用后 | 记录成本追踪 |

### 结构化压缩摘要

当上下文超过阈值触发压缩时，会自动生成结构化摘要：

```
## Context Summary

### Scope
- Total messages: 45
- User: 15, Assistant: 30

### Tools Used
- Edit: 12 times
- Bash: 8 times
- Read: 5 times

### Files Referenced
- src/main.ts
- src/utils.ts
- config.json

### Pending Tasks
- Fix bug in authentication
- Add tests for new feature

### Timeline
- Session: 10:30 -> 11:45
```

## 文件结构

```
iflow-boost/
├── patch-iflow.ps1          # countTokens 补丁
├── deploy.ps1               # 部署脚本
├── uninstall.ps1            # 卸载脚本
├── hooks/
│   ├── git-context.ps1      # Git 上下文注入
│   ├── skills-inject.ps1    # Skills 注入
│   ├── compress-summary.ps1 # 结构化压缩摘要
│   └── cost-tracker.ps1     # 成本追踪
├── skills/                  # Skills JSON 文件
│   ├── remember.json
│   ├── stuck.json
│   ├── verify.json
│   ├── simplify.json
│   ├── debug.json
│   └── skillify.json
└── README.md
```

## 配置

部署后需要在 `~/.iflow/settings.json` 中添加以下配置：

```json
{
  "tokensLimit": 256000,
  "compressionTokenThreshold": 0.8,
  "contextFileName": ["IFLOW.md", "CLAUDE.md"],
  "hooks": {
    "SetUpEnvironment": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "powershell -ExecutionPolicy Bypass -File ~/.iflow/hooks/git-context.ps1",
            "timeout": 5
          },
          {
            "type": "command",
            "command": "powershell -ExecutionPolicy Bypass -File ~/.iflow/hooks/skills-inject.ps1",
            "timeout": 5
          }
        ]
      }
    ],
    "SessionStart": [
      {
        "matcher": "compress",
        "hooks": [
          {
            "type": "command",
            "command": "powershell -ExecutionPolicy Bypass -File ~/.iflow/hooks/compress-summary.ps1",
            "timeout": 10
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "powershell -ExecutionPolicy Bypass -File ~/.iflow/hooks/cost-tracker.ps1",
            "timeout": 5
          }
        ]
      }
    ]
  }
}
```

### 配置参数说明

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `tokensLimit` | 上下文 token 上限，超过此值触发压缩 | 256000 |
| `compressionTokenThreshold` | 压缩阈值比例，当 token 数超过 `tokensLimit * compressionTokenThreshold` 时触发压缩 | 0.8 |

### 常用模型的 tokensLimit 参考

| 模型 | tokensLimit |
|------|------------|
| mimo-v2-flash | 256000 |
| deepseek-chat / deepseek-r1 | 128000 |
| gpt-4o | 128000 |
| claude-3.5-sonnet (Anthropic) | 200000 |
| qwen-max | 128000 |

## 卸载

```powershell
.\uninstall.ps1
```

## 注意事项

- iflow 更新后补丁会失效，需重新运行 `.\deploy.ps1`
- 补丁脚本会自动备份原始 `iflow.js` 为 `iflow.js.bak`
- `tokensLimit` 设置不当会导致压缩时机不对
- 本工具仅修改 `countTokens` 方法，不改变 iflow 的压缩逻辑

## 免责声明

本项目为非官方社区工具，与 iFlow 官方团队无任何关联。使用本工具修改 iflow.js 可能违反 iFlow 的使用条款，且 iflow 更新后补丁可能失效。使用本工具产生的任何问题（包括但不限于数据丢失、API 费用异常、服务中断），由使用者自行承担。请确保你理解本工具的工作原理后再使用。

## 致谢

- [iFlow CLI](https://github.com/iflow-ai/iflow-cli) - 本工具所修补的原始项目
