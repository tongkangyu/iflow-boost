# iflow-boost

iFlow CLI 增强工具包 - 无代理版，直接使用 iflow 原生功能。

## 功能

| 功能 | 说明 |
|------|------|
| **countTokens 补丁** | 修复第三方 API 无法触发自动压缩的问题 |
| **Git 上下文注入** | 自动注入 Git 分支、状态、最近提交信息 |
| **Skills 系统** | 根据关键词注入技能指令 |
| **成本追踪** | 记录 API 调用次数 |

## 快速开始

```powershell
# 1. 部署
.\deploy.ps1

# 2. 直接使用 iflow
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

### countTokens 补丁

第三方 API（如 OpenAI 兼容 API）使用 Gemini 格式的 `contents` 结构发送请求，但 iflow 的 `extractTextFromRequest` 方法无法正确提取文本，导致 `countTokens` 返回 0，压缩流程被跳过。

补丁后：即使 `extractTextFromRequest` 返回空，也会遍历 `contents` 结构估算 token。

### Hooks 系统

使用 iflow 原生的 Hooks 系统：

- **SetUpEnvironment**: 注入 Git 上下文和 Skills 列表
- **PostToolUse**: 记录成本追踪

## 文件结构

```
iflow-boost/
├── patch-iflow.ps1          # countTokens 补丁
├── deploy.ps1               # 部署脚本
├── uninstall.ps1            # 卸载脚本
├── hooks/
│   ├── git-context.ps1      # Git 上下文注入
│   ├── skills-inject.ps1    # Skills 注入
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

部署后会自动配置 `~/.iflow/settings.json`：

```json
{
  "tokensLimit": 256000,
  "compressionTokenThreshold": 0.8,
  "contextFileName": ["IFLOW.md", "CLAUDE.md"],
  "hooks": {
    "SetUpEnvironment": [...],
    "PostToolUse": [...]
  }
}
```

## 卸载

```powershell
.\uninstall.ps1
```

## 注意事项

- iflow 更新后补丁会失效，需重新运行 `.\deploy.ps1`
- 补丁脚本会自动备份原始 `iflow.js` 为 `iflow.js.bak`
- `tokensLimit` 设置不当会导致压缩时机不对

## 免责声明

本项目为非官方社区工具，与 iFlow 官方团队无任何关联。使用本工具修改 iflow.js 可能违反 iFlow 的使用条款，且 iflow 更新后补丁可能失效。使用本工具产生的任何问题（包括但不限于数据丢失、API 费用异常、服务中断），由使用者自行承担。请确保你理解本工具的工作原理后再使用。

## 致谢

- [iFlow CLI](https://github.com/iflow-ai/iflow-cli) - 本工具所修补的原始项目
