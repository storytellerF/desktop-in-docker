# 开发与验证

需要 Python 3.10+，不需要第三方 Python 依赖。真实镜像构建和运行还需要 Docker、Docker Compose，发布需要可用的 buildx builder 和 `docker login`。

## 离线测试

从仓库根目录运行（Linux/macOS 可使用 `python3`）：

```bash
python -m unittest discover -s tests -v
```

仅运行一个独立用例：

```bash
python -m unittest discover -s tests -v -k test_build_x11_debian_xfce_cn
```

`tests/test_build_image.py` 调用真实 Python 构建入口，每次 Docker 调用由独立的 `tests/fakes/docker.py` 子进程处理。每个测试用例拥有唯一临时目录、模板副本、生成文件和 JSON Lines 日志，退出后仅清理自己的目录。环境配置通过副本传入，不修改进程环境或仓库 `.env`。矩阵中的每个组合都作为独立测试发现、执行和报告。

覆盖内容包括：

- X11 的 31 个可用系统/桌面组合 × 2 种镜像源模式，另验证 Alpine/MATE 被拒绝。
- Webtop 的 14 个可用系统/桌面组合 × 2 种镜像源模式；其余 26 个组合在两种镜像源模式下均验证在调用 Docker 和生成 Dockerfile 前拒绝。
- Wayland 的 Arch/Weston × 2 种镜像源模式。
- 非法系统、桌面、版本及变体在调用 Docker 前拒绝。
- Dockerfile 合并、基础镜像引用、标签、配置优先级和 `.env` 更新。
- 三类镜像的发布和 Compose 启动、停止、端口查询，以及 Docker 失败状态传播。
- 并行准备 Alpine Webtop KDE 与 Debian Webtop KDE/MATE 时，每个构建拥有独立文件且不会丢失桌面专用配置；纯停止操作不受不支持的桌面组合影响，启动与构建仍执行完整校验。

fake Docker 按 JSON 数组记录原始参数，另记录用于 Compose 的非敏感配置，不记录密码。失败路径使用 `FAKE_DOCKER_FAIL_COMMANDS`（如 `build`、`buildx-build`、`compose-up`、`compose-down`、`compose-port`）和 `FAKE_DOCKER_FAIL_EXIT_CODE` 控制；这些变量仅供测试替身使用。

离线测试不验证 Dockerfile 的包安装、真实 buildx 发布或桌面容器运行。涉及这些行为的修改应另外执行实际构建并连接桌面验证；构建和运行方式见 [README.md](README.md)。

Alpine 容器启动后，可将 `tests/verify_alpine_runtime.py` 复制进容器，以桌面用户执行 `python3 verify_alpine_runtime.py --desktop cinnamon`（Webtop 另加 `--variant webtop`）。这组 Python 测试读取实际桌面进程，检查会话 D-Bus、继承的文件描述符上限和已安装的运行依赖；Cinnamon 会实际加载 PolkitAgent、Python XApp 并查询 GNOME schemas。它不能替代桌面画面、应用启动和键盘输入检查。

## 构建实现

`scripts/build_image.py` 是配置解析、模板合并、标签和 Docker 调用的唯一实现。`scripts/build-image.sh` 仅转发旧命令，不承载构建逻辑。`-P` 直接为基础层和桌面层执行 buildx 推送（Webtop 只有一层）；`-m` 为兼容参数，发布始终针对 `linux/amd64,linux/arm64`。

维护 `docker/dockerfiles/` 下的模板和 `.dockerfrag` 片段；不要手工维护 `build/x11/`、`build/wayland/`、`build/webtop/` 中的生成文件。每次构建使用唯一子目录，生成文件保留用于诊断；其他构建不会覆盖它。注入片段必须出现在 `__INJECT_BEFORE_DEPS__` 标记之后、原始依赖安装之前；缺失模板或标记会在 Docker 调用前失败。

优先通过 `docker/config/packages/` 的包管理器配置排除独立屏保，不屏蔽桌面应用、主题或电源管理依赖。Alpine 的 LXQt 元包直接依赖屏保，`docker/build/screensaver-packages.py` 从仓库读取元包依赖，只安装非屏保组件。构建结束时还会用 `remove-optional-screensavers.py` 清理父镜像继承的可选屏保，先检查依赖，不强制删除、不自动清理其他包；Alpine 清理元包前先保留其他桌面组件。Fedora 的 LXQt 面板强制依赖 `xscreensaver-base`，且运行验证确认其快捷键仍能触发锁屏，因此保留包，移除自动启动项并关闭守护程序执行权限。

