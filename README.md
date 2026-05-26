# desktop-in-docker

在 Docker 容器里运行一个完整的 Linux 桌面环境，并通过 VNC / noVNC 在宿主机访问图形桌面。

- **noVNC（浏览器访问）**：容器内 `6080`，打开 `/vnc.html`
- **VNC（客户端直连）**：容器内 `5901`（TigerVNC 显示号 `:1`）

支持的发行版与桌面环境见 [scripts/build-image.sh](file:///home/kx/Projects/desktop-in-docker/scripts/build-image.sh) 的参数说明：
- 发行版：debian / ubuntu / fedora / arch / alpine
- 桌面：xfce / lxqt / kde / mate / cinnamon / lxde / gnome / enlightenment

## 快速开始（Docker Compose）

1) 建议先创建 `.env`（至少设置 VNC 密码）：

```bash
cat > .env <<'EOF'
VNC_PASSWD="change-me"
EOF
```

2) 启动：

```bash
docker compose up -d
```

3) 查看映射到宿主机的端口（本项目 compose 使用随机宿主端口映射）：

```bash
docker compose port desktop 6080
docker compose port desktop 5901
```

4) 访问：
- noVNC：`http://localhost:<6080映射端口>/vnc.html`
- VNC：`localhost:<5901映射端口>`

