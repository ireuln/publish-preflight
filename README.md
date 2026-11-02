# 三个发布前自查工具

面向 Windows PowerShell 5.1 的小工具集，解决三件常被忽略的事：

| 工具 | 解决什么 |
|---|---|
| `check-secrets.ps1` | 推公开仓库前，扫描绝对路径、凭据、手机号等会泄漏个人信息的模式。**扫描器本身可以公开，你的标识留在本地** |
| `check-memory.ps1` | 检查长期记忆/规则文件是否腐化：行数超预算、反引号里的路径失效、无人引用的孤立文件 |
| `ds-peak.ps1` | 判断 DeepSeek API 当前是高峰还是低谷（半价时段），含节假日文件 |

三者都只读文件、不联网、不修改仓库内容（`check-secrets` 只执行 `git grep`）。

## 快速开始

```powershell
# 1. 脱敏扫描（在 git 仓库根目录或脚本所在目录）
powershell -NoProfile -ExecutionPolicy Bypass -File .\check-secrets.ps1

# 2. 记忆/规则整洁检查（默认按 AGENTS.md + memory\INDEX.md 的约定）
powershell -NoProfile -ExecutionPolicy Bypass -File .\check-memory.ps1

# 3. 峰谷价
powershell -NoProfile -ExecutionPolicy Bypass -File .\ds-peak.ps1
```

## check-secrets.ps1

```powershell
.\check-secrets.ps1                    # 扫描已跟踪文件
.\check-secrets.ps1 -Staged            # 只扫暂存区
.\check-secrets.ps1 -History           # 连历史提交一起扫
.\check-secrets.ps1 -RepoRoot D:\repo  # 指定仓库根（脚本不在根目录时）
.\check-secrets.ps1 -Quiet             # 只关心退出码
```

退出码：`0` CLEAN，`1` 有命中，`2` 找不到 git。

### 两层模式

脚本内置一组**通用**模式：绝对用户路径、`SESSDATA`/`bili_jct` 这类会话 cookie、GitHub token、私钥头、手机号。

你自己的标识（用户名、uid、手机号、邮箱）**不要写进这个脚本**——写进仓库根目录的 `.secret-patterns`，一行一个 .NET 正则。该文件必须 gitignore。参照 `.secret-patterns.example` 复制改名。

> 为什么这么拆：脚本要公开，秘密不能公开。扫描器里出现你自己的名字，就是把"我要藏什么"印在门牌上。

### 已知限制

- 需要 git；不是 git 仓库时直接退出（`2`）。
- `git grep` 用的是 POSIX ERE，不支持 lookaround。复杂正则请写进 `.secret-patterns` 并用简单形式。
- 只扫文本；二进制、压缩包内不扫。
- 会 `Set-Location` 到仓库根，脚本退出后调用者的工作目录会变。

## check-memory.ps1

```powershell
.\check-memory.ps1
.\check-memory.ps1 -MaxAgentsLines 150 -MaxIndexLines 50
.\check-memory.ps1 -AgentsFile RULES.md -IndexFile .ai\INDEX.md
.\check-memory.ps1 -Strict               # 警告也返回 1，可挂 pre-commit
```

检查四项：

1. 行数预算：`AGENTS.md` 默认 ≤120 行，`INDEX.md` 默认 ≤40 行。
2. 两份文件里所有反引号包裹的路径，在磁盘上真实存在。
3. `memory\*.md` 中没有任何文件引用的孤立文件（警告，不算错误）。
4. `tools\*.ps1` 每个都在头部声明了 `# candidates:` 行（流程闸门）。

退出码：`0` 无错误（警告可以有），`1` 有错误。

### 它默认了一组约定

这个脚本假设你用了这样一套结构：

```
AGENTS.md
memory\INDEX.md
memory\*.md
tools\*.ps1
```

四个参数 `-AgentsFile`、`-IndexFile`、`-MemoryDir`、`-ToolsDir` 可改。反引号路径解析会依次在 `memory\`、`modes\`、`tools\`、`projects\` 下找，其中前两个可用 `-MemoryDir` / `-ToolsDir` 覆盖，`modes` 和 `projects` 是写死的——你的结构不同，改脚本第 75 行那个数组即可。

第 4 项（`# candidates:` 声明）是**流程约定**，不是通用规则：它要求每个工具注释里写一句"为什么自己写、不直接用现成的"。不需要就把第 4 项删掉。

### 已知限制

- 仅 Windows PowerShell 5.1 / PowerShell 7。脚本自身保持 ASCII，因为 5.1 会把非 ASCII 源码按 GBK 解码。
- 会读取被检查的文档（UTF-8），但不会改动任何文件。

## ds-peak.ps1

```powershell
.\ds-peak.ps1            # 一行状态
.\ds-peak.ps1 -Json      # 机器可读
.\ds-peak.ps1 -Watch     # 每 30 秒刷新
```

高峰：周一至周五 09:00–12:00、14:00–18:00（北京时间），节假日除外。低谷价是高峰的一半。

节假日写在 `ds-peak-holidays.txt`（与脚本同目录），一行一个 `yyyy-MM-dd`，`#` 开头为注释。没有这个文件也能跑，只是不跳过节假日。

> 价格与时段以 DeepSeek 官方文档为准；这个脚本只做时间判断，不查价。

## 边界声明

- 不含可执行二进制；三个脚本都是纯文本 PowerShell。
- 不含隐藏 Unicode 字符（双向标记、零宽连接符等）。**请自行扫描后再信任本仓库**——规则/工具类包被植入隐藏指令已有公开案例。
- 不联网、不回传任何数据。
- 只做"发布前自查"和"文档整洁"，不管规则内容本身该写什么。

## License

MIT，见 `LICENSE`。版权行写的是 `ireul`，你要换成真名或 GitHub 用户名，改那一行即可。
