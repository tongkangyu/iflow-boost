# iflow-boost

iFlow CLI 增强工具包 — 无代理版，直接使用 iflow 原生功能。

## 功能

| 功能 | 说明 |
|------|------|
| **countTokens 补丁** | 修复第三方 API（Gemini 格式）无法触发自动压缩的问题 |
| **主动压缩** | 每次发消息前主动检查上下文用量，超过 80% 提前压缩 |
| **模型上下文自动检测** | 根据 settings.json 中的模型名自动设置 tokensLimit，覆盖 20+ 模型系列 |
| **结构化压缩摘要** | 压缩时自动生成包含 Scope / Tools / Files / Pending 的摘要 |
| **Git 上下文注入** | 自动注入当前分支、变更状态、最近提交信息 |
| **Skills 系统** | 根据触发关键词自动注入技能指令，让 AI 按规则行事 |
| **成本追踪** | 记录每次 API 调用的 token 消耗 |

## 快速开始

```powershell
# 1. 克隆项目
git clone https://github.com/your-repo/iflow-boost.git
cd iflow-boost

# 2. 一键部署
.\deploy.ps1

# 3. 直接使用
iflow
```

## 完整使用样例

以下是从零开始的完整流程，展示所有增强功能的效果。

### 场景：首次部署 + 日常使用

**步骤 1：以管理员身份打开 PowerShell**

```powershell
# 确认执行策略允许脚本运行
Get-ExecutionPolicy
# 如返回 Restricted，先设置：
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

**步骤 2：部署增强工具包**

```powershell
# 进入项目目录
cd C:\personal\iflow-boost

# 部署——补丁 + 模型检测 + hooks + skills 一键完成
.\deploy.ps1
```

终端输出示例：

```
========================================
  iflow-boost Deploy (No Proxy)
========================================

==> Backing up current configuration...
[OK] Backed up 4 hook(s) to ...\.iflow\.deploy-backup\pre-deploy-20260427_162011
[OK] Backed up settings.json to ...\.iflow\.deploy-backup\pre-deploy-20260427_162011

==> Patching countTokens...
Patching iflow.js (v5)...
[OK] countTokens: patched
[OK] Proactive compression: patched
[OK] Reasoning mode content field: patched

==> Auto-detecting model context limit...
  Detected model: deepseek-v4-flash
  Recommended tokensLimit: 1000000
  Current tokensLimit: 256000
[OK] Auto-set tokensLimit to 1000000 for model 'deepseek-v4-flash'

==> Deploying Hooks...
[OK] Deployed: compress-summary.ps1
[OK] Deployed: cost-tracker.ps1
[OK] Deployed: git-context.ps1
[OK] Deployed: skills-inject.ps1

==> Deploying Skills...
[OK] Deployed: debug.json, remember.json, simplify.json ...

==> Configuring settings.json...
[OK] settings.json updated

Features enabled:
  - countTokens patch (3rd party API compression)
  - Proactive compression
  - Model auto-detection: tokensLimit matched to your model
  - Git context injection
  - Skills system
  - Structured compression summary
  - Cost tracking

Now run: iflow
```

**步骤 3：确认配置已自动生效**

```powershell
# 查看 settings.json 中的 tokensLimit 是否正确匹配模型
Get-Content "$env:USERPROFILE\.iflow\settings.json" -Raw | ConvertFrom-Json | Select-Object modelName, tokensLimit, compressionTokenThreshold
```

输出：

```
modelName         tokensLimit compressionTokenThreshold
---------         ----------- -------------------------
deepseek-v4-flash     1000000                       0.8
```

> 如果使用 DeepSeek v4，`tokensLimit` 自动设为 `1000000`（1M）；Claude 3.5 则为 `200000`；GPT-4o 为 `128000`。不正确？确认 `settings.json` 中的 `modelName` 是否准确。

**步骤 4：启动 iflow**

```powershell
iflow
```

进入 iFlow CLI 交互界面。此时 SetUpEnvironment hooks 已自动运行：

```
# Git 上下文（由 git-context.ps1 注入）
[Git] Branch: main | Changes: 3 modified | Last commit: "fix: ..."

