# ngx_http_xquic_module

Tengine ngx_http_xquic_module 主要用于在服务端启用 QUIC/HTTP3 监听服务。

# 编译

ngx_http_xquic_module 编译依赖

依赖库：

* Tongsuo: https://github.com/Tongsuo-Project/Tongsuo
* xquic: https://github.com/alibaba/xquic

```shell
# 下载 Tongsuo，示例中下载 8.3.2 版本
wget -c "https://github.com/Tongsuo-Project/Tongsuo/archive/refs/tags/8.3.2.tar.gz"
tar -x 8.3.2.tar.gz

# 下载 xquic，示例中下载 1.6.0 版本
wget -c "https://github.com/alibaba/xquic/archive/refs/tags/v1.6.0.tar.gz"
tar -xf v1.6.0.tar.gz

# 下载 Tengine 3.0.0 以上版本，示例从 master 获取最新版本，也可下载指定版本
git clone git@github.com:alibaba/tengine.git

# 编译 Tongsuo
cd Tongsuo-8.3.2
./config --prefix=/usr/local/babassl
make
make install
export SSL_TYPE_STR="babassl"
export SSL_PATH_STR="${PWD}"
export SSL_INC_PATH_STR="${PWD}/include"
export SSL_LIB_PATH_STR="${PWD}/libssl.a;${PWD}/libcrypto.a"
cd ../../

# 编译 xquic 库
cd xquic-1.6.0/
mkdir -p build; cd build
cmake -DXQC_SUPPORT_SENDMMSG_BUILD=1 -DXQC_ENABLE_BBR2=1 -DXQC_DISABLE_RENO=0 -DSSL_TYPE=${SSL_TYPE_STR} -DSSL_PATH=${SSL_PATH_STR} -DSSL_INC_PATH=${SSL_INC_PATH_STR} -DSSL_LIB_PATH=${SSL_LIB_PATH_STR} ..
make
cp "libxquic.so" /usr/local/lib/
cd ..

# 编译 Tengine
cd tengine

# 注：xquic 依赖 ngx_http_v2_module，需要参数 --with-http_v2_module
./configure \
  --prefix=/usr/local/tengine \
  --sbin-path=sbin/tengine \
  --with-xquic-inc="../xquic-1.6.0/include" \
  --with-xquic-lib="../xquic-1.6.0/build" \
  --with-http_v2_module \
  --without-http_rewrite_module \
  --add-module=modules/ngx_http_xquic_module \
  --with-openssl="../Tongsuo-8.3.2"

make
make install
```

精简示例配置，其中 default-fake-certificate.pem 为可用证书。

```nginx
worker_processes  1;

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
/usr/local/tengine/sbin/tengine -p /usr/local/tengine/ -c conf/nginx.conf
```

启动后 tengine 监听 2443 UDP 端口，此端口可以接收 HTTP3 请求，可以通过编译 xquic 自带的 `test_client` 测试（cmake 编译 xquic 时需要带 `-DXQC_ENABLE_TESTING=1` 参数）

```shell
./test_client -a 127.0.0.1 -p 2443 -u https://domain/
```

更为详细的指令可参考官网文档 [XQUIC模块](http://tengine.taobao.org/document_cn/xquic_cn.html)
