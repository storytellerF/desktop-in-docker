# desktop-in-docker

在 Docker 容器中运行 Linux 桌面环境，并通过浏览器、VNC 客户端或 RDP 客户端访问。项目提供三类镜像构建方式：

- `x11`：从发行版基础镜像开始安装 TigerVNC、noVNC、supervisor 和指定桌面环境。
- `wayland`：从 Arch Linux 基础镜像开始安装 Weston，并通过 Weston RDP backend 暴露轻量 Wayland 桌面。
- `webtop`：基于 LinuxServer Webtop 镜像扩展，额外加入 fcitx 输入法和 supervisor 服务。

默认构建组合是 `x11 + debian:trixie + xfce`。

## 快速开始

创建 `.env`，至少设置 VNC 密码：

```bash
cat > .env <<'EOF'
VNC_PASSWD="change-me"
EOF
```

启动默认镜像：

```bash
docker compose up -d
```

查看随机映射到宿主机的端口：

```bash
docker compose port desktop 6080
docker compose port desktop 5901
docker compose port desktop 3389
```

访问桌面：

- x11 Web VNC：`http://localhost:<6080映射端口>/vnc.html`
- x11 VNC 直连：`localhost:<5901映射端口>`
- wayland RDP：`localhost:<3389映射端口>`

compose 示例还暴露了 Webtop 使用的 `3000` 和 `3001` 端口。Webtop 镜像启动后通常访问：

- Webtop Web UI：`http://localhost:<3000映射端口>/`
- Webtop HTTPS UI：`https://localhost:<3001映射端口>/`（上游默认使用自签名证书）

日志默认挂载到 `./logs`，浏览器缓存和 shell 历史会保存在 Docker volume 中，配置见 [docker-compose.yml](docker-compose.yml)。

## 构建与启动脚本

推荐使用 [scripts/build_image.py](scripts/build_image.py) 管理构建、打标签、启动和停止。需要 Python 3.10+、Docker 和 Docker Compose；Python 部分无需安装第三方依赖。从项目根目录运行，Linux/macOS 可将命令中的 `python` 换为 `python3`。旧的 `scripts/build-image.sh` 保留为兼容入口，通过 `PYTHON` 环境变量可以指定解释器。

生成或更新 `.env`：

```bash
python scripts/build_image.py -c
```

构建默认镜像：

```bash
python scripts/build_image.py -b
```

构建并启动：

```bash
python scripts/build_image.py -b -S
```

停止 compose 服务：

```bash
python scripts/build_image.py -T
```

构建 Webtop 变体：

```bash
python scripts/build_image.py --image-variant webtop -s arch -d xfce -b
```

构建 Arch Wayland + RDP 变体：

```bash
python scripts/build_image.py --image-variant wayland -s arch -b
```

发布多架构镜像到 Docker Hub，需要提前 `docker login`：

```bash
python scripts/build_image.py -P -m --latest
```

连接正在运行的 VNC 服务。如果本机安装了 `remmina` 会优先使用，否则尝试 `vncviewer`：

```bash
./scripts/vnc.sh
```

## 常用参数

`scripts/build_image.py` 支持的主要参数：

| 参数 | 说明 |
| --- | --- |
| `-s, --system` | 发行版或 Webtop 上游 tag 的系统部分：`debian`、`ubuntu`、`fedora`、`arch`、`alpine`；Wayland 仅支持 `arch` |
| `-v, --version` | 发行版版本，默认：Debian `trixie`、Ubuntu `noble`、Fedora `41`、Arch `latest`；Alpine 按桌面选择，见下文 |
| `-d, --desktop` | 桌面环境：`xfce`、`lxqt`、`kde`、`mate`、`cinnamon`、`lxde`、`gnome`、`enlightenment`；Wayland 仅支持 `weston` |
| `-i, --image-variant` | 镜像类型：`x11`、`wayland`、`webtop` |
| `-p, --password` | 写入 `.env` 时使用的 VNC 密码 |
| `-b, --build` | 本地构建当前架构镜像 |
| `-S, --start` | 使用 Docker Compose 启动服务 |
| `-T, --stop` | 停止 Docker Compose 服务 |
| `-P, --publish` | 使用 buildx 构建并推送多架构镜像 |
| `-m, --multi-arch` | 标记多架构模式；发布路径使用 `linux/amd64,linux/arm64` |
| `--cn-mirror` | 强制启用国内镜像源和 `-cn` 标签 |
| `--no-cn-mirror` | 强制禁用国内镜像源 |
| `--latest` | 额外生成 `latest` 标签 |
| `--no-snapshot` | 不生成 `snapshot` 标签 |

