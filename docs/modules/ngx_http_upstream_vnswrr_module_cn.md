
## 名称 

ngx_http_upstream_vnswrr_module.


## 介绍

`VNSWRR`模块是一个高效的负载均衡算法，同Nginx官方的加权轮询算法`SWRR`相比，`VNSWRR` 具备 平滑、散列和高性能特征。

## 配置列子

```
http {

    upstream backend {
        vnswrr; # enable VNSWRR load balancing algorithm.
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

./configure --add-module=./modules/ngx_http_upstream_vnswrr_module
make
make install

```
    

## 指令描述

vnswrr
=======
```
Syntax: vnswrr
Default: none
Context: upstream
```

在upstream里面启用 `vnswrr` 加权轮询算法。
    
    

## 性能数据


在相同的压测环境下，`VNSWRR` 算法核心函数(`ngx_http_upstream_get_vnswrr`)CPU消耗占比仅有 `0.27%`，而在`SWRR`算法下其核心处理函数（`ngx_http_upstream_get_peer`）CPU消耗占比高至 `39%`。 其CPU消耗比`VNSWRR`算法要高出一个数量级。

* 压测环境

```
CPU型号： Intel(R) Xeon(R) CPU E5-2682 v4 @ 2.50GHz

压测工具：./wrk -t25  -d5m -c500  'http://ip/t2000'

Tengine核心配置：配置2个worker进程、2000 endpoint，压力源 --长连接--> Tengine/Nginx --短连接--> 后端
```

![image](/docs/image/vnswrr_vs_swrr_fhot.png)


在上述的压测环境下，`VNSWRR`算法的QPS处理能力相比`SWRR`提升 `60%`左右，如下图所示。

![image](/docs/image/vnswrr_vs_swrr_2000.png)


通过试验，控制变量是upstream里面配置的server数量，观察不同场景下Nginx的QPS处理能力以及响应时间RT变化情况。从图中可以发现当后端upstream里面的server数量每增加500台则Nginx的QPS处理能力下降 10% 左右，响应RT增长 1ms 左右。

![image](/docs/image/vnswrr_vs_swrr_qps.png)

![image](/docs/image/vnswrr_vs_swrr_rt.png)

