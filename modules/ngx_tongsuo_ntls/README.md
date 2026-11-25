# Quick Start

## Install Tengine
1. Get Tongsuo

NTLS (TLCP and GM/T 0024) is based on Tongsuo.

The base NTLS directives (`enable_ntls`, `ssl_sign_certificate(_key)`,
`ssl_enc_certificate(_key)`) work with Tongsuo 8.3.x and later. The newer
features use APIs introduced in later releases: `ssl_force_ntls` relies on
`SSL_enable_force_ntls()` (8.4.0), while `ssl_ntls_cert_key_usage_check`
and the `$ssl_client_enc_cert` / `$ssl_client_raw_enc_cert` variables rely
on `SSL_CTX_set_ntls_cert_key_usage_check()` and
`SSL_get0_peer_enc_certificate_ntls()` (8.5.0); 8.5.0 also enables the
GB/T 20518 sign/enc keyUsage check by default.

On older Tongsuo the newer features are masked off, so Tengine stays
buildable and the base NTLS behaviour is unchanged.  Each API is detected
at configure time, not by the version number (which the 8.5.0
pre-releases share with the release), so against 8.3.x
`ssl_force_ntls` and `ssl_ntls_cert_key_usage_check` are rejected at
start-up with a clear "requires Tongsuo <version> or later" error, and
the two variables are always empty; against 8.4.x, `ssl_force_ntls` works
as documented while the other two still degrade the same way. Use the
8.5.0 release or later for full functionality.
```bash
git clone https://github.com/Tongsuo-Project/Tongsuo.git
```

2. Get Tengine

```bash
git clone https://github.com/alibaba/tengine.git
```

3. Build Tengine

- Add ngx_tongsuo_ntls module
- Set OpenSSL library path to Tongsuo
- Set build options for Tongsuo: enable-ntls

```bash
cd tengine

./configure --add-module=modules/ngx_tongsuo_ntls \
    --with-openssl=../Tongsuo \
    --with-openssl-opt="--strict-warnings --api=1.1.1 enable-ntls" \
    --with-http_ssl_module --with-stream \
    --with-stream_ssl_module --with-stream_sni

make -j
sudo make install
```

For Tongsuo 8.3.x drop `--api=1.1.1`: that compatibility level was only
added to the Tongsuo Configure apitable in 8.4.0, and passing it to 8.3.x
aborts with "Unsupported api compatibility level: 1.1.1".

```bash
./configure --add-module=modules/ngx_tongsuo_ntls \
    --with-openssl=../Tongsuo \
    --with-openssl-opt="--strict-warnings enable-ntls" \
    --with-http_ssl_module --with-stream \
    --with-stream_ssl_module --with-stream_sni
```

## Run Tengine

Example of nginx.conf:
```
worker_processes  1;

events {
    worker_connections  1024;
}

http {
    include       mime.types;
    default_type  application/octet-stream;

    server {
        listen       443 ssl;
        server_name  localhost;

        enable_ntls  on;
        ssl_sign_certificate        server_sign.crt;
        ssl_sign_certificate_key    server_sign.key;
        ssl_enc_certificate         server_enc.crt;
        ssl_enc_certificate_key     server_enc.key;

        location / {
            return 200 "body $ssl_protocol:$ssl_cipher";
        }
    }
}

stream {
     server {
        listen       8443 ssl;

        enable_ntls  on;
        ssl_sign_certificate        server_sign.crt;
        ssl_sign_certificate_key    server_sign.key;
        ssl_enc_certificate         server_enc.crt;
        ssl_enc_certificate_key     server_enc.key;

        return "body $ssl_protocol:$ssl_cipher";
    }
}
```

## Test NTLS

We need NTLS client to test tengine NTLS server. NTLS client is provided by
Tongsuo, so we need install Tongsuo firstly.
```bash
git clone https://github.com/Tongsuo-Project/Tongsuo.git

cd Tongsuo

./config --prefix=/opt/tongsuo enable-ntls no-shared
make -j
sudo make install

cd ../
```

Set TEST_OPENSSL_BINARY to the path of openssl binary provided by Tongsuo.

```bash
cd tengine

TEST_OPENSSL_BINARY=/opt/tongsuo/bin/openssl \
TEST_NGINX_BINARY=`pwd`/objs/nginx \
prove -Itests/nginx-tests/nginx-tests/lib/ modules/ngx_tongsuo_ntls/t -v
```

## Directives

### ssl_ntls_cert_key_usage_check

