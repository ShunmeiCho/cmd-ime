<div align="center">
  <img src="Assets/AppIcon.png" alt="CmdIME 应用图标" width="112">
  <h1>CmdIME</h1>
  <p><strong>为多语言输入提供确定性的 macOS 输入源切换。</strong></p>
  <p><a href="README.md">English</a> · <strong>简体中文</strong> · <a href="README.ja.md">日本語</a></p>

  <p>
    <a href="https://github.com/ShunmeiCho/cmd-ime/actions/workflows/swift.yml"><img alt="Swift" src="https://github.com/ShunmeiCho/cmd-ime/actions/workflows/swift.yml/badge.svg"></a>
    <a href="https://github.com/ShunmeiCho/cmd-ime/releases"><img alt="Release" src="https://img.shields.io/github/v/release/ShunmeiCho/cmd-ime"></a>
    <a href="LICENSE"><img alt="License: MIT" src="https://img.shields.io/badge/License-MIT-blue.svg"></a>
  </p>
</div>

CmdIME 是一款 macOS 输入源切换工具，核心是可配置的切换槽位和直达目标的切换方式。
你不需要在多个输入源之间循环切换，只要按下想要的槽位，CmdIME 就会选中与之匹配的
macOS 输入源。

为什么不直接用系统自带的 `Control+Space`？它是循环切换的，输入源达到三个或更多时，
你必须看一眼才知道切到了哪里；不少用户还发现按键偶尔会有延迟，或者看起来没有反应。
CmdIME 给每个输入源分配一个独立的按键，确认 macOS 确实完成了切换（没有完成时会重试），
并在光标附近显示一个小的指示气泡，让你不用看菜单栏也知道当前在用哪个输入法。

## 功能概览

CmdIME 会扫描 macOS 中已经安装的输入源，而不是写死某一种键盘布局。首次设置时，
它为每种主要语言创建一个槽位，并按系统顺序取该语言下第一个可选的输入源。
没有主要语言的输入源会被跳过。每个槽位都可以在它的卡片上指向任意一个已安装的输入源，
显示 "Not matched"（未匹配）的槽位也一样。

设置窗口是一块槽位面板。左侧列出已安装的输入源，右侧是你的槽位：

- 把输入源拖进槽位列表，或者使用 **Add Slot**（添加槽位），即可创建槽位。拖动槽位的
  拖动柄可以调整顺序；按 Esc 取消拖动。"..." 菜单里有 Move Up、Move Down、Rename、
  Color 和 Remove Slot，这些操作同样可以通过键盘和 VoiceOver 完成。被移除的槽位可以用
  **Undo**（撤销）恢复，直到下一次槽位变更为止。
- 点击槽位的徽标可以为它指定一种颜色。输入源列表、Live keys 和切换指示气泡都会跟随
  这个颜色。
- 输入源列表与系统设置保持同步：添加或移除输入源后无需重新启动即可更新，并且始终提供
  一个 Refresh（刷新）按钮。
- "Current"（当前）标记的是 macOS 当前选中的输入源，不论它是通过什么方式选中的。
  **Switch**（切换）会直接选中该槽位的输入源；它不会测试触发键。
- 面板下方的 Live keys（实时按键）是一个小键盘，会点亮绑定到当前槽位的按键。

| 检测到的槽位 | 默认触发键 |
| --- | --- |
| 第一个 | 左 Command |
| 第二个 | 右 Command |
| 第三个 | 左 Option |
| 第四个 | 右 Option |
| 第五个 | 左 Control |
| 第六个及之后 | 无触发键（需手动指定） |

已有的配置及其触发键保持不变。如果没有任何可选输入源具有可用的主要语言，
初始化时会使用旧版默认值：英文对应左 Command，中文对应右 Command，日文对应 **Option+J**。

下面的演示用的是一种可能的设置（左 Command 对应英文，右 Command 对应中文，右 Shift
对应日文）；你的槽位会按你 Mac 上安装的输入源来生成。演示里出现的是 Switcher、Glass 和
Liquid Glass 三种指示气泡主题。