独立屏保之外，X11 服务器也有空闲遮屏定时器。`start-vnc.sh` 在 TigerVNC 原生配置中写入 `s=0`，不依赖桌面额外安装 `xset`。Webtop 的部分上游桌面仍保留十分钟定时器，通过 XDG 会话启动项调用已有 X11 库关闭它。运行测试直接查询 X11 定时器，确认实际值为零。

Cinnamon 的屏保属于强制依赖，保留包并通过 `cinnamon-no-lock.dockerfrag` 禁用会话和 D-Bus 激活。`start-cinnamon-unlocked.sh` 在会话 D-Bus 内关闭自动锁屏并清空相关快捷键，覆盖已有用户目录中的旧设置。只有包策略无法消除的运行时锁屏才增加桌面专项处理。在运行中的容器内，以桌面用户执行 `python3 verify_desktop_locking.py --desktop mate`（先复制 `tests/verify_desktop_locking.py`），检查屏保激活入口并通过 XTest 发送真实 `Ctrl+Alt+L`、`Super+L` 和屏保硬件键；Cinnamon 对应 `--desktop cinnamon`。虚拟键盘没有硬件键映射时，仅跳过该按键用例。

Enlightenment 的锁屏集成在桌面中，运行验证确认其快捷键仍可触发锁屏。`enlightenment-no-lock.py` 使用已有 Eet 库修改原生配置，关闭自动激活并移除锁屏动作；个人密码模式不设置密码，使手动请求在锁屏前退出。构建时处理系统配置，启动时处理已有用户配置，其他偏好和文件权限保持不变。保留原生锁屏模块，避免卸载模块后留下无法退出的黑屏。