## 支持矩阵

x11 桌面环境：

- `xfce`
- `lxqt`
- `kde`
- `mate`
- `cinnamon`
- `lxde`
- `gnome`
- `enlightenment`

x11 发行版：

- `debian`
- `ubuntu`
- `fedora`
- `alpine`

Wayland 发行版和桌面：

- `arch + weston`

`weston` 是轻量 Wayland compositor，负责显示合成和 RDP 输出；它不是 XFCE、MATE、KDE、GNOME 这类完整桌面环境。首版 Wayland 镜像提供 Weston 桌面、RDP 入口和常用 GUI 应用，不实现完整 Plasma/GNOME 会话。

Webtop 支持的系统与桌面组合（受[上游镜像标签](https://docs.linuxserver.io/images/docker-webtop/#version-tags)限制）：

| 系统 | 桌面 |
| --- | --- |
| Debian | xfce、kde、mate |
| Ubuntu | xfce、lxqt、kde、mate |
| Fedora | xfce、kde、mate |
| Arch | xfce、kde、mate |
| Alpine | kde |

本入口使用 `<system>-<desktop>` 形式的上游标签。Alpine/XFCE 在上游使用 `latest`，没有对应的 `alpine-xfce` 标签，当前入口尚未映射这个别名。

其他 Webtop 组合会在调用 Docker 前拒绝，并列出该系统支持的桌面；不会回退到其他桌面。国内镜像源开关不改变支持范围。构建入口允许的矩阵为 x11 62 项、Webtop 28 项、Wayland 2 项，共 92 项（均包含国内镜像源开/关）。

当前限制：

- Alpine + MATE 因 Xvnc 崩溃导致会话不稳定而禁用。禁用覆盖 X11 和 Webtop 的构建、发布和启动入口；显式版本、环境变量和国内镜像源开关均不能绕过。纯停止命令 `-T` 仍可使用。
- x11 默认 Fedora 41 的构建使用 Fedora 官方归档仓库；Webtop 的发行版版本由上游镜像标签决定。
- `--image-variant x11 -s arch` 不支持。Arch 请使用 `--image-variant wayland -d weston` 或 `--image-variant webtop`。
- `--image-variant wayland` 仅支持 `-s arch -d weston`。
- `--image-variant x11 -s ubuntu` 只支持 `noble` / `24.04` 或更早版本。

Alpine x11 未通过 `-v` 或 `SYSTEM_VERSION` 指定版本时，按桌面选择完整的发行版分支：

| 桌面 | Alpine 默认版本 | 原因 |
| --- | --- | --- |
| KDE | `3.21` | 该分支提供 `plasma-workspace-x11`；较新 Alpine 包移除了 X11 启动器 |
| GNOME | `3.22` | 使用仍支持 X11 的 GNOME/Mutter 48 |
| Cinnamon、Enlightenment | `edge` | 所需 Cinnamon、EFL、Terminology 位于 `edge/testing`，保持基础镜像与依赖分支一致 |
| XFCE、LXQt、LXDE | `latest` | 使用当前稳定分支的组件 |

LXDE 使用 Alpine 的 LXSession、PCManFM、Openbox，并构建缺失的上游 LXPanel 和 lxde-common。Enlightenment 使用真正的现代 Enlightenment 0.27.1 源码及 Alpine EFL，不以 E16 或其他桌面替代。源码版本及校验值固定在构建脚本中。显式版本配置仍优先，不会静默切换到另一个发行版。

Alpine X11 与 Alpine Webtop KDE 会将桌面会话中过高的文件描述符硬上限限制为 65536，保留更低的已有上限。部分 Docker 主机的默认值超过十亿，musl 上的 D-Bus、Qt 子进程启动路径会因此长时间阻塞，表现为黑屏。实际验证需同时检查桌面画面、应用启动及键盘输入；仅有服务启动或协议握手成功不能视为桌面可用。

部分桌面环境没有对应系统的专用 Dockerfile 时，脚本会回退到该桌面的 Debian Dockerfile。Webtop 模式下如果没有系统专用模板，也会回退到 Debian 模板，并通过 `WEBTOP_BASE_IMAGE` 指定上游镜像 tag。

## 配置

构建脚本按命令行参数、`.env`、进程环境变量、默认值的顺序读取配置。`.env` 使用 `KEY=value` 格式，支持注释和引号；Python 入口按字面值读取，不执行 Shell 命令或变量展开。`-c` 会交互更新密码、Docker Hub 用户名和时间戳，并保留其他配置。Wayland 未指定 `-d` 时使用 `weston`。

可以在 `.env` 或 `docker-compose.yml` 的 `environment:` 中设置：

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `DOCKER_USERNAME` | `storytellerf` | compose 拉取镜像时使用的 Docker Hub 用户或命名空间 |
| `IMAGE_TAG` | `snapshot` | compose 使用的镜像标签 |
| `VNC_PASSWD` | 构建入口默认 `password` | x11 VNC 密码；使用前请设置自己的密码 |
| `VNC_GEOMETRY` | `1280x800`，compose 示例为 `1920x1080` | x11 VNC 分辨率 |
| `VNC_DEPTH` | `24` | x11 VNC 色深 |
| `RDP_PORT` | `3389` | wayland Weston RDP 容器内监听端口 |
| `CONTAINER_RDP_PORT` | `3389` | compose 暴露和脚本查询的 wayland RDP 容器端口；通常与 `RDP_PORT` 保持一致 |
| `CONTAINER_HOME` | x11/wayland 为 `/home/<user>`，webtop 为 `/config` | 日志和持久化目录挂载位置 |
| `ENABLE_CN_MIRROR` | 按时区自动判断 | 可用 `true` / `false` 控制脚本的国内镜像源模式 |

请在直接启动容器时设置 `VNC_PASSWD`。容器启动脚本在密码为空时会请求无认证模式，但 Debian 等发行版的 TigerVNC 会拒绝对外监听的无认证服务，导致桌面无法启动。Python 构建入口通过 Compose 启动时会提供密码，逻辑见 [base-scripts/start-vnc.sh](base-scripts/start-vnc.sh)。

## 镜像标签

脚本会根据系统、版本、桌面和时间生成标签。常见格式：

- `<system>-<version>-<desktop>-<timestamp>`
- `<system>-<version>-<desktop>-snapshot`
- `<system>-<version>-<desktop>-latest`
- 启用国内镜像源时会在前缀中加入 `-cn`

默认组合 `debian:trixie + xfce` 会额外生成简写标签：

- `desktop-in-docker:<timestamp>`
- `desktop-in-docker:snapshot`
- `desktop-in-docker:latest`

Webtop 标签会以 `webtop-` 开头，例如：

- `webtop-arch-xfce-snapshot`
- `webtop-kde-snapshot`
- `webtop-snapshot`

Wayland 标签会以 `wayland-` 开头，例如：

- `wayland-arch-latest-weston-snapshot`
- `wayland-arch-latest-weston-latest`

## 项目结构

```text
.
├── base-scripts/              # 容器内启动脚本
├── docker/
│   ├── config/                # supervisor 与 Webtop 自定义服务配置
│   └── dockerfiles/           # base、x11、wayland、webtop 和构建片段
├── fcitx/                     # fcitx 配置
├── scripts/
│   ├── build_image.py         # Python 构建、发布、启动主脚本
│   ├── build-image.sh         # 兼容旧命令的简短入口
│   └── vnc.sh                 # 本机 VNC 连接辅助脚本
├── tests/                     # fake docker 测试
├── docker-compose.yml
└── README.md
```

构建时生成的 Dockerfile 会写入：

- `build/x11/`
- `build/wayland/`
- `build/webtop/`

这些文件由脚本从 Dockerfile 模板和 `.dockerfrag` 片段合并生成。

## 开发

离线测试、生成文件和开发流程见 [DEVELOPMENT.md](DEVELOPMENT.md)。

## 安全提示

- 请设置 `VNC_PASSWD`，不要把 VNC 端口直接暴露到不可信网络。
- Wayland RDP 首版使用自签名 TLS 证书，不提供额外登录认证层；请只绑定本机或可信网络，不要把 RDP 端口直接暴露到公网。
- x11 基础镜像会创建带免密 sudo 的非 root 用户，方便开发和调试，但不适合运行不可信工作负载。
- 构建时优先排除可选的独立屏保包，避免远程桌面进入无法解锁的状态。Cinnamon、Fedora LXQt 等桌面强制依赖的屏保保留包并禁用启动入口；Enlightenment、X11 KDE 的集成锁屏通过原生配置禁用。连接认证仍由 `VNC_PASSWD` 控制。
- Webtop 模式继承 LinuxServer Webtop 的运行模型，容器内主要用户为 `abc`，持久化目录为 `/config`。
