# Quick Start

## Install Tengine
1. Get Tongsuo

NTLS (TLCP and GM/T 0024) is based on Tongsuo.
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

# For Tongsuo master branch
./configure --add-module=modules/ngx_tongsuo_ntls \
    --with-openssl=../Tongsuo \
    --with-openssl-opt="--strict-warnings --api=1.1.1 enable-ntls" \
    --with-http_ssl_module --with-stream \
    --with-stream_ssl_module --with-stream_sni

# for Tongsuo version 8.3 or lower
./configure --add-module=modules/ngx_tongsuo_ntls \
    --with-openssl=../Tongsuo \
    --with-openssl-opt="--strict-warnings enable-ntls" \
    --with-http_ssl_module --with-stream \
    --with-stream_ssl_module --with-stream_sni

make -j
sudo make install
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

## Reference
- [Tongsuo website](https://www.tongsuo.net/)
- [Tongsuo document](https://www.yuque.com/tsdoc)