# Skills 已加载（由 skills-inject.ps1 注入）
可用技能: debug / remember / simplify / verify / ...
输入 /<技能名> 激活
```

**步骤 5：正常使用，注意观察压缩行为**

在对话过程中，留意上下文百分比的变化：

```
Context: [████████████░░░░] 72% (756K / 1.0M)
```

- 百分比按模型实际上下文上限计算（这里是 1M 的 72%）
- 超过 80%（800K）时，iflow 自动触发压缩，生成结构化摘要
- 压缩后 hooks 自动运行 `compress-summary.ps1`，输出：

```
[Compress] Context Summary
  Scope: 48 messages (User: 16, Assistant: 32)
  Tools: Edit(14)  Bash(9)  Read(4)
  Files: src/main.ts · src/utils.ts · config.json
  Pending: None
  Saved: 720K → 85K (88% reduction)
```

**步骤 6：查看每次 API 调用的成本**

每次工具调用后，`cost-tracker.ps1` 自动记录：

```
[Cost] prompt=45.2K  completion=12.8K  total=58.0K  model=deepseek-v4-flash
```

历史累计统计可从 `~/.iflow/hooks/.cost-history.json` 查看：

```powershell
Get-Content "$env:USERPROFILE\.iflow\.cost-history.json" -Raw | ConvertFrom-Json
```

### 场景：更换模型后自动适配

```powershell
# 假设 settings.json 中 modelName 本为 gpt-4o，现改为 claude-3.5-sonnet

# 1. 更改模型名
# 编辑 ~/.iflow/settings.json，将 modelName 改为 "claude-3.5-sonnet"

# 2. 只运行 patch-iflow（更快，不重新部署 hooks/skills）
.\patch-iflow.ps1
```

输出：

```
Patching iflow.js (v5)...
[OK] Patch v5 already applied!

==> Checking model context limit...
  Detected model: claude-3.5-sonnet
  Recommended tokensLimit: 200000
  Current tokensLimit: 1000000
[OK] Auto-set tokensLimit to 200000 for model 'claude-3.5-sonnet'
```

> `tokensLimit` 自动从 1M 更新为 200K，无需手动干预。

### 场景：手动覆盖 tokensLimit

```powershell
# 通过 API 代理使用模型，实际上下文受代理限制（例如 64K）
.\deploy.ps1 -TokensLimit 64000
```

### 场景：完整卸载

```powershell
.\uninstall.ps1
```

输出：

```
[OK] Restored original iflow.js from backup
[OK] Removed version marker
[OK] Removed hooks directory
[OK] Removed skills directory
[OK] Removed backup directory
[OK] Cleaned up settings.json entries