[![CmdIME 演示：一个键对应一个输入源](demo-videos/renders/preview-promo.gif)](demo-videos/renders/cmdime-promo.mp4)

[打开完整的演示视频](demo-videos/renders/cmdime-promo.mp4)

## 分发状态

CmdIME 目前以**未经公证的预览版本**分发。

它不通过 Mac App Store 分发，并且除非某个发布版本明确说明，当前的预览版本没有使用
Developer ID 证书签名。macOS 可能会在首次启动时阻止该应用，或者要求你在系统设置中
手动批准。

在你批准 CmdIME 并授予所需权限之后，它就能正常运行。这种预览分发方式面向技术用户和
早期使用者。

Apple 的 Gatekeeper 文档说明，从 App Store 以外下载的应用会被检查是否由已识别的开发者
签名、是否经过公证以及是否被修改过。对于更大范围的公开分发，Developer ID 签名加公证是
更顺畅的途径：

- [Gatekeeper and runtime protection in macOS](https://support.apple.com/guide/security/gatekeeper-and-runtime-protection-sec5599b66df/web)
- [Signing Mac Software with Developer ID](https://developer.apple.com/developer-id/)

## 安装

### 推荐的预览版安装方式

```sh
curl -fsSL https://raw.githubusercontent.com/ShunmeiCho/cmd-ime/main/script/install.sh | bash
```

安装脚本会解析最新的发布版本，下载 zip，用随发布版本一同公布的 `.sha256` 文件对其进行
校验，把 `CmdIME.app` 安装到 `/Applications`，链接 `keyboardctl`，然后打开应用，
以便 macOS 请求权限。

如果想自己固定确切的版本和校验和（两者都从发布说明中复制）：

```sh
curl -fsSL https://raw.githubusercontent.com/ShunmeiCho/cmd-ime/main/script/install.sh | \
  CMDIME_VERSION=0.7.0 CMDIME_SHA256=76ffc1e46d594179452719eac58923df1020d129307d05296ab594fd44237420 bash
```

安装完成后，打开 CmdIME，并在系统设置 > 隐私与安全性中同时授予 **Accessibility**（辅助功能）
和 **Input Monitoring**（输入监控）权限。

[![CmdIME 安装与权限演示](demo-videos/renders/preview-install-permissions.gif)](demo-videos/renders/cmdime-install-permissions-demo.mp4)

[打开完整的安装与权限演示](demo-videos/renders/cmdime-install-permissions-demo.mp4)

### 从源码构建

```sh
git clone https://github.com/ShunmeiCho/cmd-ime.git
cd cmd-ime
swift test
./script/build_and_run.sh
```

本地构建的应用同样需要 Accessibility 和 Input Monitoring 权限，全局键盘监听才能工作。

## 首次启动与权限

全新安装后，设置窗口顶部会显示一个三步的 **Setup guide**（设置向导）：允许键盘访问、
检查检测到的槽位、然后试着切换一次。它可以跳过，之后通过 **General > Show Setup Guide**
可以再次打开。从早期版本更新的用户看到的则是一行 "New in 0.4" 提示。

CmdIME 需要以下两项 macOS 权限：

- Accessibility
- Input Monitoring

授予权限时请使用一个固定的应用位置。macOS 是针对应用的代码身份保存授权的，
所以如果你批准了某一个重新构建的 `CmdIME.app`，随后又从 `dist/`、`dist/release/` 或
`/Applications` 运行另一份副本，macOS 可能会再次询问。

推荐的权限重置流程：

1. 退出 CmdIME。
2. 在系统设置 > 隐私与安全性 > Accessibility 和 Input Monitoring 中移除旧的
   `CmdIME.app` 条目。
3. 把应用安装或复制到你实际使用的位置，例如
   `/Applications/CmdIME.app`。
4. 打开这一份应用，并授予两项权限。
5. 退出并重新打开 CmdIME。

## Gatekeeper 故障排除

由于当前的预览版本没有经过公证，当你打开通过浏览器下载的 zip 时，macOS 可能会显示
"CmdIME is damaged"（CmdIME 已损坏）或 "Apple cannot check it for malicious software"
（Apple 无法检查其是否包含恶意软件）之类的警告。

如果你信任自己下载的发布版本，请先尝试打开一次 CmdIME，然后前往系统设置 > 隐私与安全性，
选择 **Open Anyway**（仍要打开）。

如有需要，也可以移除浏览器添加的隔离属性：

```sh
xattr -dr com.apple.quarantine /Applications/CmdIME.app
```

条件允许时，请优先使用固定版本的安装脚本方式。这种方式不会经过浏览器的隔离流程。

## 应用行为

CmdIME 是一个后台输入源代理程序。设置窗口只是一个控制面板：关闭窗口不会停止键盘监听。
发布版本打包时带有 `LSUIElement`，因此应用不会出现在 Dock 或应用切换器中。

设置窗口跟随 macOS 的外观。也可以在 **General > Appearance** 里把它固定为 **Light** 或
**Dark**，或者交还给 **System**。窗口建立在系统材质之上，顶部状态条和更新条在 macOS 26
及以上使用 Liquid Glass；开启“减少透明度”时，全部退回不透明。切换指示气泡是另一回事：
它出现在其他应用之上，所以它的主题跟随 macOS 的外观，除非主题自己把色调固定了。

需要打开设置时，再次打开 `CmdIME.app` 即可。要停止后台代理程序，请使用设置窗口顶部
状态栏中的 **General > Quit CmdIME**，或者运行：

```sh
keyboardctl quit
```

如果 CLI 还没有链接，请使用：

```sh
pkill -x CmdIME
```

## 绑定

每个槽位有三种可选的触发方式。你设置的任意一种都会切换到该槽位，它们也可以组合使用
（例如日常用单击，再配一个快捷键作为备用）。其余的留空即可。

- `Single tap`（单击）：从菜单中选择八个物理修饰键之一（左或右的 Command、Option、
  Control、Shift）。
- `Double tap`（双击）：同一个菜单，用于双击。
- `Shortcut`（快捷键）：点击 **Record…**（录制），同时按下一个修饰键和一个按键，例如
  `option+j`，然后点 Save。按 Esc 取消；录制期间单击和双击触发会暂停。

如果某个按键已经被另一个槽位用于同一种手势，或者已被某个按键重映射占用，
它会显示为已占用并且无法选择。同一个按键可以是一个槽位的单击触发键，同时是另一个槽位的
双击触发键。许多中文输入法使用 Shift 来切换中英文，因此 CmdIME 从不自动分配 Shift。

单个修饰键的绑定与键盘快捷键被有意分开处理，这样 `Command+C`、`Command+V`、
`Command+Tab` 等常用快捷键以及多修饰键组合就不会被当成一次 Command 单击。
单击修饰键的绑定会立即切换；只有当同一个修饰键还绑定了 CmdIME 的双击时，
CmdIME 才会短暂等待。

设置界面会拒绝 `control+space` 和 `control+option+space` 这类 macOS 输入源快捷键，
以免 CmdIME 意外抢占系统的输入源选择器。

CmdIME 通过编程方式切换输入源，因此不会调出 macOS 私有的输入源选择器。启用
`Show switch indicator` 后，CmdIME 会在切换后显示自己的轻量确认气泡。在设置中，
切换指示气泡可以关闭，可以选用内置主题之一（Glass（玻璃）、适用于 macOS 26 及以上的
Liquid Glass、使用一种或两种油墨的纸张风格、纯文字、纯色块、单行，或者显示所有槽位的
Switcher（切换器）），可以通过预设和缩放滑块调整大小，可以在图标/文字显示模式之间切换，
还可以按每个槽位自己的颜色、系统强调色或单色来着色。字体族、字重和文字大小属于主题；
编辑内置主题时会生成一份副本。自定义主题以 JSON 文件的形式存放在
`~/.config/cmd-ime/themes`，导入的字体存放在 `~/.config/cmd-ime/fonts`
（两者都在配置文件旁边）；字体只为 CmdIME 注册，不会在系统范围内安装任何内容。
主题文件可以使用任意名称；在设置中移除主题会把它的文件移到废纸篓。

如果切换到日文时打开的是假名面板而不是平假名输入，请刷新输入源，或者更新到
CmdIME 0.1.10 或更高版本。macOS 把 `com.apple.50onPaletteIM` 暴露为一个可选的日文输入源，
但它是辅助用的假名面板，而不是常规的平假名输入法。

### 切换后仍然打出拉丁字母的输入法

从后台选中输入源，有时输入法并没有接到当前应用上：菜单栏显示的是新输入源，打出来的
却还是拉丁字母。Google 日本語入力在你用 ABC 打过字之后就会这样。对它，CmdIME 会先按一下
かな键，通过系统自己的路径进入日文，60 毫秒后再选中槽位指定的输入源。其他输入法仍然是
直接选中，不增加延迟。

如果别的日文输入法出现同样的症状，可以在 `~/.config/cmd-ime/activation-recipes.json`
里加一条激活配方，然后在设置里点 Refresh：

```json
{ "recipes": [
  { "sourceIDPrefix": "com.example.inputmethod", "strategy": "kanaThenSelect", "delayMs": 60 }
] }
```

输入源 ID 可以用 `keyboardctl scan` 查到。你的配方优先于内置配方，所以写
`"strategy": "select"` 可以关掉内置的那一条。`kanaThenSelect` 只对日文输入源生效，
`delayMs` 限制在 0 到 500 之间，读不出来的条目会被跳过，并在状态栏里指出。有效的配方
欢迎提 issue 告诉我们，好把它收进内置列表。

## CLI

槽位 ID 取决于检测到的输入源。下面的示例假设槽位名为
`english`、`chinese` 和 `japanese`；请运行 `keyboardctl slots` 查看你实际的 ID。

```sh
swift run keyboardctl scan
swift run keyboardctl init
swift run keyboardctl slots
swift run keyboardctl slot add
swift run keyboardctl slot add 1 --name Korean
swift run keyboardctl slot remove japanese
swift run keyboardctl switch english
swift run keyboardctl diagnose
swift run keyboardctl diagnose --json
swift run keyboardctl bind left-command english
swift run keyboardctl bind right-command chinese
swift run keyboardctl bind option+j japanese
swift run keyboardctl bind double-left-command english
swift run keyboardctl remap right-control escape
swift run keyboardctl quit
swift run keyboardctl listen
```

- `keyboardctl init`：使用与 GUI 首次启动相同的检测逻辑，创建根据输入源检测得到的默认值。
  已有的配置不会被改动，除非你传入 `--force`，它会用检测到的默认值替换整个配置。
  强制重置之前请备份自定义设置；它不会创建 GUI 的重置前备份（下文的旧版迁移备份
  仍然适用）。
- `keyboardctl switch <slot>`：选中某个槽位匹配到的输入源，并确认 macOS 已经应用了
  这次切换。如果 macOS 没有应用该选择，它会向 `stderr` 输出错误信息并以非零状态退出。
- `keyboardctl diagnose [--json]`：输出每个槽位配置的偏好
  （`preferredIDs`、`languagePrefixes`、`nameContains`）、匹配到的输入源，
  以及匹配原因（`preferredID`、`fallbackLanguage`、`languagePrefix`、`nameContains` 或 `none`）。
  传入 `--json` 可得到结构化的 JSON 输出：`slots` 条目保留 `slot` ID，
  并包含 `name` 和 `duplicateSlots`（没有重复时为空数组）。
- `keyboardctl slots`：按顺序列出槽位 ID、名称、触发键和匹配结果，
  并标出回退匹配。
- `keyboardctl slot add [<number|source-id>] [--name N]`：不带输入源时，
  列出带编号的未分配输入源；带输入源时，添加一个槽位，并从左 Command、右 Command、
  左 Option、右 Option、左 Control 中分配第一个空闲的触发键。全部被占用时，
  该槽位没有触发键；请用 `bind` 指定一个。Shift 从不自动分配，因为许多中文输入源
  使用单击 Shift 来切换中英文。右 Control 也只能手动指定，因为笔记本键盘上没有这个键。
- `keyboardctl slot remove <slot>`：移除它的绑定、偏好和自定义颜色。
  最后一个槽位不能移除。
- 槽位查询先按精确 ID 匹配，然后按唯一的、不区分大小写的 ID 或名称匹配。
  已删除或未知的槽位会以退出码 1 失败；它们绝不会被重定向到别的槽位。
  `bind <trigger> <slot>` 保留抢占触发键的行为，并会在原先的槽位因此失去触发键时给出提示。

新槽位优先使用所选的输入源，并按其**主要**语言回退。
一个输入源不能同时作为两个槽位的首选输入源，但回退规则和旧版规则可能把多个槽位解析到
同一个输入源：两者都仍然可用，`diagnose` 会报告 `duplicate with: <ids>`。
已有的匹配规则保持不变。只有在配置文件不存在时，首次启动才会检测槽位；
刷新输入源不会替换已有的槽位或触发键。

在设置中，**Reset to Detected**（重置为检测结果）会先请求确认，然后才用检测到的默认值
替换所有槽位和触发键。无关的设置会被保留，包括通用的指示气泡偏好。保存之前，
GUI 会把原文件备份为配置文件旁边的 `config.json.before-reset.bak`；
之后的重置会使用各不相同的备份名称，而不是覆盖之前的备份。
如果备份或保存失败，重置不会生效。

用 CLI 编辑配置之前请先退出 GUI，之后再重新打开：运行中的 GUI 不会监视该文件，
可能会覆盖 CLI 所做的更改。

配置文件位于：

```text
~/.config/cmd-ime/config.json
```

### 配置的升级与降级

版本 2 保存一个有序的 `slots` 集合，其中包含稳定的 ID、名称和色调。
旧配置在加载时于内存中迁移。`show`、`slots`、`diagnose`、
`switch` 和 `listen` 不会保存迁移结果，也不会输出升级提示。
每次成功的写入（`bind`、`remap`、`slot add`、`slot remove` 或
`init --force`）都会把缺少 `slots` 的文件备份为同目录下的 `config.json.v1.bak`，
然后向 stderr 输出一条说明。这也涵盖 `slots` 键被旧版二进制丢弃的版本 2 文件。
如果该备份已经存在，则会创建一个新的 `config.json.v1.bak.<uuid>`；
之前的备份绝不会被复用或覆盖。说明中会给出新备份的路径。备份失败会阻止保存。
迁移时会保留旧版 ID 和绑定。

降级之前，请退出 CmdIME，并把最近一次迁移说明中指出的备份恢复为 `config.json`
（请另外保留一份你的版本 2 设置）。多次升级之后，该备份可能带有 UUID 后缀；
最初的 `config.json.v1.bak` 仍然保存着第一次迁移时的设置。旧版二进制无法解码自定义的
槽位 ID，可能会把该配置移到 `.corrupt.<uuid>` 并将其重置。即使只有旧版 ID，
旧版二进制也会在保存时丢弃 `slots`，导致名称/色调丢失，并可能在下次升级时恢复
已被移除的旧版槽位。

## 构建

```sh
swift test
./script/build_and_run.sh
```

用于本地开发时，`script/build_and_run.sh` 会在生成应用包之后对其签名。
它使用能找到的第一个本地 Apple Development 或 Developer ID 签名身份，
找不到时回退到 ad-hoc 签名。你可以设置 `CODESIGN_IDENTITY` 来选择特定的身份：

```sh
CODESIGN_IDENTITY="Apple Development: Your Name (TEAMID)" ./script/build_and_run.sh
```

发布的应用保持原生 SwiftUI/AppKit 实现。React 适合用来做网页原型，
或者将来可选的设置界面，但它无法替代 CmdIME 所依赖的 macOS API：
全局键盘监听、Accessibility/Input Monitoring 权限、登录项以及输入源切换。

通过 Mac App Store 分发需要一个单独的、启用沙盒的 App Store 构建。参见
[docs/app-store.md](docs/app-store.md)。

## 打包与发布

```sh
CMDIME_ALLOW_UNNOTARIZED=1 ./script/package_app.sh 0.7.0
shasum -a 256 dist/CmdIME-0.7.0.zip
```

经过公证的发布打包需要 `Developer ID Application` 签名身份。
如果要打包明确标注为未经公证的预览版，请设置
`CMDIME_ALLOW_UNNOTARIZED=1`。

一次性的公证设置：

```sh
security find-identity -p codesigning -v
xcrun notarytool store-credentials "cmd-ime-notary" \
  --apple-id "YOUR_APPLE_ID" \
  --team-id "YOUR_TEAM_ID" \
  --password "APP_SPECIFIC_PASSWORD"
```

打包脚本会使用 Developer ID 签名，把 zip 提交给 Apple 公证服务，
把票据装订到 `CmdIME.app` 上，重新生成用于分发的 zip，并输出 SHA-256。
如果你的钥匙串配置名称不是 `cmd-ime-notary`，请使用 `CMDIME_NOTARY_PROFILE`。

发布 Homebrew cask 之前，请用发布版 zip 的 SHA-256 更新 `Casks/cmd-ime.rb`。
该 cask 通过 `Contents/Resources` 链接 `keyboardctl`，
这是一个指向 `Contents/MacOS` 中已签名辅助程序的兼容性符号链接。

### 更新

CmdIME 大部分时间没有窗口，所以它会自己检查新版本：默认每六小时向 GitHub 查询一次最新的
Release（除此之外不发送任何内容），发现新版本时，为这个版本发一条系统通知。设置窗口顶部
会显示同一条更新提示，并附上这一版的一句话概括和每项改动的标题，不用打开浏览器就能知道
更新了什么。

**General** 里有用于手动检查的 **Check**、**Check automatically** 开关、
**Every 6 hours / Daily / Weekly** 频率选择，以及 **Notify me about updates**：关掉它就不再
发通知，但窗口里的更新提示照常显示。通知权限只在有更新要通知时、或者你打开这个开关时
申请，首次启动时不会申请。macOS 不允许应用自己修改通知权限：如果通知在系统里被关掉了，
General 会提示，并提供 **Open Notification Settings…** 直达系统设置。

**Update Now** 会原地安装更新：下载发布的 zip，对照发布的 `.sha256` 校验，
验证新应用带有有效的代码签名、并且与正在运行的应用来自同一个开发者团队，
然后替换应用包并重新打开 CmdIME。由于签名身份没有变化，Accessibility 和
Input Monitoring 的授权会保留。**Release Notes** 打开 GitHub 的发布页面，
**Skip** 不再提醒这个版本。如果 CmdIME 是用 Homebrew 安装的，`brew upgrade`
照常可用；原地更新之后，Homebrew 记录的版本号会落后，直到下一次 `brew upgrade`。

## 项目结构

- `Sources/KeyboardSwitcherCore`：配置、快捷键解析、输入源扫描、
  匹配、切换以及全局事件监听（event tap）逻辑
- `Sources/CmdIME`：带有 SwiftUI 设置窗口的 AppKit 后台应用
- `Sources/keyboardctl`：用于扫描、配置、切换和监听模式的 CLI
- `script`：本地运行和发布打包脚本
- `Casks`：Homebrew cask 模板

## 支持

如果 CmdIME 帮你减少了一点键盘上的麻烦，你可以在这里支持本项目：
[buymeacoffee.com/shunmeicor7](https://buymeacoffee.com/shunmeicor7)。

你也可以给仓库点个 star：
[github.com/ShunmeiCho/cmd-ime](https://github.com/ShunmeiCho/cmd-ime)。