```
Syntax:  ssl_ntls_cert_key_usage_check on | off;
Default: —
Context: http, server
```

The same directive is available in the stream module (stream, server).

Tongsuo 8.5.0 rejects sign/enc certificates without the proper GB/T 20518
keyUsage bits, on both ends of a TLCP handshake. Set this to off to keep
accepting legacy certificates that were issued without a keyUsage
extension. When the directive is absent the check keeps its Tongsuo
default (on since 8.5.0); Tengine writes that value to the SSL_CTX
itself, so a `system_default` policy in `OPENSSL_CONF` does not turn the
check off — set the directive to off explicitly. On Tongsuo older than
8.5.0 the directive is rejected at start-up; the library performs no
such check there.

The check reads a field of the connection, which SSL_new() copies from
the SSL_CTX and SSL_set_SSL_CTX() does not carry over. The default
server's value thus reaches every connection via SSL_new(); for an
SNI-selected virtual server Tengine copies that server's value onto
the connection in the SNI callback, so the directive works per virtual
server, in both directions (an off default server with an on virtual
server, and the reverse).

The proxy modules have no counterpart directive. Tongsuo 8.5.0 also runs
the check on the client side, so proxying to a legacy NTLS upstream whose
certificates lack a keyUsage extension fails the handshake; relax the
client-side check with
`proxy_ssl_conf_command enable_ntls_cert_key_usage_check off;`.

The switch can also be set with
`ssl_conf_command enable_ntls_cert_key_usage_check off`.  Both knobs end
up on the same per-server value that is copied to connections, so the
result is the same whether it comes from the directive or from the
command. If both are used, `ssl_conf_command` is applied after the
directive and overrides it — avoid mixing the two.

The dedicated directive is still preferable: it accepts only on|off and
reports the required Tongsuo version at configuration time, whereas the
SSL_CONF knob treats any value other than "on" as off, including a
misspelling.

### ssl_force_ntls

```
Syntax:  ssl_force_ntls on | off;
Default: off
Context: server
```

The same directive is available in the stream module (server).

It is only accepted inside a `server {}` block: a top-level
`ssl_force_ntls on` would be inherited by every virtual server sharing
the address and trip the default-server check at startup, so the
main-conf context is not offered.

Serve NTLS (TLCP) only: the connection enters the NTLS state machine
directly, plain TLS records are rejected, and the first-record detection
used by "enable_ntls on" is skipped. The NTLS/TLS choice has to be made
before the ClientHello — and therefore before the SNI extension — can be
parsed, so this is a listen-level setting: it requires "enable_ntls on"
in the default server of the ssl port and must not appear in any other
virtual server sharing that port (the configuration is rejected at
startup otherwise). There is no proxy counterpart: Tongsuo applies
forced NTLS on the accepting side only.

The default-server check is applied per listen address, so a server that
enables `ssl_force_ntls` must be the default server of every
`listen ... ssl` address it appears on. If the same server is the default
for one address but a non-default server for another, the configuration
is rejected at startup for the latter address.

The directive only takes effect on `listen ... ssl` addresses. On a
plain `listen` address (without `ssl`) there is no SSL handshake path,
so `ssl_force_ntls` is silently ignored, consistent with `enable_ntls`.

A dedicated directive is still preferable: it validates on|off at
configuration time, reports the required Tongsuo version, and enforces
the default-server-only placement.  `ssl_conf_command enable_force_ntls on`
in the default server can also force NTLS (SSL_new() copies the flag to
each connection), but it has none of those checks, and
`ssl_conf_command enable_force_ntls off` does not override the
per-connection `ssl_force_ntls on`.

## Variables

```
$ssl_client_enc_cert
$ssl_client_raw_enc_cert
```

The client encryption certificate of a TLCP mutual handshake. The
`$ssl_client_cert` family exposes only the sign certificate, so the
encryption certificate of the peer was previously unreachable. Both
variables are empty for non-NTLS handshakes or when the client presents
no encryption certificate.

Session resumption limitation: after a full TLCP mutual handshake both
variables hold the client encryption certificate.  With Tongsuo 8.5.0
the encryption certificate is NOT restored for sessions resumed via
session tickets or a shared session cache (the session serialization
keeps only the sign peer certificate, not the encryption chain), so the
variables may be empty even though `$ssl_client_cert` is set.  Do not
use them to decide whether mutual authentication took place.

## Reference
- [Tongsuo website](https://www.tongsuo.net/)
- [Tongsuo document](https://www.yuque.com/tsdoc)