Done. iflow is restored to original state.
```

## 权限要求

| 路径 | 用途 | 权限 |
|------|------|------|
| `%APPDATA%\npm\node_modules\@iflow-ai\iflow-cli\bundle\` | 修补 `iflow.js` | **管理员** |
| `%USERPROFILE%\.iflow\` | 部署 hooks、skills、更新 settings | 用户权限（通常无需提权） |

> 修补 `iflow.js` 需要**以管理员身份运行 PowerShell**。如无管理员权限，`deploy.ps1` 会自动检测并输出手动操作步骤。

## 详细使用

### 部署

```powershell
.\deploy.ps1
```

脚本会自动：
1. 应用 countTokens 补丁到 `iflow.js`
2. 自动检测模型名并设置正确的 `tokensLimit`（覆盖 20+ 模型系列）
3. 创建 `~/.iflow/hooks/` 和 `~/.iflow/skills/` 目录
4. 复制 hook 脚本和 skill 配置文件
5. 更新 `~/.iflow/settings.json`
6. 备份已有 hooks 和 settings 到 `~/.iflow/.deploy-backup/`（多次部署保留多份历史）

如需手动覆盖 `tokensLimit`：

```powershell
.\deploy.ps1 -TokensLimit 1000000
```

### 卸载

```powershell
.\uninstall.ps1
```

- 从受保护的原始备份 `iflow.js.bak.original` 还原 `iflow.js`
- 清理所有配置、hooks、skills、版本标记
- 清理历史备份目录

### 验证配置

```powershell
cat ~/.iflow/settings.json
```

### 重复部署 / 补丁更新

- **版本一致**：直接跳过，不会重复打补丁
- **补丁更新**：自动检测版本变更 → 从原始备份恢复 → 重新打补丁
- **原始备份** `iflow.js.bak.original` 仅在第一次安装时创建，**永不覆盖**

## 原理

```
┌──────────────────────────────────────────────────────────────┐
│                      iflow-boost (无代理版)                   │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│   ┌──────────────┐    ┌──────────────┐    ┌──────────────┐  │
│   │  patch-iflow │    │    Hooks     │    │    Skills    │
│   │  countTokens │    │  (4 个脚本)  │    │  (6 个 JSON) │
│   │  + 模型检测  │    │              │    │              │
│   └──────┬───────┘    └──────┬───────┘    └──────┬───────┘  │
│          │                    │                    │          │
│          ▼                    ▼                    ▼          │
│   ┌──────────────────────────────────────────────────────┐   │
│   │               iflow CLI 原生功能                       │   │
│   │   ┌─────────────┐ ┌──────────────┐ ┌──────────────┐ │   │
│   │   │ Hooks 系统  │ │ 上下文发现   │ │   压缩器     │ │   │
│   │   └─────────────┘ └──────────────┘ └──────────────┘ │   │
│   └──────────────────────────────────────────────────────┘   │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

## countTokens 补丁详解

### 问题

iFlow 内置的自动压缩依赖 `countTokens` 方法统计上下文 token 数。该方法内部调用 `extractTextFromRequest` 提取文本，但该函数只处理原生格式（Claude API 格式）。使用 OpenAI 兼容 API 时请求体是 Gemini 格式的 `contents` 结构，`extractTextFromRequest` 无法从中提取文本，返回空字符串，导致 `countTokens` 返回 0，压缩流程被跳过。

### 补丁做了什么

补丁包含四个修复：

**1. countTokens 回退解析** — 修改 `countTokens` 方法，在 `extractTextFromRequest` 返回空时，主动遍历 `contents` 结构手动计算 token：

```javascript
// patch 后的核心逻辑
countTokens() {
  let text = extractTextFromRequest(request);
  let tokens = Math.ceil(text.length / 4);

  // fallback: 从 Gemini-format contents 提取
  if (tokens === 0 && request?.contents) {
    for (const content of request.contents) {
      for (const part of content.parts ?? []) {
        if (part.text)  tokens += Math.ceil(part.text.length / 4);
        if (part.functionCall)    tokens += JSON.stringify(part.functionCall).length / 4;
        if (part.functionResponse) tokens += JSON.stringify(part.functionResponse).length / 4;
      }
    }
  }
  return { totalTokens: tokens || 1 };
}
```

**2. 主动压缩（Proactive Compression）** — 在每次发送消息前，主动检查上下文使用率是否超过阈值（80%），超过则提前触发压缩，而不是被动等待 API 返回超长错误。

```
# 补丁前：被动等待 API 报错
sendMessage → API 报 "Content too long" → 触发压缩

# 补丁后：主动检查
sendMessage → 检查上下文 > 80% → 是 → 提前压缩 → 发送
                                    └── 否 → 正常发送
```