X11 KDE 在排除独立屏保后仍能通过 Super+L 启动集成锁屏。`kde-no-lock.dockerfrag` 追加原生 Kiosk 配置，禁止 `action/lock_screen` 并关闭自动、恢复和启动锁屏；不可变配置项覆盖已有用户目录中的旧值，不改变其他桌面偏好。[KScreenLocker 使用该动作权限检查快捷键和 D-Bus 入口](https://github.com/KDE/kscreenlocker/blob/master/interface.cpp)。`verify_desktop_locking.py --desktop kde` 通过 KDE 原生配置读取器、旧用户配置、D-Bus 和真实快捷键验证策略。Webtop KDE 的上游配置已关闭该入口，不重复增加专项配置。

Fedora XFCE 的电源管理器在启动时会恢复十分钟 X11 遮屏定时器。该组合通过 `start-xfce-unblanked.sh` 在会话 D-Bus 中将外接电源和电池的原生 `blank-on-*` 配置设为零，再启动桌面；保留电源管理器和其他偏好。其他 XFCE 组合实测不会恢复此定时器，不增加相同处理。

MATE 移除屏保后仍保留原生 Ctrl+Alt+L 绑定和锁屏菜单权限。`start-mate-unlocked.sh` 在会话 D-Bus 中关闭该权限并清空屏保快捷键，覆盖已有用户配置；不修改 Marco 的其他自定义命令。运行回归直接检查绑定、权限及实际按键后的桌面行为。

Alpine + MATE 已在 X11、Webtop 入口统一禁用。X11 组合测试中观察到 Xvnc 崩溃，导致桌面会话丢失。当前通过禁用组合收敛支持范围，未引入 Xvnc 源码编译或二进制修补。参数验证必须在生成 Dockerfile 或调用 Docker 前拒绝构建、发布、启动及组合重启；纯停止继续绕过桌面组合验证，允许清理既有容器。测试同步维护独立的 92 项可用矩阵和禁用组合的 CLI、环境变量、版本及停止回归。恢复支持前，须验证崩溃问题已修复，并同步更新白名单、支持说明和独立测试矩阵。

新增 Webtop 组合前，先确认上游标签存在，再同步 `WEBTOP_DESKTOPS`、测试中独立维护的期望表和 README 支持表。测试期望不应直接导入生产白名单，否则无法发现误开放不支持组合的回归。

配置按命令行参数 > `.env` > 进程环境变量 > 默认值解析。`.env` 仅接受字面赋值，不再作为 Shell 脚本执行。单、双引号值均支持闭合引号后的行尾注释，引号内的 `#` 保留为值；双引号内识别常见转义（如 `\n`、`\t`、`\"`、`\\`），其他反斜杠（如 `\q`）按字面保留，单引号内的内容均按字面保留。未闭合的引号或闭合引号后的非注释内容会报告行号。

Docker 通过参数数组执行，启动和构建失败返回非零状态；Compose 启动成功但端口查询失败时报告缺失映射，不将其误报为启动失败。

构建入口不自动清理 Docker 镜像，以避免影响共享主机上的其他工作。需要清理时，应只删除自己创建且不再使用的资源。

桌面元包及其推荐依赖共同提供默认主题、应用和渲染插件。不要通过 APT 负优先级禁用桌面元包的必需依赖（如 `upower` 或 `lxqt-powermanagement`），否则安装会直接失败。Alpine 的 LXQt 元包不包含完整图标主题，需额外安装 Papirus 并在用户配置中选择它。容器中无法工作的登录会话认证和锁屏组件应通过会话自动启动配置禁用，而不是破坏包依赖。

GNOME 的 X11 会话需要可用的容器内系统 D-Bus。非 systemd 容器不应保留软件包安装时创建的空 `/run/systemd/seats` 目录，否则 GNOME Shell 会误用 logind 路径并退出；仅移除构建阶段的空目录，不修改 GNOME 程序。VNC 使用独立的 `gnome-vnc` 会话配置，排除依赖 logind 的电源控制必需组件，并关闭它的用户自动启动。

VNC 配置以 `~/.config/tigervnc` 为主目录。启动脚本仅在旧目录不存在时创建 `~/.vnc` 兼容链接，使 Ubuntu noble 的 TigerVNC 1.13 能读取同一份配置、密码和会话脚本；保留已有的用户目录或链接。

Alpine 的 TigerVNC 使用 Xsession 桌面条目，不直接读取项目的 `xstartup`。基础镜像注册 `desktop-in-docker.desktop`，VNC 配置明确选择该会话，由 `start-desktop-session.sh` 执行当前用户的 `~/.config/tigervnc/xstartup`，以应用各桌面的 D-Bus、运行时目录等设置。不要依赖 `/usr/share/xsessions` 中第一个发行版默认会话；这会绕过模板配置。启动桥接脚本的 POSIX 测试同时验证用户目录选择和退出状态传播。

edge 镜像的仓库别名通过单独片段归一为 Alpine 官方完整 CDN 路径，再注入国内镜像配置；稳定分支不改写。国内镜像初始化的 APK 安装或证书更新失败必须让构建失败，不能用 `|| true` 隐藏后再报 Bash 缺失。APK 3 不接受虚拟包依赖列表中的仓库标签，Enlightenment 的 `efl-dev@testing` 单独安装为带标签的顶层构建依赖，并在构建后显式移除。

Fedora 的 KDE 桌面组默认安装 Wayland 会话，VNC 镜像必须额外安装 `plasma-workspace-x11` 和 `kwin-x11`，否则 `startplasma-x11` 不存在。

Alpine 的默认 X11 版本由 `ALPINE_X11_VERSIONS` 按桌面选择；显式 `-v` 和 `SYSTEM_VERSION` 保持优先。GNOME 使用 3.22 的 GNOME/Mutter 48，移除了已下架的可选 `gnome-apps-extra`，按实际需要安装终端和文件管理器。KDE 使用 3.21，并显式安装、检查 X11 会话；[Alpine 3.24 的打包脚本](https://gitlab.alpinelinux.org/alpine/aports/-/blob/3.24-stable/community/plasma-workspace/APKBUILD)会删除 `startplasma-x11`，不能仅安装 `plasma-workspace` 就认为 VNC 会话存在。

Cinnamon 与 Enlightenment 使用完整 edge 基础镜像；从该基础镜像当前的 community 镜像地址派生带标签的 testing 地址，保留国内镜像选择，不向 stable 镜像混入 edge 的 ABI。Cinnamon 还需要 cinnamon-session、设置服务、控制中心，以及未被上游包依赖完整声明的 `gsettings-desktop-schemas`、`polkit`、`networkmanager`、`accountsservice`、`py3-cairo` 和 `py3-xapp@testing`；缺失时 Shell、Nemo 或屏保会直接退出。Enlightenment 的 EFL 与 Terminology 从 testing 安装，桌面本体从 [0.27.1 上游发布源码](https://www.enlightenment.org/download)构建；`docker/build/build-alpine-enlightenment.sh` 使用 Debian 保存的相同原始归档，并核对签名源包描述中的 SHA256。移除编译依赖时也使用 `apk del --no-cache` 加载仓库索引，否则 APK 3 会因现存的带标签 world 依赖找不到仓库标签而拒绝提交。

Alpine 当前没有 LXPanel、lxde-common 软件包。`docker/build/build-alpine-lxde.sh` 固定构建上游 LXPanel 0.11.1（GTK3）和 lxde-common 0.99.2，校验源码 SHA512，再链接当前 Alpine 自己的 libfm、libwnck3 和 keybinder3。不要改装 LXQt 来掩盖 LXDE 缺失；测试必须确认实际的 LXSession、面板、Openbox 及文件桌面均可工作。临时编译依赖在安装完成后移除，运行时依赖由 Dockerfile 明确保留。

Cinnamon 的新版键盘管理器还需要 `ibus`；AccountsService 的类型库与共享库分包，需显式安装 `libaccountsservice`。GI 导入本身可能仅给出警告并返回 `void` 类型，因此容器回归测试还检查实际 GType，避免把应用菜单加载失败误判为通过。

源码安装的 Enlightenment 不在 APK 的依赖图中，清理编译依赖后要显式安装 `libexif`、`libpulse` 和 `polkit`。保留默认桌面配置会加载的 Polkit 模块，不能在编译时禁用它却保留配置；运行测试检查所有模块缺失的共享库。上游 0.27.1 的 `--version` 会打印版本后返回 11，回归测试同时核对版本输出和这个已核实的退出状态。

Alpine KDE 需补齐 `breeze`（含默认 Next 壁纸）、`breeze-icons`、`kglobalacceld`、`kquickcharts`、`kpipewire` 和 `plasma-pa`；仅安装工作区不保证默认主题、通知与音量模块完整。会话还需运行系统 D-Bus，容器回归测试核对实际依赖、默认壁纸和 D-Bus，而画面检查继续核对面板及应用是否正常。

Alpine X11 和 Alpine Webtop KDE 的会话会加载共用的 `base-scripts/session-process-limits.sh`，将超过 65536 的硬文件描述符上限降至 65536，并保留更低的已有上限。在 Docker 默认硬上限超过十亿的环境中，musl 上的旧 D-Bus、Qt 子进程关闭描述符回退路径会逐个调用 `fcntl`，使父进程一直阻塞在 `vfork`，最终表现为桌面无法启动或黑屏。该修复仅影响桌面会话，不更改宿主机资源限制，不强制软件渲染，也不移除上游输入拦截库。POSIX 回归测试在独立子进程中设置高/低上限并验证实际 Shell 行为；Windows 跳过这些容器内会话测试。

Ubuntu MATE 使用 Debian 回退模板时，还需为 Ubuntu 的默认面板布局安装 `mate-indicator-applet`、`dconf-cli` 及 Ayatana 的应用和时间指示器，避免缺失插件错误及空的指示器区域。Ubuntu 的 Ayatana 时间指示器还需要容器内系统 D-Bus，会话启动时检查并在缺失时启动它。

Fedora XFCE 的 `xfce-polkit` 依赖可识别的登录会话；VNC 容器通过用户自动启动覆盖禁用它，避免认证代理启动错误弹窗。

Fedora Cinnamon 的 VNC 会话需明确导出 X11 会话类型及 Cinnamon 桌面标识，避免 Muffin 因未知会话类型退出、仅剩 Nemo 文件桌面。

Fedora Cinnamon 的输入法由会话内的原生 IMSettings 启动，不再同时保留 Supervisor 的 Fcitx 启动项，避免两个进程争用同一输入法实例，以及 X11 尚未就绪时提前启动。

Fedora 41 的 GNOME 组 ID 是 `gnome-desktop`，VNC 还需显式安装 `gnome-session-xsession`；不要把组名写成不存在的 `gnome-desktop-environment`。其 Mutter 也要求明确的 `XDG_SESSION_TYPE=x11`；启动脚本设置 GNOME 会话标识，并在没有运行时目录时使用权限为 0700 的用户目录。

Fedora 41 和 Ubuntu noble 的 Enlightenment 0.26 在容器中看到 `/proc/acpi` 时要求原生 acpid。Fedora 镜像显式安装该服务，Ubuntu 的桌面推荐依赖包含它；对应会话在其真实套接字不存在时启动它，避免 ACPI 错误弹窗；不伪造套接字或修改桌面程序。

镜像源切换脚本的下载设置 10 秒连接超时、120 秒单次总时限及 3 次重试。所有变体通过 `bash -o pipefail` 运行下载管道，下载失败应让构建失败，不能静默使用原镜像源。包管理器的大文件下载不受这个 curl 时限影响。
