
## 名称 

ngx_http_upstream_iwrr_module.


## 介绍

`IWRR`模块是一个高效的负载均衡算法，与`VNSWRR`相同，它具有`O(1)`的时间复杂度，但是`IWRR`不需要执行渐进式初始化操作。

同Nginx官方的加权轮询负载均衡算法及`VNSWRR`相比，`IWRR`在保证加权负载均衡算法正确性的前提下，牺牲了平滑的特点，保证无论集群总权重如何变化，`IWRR`空间复杂度总是`O(n)`的。

## 配置列子

```
http {

    upstream backend {
        iwrr; # enable IWRR load balancing algorithm.
        127.0.0.1 port=81;
        127.0.0.1 port=82 weight=2;
        127.0.0.1 port=83;
        127.0.0.1 port=84 backup;
        127.0.0.1 port=85 down;
    }
    
    server {
        server_name localhost;
        
        location / {
            proxy_pass http://backend;
        }
    }
}

```
    
## 安装方法

在Tengine中，通过源码安装此模块：


```

./configure --add-module=./modules/ngx_http_upstream_iwrr_module
make
make install

```
    

## 指令描述

iwrr
=======
```
Syntax: iwrr
Default: none
Context: upstream
```

在upstream里面启用 `iwrr` 加权轮询算法。
