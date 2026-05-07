# 计划：将 USE_CN_MIRROR 改为使用时区参数

## 目标
将当前的 USE_CN_MIRROR 参数系统改为直接传入时区参数，内部通过时区判断是否需要设置 mirror，并在设置 mirror 之后设置容器的时区为传入的时区。

## 当前系统分析
- USE_CN_MIRROR 在 build-image.sh 中通过检测系统时区自动设置
- 支持多个 Linux 发行版：Debian、Ubuntu、Fedora、Arch、Alpine
- 所有 Dockerfile 都使用相同的模式：检查 USE_CN_MIRROR="true" 然后切换镜像源

## 实施步骤

### 1. 修改构建脚本 (build-image.sh)
- 移除 USE_CN_MIRROR 变量和相关逻辑
- 改为直接获取和传递时区参数
- 将时区作为构建参数传递给 Docker

### 2. 修改所有基础 Dockerfile
- 将 USE_CN_MIRROR 构建参数替换为 TIMEZONE 参数
- 在 Dockerfile 内部实现时区到中国镜像的判断逻辑
- 添加设置容器时区的步骤
- 支持的 Dockerfile：
  - dockerfiles/base/Dockerfile (Debian)
  - dockerfiles/base/ubuntu.Dockerfile
  - dockerfiles/base/fedora.Dockerfile  
  - dockerfiles/base/arch.Dockerfile
  - dockerfiles/base/alpine.Dockerfile

### 3. 实现细节
- 时区判断逻辑：Asia/Shanghai、Asia/Chongqing、Asia/Harbin、Asia/Urumqi、PRC
- 镜像源切换保持现有逻辑不变
- 添加时区设置命令：根据发行版使用相应的时区设置方式

### 4. 验证和测试
- 确保所有修改后的 Dockerfile 都能正常构建
- 验证时区设置是否正确
- 验证中国镜像源是否正确切换