日志默认挂载到 `./logs`（对应容器内 supervisor 日志目录），见 [docker-compose.yml](file:///home/kx/Projects/desktop-in-docker/docker-compose.yml)。

## 使用脚本（推荐）

仓库提供了构建/启动一体化脚本 [scripts/build-image.sh](file:///home/kx/Projects/desktop-in-docker/scripts/build-image.sh)：

- 生成/覆盖 `.env`（交互式设置 VNC 密码，可选 Docker Hub 用户名）：

```bash
./scripts/build-image.sh -c
```

- 本地构建镜像（默认 debian:trixie + xfce）：

```bash
./scripts/build-image.sh -b
```

- 基于 LinuxServer Webtop 构建增强镜像（`system + desktop` 会组成上游 webtop tag，例如 `arch-xfce`）：

```bash
./scripts/build-image.sh --image-variant webtop -s arch -d xfce -b
```

webtop 模式下切换系统和桌面仍然使用原来的参数名：`-s/--system` 与 `-d/--desktop`。

- 构建后用 compose 启动（会输出可访问的 Web/VNC 地址）：

```bash
./scripts/build-image.sh -b -S
```

- 停止：

```bash
./scripts/build-image.sh -T
```

脚本还提供快捷连接 VNC（需要宿主机安装 `vncviewer`）：

```bash
./scripts/vnc.sh
```

## 脚本测试（Fake Docker）

仓库提供了一个假的 Docker 命令 [tests/fakes/docker](/home/kx/Projects/desktop-in-docker/tests/fakes/docker)，用于验证构建脚本生成的 Docker 调用，而不实际构建镜像或启动容器。

```bash
./tests/verify-fake-docker.sh
```

也可以手动把 fake Docker 放到 `PATH` 前面，只验证某一条命令：

```bash
FAKE_DOCKER_LOG=/tmp/desktop-in-docker-fake-docker.log PATH="$PWD/tests/fakes:$PATH" ./scripts/build-image.sh -b --no-cn-mirror
```

查看记录到的 Docker 调用：

```bash
cat /tmp/desktop-in-docker-fake-docker.log
```

需要测试失败路径时，可用逗号分隔的 `FAKE_DOCKER_FAIL_COMMANDS` 指定要失败的命令，例如 `build`、`buildx-build`、`image-prune`、`compose-up`、`compose-down`、`compose-port`。

## 配置项

**VNC 密码**
- 通过环境变量 `VNC_PASSWD` 控制（建议务必设置）。
- 若未设置 `VNC_PASSWD`，VNC 会以无密码模式启动，逻辑见 [start-vnc.sh](file:///home/kx/Projects/desktop-in-docker/base-scripts/start-vnc.sh)。

**分辨率与色深**
- `VNC_GEOMETRY`：默认 `1280x800`（compose 示例默认 `1920x1080`）
- `VNC_DEPTH`：默认 `24`

可在 `.env` 或 compose 的 `environment:` 中设置，见 [docker-compose.yml](file:///home/kx/Projects/desktop-in-docker/docker-compose.yml)。

## 构建矩阵与镜像标签

默认 `--image-variant x11` 构建流程大致为：
- 先构建 base 镜像（安装 TigerVNC、supervisor、noVNC/websockify 等基础依赖）
- 再在 base 上安装指定桌面环境
- 运行时用 supervisor 拉起 VNC 与 noVNC 服务，见 [supervisord.conf](file:///home/kx/Projects/desktop-in-docker/supervisord.conf)

x11 模式的 base Dockerfile 会在构建时由系统 Dockerfile、[docker/dockerfiles/fragments/custom/user-config.dockerfrag](/home/kx/Projects/desktop-in-docker/docker/dockerfiles/fragments/custom/user-config.dockerfrag) 和 [docker/dockerfiles/fragments/custom/fcitx-config.dockerfrag](/home/kx/Projects/desktop-in-docker/docker/dockerfiles/fragments/custom/fcitx-config.dockerfrag) 合并生成到 `build/x11/`。

`--image-variant webtop` 会改为直接基于上游 `lscr.io/linuxserver/webtop:<system>-<desktop>` 构建。系统和桌面继续用原来的 `-s/--system`、`-d/--desktop` 参数指定，例如：
- `-s arch -d xfce` 使用 `lscr.io/linuxserver/webtop:arch-xfce`
- `-s ubuntu -d kde` 使用 `lscr.io/linuxserver/webtop:ubuntu-kde`

在 webtop 模式下，本项目不会再安装桌面环境，只会在上游 webtop 镜像上增加 fcitx 输入法和一个用于启动 fcitx 的 supervisor 附加服务。系统值会继续用于选择包管理器和上游 tag。

最终增强镜像的 Dockerfile 会在构建时由 [docker/dockerfiles/webtop/](/home/kx/Projects/desktop-in-docker/docker/dockerfiles/webtop) 下对应系统的 Dockerfile 和 [docker/dockerfiles/fragments/webtop/config.dockerfrag](/home/kx/Projects/desktop-in-docker/docker/dockerfiles/fragments/webtop/config.dockerfrag) 合并生成到 `build/webtop/`。

CN mirror 在 webtop 模式下是单阶段最终镜像构建：脚本会把 [docker/dockerfiles/fragments/webtop/cn/](/home/kx/Projects/desktop-in-docker/docker/dockerfiles/fragments/webtop/cn) 下对应系统的 dockerfrag 注入到系统 Dockerfile 的依赖安装前，再追加共享配置片段。

标签规则由 [scripts/build-image.sh](file:///home/kx/Projects/desktop-in-docker/scripts/build-image.sh) 自动生成，常见形式：
- `<system>-<version>-<desktop>-snapshot`
- `<system>-<version>-<desktop>-latest`（加 `--latest`）
- `<system>-<version>-<desktop>-<timestamp>`
- `-cn` 变体：根据时区自动启用，或用 `--cn-mirror/--no-cn-mirror` 强制控制

webtop 模式的标签会使用 `webtop-<system>-<desktop>` 前缀，例如 `webtop-arch-xfce-snapshot`。

webtop 模式保留简写标签，但不会省略 `webtop` 前缀：
- `-s debian -d xfce` 会额外生成 `webtop-snapshot`
- `-s debian -d kde` 会额外生成 `webtop-kde-snapshot`
- `-s arch -d xfce` 会额外生成 `webtop-arch-snapshot`

默认组合（debian:trixie + xfce）会生成简写标签：`desktop-in-docker:snapshot` / `desktop-in-docker:latest` 等。

## 目录结构

- [docker/dockerfiles/](file:///home/kx/Projects/desktop-in-docker/docker/dockerfiles)：各发行版 base 与各桌面环境 Dockerfile
- [docker/dockerfiles/fragments/](/home/kx/Projects/desktop-in-docker/docker/dockerfiles/fragments)：构建时拼接或注入的 `.dockerfrag` 片段
- [docker/dockerfiles/webtop/](/home/kx/Projects/desktop-in-docker/docker/dockerfiles/webtop)：Webtop 按系统拆分的增强 Dockerfile 模板
- [docker/dockerfiles/fragments/webtop/cn/](/home/kx/Projects/desktop-in-docker/docker/dockerfiles/fragments/webtop/cn)：Webtop CN mirror 注入片段
- [docker/dockerfiles/fragments/custom/user-config.dockerfrag](/home/kx/Projects/desktop-in-docker/docker/dockerfiles/fragments/custom/user-config.dockerfrag)：x11 构建时拼接进最终镜像的“用户侧片段”（拷贝脚本、暴露端口、设置 ENTRYPOINT）
- [docker/dockerfiles/fragments/custom/fcitx-config.dockerfrag](/home/kx/Projects/desktop-in-docker/docker/dockerfiles/fragments/custom/fcitx-config.dockerfrag)：x11 CN mirror 构建时拼接进最终镜像的 fcitx 片段
- [docker/dockerfiles/fragments/webtop/config.dockerfrag](/home/kx/Projects/desktop-in-docker/docker/dockerfiles/fragments/webtop/config.dockerfrag)：webtop 构建时拼接进最终增强镜像的共享片段
- [base-scripts/](file:///home/kx/Projects/desktop-in-docker/base-scripts)：容器内启动脚本（entrypoint、supervisord、VNC）
- [supervisord.conf](file:///home/kx/Projects/desktop-in-docker/supervisord.conf)：启动 vnc/noVNC 的 supervisor 配置

## 安全提示

- **务必设置 `VNC_PASSWD`**，并避免在不受信网络中暴露 VNC 端口。
- base 镜像默认创建了一个拥有免密 sudo 权限的非 root 用户（方便开发/调试），不建议用于运行不受信任的工作负载；实现见 [docker/dockerfiles/base/debian.Dockerfile](file:///home/kx/Projects/desktop-in-docker/docker/dockerfiles/base/debian.Dockerfile)。
