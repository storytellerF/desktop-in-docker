# desktop-in-docker

在 Docker 容器中运行 Linux 桌面环境，并通过浏览器或 VNC 客户端访问。项目提供两类镜像构建方式：

- `x11`：从发行版基础镜像开始安装 TigerVNC、noVNC、supervisor 和指定桌面环境。
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
```

访问桌面：

- x11 Web VNC：`http://localhost:<6080映射端口>/vnc.html`
- x11 VNC 直连：`localhost:<5901映射端口>`

compose 示例还暴露了 Webtop 使用的 `3000` 和 `3001` 端口。Webtop 镜像启动后通常访问：

- Webtop Web UI：`http://localhost:<3000映射端口>/`
- Webtop VNC 直连：`localhost:<3001映射端口>`

日志默认挂载到 `./logs`，浏览器缓存和 shell 历史会保存在 Docker volume 中，配置见 [docker-compose.yml](docker-compose.yml)。

## 构建与启动脚本

推荐使用 [scripts/build-image.sh](scripts/build-image.sh) 管理构建、打标签、启动和停止。

生成或更新 `.env`：

```bash
./scripts/build-image.sh -c
```

构建默认镜像：

```bash
./scripts/build-image.sh -b
```

构建并启动：

```bash
./scripts/build-image.sh -b -S
```

停止 compose 服务：

```bash
./scripts/build-image.sh -T
```

构建 Webtop 变体：

```bash
./scripts/build-image.sh --image-variant webtop -s arch -d xfce -b
```

发布多架构镜像到 Docker Hub，需要提前 `docker login`：

```bash
./scripts/build-image.sh -P -m --latest
```

连接正在运行的 VNC 服务。如果本机安装了 `remmina` 会优先使用，否则尝试 `vncviewer`：

```bash
./scripts/vnc.sh
```

## 常用参数

`scripts/build-image.sh` 支持的主要参数：

| 参数 | 说明 |
| --- | --- |
| `-s, --system` | 发行版或 Webtop 上游 tag 的系统部分：`debian`、`ubuntu`、`fedora`、`arch`、`alpine` |
| `-v, --version` | 发行版版本，默认：Debian `trixie`、Ubuntu `noble`、Fedora `41`、Arch/Alpine `latest` |
| `-d, --desktop` | 桌面环境：`xfce`、`lxqt`、`kde`、`mate`、`cinnamon`、`lxde`、`gnome`、`enlightenment` |
| `-i, --image-variant` | 镜像类型：`x11`、`webtop`；`wayland` 已识别但尚未实现 |
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

桌面环境：

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

Webtop 发行版：

- `debian`
- `ubuntu`
- `fedora`
- `arch`
- `alpine`

当前限制：

- `--image-variant x11 -s arch` 不支持。Arch 请使用 `--image-variant webtop`。
- `--image-variant x11 -s ubuntu` 只支持 `noble` / `24.04` 或更早版本。
- `--image-variant wayland` 仍是预留选项，暂未实现。

部分桌面环境没有对应系统的专用 Dockerfile 时，脚本会回退到该桌面的 Debian Dockerfile。Webtop 模式下如果没有系统专用模板，也会回退到 Debian 模板，并通过 `WEBTOP_BASE_IMAGE` 指定上游镜像 tag。

## 配置

可以在 `.env` 或 `docker-compose.yml` 的 `environment:` 中设置：

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `DOCKER_USERNAME` | `storytellerf` | compose 拉取镜像时使用的 Docker Hub 用户或命名空间 |
| `IMAGE_TAG` | `snapshot` | compose 使用的镜像标签 |
| `VNC_PASSWD` | 未设置时无密码 | x11 VNC 密码；建议务必设置 |
| `VNC_GEOMETRY` | `1280x800`，compose 示例为 `1920x1080` | x11 VNC 分辨率 |
| `VNC_DEPTH` | `24` | x11 VNC 色深 |
| `CONTAINER_HOME` | x11 为 `/home/<user>`，webtop 为 `/config` | 日志和持久化目录挂载位置 |
| `ENABLE_CN_MIRROR` | 按时区自动判断 | 可用 `true` / `false` 控制脚本的国内镜像源模式 |

如果 `VNC_PASSWD` 未设置，x11 的 TigerVNC 会以无密码模式启动，逻辑见 [base-scripts/start-vnc.sh](base-scripts/start-vnc.sh)。

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

## 项目结构

```text
.
├── base-scripts/              # 容器内启动脚本
├── docker/
│   ├── config/                # supervisor 与 Webtop 自定义服务配置
│   └── dockerfiles/           # 各系统、桌面环境和构建片段
├── fcitx/                     # fcitx 配置
├── scripts/
│   ├── build-image.sh         # 构建、发布、启动主脚本
│   └── vnc.sh                 # 本机 VNC 连接辅助脚本
├── tests/                     # fake docker 测试
├── docker-compose.yml
├── supervisord.conf
└── README.md
```

构建时生成的 Dockerfile 会写入：

- `build/x11/`
- `build/webtop/`

这些文件由脚本从 Dockerfile 模板和 `.dockerfrag` 片段合并生成。

## 测试

项目提供 fake Docker 测试，用来验证脚本生成的 Docker 命令，不会真正构建镜像或启动容器：

```bash
./tests/verify-fake-docker.sh
```

也可以手动只验证某个命令：

```bash
FAKE_DOCKER_LOG=/tmp/desktop-in-docker-fake-docker.log \
PATH="$PWD/tests/fakes:$PATH" \
./scripts/build-image.sh -b --no-cn-mirror
```

查看记录：

```bash
cat /tmp/desktop-in-docker-fake-docker.log
```

需要测试失败路径时，可设置 `FAKE_DOCKER_FAIL_COMMANDS`，值为逗号分隔的 fake 命令名，例如 `build`、`buildx-build`、`image-prune`、`compose-up`、`compose-down`、`compose-port`。

## 安全提示

- 请设置 `VNC_PASSWD`，不要把 VNC 端口直接暴露到不可信网络。
- x11 基础镜像会创建带免密 sudo 的非 root 用户，方便开发和调试，但不适合运行不可信工作负载。
- Webtop 模式继承 LinuxServer Webtop 的运行模型，容器内主要用户为 `abc`，持久化目录为 `/config`。