**3. 思考模式 content 字段修复** — 修复 `convertToOpenAIMessages` 中组装 assistant 消息时，有 tool_calls 但无文本内容时 content 为 `""`（空字符串）而非 `null` 的问题。OpenAI 规范要求 tool_calls 存在时 content 应为 `null`，某些 API（如 DeepSeek）遇到 `content: ""` + `tool_calls: [...]` 会返回 400 错误。

```javascript
// 补丁前：有 tool_calls 但无文本时 content 留空
{ role: "assistant", content: "", reasoning_content: "...", tool_calls: [...] }
//                                                          ↑ DeepSeek API 可能报 400

// 补丁后：有 tool_calls 且无文本内容时将 content 设为 null
d.tool_calls.length > 0 && h.length === 0 && (d.content = null)
// → { role: "assistant", content: null, reasoning_content: "...", tool_calls: [...] }
```

**4. 模型上下文自动检测** — 每次运行 `patch-iflow.ps1` 或 `deploy.ps1` 时，自动读取 `settings.json` 中的 `modelName`，匹配内置模型表，将 `tokensLimit` 设为目标值。已在同一版本下重新运行也会执行检测，用户更换模型后无需任何手动配置。

### 兼容的 API

| API | 兼容性 |
|-----|--------|
| OpenRouter | ✅ |
| DeepSeek | ✅ |
| Qwen（通义千问） | ✅ |
| Kimi（月之暗面） | ✅ |
| 智谱 AI | ✅ |
| 其他 Gemini 格式兼容 API | ✅ |

## Hooks

利用 iflow 原生 Hooks 系统注入自定义逻辑：

| Hook | 触发时机 | 功能 |
|------|---------|------|
| **SetUpEnvironment** | 会话开始时 | 注入 Git 上下文 + Skills 列表 |
| **SessionStart (compress)** | 压缩触发后 | 生成结构化压缩摘要 |
| **PostToolUse** | 工具调用后 | 记录 API 调用成本 |

### 压缩摘要示例

```text
## Context Summary

### Scope
- Total messages: 45 (User: 15, Assistant: 30)

### Tools Used
- Edit: 12 | Bash: 8 | Read: 5

### Files Referenced
- src/main.ts · src/utils.ts · config.json
```

## 项目结构

```
iflow-boost/
├── deploy.ps1              # 一键部署（补丁 + hooks + skills + 配置）
├── patch-iflow.ps1         # countTokens 补丁 + 模型上下文自动检测（含版本追踪）
├── uninstall.ps1           # 完整卸载
├── hooks/
│   ├── git-context.ps1     # Git 上下文注入
│   ├── skills-inject.ps1   # Skills 注入
│   ├── compress-summary.ps1# 结构化压缩摘要
│   └── cost-tracker.ps1    # 成本追踪
├── skills/
│   ├── debug.json          # 系统化调试辅助
│   ├── remember.json       # 跨会话记忆
│   ├── simplify.json       # 精简输出
│   ├── skillify.json       # 操作→Skill 转换
│   ├── stuck.json          # 卡住恢复
│   └── verify.json         # 代码验证
└── README.md
```

### 运行时产生的文件

```
~/.iflow/
├── .patch-version           # 补丁版本号（v5）
├── .deploy-backup/          # 部署历史备份（含时间戳）
├── settings.json            # iflow 配置
├── hooks/                   # 部署的 hook 脚本
└── skills/                  # 部署的 skill JSON
```

## 配置

部署后 `~/.iflow/settings.json` 如下：

```json
{
  "tokensLimit": 1000000,
  "compressionTokenThreshold": 0.8,
  "contextFileName": ["IFLOW.md", "CLAUDE.md"]
}
```

| 参数 | 说明 | 默认行为 |
|------|------|---------|
| `tokensLimit` | 上下文 token 上限 | **自动检测**：根据模型名查表设置 |
| `compressionTokenThreshold` | 压缩触发阈值（比例） | 0.8（80%） |

> `tokensLimit` 由 `patch-iflow.ps1` 根据 `settings.json` 中的 `modelName` 自动检测。如需手动覆盖，运行 `.\deploy.ps1 -TokensLimit <值>`。

