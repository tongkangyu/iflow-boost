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
# 1. 克隆或下载项目
git clone https://github.com/your-repo/iflow-boost.git
cd iflow-boost

# 2. 运行部署脚本
.\deploy.ps1

# 3. 完成！直接使用 iflow
iflow
```

就这么简单！无需启动代理，无需占用端口。

## 权限要求

部署脚本需要以下目录的写入权限：

| 路径 | 用途 |
|------|------|
| `%APPDATA%\npm\node_modules\@iflow-ai\iflow-cli\bundle\` | 修补 iflow.js |
| `%USERPROFILE%\.iflow\` | 部署 hooks、skills，更新 settings.json |

**Windows 用户：**
- 修补 iflow.js 需要**以管理员身份运行 PowerShell**
- ~/.iflow/ 目录通常不需要特殊权限（用户目录）

**如果没有管理员权限：**
- 脚本会自动检测权限问题并输出手动步骤
- 按照打印的指令手动完成配置即可

## 详细使用

### 步骤 1：部署

在 PowerShell 中运行部署脚本：

```powershell
.\deploy.ps1
```

脚本会自动：
1. 应用 countTokens 补丁到 iflow.js
2. 创建 `~/.iflow/hooks/` 和 `~/.iflow/skills/` 目录
3. 复制 hook 脚本到 `~/.iflow/hooks/`
4. 复制 skill JSON 文件到 `~/.iflow/skills/`
5. 更新 `~/.iflow/settings.json` 配置

### 步骤 2：验证配置

检查 `~/.iflow/settings.json`：

```powershell
cat ~/.iflow/settings.json
```

确保包含：
- `tokensLimit`：模型的上下文限制
- `compressionTokenThreshold`：0.8（在 80% 限制时压缩）
- `hooks`：Hook 配置

### 步骤 3：使用 iflow

直接正常使用 iflow：

```powershell
iflow
```

当上下文超过阈值时，会自动触发压缩。

### 步骤 4：卸载（可选）

恢复 iflow 原始状态：

```powershell
.\uninstall.ps1
```

这会：
1. 从备份还原 iflow.js
2. 移除 settings.json 中添加的配置
3. 清理 hook 脚本和 skill 文件

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
  let tokens = Math.ceil(text.length / 4);
  
  // 如果 extractTextFromRequest 返回空，尝试从 contents 提取
  if (tokens === 0 && this.currentRequest?.contents) {
    for (const content of this.currentRequest.contents) {
      if (content.parts) {
        for (const part of content.parts) {
          if (part.text) tokens += Math.ceil(part.text.length / 4);
        }
      }
    }
  }
  
  return { totalTokens: tokens || 1 };
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

部署后 `~/.iflow/settings.json` 会被配置：

```json
{
  "tokensLimit": 256000,
  "compressionTokenThreshold": 0.8,
  "contextFileName": ["IFLOW.md", "CLAUDE.md"],
  "hooks": {
    "SetUpEnvironment": [...],
    "SessionStart": [...],
    "PostToolUse": [...]
  }
}
```

### 配置参数说明

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `tokensLimit` | 上下文 token 上限，超过此值触发压缩 | 256000 |
| `compressionTokenThreshold` | 压缩阈值比例，当 token 数超过 `tokensLimit * ratio` 时触发压缩 | 0.8 |

### 常用模型的 tokensLimit 参考

| 模型 | tokensLimit |
|------|------------|
| mimo-v2-flash | 256000 |
| deepseek-chat / deepseek-r1 | 128000 |
| gpt-4o | 128000 |
| claude-3.5-sonnet (Anthropic) | 200000 |
| qwen-max | 128000 |

## 故障排除

### 补丁失败

如果提示 "Could not find exact match"：

1. iflow 可能已更新
2. 检查 iflow.js 中是否存在 countTokens 方法
3. 可能需要手动修补

### 压缩未触发

1. 检查补丁是否应用：`.\deploy.ps1` 应显示 "[OK] Patch already applied!"
2. 检查 settings.json 中的 `tokensLimit` 是否匹配你的模型
3. 检查 `compressionTokenThreshold` 是否设置（默认 0.8）

### Hooks 不工作

1. 检查 hook 文件是否存在于 `~/.iflow/hooks/`
2. 检查 settings.json 中的 hooks 配置
3. 检查 PowerShell 执行策略：`Get-ExecutionPolicy`

## 注意事项

- iflow 更新后补丁会失效，需重新运行 `.\deploy.ps1`
- 补丁脚本会自动备份原始 `iflow.js` 为 `iflow.js.bak`
- `tokensLimit` 设置不当会导致压缩时机不对
- 本工具仅修改 `countTokens` 方法，不改变 iflow 的压缩逻辑

## 免责声明

本项目为非官方社区工具，与 iFlow 官方团队无任何关联。使用本工具修改 iflow.js 可能违反 iFlow 的使用条款，且 iflow 更新后补丁可能失效。使用本工具产生的任何问题（包括但不限于数据丢失、API 费用异常、服务中断），由使用者自行承担。请确保你理解本工具的工作原理后再使用。

## 致谢

- [iFlow CLI](https://github.com/iflow-ai/iflow-cli) - 本工具所修补的原始项目
