<h1 align="center" style="border-bottom: none">
    <br>Tengine
</h1>

<p align="center">Visit <a href="https://tengine.taobao.org" target="_blank">tengine.taobao.org</a> for the full documentation, examples and guides.</p>

<div align="center">

[![GitHub license](https://img.shields.io/github/license/alibaba/tengine.svg)](https://github.com/alibaba/tengine/blob/main/LICENSE)
[![GitHub stars](https://img.shields.io/github/stars/alibaba/tengine.svg)](https://github.com/alibaba/tengine/stargazers)
[![GitHub stars](https://img.shields.io/badge/contributions-welcome-orange.svg)](https://github.com/alibaba/tengine/blob/main/CONTRIBUTING.md)
[![Build Status](https://github.com/alibaba/tengine/actions/workflows/ci.yml/badge.svg)](https://github.com/alibaba/tengine/actions/workflows/ci.yml)

</div>


## Introduction
Tengine is a high-performance web server and reverse proxy originated by [Taobao](https://en.wikipedia.org/wiki/Taobao), the largest e-commerce website in Asia. It offers HTTP/3, Kubernetes Ingress support, zero-downtime dynamic configuration, active upstream health checks, and NTLS/TLCP (SM2/SM3/SM4), while remaining 100% compatible with [nginx](https://nginx.org). Tengine has proven to be very stable and efficient on some of the top 100 websites in the world, including [taobao.com](https://www.taobao.com) and [tmall.com](https://www.tmall.com).

Tengine has been an open source project since December 2011. It is being actively developed by the Tengine team, whose core members are from Taobao, Sogou and other Internet companies. Tengine is a community effort and everyone is encouraged to [get involved](https://github.com/alibaba/tengine).

## Features
* All features of nginx-1.31.5 are inherited, i.e., it is 100% compatible with nginx.
* Dynamically configure the servers, locations and upstreams without reloading or restarting worker processes with [tengine-ingress](https://github.com/alibaba/tengine-ingress), the Kubernetes Ingress controller for Tengine.
* HTTP/3 support (QUIC v1 and draft-29) with [xquic](https://github.com/alibaba/xquic), including connection management and multiplexing for lower latency and higher resilience to packet loss on unstable networks.
* High-speed UDP transmission with kernel-bypass.
* Dynamically configure different TLS protocols for different server names with [tengine-ingress](https://github.com/alibaba/tengine-ingress).
* Dynamically configure timeout setting, SSL Redirects, CORS and enabling/disabling robots for the server and location with [tengine-ingress](https://github.com/alibaba/tengine-ingress).
* Dynamically configure HTTP routing based on multiple values of a specific header, cookie or query parameter with [tengine-ingress](https://github.com/alibaba/tengine-ingress).
* Dynamically configure HTTP routing based on multiple upstream according to weight with [tengine-ingress](https://github.com/alibaba/tengine-ingress).
* Dynamically configure HTTP routing based on modulo operation for a specific header, cookie or query parameter with [tengine-ingress](https://github.com/alibaba/tengine-ingress).
* Dynamically configure HTTP routing to add/append custom header or add query parameter in the HTTP request to the upstream with [tengine-ingress](https://github.com/alibaba/tengine-ingress).
* Dynamically configure HTTP routing to add custom header in the HTTP response to the client with [tengine-ingress](https://github.com/alibaba/tengine-ingress).
* Dynamically configure failover to a backup upstream or a redirect by response status code with [tengine-ingress](https://github.com/alibaba/tengine-ingress).
* Support the CONNECT HTTP method for forward proxy.
* Support asynchronous OpenSSL, using hardware such as QAT for HTTPS acceleration.
* NTLS/TLCP (dual-certificate TLS, GM/T 0024) support with the Chinese SM2/SM3/SM4 algorithms via [Tongsuo](https://github.com/Tongsuo-Project/Tongsuo).
* Zstandard (zstd) response compression, and serving pre-compressed static files.
* Enhanced operations monitoring, such as asynchronous log & rollback, DNS caching, memory usage, etc.
* Fine-grained timing statistics variables for the request and for each stage of the upstream interaction.
* Support server_name in Stream module.
* More load balancing methods, e.g., consistent hashing, session persistence, and a weighted round-robin with O(1) time and O(n) memory.
* Input body filter support. It's quite handy to write Web Application Firewalls using this mechanism.
* Dynamic scripting language (Lua) support, which is very efficient and makes it easy to extend core functionalities.
* Limits retries for upstream servers (proxy, memcached, fastcgi, scgi, uwsgi).
* Includes a mechanism to support standalone processes.
* Protects the server in case system load or memory use goes too high.
* Multiple CSS or JavaScript requests can be combined into one request to reduce download time.
* Removes unnecessary white spaces and comments to reduce the size of a page.
* Active health checks of upstream servers can be performed.
* The number of worker processes and CPU affinities can be set automatically.
* The limit_req module is enhanced with whitelist support and more conditions are allowed in a single location.
* Enhanced diagnostic information makes it easier to troubleshoot errors.
* More user-friendly command lines, e.g., showing all compiled-in modules and supported directives.
* Expiration times can be specified for certain MIME types.
* Receives HTTP traffic on the TLS listener with option.
* Debugging HTTP connection usage.
* Appends content to the response body.
* ...

## Installation

### Container image

Multi-arch (amd64 + arm64) images with the full feature set -- Tongsuo (NTLS), xquic (QUIC/HTTP-3) and Lua -- are published on every release:

```bash
docker pull ghcr.io/alibaba/tengine:latest         # Debian based
docker pull ghcr.io/alibaba/tengine:latest-alpine  # Alpine based, smaller

docker run --rm -p 8080:80 ghcr.io/alibaba/tengine:latest
```

The server runs as `/usr/sbin/tengine` with `/etc/tengine/tengine.conf`; drop your own server blocks into `/etc/tengine/conf.d/`.

### Distribution packages

Every release ships `.rpm`, `.deb` and `.apk` packages for the mainstream distributions (RHEL/Rocky/Alma/Anolis/openEuler/SLES, Debian/Ubuntu, Alpine) on both x86_64 and aarch64, attached to the [release page](https://github.com/alibaba/tengine/releases):

```bash
dnf install https://github.com/alibaba/tengine/releases/download/3.2.0/tengine-3.2.0-<ts>.el9.x86_64.rpm
```

These packages install alongside a distribution nginx without conflicting. See [packages/build/README.md](packages/build/README.md) for the exact feature set, how to build them yourself, and how the container images are produced.

### From source
Tengine can be downloaded at [https://tengine.taobao.org/download/tengine.tar.gz](https://tengine.taobao.org/download/tengine.tar.gz). You can also checkout the latest source code from GitHub at [https://github.com/alibaba/tengine](https://github.com/alibaba/tengine)

To install Tengine, just follow these three steps:
```bash
./configure
make
sudo make install
```

By default, it will be installed to _/usr/local/tengine_. Everything is named after Tengine, which matches the layout used by the `.rpm`/`.deb`/`.apk` packages and the container images:

| | Default path |
|---|---|
| binary | `/usr/local/tengine/sbin/tengine` |
| configuration | `/usr/local/tengine/conf/tengine.conf` |
| pid file | `/usr/local/tengine/logs/tengine.pid` |
| error log | `/usr/local/tengine/logs/error.log` |
| access log | `/usr/local/tengine/logs/access.log` |
| dynamic modules | `/usr/local/tengine/modules` |

You can use the __'--prefix'__ option to specify the root directory, or `--sbin-path`, `--conf-path`, `--pid-path`, `--error-log-path` and `--http-log-path` to place the individual files.
If you want to know all the _'configure'_ options, you should run __'./configure --help'__ for help.

> **Upgrading from 3.1.0 or earlier.** Those releases installed to
> _/usr/local/nginx_ as `sbin/nginx` driven by `conf/nginx.conf`. Because
> 3.2.0 writes to different paths, `make install` does not replace that
> install -- the old binary stays on disk and keeps serving traffic, and
> running it still reports the old version, which easily reads as "the
> upgrade did not take effect". After switching over, stop and remove the old
> install, and update any systemd unit, init script or log rotation config
> still pointing at the old paths. `configure` prints a warning when it finds
> an install at `/usr/local/nginx/sbin/nginx`.
>
> To keep the previous layout instead, pass the old paths explicitly:
>
> ```bash
> ./configure --prefix=/usr/local/nginx \
>     --sbin-path=/usr/local/nginx/sbin/nginx \
>     --conf-path=/usr/local/nginx/conf/nginx.conf \
>     --pid-path=/usr/local/nginx/logs/nginx.pid
> ```

A plain `./configure` builds without Tongsuo, xquic and Lua -- those need their own libraries. To reproduce the full feature set of the released packages and images, use the packaging helpers:

```bash
packages/build/fetch-deps.sh                       # download pinned sources
packages/build/build-deps.sh --libdir /usr/lib/tengine
. dist/deps-build/deps-env.sh
./configure $(sh packages/build/configure-args.sh) \
    --with-cc-opt="-Wno-error" \
    --with-ld-opt="$(sh packages/build/configure-args.sh --print-ld-opt)" \
    --with-openssl-opt="$(sh packages/build/configure-args.sh --print-openssl-opt)"
make
```

## Documentation
The homepage of Tengine is at [https://tengine.taobao.org/](https://tengine.taobao.org/)
You can access [https://tengine.taobao.org/documentation.html](https://tengine.taobao.org/documentation.html) for more information.

## Contact
[https://github.com/alibaba/tengine/issues](https://github.com/alibaba/tengine/issues)

Dingtalk user group: 23394285

## License

[BSD-2-Clause License](https://github.com/alibaba/tengine/blob/master/LICENSE)

<h1 align="center" style="border-bottom: none">
    <a href="https://tengine.taobao.org" target="_blank"><img alt="Tengine" src="/docs/image/tengine-logo.png" width="294"></a>
</h1>