### 自动检测覆盖的模型

| 模型系列 | 匹配模式 | tokensLimit |
|----------|----------|-------------|
| DeepSeek v4 | `deepseek-v4`, `deepseek-chat` | 1,000,000 |
| DeepSeek v3 / R1 | `deepseek-v3`, `deepseek-r1`, `deepseek` | 128,000 |
| Gemini 2.5 / 2.0 / 1.5 | `gemini-2.5`, `gemini-2.0`, `gemini-1.5` | 1,048,576 |
| GPT-4o / GPT-4-turbo | `gpt-4o`, `gpt-4-turbo` | 128,000 |
| GPT-4 | `gpt-4`（不含 4o/turbo） | 8,192 |
| Claude 全系 | `claude`, `sonnet`, `opus`, `haiku` | 200,000 |
| Qwen3-Coder | `qwen3-coder` | 256,000 |
| Qwen3 / Qwen2.5 | `qwen3`, `qwen2.5`, `qwen-max`, `qwen-plus` | 128,000 |
| Kimi K2 | `kimi-k2` | 128,000 |
| Kimi | `kimi`（不含 K2） | 32,768 |
| GLM-4 | `glm-4`, `glm-4v` | 128,000 |
| Yi-Large | `yi-large`, `yi` | 200,000 |
| Minimax | `minimax` | 64,000 |
| Mistral-Large | `mistral-large` | 128,000 |
| Llama 3.1 / 3.2 / 4 | `llama-3.1`, `llama-3.2`, `llama-4` | 128,000 |
| Command R+ | `command-r-plus`, `command-r` | 128,000 |
| Grok 3 | `grok-3` | 1,000,000 |
| 未知模型 | 未匹配任何模式 | 128,000（安全默认值） |

> 如果一张表中未覆盖的模型，自动检测默认设为 128K。你也可以手动指定：`.\deploy.ps1 -TokensLimit <值>`

## 故障排除

| 现象 | 原因 | 解决 |
|------|------|------|
| 提示 `Could not find exact match` | iflow 版本更新，`countTokens` 源码已变 | 重新运行 `.\deploy.ps1`；如仍失败需手动修补 |
| 压缩未触发 | 补丁未生效 | 运行 `.\deploy.ps1` 检查状态 |
| Hooks 未执行 | 文件缺失 / 配置错误 / 执行策略限制 | 检查 `~/.iflow/hooks/` 和 settings.json；运行 `Get-ExecutionPolicy` |
| 补丁版本冲突 | 手动修改过 `iflow.js` 导致版本检测异常 | 运行 `.\uninstall.ps1` 彻底清除后重新部署 |

## 注意事项

- **iflow 更新后补丁会失效**，需要重新运行 `.\deploy.ps1`
- 原始备份文件：`iflow.js.bak.original`（仅首次安装创建，**永不覆盖**）
- 版本标记文件：`~/.iflow/.patch-version`（用于追踪当前补丁版本、安全更新）
- 配置文件备份：每次部署自动备份到 `~/.iflow/.deploy-backup/`
- `tokensLimit` 由脚本根据模型名自动检测，如需覆盖使用 `.\deploy.ps1 -TokensLimit <值>`
- 本工具仅修改 `countTokens` 一个方法和添加主动压缩检查，不改变 iflow 的核心机制

## 免责声明

本项目为非官方社区工具，与 iFlow 官方团队无任何关联。使用本工具修改 `iflow.js` 可能违反 iFlow 的使用条款，且 iFlow 更新后补丁可能失效。使用本工具产生的任何问题（包括但不限于数据丢失、API 费用异常、服务中断），由使用者自行承担。请确保你理解本工具的工作原理后再使用。

## 致谢

- [iFlow CLI](https://github.com/iflow-ai/iflow-cli) — 本工具所修补的原始项目