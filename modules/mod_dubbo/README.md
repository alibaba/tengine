# Quick Start

## Install Tengine

### Get Tengine
```
git clone https://github.com/alibaba/tengine.git
```
### Get some other vendor
```
cd ./tengine

wget https://ftp.pcre.org/pub/pcre/pcre-8.43.tar.gz
tar xvf pcre-8.43.tar.gz

wget https://www.openssl.org/source/openssl-1.0.2s.tar.gz
tar xvf openssl-1.0.2s.tar.gz

wget http://www.zlib.net/zlib-1.2.11.tar.gz
tar xvf zlib-1.2.11.tar.gz
```

### Build Tengine
```
./configure --add-module=./modules/mod_dubbo --add-module=./modules/ngx_multi_upstream_module --add-module=./modules/mod_config --with-pcre=./pcre-8.43/ --with-openssl=./openssl-1.0.2s/ --with-zlib=./zlib-1.2.11
make
sudo make install
```

CentOS maybe need
```
sudo yum install gcc
sudo yum install gcc-c++
```

### Run Tengine

modify tengine config file ```/usr/local/nginx/conf/nginx.conf``` to 

```
worker_processes  1;

events {
    worker_connections  1024;
}


http {
    include       mime.types;
    default_type  application/octet-stream;

    sendfile        on;

    server {
        listen       8080;
        server_name  localhost;
        
        #pass the Dubbo to Dubbo Provider server listening on 127.0.0.1:20880
        location / {
            set $dubbo_service_name "org.apache.dubbo.samples.tengine.DemoService";
            set $dubbo_service_name "0.0.0";
            set $dubbo_service_name "tengineDubbo";

            dubbo_pass_all_headers on;
            dubbo_pass_set args $args;
            dubbo_pass_set uri $uri;
            dubbo_pass_set method $request_method;
        
            dubbo_pass $dubbo_service_name $dubbo_service_version $dubbo_method dubbo_backend;
        }
    }

    #pass the Dubbo to Dubbo Provider server listening on 127.0.0.1:20880
    upstream dubbo_backend {
        multi 1;
        server 127.0.0.1:20880;
    }
}
```

### Start Tengine

```
/usr/local/nginx/sbin/nginx
```

Other Commond (no need execute usual)
```
#restart
/usr/local/nginx/sbin/nginx -s reload
#stop
/usr/local/nginx/sbin/nginx -s stop
```

### More document
```
https://github.com/alibaba/tengine/blob/master/docs/modules/ngx_http_dubbo_module.md
https://github.com/alibaba/tengine/blob/master/docs/modules/ngx_http_dubbo_module_cn.md
```

## Install Dubbo
### Get Dubbo Samples

```
git clone https://github.com/apache/dubbo-samples.git
```

### Build Dubbo Tengine Sample
depend on ```maven``` and ```jdk8```

```
cd ./dubbo-samples/dubbo-samples-tengine
mvn package
```

CentOS maybe need
```
sudo yum install maven

#or

wget http://repos.fedorapeople.org/repos/dchen/apache-maven/epel-apache-maven.repo -O /etc/yum.repos.d/epel-apache-maven.repo
sudo yum -y install apache-maven


sudo yum install java-1.8.0-openjdk-devel
```

Ubuntu maybe need
```
sudo apt install maven
sudo apt install openjdk-8-jdk-devel

#some times
sudo apt-get install software-properties-common
sudo add-apt-repository ppa:openjdk-r/ppa
sudo apt-get update
sudo apt-get install openjdk-8-jdk
sudo update-alternatives --config java
```

### Run Dubbo Demo
```
cd dubbo-samples-tengine-provider/target/
java -Djava.net.preferIPv4Stack=true -jar dubbo-demo-provider.one-jar.jar
```


## Do Test

```
curl http://127.0.0.1:8080/dubbo -i
```

Like this

```
curl http://127.0.0.1:8080/dubbo -i

HTTP/1.1 200 OK
Server: Tengine/2.3.1
Date: Thu, 15 Aug 2019 05:42:15 GMT
Content-Type: application/octet-stream
Content-Length: 13
Connection: keep-alive
test: 123

dubbo success
```

This doc Verified on
```
Ubuntu 14.04
Ubuntu 16.04
Ubuntu 18.04

Centos 7
Centos 6
```