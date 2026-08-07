# Tengine 发行版打包与容器镜像

从当前源码树构建 Tengine 的原生系统包与容器镜像。所有平台、所有镜像共用一份
configure 参数（[configure-args.sh](configure-args.sh)），因此不同发行版产出的
包与镜像功能集、文件布局完全一致。

**默认即完备功能集**：Tongsuo（NTLS / 国密）、xquic（QUIC / HTTP-3）、
LuaJIT + resty 运行时库全部内置，版本 pin 在 [deps.env](deps.env)。这三者
不在任何发行版仓库里，因此每次构建都从源码编译 —— 详见
[功能集与第三方依赖](#功能集与第三方依赖)。

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
tengine-3.2.0-20260604232239.el9.x86_64.rpm
tengine-3.2.0-20260604232239.el9.aarch64.rpm
tengine_3.2.0-20260604232239~bookworm_amd64.deb
tengine-3.2.0_p20260604232239-r0.apk
```

每个目标除主包外还产出两类子包：

| 子包 | rpm | deb | apk |
|---|---|---|---|
| perl 模块 | `tengine-module-perl` | `tengine-module-perl` | `tengine-mod-perl` |
| 调试符号 | `tengine-debuginfo`<br>`tengine-debugsource` | `tengine-dbgsym`<br>（Ubuntu 为 `.ddeb`） | `tengine-dbg` |

`ngx_http_perl_module` 单独成包是为了让主包不必依赖 libperl。它是动态模块且
**默认不加载**，需在主配置中显式 `load_module`。调试符号包在发布时分流到独立
目录，见 [collect-release.sh](collect-release.sh)。

版本号 `3.2.0` 自动取自 `src/core/nginx.h` 的 `TENGINE_VERSION`，
Release 为构建时间戳（可用 `--timestamp` 固定）。

deb 版本号带 `~<codename>` 后缀（`~bookworm`、`~noble`……）：deb 的版本与文件名
本身都不含发行版标识，六个 debian/ubuntu 目标会产出完全同名的文件，扁平化到
同一个 Release 时互相覆盖，`apt` 也无法区分。`~` 排序低于无后缀，是 Debian 惯例。

发布时 [collect-release.sh](collect-release.sh) 会把 deb **文件名**里的 `~` 换成 `.`。
GitHub 上传 release 附件时会做同样的替换，不提前换掉的话 `SHA256SUMS` 记的名字与
下载到的文件不一致，`sha256sum -c` 对每个 deb 都失败（且在 `--ignore-missing` 下
静默跳过）。包内的 `Version:` 字段仍保留 `~`，`apt` 比较的是后者，排序不受影响。

apk 文件名不含架构，发布时由 [collect-release.sh](collect-release.sh) 补 `.x86_64` /
`.aarch64`。

## 用法

### 容器构建（推荐，宿主只需 docker/podman）

```sh
packages/build/build.sh docker el9          # Rocky 9
packages/build/build.sh docker ubuntu2404   # Ubuntu 24.04
packages/build/build.sh docker alpine324    # Alpine 3.24
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
| `sles15` / `sles16` | `registry.suse.com/bci/bci-base:15.6` / `:16.0` | rpm |
| `debian11` / `debian12` / `debian13` | `debian:11` / `:12` / `:13` | deb |
| `ubuntu2204` / `ubuntu2404` / `ubuntu2604` | `ubuntu:22.04` / `:24.04` / `:26.04` | deb |
| `alpine321` / `alpine322` / `alpine323` / `alpine324` | `alpine:3.21` / `:3.22` / `:3.23` / `:3.24` | apk |

apk 绑定构建时的 musl 与各库 soname，不像 rpm/deb 那样能搬到更高版本，因此每个
Alpine 版本一个目标，覆盖 nginx 官方同样发布的 3.21~3.24。

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
**不在日常 push/PR 上触发**：每个目标要编 Tongsuo（两遍）、xquic、LuaJIT 与
Tengine，40 个 job 全跑一遍代价很高，因此仅：

- push tag `tengine-*` 时自动触发（并发布 Release）
- 手动 `workflow_dispatch`（可传 `dist_tag`，如 `.el7u2`）

矩阵为 20 目标 × 2 架构 = 40 个 job，单 job `timeout-minutes: 150`。`aarch64` 跑在
原生 `ubuntu-24.04-arm` runner（QEMU 模拟会让单次编译慢 5~10 倍）。`fedora`
与 `sles12` 未进矩阵，需要时用 `build.sh docker <目标>`。

`fedora` 刻意不进矩阵：nginx 官方包支持清单本就不含 Fedora，而 `fedora:latest`
是 rolling tag，每半年换一个大版本，产出的 `%dist`（`.fc43` 之类）会随之漂移，
损害构建可复现性；单版本 EOL 也只有约 13 个月。它的用途是本地
`build.sh docker fedora` 随手验证，不需要 CI 常驻。

矩阵已完整覆盖 nginx 官方包支持的发行版清单（RHEL 8/9/10、Debian 11/12/13、
Ubuntu 22.04/24.04/26.04、SLES 15 SP6+/16、Alpine 3.21~3.24，均双架构），并额外
包含 `el7`、`anolis8`、`anolis23`、`openeuler2203`、`openeuler2403`，以及 nginx
只发 x86_64 的 SLES 15 的 aarch64。信创发行版（龙蜥、openEuler）是 Tengine 的核心
用户群，因此两个版本各覆盖一条 LTS。

> openEuler 镜像的 `%dist` 为空，两个 openEuler 目标会产出同名 rpm，因此
> `build.sh` 为它们分别指定 `.oe2203` / `.oe2403`（见 `run_docker_target` 的
> `target_dist`）。Anolis 无此问题 —— 其镜像自带 `%dist`，产物形如
> `tengine-3.2.0-<ts>.an8.x86_64.rpm`。

**只有 `el7` + `aarch64` 标记 `continue-on-error`**：CentOS 7 EOL 后镜像源迁到
`vault.centos.org`，其主树只有 x86_64，aarch64 归档在 `/altarch/` 另一路径下，
bootstrap 的源改写没覆盖，该组合不可能成功。

**`el7` + `x86_64` 不免检。** 完备功能集已实测可用 gcc 4.8.5 编出：Tongsuo 的
OpenSSL 3.0 基线、xquic 的 `-std=gnu11` 及其自带 `-Werror` 都没有问题。唯一的真实
障碍是 CMake —— el7 只打包 2.8，而通常的替代 `cmake3` 只存在于同样已 EOL 的
EPEL 7（metalink 已失效，仅剩归档镜像）。因此 bootstrap 改为直接取 Kitware 的静态
tarball（只需 glibc 2.17，el7 满足）；`build.sh` 会发现这个 CMake 不属于 rpm，
自动为 spec 关掉对应的 `BuildRequires`（见 `external_cmake`）。

> 在自带完整仓库的 el7 系统上无需这些周折，直接
> `build.sh rpm --dist .el7u2` 即可 —— 已实测产出 4.9 MB 的完备功能集包
> （Tongsuo 静态链入、`libxquic.so` 与 `libluajit` 随包、`resty.core` 可加载）。

前置 `prepare` job 做两件事：钉住整个 run 共享的时间戳（36 个包 Release 号一致），
以及跑一次 [fetch-deps.sh](fetch-deps.sh) 把 pin 的依赖源码下载校验后上传为
artifact —— 36 个矩阵 job 各自下载它，既省 36 次重复下载，又保证全矩阵编译的是
同一份字节。

`verify` job 另取 4 个组合（el9/ubuntu2404 × x86_64/aarch64）实机装包，校验
`/usr/sbin/tengine` 与 `/etc/tengine/tengine.conf` 存在、`tengine -V` 输出里含
`ngx_tongsuo_ntls` / `ngx_http_xquic_module` / `ngx_http_lua_module` 与 Tongsuo
版本串、`tengine -t` 通过。

> `tengine -V` 能跑起来本身就验证了动态链接器解析到了随包的 `libxquic.so` 与
> `libluajit`，也就是验证了 rpath；`tengine -t` 通过则验证了 `resty.core` 能被
> 加载（启动即 require），也就是验证了 `lua_package_path`。

### Release 发布（tag 触发）

`release` job 在 tag 上跑：下载全部 36 份 artifact →
[collect-release.sh](collect-release.sh) 扁平化 → `softprops/action-gh-release`
上传为 **Release assets**。

与 workflow artifact 的关键区别：Release assets **永久保存、匿名可下载**，而
artifact 90 天过期且需要登录 GitHub。

- **正式版与预发布一视同仁上传**；tag 名含 `-rc` / `-beta` / `-alpha` / `-pre`
  （大小写不敏感）则标记为 GitHub prerelease，仅此区别。
- [collect-release.sh](collect-release.sh) 负责三类撞名：apk 补架构后缀、各架构
  重复的 `.src.rpm` 比对 sha256 后去重、其余冲突加 `<target>-` 前缀 —— 撞名绝不
  静默覆盖，无法消解时直接失败。
- 同时生成 `SHA256SUMS`，Release 说明里带 `dnf install <url>` / `apt install ./x.deb`
  / `docker pull` 与校验示例。

## Docker 镜像

两条线 × 两个变体，都是 multi-arch（amd64 + arm64），推到 ghcr.io：

| Dockerfile | 基底 | 变体 | 镜像 tag |
|---|---|---|---|
| [Dockerfile](../../Dockerfile) | `debian:13` → `debian:13-slim` | 默认 | `3.2.0`、`3.2`、`3`、`latest`、`3.2.0-trixie`、`3.2-trixie`、`3-trixie`、`trixie` |
| 同上 | 同上 | `--target perl` | 上面每个 tag 加 `-perl` 后缀，浮动别名为 `perl` / `trixie-perl` |
| [Dockerfile.alpine](../../Dockerfile.alpine) | `alpine:3.24` | 默认 | `3.2.0-alpine`、`3.2-alpine`、`3-alpine`、`alpine`、`3.2.0-alpine3.24`、`3.2-alpine3.24`、`3-alpine3.24`、`alpine3.24` |
| 同上 | 同上 | `--target perl` | 同样加 `-perl`：`3.2.0-alpine-perl`、`alpine-perl`、`3.2.0-alpine3.24-perl`、`alpine3.24-perl` |

基底与 nginx 官方镜像一致（trixie + 最新 Alpine），tag 形状也照其体系：版本号、
minor/major 系列、浮动别名，各自再带一份发行版后缀，变体后缀再乘一遍（nginx 的
写法是 `perl` / `alpine-perl`，不是 `latest-perl`，此处一致）。tag 清单由
[.github/scripts/image-tags.sh](../../.github/scripts/image-tags.sh) 统一生成，
发行版部分是从两个 Dockerfile 的 `BASE_IMAGE` 反解出来的——换基底时 tag 自动跟着变，
Debian 只需在脚本的版本号→代号表里补一行。

预发布 tag（`3.2.0-rc1` 等）只发版本号形态的 `3.2.0-rc1`、`3.2.0-rc1-trixie`，
不移动 `latest` / `3.2` / `3` 这类滚动 tag。

本地构建：

```sh
docker build -t tengine .                                    # 默认
docker build -t tengine:perl --target perl .                 # + perl 模块
docker build -f Dockerfile.alpine -t tengine:alpine .
docker run --rm -p 8080:80 tengine
```

两个 Dockerfile 都是多阶段：builder 跑 `fetch-deps.sh` + `build-deps.sh` 编出三大
依赖再编 Tengine，runtime 只留安装树加必要运行时库（含 `libstdc++`，xquic 需要）。
configure 参数同样出自 [configure-args.sh](configure-args.sh)，因此镜像与包功能集
一致。日志软链到 `/dev/stdout` 与 `/dev/stderr`，`STOPSIGNAL SIGQUIT`（Tengine 的
优雅退出信号），暴露 `80 443 443/udp`（HTTP/3 走 UDP）。

#### perl 变体只多一层，不是第二次编译

`ngx_http_perl_module` **始终**被编译（永远是动态模块），builder 随后把
`ngx_http_perl_module.so` 与 `nginx.pm` 挪到 `/out-perl`，默认 runtime 不拷贝它们；
`--target perl` 的 stage 从默认镜像继承（`FROM runtime`），只多装一个 perl 运行时包
再把这两个文件拷进去。因此 perl 变体的成本是一层几百 KB，而不是再跑一遍 90 分钟的
Tongsuo + xquic 编译，两个变体在 buildx 里共享全部 builder 层。

- **`tengine -V` 在默认镜像里也会列出 `--with-http_perl_module=dynamic`，但 `.so`
  不在镜像内。** 这与 nginx 官方镜像行为一致（其 slim 变体同样列着没随包发的动态
  模块），因为一次构建喂多个变体。要判断某个镜像是否真带 perl，看
  `/usr/lib/tengine/modules/ngx_http_perl_module.so` 是否存在，`verify-image.sh`
  正是这么断言的（并且反向断言默认镜像里**没有**它）。
- perl 变体的 `tengine.conf` 顶部预置了 `load_module`，开箱即用（nginx 官方 perl
  镜像只放模块、要用户自己加载）；这也让 stage 内的 `tengine -t` 真正验证了模块可加载。
- `nginx.pm` 装在 `/usr/lib/tengine/perl`（`--with-perl_modules_path`），该路径被
  编译进二进制的 `@INC`，`use nginx;` 无需额外配置。
- 系统包（rpm/deb/apk）**不含** perl 模块：`TENGINE_WITH_PERL` 默认 `no`，因为 spec
  的 `%files` 没有对应条目，rpmbuild 会因 unpackaged files 直接失败。

发布由 [docker.yml](../../.github/workflows/docker.yml) 负责，触发与打包一致
（tag `tengine-*` 自动，`workflow_dispatch` 手动且默认只构建不推送）：

- 每个 flavor × 架构在原生 runner 上构建，**按 digest 推送**，再由 `manifest` job
  用 `docker buildx imagetools create` 合成 multi-arch tag，注册表里不留架构专用 tag
- 两个变体在**同一个 job 内**先后构建（`--target default` / `--target perl`），不拆成
  独立 matrix 项：第二次构建的 builder 层已在该 runner 的 buildx 里，只需跑几条
  runtime 指令；拆开则要从 GHA cache 重新导入整套层，且两个 job 写同一 cache scope
  会互相竞争。digest 按 `<变体>-<架构>` 命名放进同一 artifact，`manifest` job 按前缀取用
- **RC 不动 `latest` / `alpine` / `3.2` / `3` 等滚动 tag**（避免 `docker pull tengine`
  拉到预发布），但 RC 的版本化 tag 与正式版一样永久留在 ghcr
- `verify` job 把发布出去的 tag 拉回来跑
  [verify-image.sh](../../.github/scripts/verify-image.sh)：断言三模块编入、Tongsuo
  在位、`tengine -t` 通过、HTTP 可访问，并真跑一段 Lua
  （`require "resty.core"` + `cjson`）验证 `lua_package_path` / `cpath` 正确；
  `--variant perl` 再额外请求一个 perl handler，用返回的 `$nginx::VERSION` 证明
  `nginx.pm` 确实从编译进 `@INC` 的路径解析成功

### ⚠️ 一次性手动操作

GHCR 包**首次推送后默认是 private**，必须手动放开一次，否则外部无法下载：

`https://github.com/<owner>?tab=packages` → `tengine` → Package settings →
Change visibility → **Public**

Release assets 无此问题，公开仓库的附件天然匿名可下。

另一项一次性操作是**配置签名密钥**，见下节。密钥未配置时 CI 照常构建并发布，
只是产物不带签名。

## 包签名

三种格式的信任模型不同，因此用了两把互不相干的密钥：

| 格式 | 签什么 | 密钥 | 在哪一步签 |
|---|---|---|---|
| rpm | 包体（写进 header） | GPG | release job，**取校验和之前** |
| apk | 包体 | abuild 的 **RSA**（非 GPG） | package job，构建时由 abuild 完成 |
| deb | — | — | 不签 |

**deb 不签是有意为之，不是遗漏。** `dpkg-sig` 早已废弃，Debian 的信任模型是签
仓库的 `Release` 文件，而这需要先有一个包仓库。在仓库建起来之前，覆盖 deb 的唯一
手段是下面的校验和签名。

此外 `SHA256SUMS` 与 `SHA256SUMS.debug` 各有一份 detached GPG 签名（`.asc`），
这是三种格式通用的兜底校验途径。

### 生成并配置密钥（一次性）

GPG 密钥，用于 rpm 包体与校验和：

```sh
gpg --batch --gen-key <<'EOF'
Key-Type: RSA
Key-Length: 4096
Name-Real: Tengine Packaging
Name-Email: tengine@taobao.net
Expire-Date: 0
Passphrase: <改成你的口令>
EOF

gpg --armor --export-secret-keys tengine@taobao.net   # -> secret GPG_PRIVATE_KEY
gpg --list-keys --with-colons tengine@taobao.net \
    | awk -F: '$1=="pub"{print $5}'                   # -> variable GPG_KEY_ID
```

abuild 的 RSA 密钥，用于 apk：

```sh
openssl genrsa -out tengine-packaging.rsa 4096        # -> secret APK_PRIVKEY
```

在仓库的 Settings → Secrets and variables → Actions 中配置：

| 名称 | 类型 | 内容 |
|---|---|---|
| `GPG_PRIVATE_KEY` | secret | 上面导出的 ASCII armored 私钥全文 |
| `GPG_PASSPHRASE` | secret | GPG 私钥口令（无口令则不设） |
| `GPG_KEY_ID` | variable | 长格式 key id；钥匙环里只有一把时可省略 |
| `APK_PRIVKEY` | secret | `tengine-packaging.rsa` 全文 |

> 文件名 `tengine-packaging.rsa` 不可随意改：abuild 会把 basename 记进 apk，
> `apk` 据此在 `/etc/apk/keys/` 里找对应公钥。改名需同步改 CI 与安装说明。

两把公钥都会作为 release 资产自动发布（`tengine-packaging-key.asc` 与
`tengine-packaging.rsa.pub`），无需手工上传。

### 本地试签

`sign-release.sh` 在 `GPG_PRIVATE_KEY` 未设置时**所有子命令都是 no-op 且返回 0**，
这正是 fork 无密钥仍能构建的原因。本地试签：

```sh
export GPG_PRIVATE_KEY="$(gpg --armor --export-secret-keys tengine@taobao.net)"
export GPG_PASSPHRASE=...
packages/build/sign-release.sh rpms dist          # 签目录下所有 rpm
packages/build/sign-release.sh detach dist/SHA256SUMS
packages/build/sign-release.sh pubkey /tmp/key.asc
```

apk 侧则是给 `build.sh` 指一个私钥：

```sh
TENGINE_APK_PRIVKEY=$PWD/tengine-packaging.rsa packages/build/build.sh apk
```

未指定时 `build.sh` 仍会签，但用的是当场生成的一次性密钥——等同未签名，
安装时必须 `--allow-untrusted`。

### 本机构建

```sh
packages/build/build.sh auto     # 按 /etc/os-release 自动选择
packages/build/build.sh rpm      # 需要 rpm-build
packages/build/build.sh deb      # 需要 build-essential debhelper
packages/build/build.sh apk      # 需要 alpine-sdk
```

除各自的打包工具外，本机构建还需要 **cmake ≥ 3.5、C++ 编译器、perl、curl**
（分别用于 xquic、xquic 链接、Tongsuo 的 Configure、拉取依赖源码）。首次构建会
下载约 17 MB 依赖源码到 `dist/deps/`，之后按 sha256 复用，可离线重复构建。

### 常用选项

```sh
# 指定厂商 dist tag，得到 ...-20260604232239.el7u2.x86_64.rpm
packages/build/build.sh rpm --dist .el7u2

# 固定时间戳（多架构构建时保持 Release 一致）
packages/build/build.sh docker all --timestamp 20260604232239

# 启用额外模块（Tongsuo / xquic / Lua 默认已开）
packages/build/build.sh rpm --with zstd --with geoip
```

## 功能集与第三方依赖

**默认启用**：http_ssl、http_v2、realip、addition、auth_request、dav、flv、
gunzip、gzip_static、mp4、random_index、secure_link、stub_status、sub、mail(+ssl)、
stream(+ssl/realip/ssl_preread/sni)、threads、file-aio、pcre-jit，以及 Tengine 模块
backtrace、debug_pool/timer/conn、concat、footer_filter、proxy_connect、reqstat、
slice、sysguard、trim_filter、upstream_check、upstream_consistent_hash、
upstream_dynamic、upstream_dyups、upstream_iwrr、upstream_keepalive(Tengine 版)、
upstream_session_sticky、upstream_vnswrr、user_agent、multi_upstream、slab_stat，
**以及下面三块完备能力**：

| 能力 | 模块 | 依赖（源码构建） |
|---|---|---|
| NTLS / 国密 | `ngx_tongsuo_ntls` | Tongsuo，静态链入 |
| QUIC / HTTP-3 | `ngx_http_xquic_module` | xquic + Tongsuo |
| Lua 脚本 | `ngx_http_lua_module` | LuaJIT + resty 运行时库 |

### 依赖版本

全部 pin 在 [deps.env](deps.env)，升级只改这一处；改完跑
`packages/build/fetch-deps.sh --print-checksums` 刷新 sha256。

| 依赖 | 版本 | 说明 |
|---|---|---|
| Tongsuo | `8.4.0` | OpenSSL 3.0.3 基线；`enable-ntls no-shared -fPIC` |
| xquic | `v1.9.4` | cmake `-DSSL_TYPE=babassl`，需 CMake ≥ 3.5 |
| luajit2 | `v2.1-20260724` | openresty fork，`CFLAGS=-fPIC` |
| lua-resty-core | `v0.1.32` | **必需**，缺它 tengine 直接起不来 |
| lua-resty-lrucache | `v0.15` | resty.core 依赖 |
| lua-cjson | `2.1.0.19` | C 模块 `cjson.so` |
| lua-resty-string / lock / dns / http | `v0.19` / `v0.09` / `v0.23` / `v0.18.0` | 常用运行时库 |

构建流程由 [fetch-deps.sh](fetch-deps.sh)（下载 + 校验）与
[build-deps.sh](build-deps.sh)（编译 + 暂存）承担，编译顺序与本仓库 CI
[test-ntls.yml](../../.github/workflows/test-ntls.yml) 一致：LuaJIT → Tongsuo →
xquic（用 Tongsuo 的静态库）→ `make clean` 后把 Tongsuo 源码树交给 Tengine 的
`--with-openssl` 二次编译。

### 包内布局

```
<libdir>/tengine/libxquic.so            随包分发，rpath 指向此目录
<libdir>/tengine/libluajit-5.1.so.*
<libdir>/tengine/lualib/cjson.so        lua_package_cpath
/usr/share/tengine/lualib/**.lua        lua_package_path
/usr/share/tengine/licenses/            各上游依赖许可
```

`tengine.conf` 里已配好 `lua_package_path` / `lua_package_cpath`；
`conf.d/default.conf` 尾部带注释版的 HTTP/3 与 NTLS server 示例（默认不启用，
因为都需要证书，开着会让 `tengine -t` 失败）。

### ⚠️ Tongsuo 静态链入的后果

包与镜像**不再使用系统 OpenSSL**（NTLS 只能通过 `--with-openssl` 拿到，见
[ngx_tongsuo_ntls/config](../../modules/ngx_tongsuo_ntls/config)）。因此发行版的
OpenSSL 安全更新**不覆盖本包**，Tongsuo 出安全公告时必须重新打包发布。

### 可选项

```sh
# 额外模块
packages/build/build.sh rpm --with zstd --with geoip

# 关掉重依赖（仅用于排查构建问题，会产出功能不完备的包）
packages/build/build.sh rpm --without xquic
packages/build/build.sh rpm --without tongsuo --without xquic
packages/build/build.sh rpm --without lua
```

**仍未纳入**：`mod_dubbo` / `mod_xudp` / `ngx_ingress_module` 等需要额外基础设施
的模块，请用独立 configure 流程自建。

## 平台差异

- **musl（Alpine）**：`ngx_backtrace_module` 依赖 `execinfo.h` 的 `backtrace()`，
  musl 不提供且其 `config` 会直接中断 configure，因此 Alpine 构建关闭该模块。
- **构建工具链**：完备功能集额外要求 **CMake ≥ 3.5**（xquic）、**C++ 编译器**
  （xquic 链 libstdc++）、**Perl**（Tongsuo 的 Configure）。三套配方的
  BuildRequires / Build-Depends / makedepends 与
  [build.sh](build.sh) 的容器 bootstrap 都已带上。
- **-Werror**：源码树默认追加 `-Werror`（[auto/cc/gcc](../../auto/cc/gcc)）。发行版
  加固 flag 叠加任意 gcc 版本几乎必然触发新告警，三套配方与两个 Dockerfile 均以
  `--with-cc-opt="... -Wno-error"` 覆盖。
- **xquic 的 rpath**：[ngx_http_xquic_module/config](../../modules/ngx_http_xquic_module/config)
  会把 `--with-xquic-lib` 的字面值写进 `-Wl,-rpath=`。打包时链接目录（临时构建树）
  与安装目录不同，因此新增了 `--with-xquic-rpath=`（默认等于 `--with-xquic-lib`，
  源码构建行为不变）。
- **PCRE**：EL9+/Fedora 33+/openSUSE Leap 15.5+ 用 pcre2-devel，更老的用 pcre-devel。
- **libdir**：RPM 走 `%{_libdir}`（x86_64 为 `/usr/lib64`），deb/apk 固定 `/usr/lib`。
  `tengine.conf` 中的 `@TENGINE_LIBDIR@` 占位符由各配方在安装阶段替换。
- **私有库的依赖生成**：`libxquic.so` / `libluajit` 是包私有库。rpm 用
  `__provides_exclude_from` + `__requires_exclude` 双向排除，deb 用
  `dh_shlibdeps -l... --ignore-missing-info` 配 `dh_makeshlibs -X`，否则包会
  因"找不到 libxquic.so 的提供者"而装不上。

## 文件说明

```
packages/build/
├── build.sh              统一入口（POSIX sh，可在容器内自举）
├── configure-args.sh     全平台共享的 configure 参数与路径布局
│                         （--print-ld-opt / --print-openssl-opt 输出含空格的参数）
├── deps.env              第三方依赖版本、仓库与 sha256（唯一真源）
├── fetch-deps.sh         下载 + 校验依赖源码（--print-checksums 用于升级）
├── build-deps.sh         编译 Tongsuo / xquic / LuaJIT / resty 库，产出 deps-env.sh
├── collect-release.sh    把各 artifact 扁平成 Release 目录 + SHA256SUMS
│                         （调试符号分流到 <outdir>-debug + SHA256SUMS.debug）
├── sign-release.sh       GPG 签名：rpm 包体、校验和 detached 签名、导出公钥
│                         （无 GPG_PRIVATE_KEY 时全部 no-op，fork 照常构建）
├── conf/
│   ├── tengine.conf      主配置（FHS 绝对路径 + lua_package_path/cpath）
│   ├── conf.d/default.conf   含注释版 HTTP/3 与 NTLS 示例
│   ├── tengine.service   systemd unit
│   ├── tengine.openrc    Alpine OpenRC 脚本
│   └── tengine.logrotate
├── rpm/tengine.spec      RHEL + SLES 共用 spec
├── deb/debian/           Debian/Ubuntu 打包目录
└── apk/APKBUILD          Alpine 包

仓库根：
├── Dockerfile            debian-slim 镜像（多阶段）
├── Dockerfile.alpine     alpine 镜像（多阶段）
└── .github/
    ├── scripts/
    │   ├── image-tags.sh         镜像 tag 清单（发行版部分反解自 Dockerfile）
    │   └── verify-image.sh       镜像冒烟校验（含真跑 Lua）
    └── workflows/
        ├── package.yml   包矩阵 + Release 上传
        └── docker.yml    镜像构建 + ghcr 发布
```

> `packages/debian/` 是历史遗留的旧 deb 打包（二进制名为 `nginx`），与本目录无关。
