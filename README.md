<div align="center">
  <h1>Mole</h1>
  <p><em>深度清理并优化你的 Mac。</em></p>
</div>

<p align="center">
  <a href="https://github.com/tw93/mole/stargazers"><img src="https://img.shields.io/github/stars/tw93/mole?style=flat-square" alt="Stars"></a>
  <a href="https://github.com/tw93/mole/releases"><img src="https://img.shields.io/github/v/tag/tw93/mole?label=version&style=flat-square" alt="Version"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg?style=flat-square" alt="License"></a>
  <a href="https://github.com/tw93/mole/commits"><img src="https://img.shields.io/github/commit-activity/m/tw93/mole?style=flat-square" alt="Commits"></a>
  <a href="https://twitter.com/HiTw93"><img src="https://img.shields.io/badge/follow-Tw93-red?style=flat-square&logo=Twitter" alt="Twitter"></a>
  <a href="https://t.me/+GclQS9ZnxyI2ODQ1"><img src="https://img.shields.io/badge/chat-Telegram-blueviolet?style=flat-square&logo=Telegram" alt="Telegram"></a>
</p>

<p align="center">
  <img src="https://gw.alipayobjects.com/zos/k/ro/ZzF8e8.png" alt="Mole - 释放 95.50GB" width="1000" />
</p>

## 功能特点

- **一体化工具包**：在一个**单一二进制文件**中集成了 CleanMyMac、AppCleaner、DaisyDisk 和 iStat Menus 的功能
- **深度清理**：清除缓存、日志、浏览器残留和孤立的应用程序数据，**回收数 GB 的磁盘空间**
- **智能卸载**：卸载应用程序的同时移除启动代理、偏好设置和**隐藏残留文件**
- **磁盘洞察**：可视化磁盘使用情况，查找大文件，**重建缓存**并刷新系统服务
- **实时监控**：显示实时的 CPU、GPU、内存、磁盘和网络状态

## 快速开始

**通过脚本安装**

```bash
# 可选参数：-s latest 使用主分支代码，-s 1.17.0 使用特定版本
curl -fsSL https://raw.githubusercontent.com/smryyyyy/Mole-cn/main/install.sh | bash
```

