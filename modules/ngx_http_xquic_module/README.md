# ngx_http_xquic_module

Tengine ngx_http_xquic_module 主要用于在服务端启用 QUIC/HTTP3 监听服务。

* [编译](#编译)
* [证书配置（必需）](#证书配置必需)
* [配置与启动](#配置与启动)
* [浏览器使用 HTTP3](#浏览器使用-http3)
* [启动失败排查](#启动失败排查)

# 编译

ngx_http_xquic_module 编译依赖

依赖库：

* Tongsuo: https://github.com/Tongsuo-Project/Tongsuo
* xquic: https://github.com/alibaba/xquic

## XQUIC 版本兼容性

Tengine 与 XQUIC 的兼容性主要取决于 CID 和默认连接设置等关键公开 C API。
下表中的 API 兼容范围表示相同的函数签名世代；推荐版本是经过 Tengine 构建和
HTTP/3 集成测试验证的组合。未列出的组合不承诺兼容。

| Tengine 版本 | 关键 XQUIC API 兼容范围 | 推荐并验证的 XQUIC 版本 | 说明 |
| --- | --- | --- | --- |
| 3.1.0 | v1.8.0 之前 | v1.6.0 | 使用不带 `xqc_engine_t` 参数的旧式 CID 和连接设置 API；不兼容 v1.8.0 及后续版本。 |
| 3.2.0 及 master | v1.8.0 至 v1.9.6 | v1.9.6 | 使用 engine-scoped CID 和连接设置 API；v1.9.6 是当前打包和 CI 基线。 |

XQUIC v1.8.0 将 `xqc_scid_str`、`xqc_dcid_str` 和
`xqc_server_set_conn_settings` 等接口改为接收 `xqc_engine_t`，这是两代
API 的兼容边界。使用发布包时应优先选择表中的推荐组合；API 兼容不
代表未经测试的版本组合具备完整的运行时兼容性。

```shell
# 下载 Tongsuo，示例中下载 8.4.0 版本
wget -c "https://github.com/Tongsuo-Project/Tongsuo/archive/refs/tags/8.4.0.tar.gz"
tar -xf 8.4.0.tar.gz

# 下载与当前 Tengine API 兼容并经过验证的 xquic 1.9.6
wget -c "https://github.com/alibaba/xquic/archive/refs/tags/v1.9.6.tar.gz"
tar -xf v1.9.6.tar.gz

# 下载 Tengine 3.0.0 以上版本，示例从 master 获取最新版本，也可下载指定版本
git clone git@github.com:alibaba/tengine.git

# 编译 Tongsuo
cd Tongsuo-8.4.0
./config --prefix=/usr/local/babassl
make
make install
export SSL_TYPE_STR="babassl"
export SSL_PATH_STR="${PWD}"
export SSL_INC_PATH_STR="${PWD}/include"
export SSL_LIB_PATH_STR="${PWD}/libssl.a;${PWD}/libcrypto.a"
cd ../../

# 编译 xquic 库
cd xquic-1.9.6/
mkdir -p build; cd build
# 追加 -DXQC_ENABLE_TESTING=1 可一并编出 test_client，用于后文的连通性验证
cmake -DXQC_SUPPORT_SENDMMSG_BUILD=1 -DXQC_ENABLE_BBR2=1 -DXQC_ENABLE_RENO=1 -DSSL_TYPE=${SSL_TYPE_STR} -DSSL_PATH=${SSL_PATH_STR} -DSSL_INC_PATH=${SSL_INC_PATH_STR} -DSSL_LIB_PATH=${SSL_LIB_PATH_STR} ..
make
cp "libxquic.so" /usr/local/lib/
cd ..

# 编译 Tengine
cd tengine

# 注：xquic 依赖 ngx_http_v2_module，需要参数 --with-http_v2_module
./configure \
  --prefix=/usr/local/tengine \
  --sbin-path=sbin/tengine \
  --with-xquic-inc="../xquic-1.9.6/include" \
  --with-xquic-lib="../xquic-1.9.6/build" \
  --with-http_v2_module \
  --without-http_rewrite_module \
  --add-module=modules/ngx_http_xquic_module \
  --with-openssl="../Tongsuo-8.4.0"

make
make install
```

# 证书配置（必需）

`xquic_ssl_certificate` 与 `xquic_ssl_certificate_key` 由 xquic engine 在 `http` 级别统一加载，
**只要配置中出现 `listen ... xquic`，这两条指令就必须配置且文件可读**，否则 Tengine 启动或
`tengine -t` 会直接失败：

```
nginx: [emerg] no "xquic_ssl_certificate" is defined for the "listen ... xquic" directive in conf/tengine.conf:97
nginx: [emerg] cannot read xquic_ssl_certificate "/usr/local/tengine/ssl/default-fake-certificate.pem" (2: No such file or directory)
```

几点说明：

* 引擎级证书与 `server` 级 `ssl_certificate` 相互独立，xquic 不会复用 `server` 段的 TLS 证书，
  也不存在缺失时自动回退的行为。多域名场景下 `server` 段仍需各自配置 `ssl_certificate`，
  引擎级证书仅作为握手时的兜底证书。
* 证书与私钥可以合并在同一个 PEM 文件中（两条指令指向同一路径，如下文示例），也可以拆成
  两个文件分别配置。
* **推荐使用绝对路径。** 相对路径按配置文件所在目录展开（与 `ssl_certificate` 一致），
  例如 `-p /usr/local/tengine/ -c conf/tengine.conf` 下 `ssl/x.pem` 展开为
  `/usr/local/tengine/conf/ssl/x.pem`，而不是相对进程的工作目录。
* **私钥必须对 worker 运行用户（`user` 指令指定的用户）可读**：xquic 是在 worker 降权之后才读取
  私钥的，若仅 root 可读，则 `tengine -t` 通过、master 启动正常，但 worker 会以
  `fatal code 2` 退出，导致该实例**所有**监听端口（包括纯 HTTP 的 80）不可用。

## session ticket key（可选，影响 0-RTT）

`xquic_ssl_session_ticket_key` 指定一份所有 worker 共享的 session ticket 密钥文件。
未配置时启动会有一条告警：

```
nginx: [warn] no "xquic_ssl_session_ticket_key" is defined, 0-RTT will be unavailable with multiple workers
```

此时每个 worker 各自生成随机密钥，A worker 签发的 ticket 在 B worker 上无法解密，
`worker_processes` 大于 1 时 0-RTT 实际不可用（其余功能不受影响）。需要 0-RTT 时生成一份
48 字节密钥并配置：

```shell
openssl rand 48 > /usr/local/tengine/ssl/session_ticket.key
chown root:nobody /usr/local/tengine/ssl/session_ticket.key
chmod 640 /usr/local/tengine/ssl/session_ticket.key
```

```nginx
http {
    xquic_ssl_session_ticket_key /usr/local/tengine/ssl/session_ticket.key;
}
```

该文件同样在 worker 内读取，权限要求与私钥一致；读取失败只降级 0-RTT，不会导致 worker 退出。
多机部署若要跨机复用 ticket，各机器需使用同一份密钥，并定期轮转。

## 生成自签 fake 证书

以示例中的 `/usr/local/tengine/ssl/default-fake-certificate.pem` 为例，把证书和私钥合并写入
同一个 PEM 文件：

```shell
mkdir -p /usr/local/tengine/ssl

# 注：-addext 需要 OpenSSL 1.1.1 及以上版本
openssl req -x509 -nodes -newkey rsa:2048 -days 3650 \
  -keyout /tmp/fake.key -out /tmp/fake.crt \
  -subj "/O=Tengine/CN=Tengine Fake Certificate" \
  -addext "subjectAltName=DNS:tengine.fake,DNS:*.tengine.fake"

# 合并为单个 PEM：xquic_ssl_certificate 与 xquic_ssl_certificate_key 可共用此文件
cat /tmp/fake.crt /tmp/fake.key > /usr/local/tengine/ssl/default-fake-certificate.pem
rm -f /tmp/fake.key /tmp/fake.crt

# 确保 worker 用户可读，此处以 worker 运行用户为 nobody 为例
chown root:nobody /usr/local/tengine/ssl/default-fake-certificate.pem
chmod 640 /usr/local/tengine/ssl/default-fake-certificate.pem
```

自签证书不被浏览器信任，仅适用于 `test_client` 等本地联调；浏览器访问需按后文
[浏览器使用 HTTP3](#浏览器使用-http3) 配置受信证书。

# 配置与启动

精简示例配置，其中 default-fake-certificate.pem 为上一节生成的证书。

```nginx
worker_processes  1;

error_log  logs/error.log debug;

events {
    worker_connections  1024;
}

xquic_log   "pipe:rollback /usr/local/tengine/logs/tengine-xquic.log baknum=10 maxsize=1G interval=1d adjust=600" info;

http {
    xquic_ssl_certificate        /usr/local/tengine/ssl/default-fake-certificate.pem;
    xquic_ssl_certificate_key    /usr/local/tengine/ssl/default-fake-certificate.pem;

    server {
        listen 2443 xquic reuseport;

        location / {
        }
    }
}
```

启动 tengine

```shell
/usr/local/tengine/sbin/tengine -p /usr/local/tengine/ -c conf/tengine.conf
```

启动后 tengine 监听 2443 UDP 端口，此端口可以接收 HTTP3 请求，可以通过编译 xquic 自带的 `test_client` 测试（cmake 编译 xquic 时需要带 `-DXQC_ENABLE_TESTING=1` 参数）

```shell
./test_client -a 127.0.0.1 -p 2443 -u https://domain/
```

更为详细的指令可参考官网文档 [XQUIC模块](https://tengine.taobao.org/document_cn/xquic_cn.html)

# 浏览器使用 HTTP3

**注意：浏览器访问需要确保证书受信。**

浏览器默认不会使用 `HTTP3` 请求，需要服务端响应包头 `Alt-Svc` 进行升级说明，浏览器通过响应包头感知到服务端是支持 `HTTP3` 的，下次请求会尝试使用 `HTTP3`。

```nginx
worker_processes  1;

user root;

error_log  logs/error.log debug;

events {
    worker_connections  1024;
}

xquic_log   "pipe:rollback /usr/local/tengine/logs/tengine-xquic.log baknum=10 maxsize=1G interval=1d adjust=600" info;

http {
    xquic_ssl_certificate        /usr/local/tengine/ssl/default-fake-certificate.pem;
    xquic_ssl_certificate_key    /usr/local/tengine/ssl/default-fake-certificate.pem;

    server {
        listen 2443 xquic reuseport;

        location / {
        }
    }

    server {
        listen 80 default_server reuseport backlog=4096;
        listen 443 default_server reuseport backlog=4096 ssl http2;
        listen 443 default_server reuseport backlog=4096 xquic;

        server_name s1.test.com;

        add_header Alt-Svc 'h3=":443"; ma=2592000,h3-29=":443"; ma=2592000' always;

        ssl_certificate     /etc/ingress-controller/ssl/s1.crt;
        ssl_certificate_key /etc/ingress-controller/ssl/s1.key;
    }

    server {
        listen 80;
        listen 443 ssl http2;
        listen 443 xquic;

        server_name s2.test.com;

        add_header Alt-Svc 'h3=":443"; ma=2592000,h3-29=":443"; ma=2592000' always;

        ssl_certificate     /etc/ingress-controller/ssl/s2.crt;
        ssl_certificate_key /etc/ingress-controller/ssl/s2.key;
    }
}
```

通过以上配置，浏览器访问对应域名，第一次访问 `HTTP2`，下次访问会切换至 `HTTP3`。

**注意**：

在生产环境中，出于安全性考虑，一般情况会以普通用户权限启动 `Tengine`，而 `xquic` 功能在普通用户权限下，监听端口必须配置为 1024 以上，如监听 2443 端口，那对外的四层负载均衡需要做 443 到 2443 端口的映射，`Tengine` `Server`段配置示例：

```nginx
    server {
        listen 80 default_server reuseport backlog=4096;
        listen 443 default_server reuseport backlog=4096 ssl http2;
        listen 2443 default_server reuseport backlog=4096 xquic;

        add_header Alt-Svc 'h3=":443"; ma=2592000,h3-29=":443"; ma=2592000' always;

        ssl_certificate     /etc/ingress-controller/ssl/s1.crt;
        ssl_certificate_key /etc/ingress-controller/ssl/s1.key;
    }
```

四层负载均衡配置示例：

```yaml
  type: LoadBalancer
  ports:
  - port: 80
    name: tengine-tcp-80
    protocol: TCP
    targetPort: 80
  - port: 443
    name: tengine-tcp-443
    protocol: TCP
    targetPort: 443
  - port: 443
    name: tengine-udp-443
    protocol: UDP
    targetPort: 2443
  selector:
    app: tengine
```

对用户来讲，还是通过 443 端口访问，通过四层负载均衡设备，转换为 `Tengine` 的 2443 端口。

# 启动失败排查

xquic 的证书由 engine 在 worker 内加载，因此证书类问题的表现与普通 `ssl_certificate` 不同：
**一旦 worker 初始化失败，master 会判定为 `fatal code 2` 且不再重启 worker，该实例所有监听端口
（包括纯 HTTP 的 80）全部不可用**。排查时先 `grep xquic` 过滤 `error_log`，`[emerg]` 那条才是根因，
`[alert] ... fatal code 2` 只是结果。

| 日志 | 原因 | 处置 |
| --- | --- | --- |
| `[emerg] no "xquic_ssl_certificate" is defined for the "listen ... xquic" directive in <file>:<line>` | 有 `listen ... xquic` 但 `http` 段未配置引擎级证书 | 按[证书配置](#证书配置必需)补齐两条指令；不需要 HTTP/3 则去掉 `listen` 上的 `xquic` 参数与 `Alt-Svc` 响应头 |
| `[emerg] cannot read xquic_ssl_certificate "<path>" (2: No such file or directory)` | 路径不存在或相对路径展开位置与预期不同 | 改用绝对路径核对 |
| `[emerg] \|xquic\|ngx_xquic_engine_init: cannot read xquic_ssl_certificate_key "<path>"\| (13: Permission denied)` | 文件存在，但 worker 运行用户不可读（`tengine -t` 与 master 均能通过） | `chown root:<worker 用户>` + `chmod 640` |
| `[warn] no "xquic_ssl_session_ticket_key" is defined, ...` | 未配置共享 ticket 密钥 | 仅影响 0-RTT，见 [session ticket key](#session-ticket-key可选影响-0-rtt) |

前两类在配置解析阶段就会拦截，`tengine -t` 与 reload 都能提前发现，reload 被拒绝时旧 worker
继续提供服务。第三类只能在 worker 降权后暴露，所以 `tengine -t` 通过并不代表私钥权限没问题。

多 worker 下真正的 `[emerg]` 容易被大量 `[alert]`/`[notice]` 淹没，排查时可临时设
`worker_processes 1;` 复现，日志会清晰很多。
