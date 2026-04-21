# iflow-boost

[iFlow CLI](https://github.com/iflow-ai/iflow-cli) 第三方 API 上下文自动压缩修复 + 增强工具包。纯 PowerShell 实现，零依赖。

## 问题背景

iFlow CLI 官方已停止维护。使用第三方 API（openai-compatible 模式）时，对话上下文**不会自动压缩**，导致长对话出错。

### 根因分析

iFlow 内部有两种 Content Generator：

| 认证类型 | Content Generator | `countTokens` 结果 | 自动压缩 |
|----------|-------------------|-------------------|---------|
| iflow 官方登录 | gH (OpenAI-compatible) | `undefined` 或 `0` | ❌ 不触发 |
| openai-compatible | gH (OpenAI-compatible) | `undefined` 或 `0` | ❌ 不触发 |
| Cloud Shell | _R (Gemini) | 实际 token 数 | ✅ 正常触发 |

`gH` 类的 `countTokens` 方法依赖 `extractTextFromRequest` 提取文本，但该方法无法正确解析 Gemini 格式的 `contents`（带 `parts` 和 `text` 结构），导致返回 `0` 或 `undefined`。而 `CompressManager.tryCompress()` 在 `totalTokens` 无效时直接跳过整个压缩流程。

## 功能特性

### 🔧 核心修复

- **iflow.js countTokens 补丁**：修复第三方 API 的自动压缩，token 使用超 60% 轻量压缩，超 80% 完整压缩

### 🚀 增强功能

| 功能 | 说明 |
|------|------|
| **结构化上下文压缩** | 摘要包含 Scope/Tools/Files/Pending/Timeline，保留关键上下文 |
| **Git 上下文自动注入** | 自动将 git branch/status/diff 注入 system prompt，让 AI 感知项目状态 |
| **指令文件发现与去重** | 从 cwd 向上遍历查找 IFLOW.md/CLAUDE.md，基于内容哈希去重，自动注入 |
| **Hooks 系统** | PreToolUse/PostToolUse 钩子，支持 Allow/Deny/Warn 三种结果 |
| **Skills 可插拔系统** | JSON 定义技能，自动注入 system prompt，支持自定义扩展 |
| **成本追踪** | 记录 input/output tokens，持久化到本地，随时查看用量 |

### 📦 内置 Skills

| Skill | 说明 | 触发关键词 |
|-------|------|-----------|
| **remember** | 跨会话记忆持久化 | 记住、remember |
| **stuck** | 卡住时恢复策略 | 卡住、stuck |
| **verify** | 验证代码修改 | 验证、verify |
| **simplify** | 简化输出 | 简化、simplify |
| **debug** | 系统化调试流程 | 调试、debug |
| **skillify** | 将操作转化为可复用 Skill | skillify |

### 🛡️ 内置 Hooks

| Hook | 事件 | 说明 |
|------|------|------|
| **01-block-dangerous-commands** | PreToolUse | 阻止 `rm -rf /` 等危险命令 |
| **02-protect-sensitive-files** | PreToolUse | 保护 `.env`、`.ssh/` 等敏感文件 |
| **01-log-tool-usage** | PostToolUse | 记录工具使用日志 |

## 快速开始

### 前置条件

- 已安装 [iFlow CLI](https://github.com/iflow-ai/iflow-cli)：`npm install -g @iflow-ai/iflow-cli`
- 已配置第三方 API（`~/.iflow/settings.json` 中 `selectedAuthType` 为 `openai-compatible`）
- Windows 系统（当前仅支持 Windows PowerShell）

### 方式 A：仅修复压缩（最简单）

```powershell
git clone https://github.com/YOUR_USERNAME/iflow-boost.git
cd iflow-boost

# 修补 iflow.js
.\patch-iflow.ps1

# 配置 settings.json
.\fix-settings.ps1

# 直接使用 iflow，压缩已修复
iflow
```

### 方式 B：完整增强（推荐）

```powershell
git clone https://github.com/YOUR_USERNAME/iflow-boost.git
cd iflow-boost

# 1. 修补 iflow.js
.\patch-iflow.ps1

# 2. 配置 settings.json
.\fix-settings.ps1

# 3. 部署代理 + skills + hooks
.\deploy.ps1

# 4. 启动代理
.\proxy.ps1

# 5. 修改 ~/.iflow/settings.json 的 baseUrl 为代理地址
# "baseUrl": "http://127.0.0.1:8899/v1"
```

## 配置说明

### 压缩配置

运行 `fix-settings.ps1` 后，`~/.iflow/settings.json` 会添加：

```json
{
    "tokensLimit": 256000,
    "outputTokensLimit": 64000,
    "compressionTokenThreshold": 0.8,
    "lightCompressionTokenThreshold": 0.6
}
```

| 字段 | 说明 | 默认值 |
|------|------|--------|
| `tokensLimit` | 模型上下文窗口大小（tokens） | 256000 |
| `outputTokensLimit` | 模型最大输出 tokens | 64000 |
| `compressionTokenThreshold` | 完整压缩触发阈值 | 0.8 |
| `lightCompressionTokenThreshold` | 轻量压缩触发阈值 | 0.6 |

**`tokensLimit` 必须根据你的模型调整**：

| 模型 | tokensLimit |
|------|------------|
| mimo-v2-flash | 256000 |
| deepseek-chat / deepseek-r1 | 128000 |
| gpt-4o | 128000 |
| claude-3.5-sonnet (Anthropic) | 200000 |
| qwen-max | 128000 |

### 增强功能配置

运行 `deploy.ps1` 后额外添加：

```json
{
    "enableGitContext": true,
    "enableInstructions": true,
    "enableHooks": true,
    "enableSkills": true,
    "enableCostTracking": true,
    "proxyPort": 8899,
    "compressAt": 60000,
    "keepRecent": 6,
    "compressModel": "mimo-v2-flash"
}
```

| 字段 | 说明 | 默认值 |
|------|------|--------|
| `enableGitContext` | 自动注入 git 上下文 | true |
| `enableInstructions` | 发现项目指令文件 | true |
| `enableHooks` | 启用钩子系统 | true |
| `enableSkills` | 启用技能系统 | true |
| `enableCostTracking` | 启用成本追踪 | true |
| `proxyPort` | 代理端口 | 8899 |
| `compressAt` | 代理压缩触发阈值 | 60000 |
| `keepRecent` | 压缩保留最近消息数 | 6 |

## 自定义

### 添加自定义 Skill

在 `~/.iflow/skills/` 下创建 JSON 文件：

```json
{
    "name": "my-skill",
    "description": "我的自定义技能描述",
    "usage": "如何触发",
    "trigger_keywords": ["关键词1", "关键词2"],
    "instructions": "当触发时 AI 应该做什么",
    "category": "custom"
}
```

### 添加自定义 Hook

在 `~/.iflow/hooks/PreToolUse/` 或 `PostToolUse/` 下创建 PowerShell 脚本：

```powershell
$data = $input | ConvertFrom-Json
$toolName = $data.tool_name

# exit 0 = Allow, exit 2 = Deny
if ($toolName -eq "dangerous_tool") {
    Write-Output "Blocked by custom hook"
    exit 2
}

exit 0
```

### 添加项目指令

在项目根目录创建 `IFLOW.md`，代理会自动发现并注入到 system prompt：

```markdown
# Project Instructions

- 使用 TypeScript strict mode
- 测试覆盖率 > 80%
- 遵循 conventional commits
```

### 查看代理状态

```powershell
Invoke-RestMethod http://127.0.0.1:8899/v1/proxy/status
```

## 卸载

```powershell
.\uninstall.ps1
```

此脚本会：
1. 还原 `iflow.js` 中的 `countTokens` 方法
2. 移除 `settings.json` 中所有新增配置项
3. 停止代理进程
4. 清理代理脚本、内置 skills、内置 hooks、成本追踪、日志
5. **保留**用户自定义的 skills 和 hooks

如果卸载后仍有问题：

```powershell
npm install -g @iflow-ai/iflow-cli
```

## 文件结构

```
iflow-boost/
├── .gitignore
├── LICENSE
├── README.md
├── patch-iflow.ps1              # 修补 iflow.js countTokens
├── fix-settings.ps1             # 配置 settings.json 压缩参数
├── deploy.ps1                   # 部署代理 + skills + hooks
├── uninstall.ps1                # 卸载所有修改
├── proxy.ps1                    # 增强代理服务器（纯 PowerShell）
├── skills/                      # 内置 Skills
│   ├── remember.json
│   ├── stuck.json
│   ├── verify.json
│   ├── simplify.json
│   ├── debug.json
│   └── skillify.json
└── hooks/                       # 内置 Hooks
    ├── PreToolUse/
    │   ├── 01-block-dangerous-commands.ps1
    │   └── 02-protect-sensitive-files.ps1
    └── PostToolUse/
        └── 01-log-tool-usage.ps1
```

## 注意事项

- iflow 更新后补丁会失效，需重新运行 `patch-iflow.ps1`
- 补丁脚本会自动备份原始 `iflow.js` 为 `iflow.js.bak`
- `tokensLimit` 设置不当会导致压缩时机不对
- Hooks 按文件名排序执行，`01-` 前缀控制优先级
- Skills 通过注入 system prompt 生效，不修改 iflow 本身
- 纯 PowerShell 实现，无需安装 Python 或其他运行时

## 免责声明

本项目为非官方社区工具，与 iFlow 官方团队无任何关联。使用本工具修改 iflow.js 可能违反 iFlow 的使用条款，且 iflow 更新后补丁可能失效。使用本工具产生的任何问题（包括但不限于数据丢失、API 费用异常、服务中断），由使用者自行承担。请确保你理解本工具的工作原理后再使用。

## 致谢

- [iFlow CLI](https://github.com/iflow-ai/iflow-cli) - 本工具所修补的原始项目
- 压缩策略（轻量/完整两级）来自 iFlow CLI 原生实现

## License

MIT