> 注意：Mole 专为 macOS 构建。实验性的 Windows 版本可在 [windows 分支](https://github.com/tw93/Mole/tree/windows) 获取，供早期体验者使用。

**运行**

```bash
mo                           # 交互式菜单
mo clean                     # 深度清理 + 已卸载应用的残留文件
mo uninstall                 # 卸载已安装的应用及其残留文件
mo optimize                  # 刷新缓存和服务
mo analyze                   # 可视化磁盘浏览器（也可用 'mo analyse'）
mo status                    # 实时系统健康仪表板
mo check                     # 运行系统诊断（别名：mo doctor）
mo purge                     # 清理项目构建产物
mo installer                 # 查找并移除安装程序文件

mo touchid                   # 配置 Touch ID 用于 sudo
mo completion                # 设置 Shell 标签补全
mo update                    # 更新 Mole
mo update --nightly          # 更新至最新的未发布主版本（仅限脚本安装）
mo remove                    # 从系统中移除 Mole
mo --help                    # 显示帮助
mo --version                 # 显示已安装版本
```

**安全预览**

```bash
mo clean --dry-run
mo uninstall --dry-run
mo purge --dry-run

# 也适用于：optimize, installer, remove, completion, touchid enable
mo clean --dry-run --debug   # 预览 + 详细日志
mo optimize --whitelist      # 管理受保护的优化规则
mo clean --whitelist         # 管理受保护的缓存
mo purge --paths             # 配置项目扫描目录
mo analyze /Volumes          # 仅分析外部驱动器
```

## 安全与防护设计

Mole 是一个本地系统维护工具，部分命令可能会执行具有破坏性的本地操作。

Mole 采用安全优先的默认设置：路径验证、受保护目录规则、保守的清理边界，以及高风险操作的明确确认。当风险或不确定性较高时，Mole 会选择跳过、拒绝或要求更强的确认，而非扩大删除范围。

`mo analyze` 更适合临时清理，因为它通过 Finder 将文件移动到废纸篓，而非直接删除。

请查阅 [SECURITY.md](SECURITY.md) 和 [SECURITY_AUDIT.md](SECURITY_AUDIT.md) 了解报告指南、安全边界和当前限制。

## 小贴士

- 视频教程：观看 [Mole 教程视频](https://www.youtube.com/watch?v=UEe9-w4CcQ0)，感谢 PAPAYA 電腦教室。
- 安全与日志：`clean`、`uninstall`、`purge`、`installer` 和 `remove` 是破坏性操作。先用 `--dry-run` 预览，需要时加上 `--debug`。文件操作记录在 `~/Library/Logs/mole/operations.log`。可通过 `MO_NO_OPLOG=1` 禁用。请查阅 [SECURITY.md](SECURITY.md) 和 [SECURITY_AUDIT.md](SECURITY_AUDIT.md)。
- 应用残留：应用已卸载时使用 `mo clean`，应用仍安装时使用 `mo uninstall`。
- 导航：Mole 支持方向键和 Vim 键位绑定 `h/j/k/l`。

## 功能详解

### 深度系统清理

```bash
$ mo clean

Scanning cache directories...

  ✓ User app cache                                           45.2GB
  ✓ Browser cache (Chrome, Safari, Firefox)                  10.5GB
  ✓ Developer tools (Xcode, Node.js, npm)                    23.3GB
  ✓ System logs and temp files                                3.8GB
  ✓ App-specific cache (Spotify, Dropbox, Slack)              8.4GB
  ✓ Trash                                                    12.3GB

====================================================================
Space freed: 95.5GB | Free space now: 223.5GB
====================================================================
```


注意：在 `mo clean` -> 开发者工具中，Mole 会移除未使用的 CoreSimulator `Volumes/Cryptex` 条目，并跳过 `IN_USE`（使用中）的项目。

### 智能应用卸载

```bash
$ mo uninstall

Select Apps to Remove
═══════════════════════════
▶ ☑ Photoshop 2024            (4.2G) | Old
  ☐ IntelliJ IDEA             (2.8G) | Recent
  ☐ Premiere Pro              (3.4G) | Recent

Uninstalling: Photoshop 2024

  ✓ Removed application
  ✓ Cleaned 52 related files across 12 locations
    - Application Support, Caches, Preferences
    - Logs, WebKit storage, Cookies
    - Extensions, Plugins, Launch daemons

Note: On macOS 15 and later, Local Network permission entries can outlive app removal. Mole warns when an uninstalled app declares Local Network usage, but it does not auto-reset `/Volumes/Data/Library/Preferences/com.apple.networkextension*.plist` because that reset is global and requires Recovery mode.

====================================================================
Space freed: 12.8GB
====================================================================
```

### 系统优化

```bash
$ mo optimize

System: 5/32 GB RAM | 333/460 GB Disk (72%) | Uptime 6d

  ✓ Rebuild system databases and clear caches
  ✓ Reset network services
  ✓ Refresh Finder and Dock
  ✓ Clean diagnostic and crash logs
  ✓ Remove swap files and restart dynamic pager
  ✓ Rebuild launch services and spotlight index

====================================================================
System optimization completed
====================================================================

Use `mo optimize --whitelist` to exclude specific optimizations.
```

### 磁盘空间分析器

> 注意：默认情况下，Mole 会跳过 `/Volumes` 下的外部驱动器以加快启动速度。要检查它们，请运行 `mo analyze /Volumes` 或指定挂载路径。

```bash
$ mo analyze

Analyze Disk  ~/Documents  |  Total: 156.8GB

 ▶  1. ███████████████████  48.2%  |  📁 Library                     75.4GB  >6mo
    2. ██████████░░░░░░░░░  22.1%  |  📁 Downloads                   34.6GB
    3. ████░░░░░░░░░░░░░░░  14.3%  |  📁 Movies                      22.4GB
    4. ███░░░░░░░░░░░░░░░░  10.8%  |  📁 Documents                   16.9GB
    5. ██░░░░░░░░░░░░░░░░░   5.2%  |  📄 backup_2023.zip              8.2GB

  ↑↓←→ Navigate  |  O Open  |  F Show  |  ⌫ Delete  |  L Large files  |  Q Quit
```


### 实时系统状态

实时仪表板，显示健康评分、硬件信息和性能指标。

```bash
$ mo status

Mole Status  Health ● 92  MacBook Pro · M4 Pro · 32GB · macOS 14.5

⚙ CPU                                    ▦ Memory
Total   ████████████░░░░░░░  45.2%       Used    ███████████░░░░░░░  58.4%
Load    0.82 / 1.05 / 1.23 (8 cores)     Total   14.2 / 24.0 GB
Core 1  ███████████████░░░░  78.3%       Free    ████████░░░░░░░░░░  41.6%
Core 2  ████████████░░░░░░░  62.1%       Avail   9.8 GB

▤ Disk                                   ⚡ Power
Used    █████████████░░░░░░  67.2%       Level   ██████████████████  100%
Free    156.3 GB                         Status  Charged
Read    ▮▯▯▯▯  2.1 MB/s                  Health  Normal · 423 cycles
Write   ▮▮▮▯▯  18.3 MB/s                 Temp    58°C · 1200 RPM

⇅ Network                                ▶ Processes
Down    ▁▁█▂▁▁▁▁▁▁▁▁▇▆▅▂  0.54 MB/s      Code       ▮▮▮▮▯  42.1%
Up      ▄▄▄▃▃▃▄▆▆▇█▁▁▁▁▁  0.02 MB/s      Chrome     ▮▮▮▯▯  28.3%
Proxy   HTTP · 192.168.1.100             Terminal   ▮▯▯▯▯  12.5%
```

健康评分基于 CPU、内存、磁盘、温度和 I/O 负载，并配有颜色编码范围。

快捷键：在 `mo status` 中，按 `k` 切换猫咪显示并保存偏好，按 `q` 退出。

启用后，`mo status` 会对持续超过配置的 CPU 阈值的进程显示只读警告横幅。使用 `--proc-cpu-threshold`、`--proc-cpu-window` 或 `--proc-cpu-alerts=false` 进行调整或禁用。

#### 机器可读输出

`mo analyze` 和 `mo status` 都支持 `--json` 参数，适用于脚本和自动化。

`mo status` 还会自动检测输出是否被管道传输（非终端），并自动切换为 JSON 格式。

```bash
# 磁盘分析输出为 JSON
$ mo analyze --json ~/Documents
{
  "path": "/Users/you/Documents",
  "overview": false,
  "entries": [
    { "name": "Library", "path": "...", "size": 80939438080, "is_dir": true },
    ...
  ],
  "large_files": [
    { "name": "backup.zip", "path": "...", "size": 8796093022 }
  ],
  "total_size": 168393441280,
  "total_files": 42187
}

# 系统状态输出为 JSON
$ mo status --json
{
  "host": "MacBook-Pro",
  "health_score": 92,
  "cpu": { "usage": 45.2, "logical_cpu": 8, ... },
  "memory": { "total": 25769803776, "used": 15049334784, "used_percent": 58.4 },
  "disks": [ ... ],
  "uptime": "3d 12h 45m",
  ...
}

# 管道传输时自动检测为 JSON
$ mo status | jq '.health_score'
92
```

### 项目构建产物清理

清理旧的构建产物，如 `node_modules`、`target`、`.build`、`build` 和 `dist`，以释放磁盘空间。

```bash
mo purge

Select Categories to Clean - 18.5GB (8 selected)

➤ ● my-react-app       3.2GB | node_modules
  ● old-project        2.8GB | node_modules
  ● rust-app           4.1GB | target
  ● next-blog          1.9GB | node_modules
  ○ current-work       856MB | node_modules  | Recent
  ● django-api         2.3GB | venv
  ● vue-dashboard      1.7GB | node_modules
  ● backend-service    2.5GB | node_modules
```

> 注意：建议在 macOS 上安装 `fd`。
> `brew install fd`

> 安全提示：此操作会永久删除选中的产物。确认前请仔细检查。7 天以内的项目会被标记且默认不选中。

<details>
<summary><strong>自定义扫描路径</strong></summary>

运行 `mo purge --paths` 配置扫描目录，或直接编辑 `~/.config/mole/purge_paths`：

```shell
~/Documents/MyProjects
~/Work/ClientA
~/Work/ClientB
```

配置自定义路径后，Mole 仅扫描这些目录。否则，它会使用默认目录，如 `~/Projects`、`~/GitHub` 和 `~/dev`。

</details>

### 安装程序清理

在 Downloads、Desktop、Homebrew 缓存、iCloud 和邮件中查找并移除大型安装程序文件。每个文件都会标注来源。

```bash
mo installer

Select Installers to Remove - 3.8GB (5 selected)

➤ ● Photoshop_2024.dmg     1.2GB | Downloads
  ● IntelliJ_IDEA.dmg       850.6MB | Downloads
  ● Illustrator_Setup.pkg   920.4MB | Downloads
  ● PyCharm_Pro.dmg         640.5MB | Homebrew
  ● Acrobat_Reader.dmg      220.4MB | Downloads
  ○ AppCode_Legacy.zip      410.6MB | Downloads
```

## 快速启动器

从 Raycast 或 Alfred 启动 Mole 命令：

```bash
curl -fsSL https://raw.githubusercontent.com/tw93/Mole/main/scripts/setup-quick-launchers.sh | bash
```

添加 5 个命令：`Mole Clean`、`Mole Uninstall`、`Mole Optimize`、`Mole Analyze`、`Mole Status`。

### Raycast 设置

运行脚本后，在 Raycast 中完成以下步骤：

1. 打开 Raycast 设置 (⌘ + ,)
2. 进入 **Extensions** → **Script Commands**
3. 点击 **"Add Script Directory"**（或 **"+"**）
4. 添加路径：`~/Library/Application Support/Raycast/script-commands`
5. 在 Raycast 中搜索：**"Reload Script Directories"** 并运行
6. 完成！搜索 `Mole Clean` 或 `clean`、`Mole Optimize` 或 `Mole Status` 即可使用这些命令

> **注意**：脚本会创建命令，但 Raycast 仍需要一次性手动设置脚本目录。

### 终端检测

Mole 会自动检测你的终端应用。iTerm2 存在已知的兼容性问题。我们强烈推荐 [Kaku](https://github.com/tw93/Kaku)。其他不错的选择有 Alacritty、kitty、WezTerm、Ghostty 和 Warp。如需覆盖，设置 `MO_LAUNCHER_APP=<名称>`。

## 社区喜爱

感谢所有帮助构建 Mole 的人。去关注他们吧。❤️

<a href="https://github.com/tw93/Mole/graphs/contributors">
  <img src="./CONTRIBUTORS.svg?v=2" width="1000" />
</a>

<br/><br/>
来自在 X 上分享 Mole 的真实用户反馈。

<img src="https://gw.alipayobjects.com/zos/k/dl/lovemole.jpeg" alt="Mole 社区反馈" width="1000" />

## 支持

- 如果 Mole 对你有帮助，请与朋友[分享](https://twitter.com/intent/tweet?url=https://github.com/tw93/Mole&text=Mole%20-%20Deep%20clean%20and%20optimize%20your%20Mac.)或给它点个星。
- 有想法或发现了 Bug？打开 Issue 或 PR，欢迎贡献你最好的 AI 模型。
- 我有两只猫，汤圆和可乐。如果你觉得 Mole 让你的生活更美好，可以给它们喂点<a href="https://cats.tw93.fun?name=Mole" target="_blank">罐头 🥩</a>。

<a href="https://cats.tw93.fun?name=Mole"><img src="https://cdn.jsdelivr.net/gh/tw93/sponsors@main/assets/sponsors.svg" width="1000" loading="lazy" /></a>

## 许可证

MIT 许可证。请随意使用 Mole 并做出贡献。
