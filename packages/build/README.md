# Tengine 发行版打包

从当前源码树构建 Tengine 的原生系统包。所有平台共用一份 configure 参数
（[configure-args.sh](configure-args.sh)），因此不同发行版产出的包功能集与
文件布局完全一致。

## 包命名与内容

| 项目 | 值 |
|---|---|
| 包名 | `tengine` |
| 二进制 | `/usr/sbin/tengine` |
| 主配置 | `/etc/tengine/tengine.conf`（`include /etc/tengine/conf.d/*.conf`） |
| 日志 | `/var/log/tengine/{access,error}.log` |
| PID | `/run/tengine.pid` |
| 动态模块目录 | `<libdir>/tengine/modules` |
| 临时目录 | `/var/cache/tengine/*` |
| 运行账号 | `tengine:tengine`（安装时自动创建） |
| 服务管理 | systemd `tengine.service`；Alpine 为 OpenRC `/etc/init.d/tengine` |

因为二进制名和配置路径都与 nginx 无重叠，本包可与发行版自带的 nginx **共存**。

产物命名示例：

```
tengine-3.2.0-20260604232239.el7u2.x86_64.rpm
tengine-3.2.0-20260604232239.el7u2.aarch64.rpm
tengine_3.2.0-20260604232239_amd64.deb
tengine-3.2.0_p20260604232239-r0.apk
```

版本号 `3.2.0` 自动取自 `src/core/nginx.h` 的 `TENGINE_VERSION`，
Release 为构建时间戳（可用 `--timestamp` 固定）。

## 用法

### 容器构建（推荐，宿主只需 docker/podman）

```sh
packages/build/build.sh docker el9          # Rocky 9
packages/build/build.sh docker ubuntu2404   # Ubuntu 24.04
packages/build/build.sh docker alpine       # Alpine 3.20
packages/build/build.sh docker all          # 全部目标
```

支持的目标：

| 目标 | 镜像 | 产物 |
|---|---|---|
| `el7` | `centos:7`（自动切 vault 源） | rpm |
| `el8` | `rockylinux:8` | rpm |
| `el9` | `rockylinux:9` | rpm |
| `el10` | `almalinux:10` | rpm |
| `fedora` | `fedora:latest` | rpm |
| `anolis8` / `anolis23` | `openanolis/anolisos:8.8` / `:23` | rpm |
| `openeuler2203` / `openeuler2403` | `openeuler/openeuler:22.03-lts-sp4` / `:24.03-lts` | rpm |
| `sles15` | `registry.suse.com/bci/bci-base:15.6` | rpm |
| `debian11` / `debian12` | `debian:11` / `debian:12` | deb |
| `ubuntu2204` / `ubuntu2404` | `ubuntu:22.04` / `ubuntu:24.04` | deb |
| `alpine` | `alpine:3.20` | apk |

同一份 spec 适用于所有 RHEL/SUSE 派生发行版，加目标只需在
[build.sh](build.sh) 的 `docker_image()` 里加一行镜像映射。若目标系统本身没有
公开容器镜像，在该系统上直接本机构建即可：

```sh
# Alibaba Cloud Linux 2，产出 ...-20260604232239.el7u2.x86_64.rpm
packages/build/build.sh rpm --dist .el7u2      # 在该系统上直接跑
```

跨架构（需 binfmt/qemu）：

```sh
packages/build/build.sh docker el9 --platform linux/arm64
```

### CI/CD

[.github/workflows/package.yml](../../.github/workflows/package.yml) —
**不在日常 push/PR 上触发**（一次矩阵要编译 22 遍），仅：

- push tag `tengine-*` 时自动触发
- 手动 `workflow_dispatch`（可传 `dist_tag`，如 `.el7u2`）

矩阵为 12 目标 × 2 架构 = 24 个 job。`aarch64` 跑在原生 `ubuntu-24.04-arm`
runner（QEMU 模拟会让单次编译慢 5~10 倍）。`fedora`（rolling）、`anolis23`、
`openeuler2203`、`sles12` 未进矩阵，需要时用 `build.sh docker <目标>`。

**只有 `el7` + `aarch64` 这一个组合标记 `continue-on-error`**：CentOS 7 EOL 后
镜像源迁到 `vault.centos.org`，其主树只有 x86_64，aarch64 归档在
`/altarch/` 另一路径下，bootstrap 的源改写没覆盖，该组合不可能成功。
`el7` + `x86_64` **不免检**——源码保留了完整的 OpenSSL 1.0.2 回退分支，也没有
gcc 4.8 默认 `-std=gnu89` 下非法的语法，预期能构建成功，失败即为真实问题。

> 这只是公共 CI 用 `centos:7` 镜像的限制，不是 spec 的限制。在自带完整
> aarch64 仓库的 el7 系统（如 Alibaba Cloud Linux 2）上直接
> `build.sh rpm --dist .el7u2` 即可产出 el7u2 的 aarch64 包。

整个 run 共享一个时间戳（由前置 `prepare` job 输出），因此 24 个包的
Release 完全一致。产物按 `tengine-<target>-<arch>` 上传为 artifact。

`verify` job 另取 4 个组合（el9/ubuntu2404 × x86_64/aarch64）实机装包，
校验 `/usr/sbin/tengine` 存在、`/etc/tengine/tengine.conf` 存在、
`tengine -V` 与 `tengine -t` 通过。

### 本机构建

```sh
packages/build/build.sh auto     # 按 /etc/os-release 自动选择
packages/build/build.sh rpm      # 需要 rpm-build
packages/build/build.sh deb      # 需要 build-essential debhelper
packages/build/build.sh apk      # 需要 alpine-sdk
```

### 常用选项

```sh
# 指定厂商 dist tag，得到 ...-20260604232239.el7u2.x86_64.rpm
packages/build/build.sh rpm --dist .el7u2

# 固定时间戳（多架构构建时保持 Release 一致）
packages/build/build.sh docker all --timestamp 20260604232239

# 启用可选模块
packages/build/build.sh rpm --with zstd --with lua
```

## 模块集

默认只启用构建依赖为 pcre / openssl / zlib 的模块，保证在原生发行版上
`rpmbuild` / `dpkg-buildpackage` 开箱即过。

**默认启用**：http_ssl、http_v2、realip、addition、auth_request、dav、flv、
gunzip、gzip_static、mp4、random_index、secure_link、stub_status、sub、mail(+ssl)、
stream(+ssl/realip/ssl_preread/sni)、threads、file-aio、pcre-jit，以及 Tengine 模块
backtrace、debug_pool/timer/conn、concat、footer_filter、proxy_connect、reqstat、
slice、sysguard、trim_filter、upstream_check、upstream_consistent_hash、
upstream_dynamic、upstream_dyups、upstream_iwrr、upstream_keepalive(Tengine 版)、
upstream_session_sticky、upstream_vnswrr、user_agent、multi_upstream、slab_stat。

**需显式开启**（`--with`）：

| 开关 | 模块 | 额外依赖 |
|---|---|---|
| `zstd` | `ngx_zstd` | libzstd-devel |
| `lua` | `ngx_http_lua_module` | LuaJIT 2.1 + lua-resty-core |
| `geoip` | `stream_geoip_module` | GeoIP-devel |

**未纳入**：QUIC/HTTP-3（`ngx_http_xquic_module`，需 xquic 库）、NTLS
（`ngx_tongsuo_ntls`，需 Tongsuo）、`mod_dubbo`/`mod_xudp`/`ngx_ingress_module`
等需要额外基础设施的模块。这些请用独立的 configure 流程自建。

## 平台差异

- **musl（Alpine）**：`ngx_backtrace_module` 依赖 `execinfo.h` 的 `backtrace()`，
  musl 不提供且其 `config` 会直接中断 configure，因此 Alpine 构建关闭该模块。
- **-Werror**：源码树默认追加 `-Werror`（[auto/cc/gcc](../../auto/cc/gcc)）。发行版
  加固 flag 叠加任意 gcc 版本几乎必然触发新告警，三套打包配方均以
  `--with-cc-opt="... -Wno-error"` 覆盖。
- **PCRE**：EL9+/Fedora 33+/openSUSE Leap 15.5+ 用 pcre2-devel，更老的用 pcre-devel。
- **libdir**：RPM 走 `%{_libdir}`（x86_64 为 `/usr/lib64`），deb/apk 固定 `/usr/lib`。

## 文件说明

```
packages/build/
├── build.sh              统一入口（POSIX sh，可在容器内自举）
├── configure-args.sh     全平台共享的 configure 参数与路径布局
├── conf/
│   ├── tengine.conf      主配置（FHS 绝对路径）
│   ├── conf.d/default.conf
│   ├── tengine.service   systemd unit
│   ├── tengine.openrc    Alpine OpenRC 脚本
│   └── tengine.logrotate
├── rpm/tengine.spec      RHEL + SLES 共用 spec
├── deb/debian/           Debian/Ubuntu 打包目录
└── apk/APKBUILD          Alpine 包
```

> `packages/debian/` 是历史遗留的旧 deb 打包（二进制名为 `nginx`），与本目录无关。
