
## Name

ngx_http_upstream_vnswrr_module.


## Introduction

The `VNSWRR` module is an efficient load balancing algorithm that is smooth, decentralized, and high-performance compared to Nginx's official `SWRR` algorithm.


## Example

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
    
## Installation

Build Tengine with this module from source:

```

./configure --add-module=./modules/ngx_http_upstream_vnswrr_module/
make
make install

```
    

## Directive

vnswrr
=======
```
Syntax: vnswrr
Default: none
Context: upstream
```

Enable `vnswrr` load balancing algorithm.
    
    
## Performance


In the same pressure environment (wrk, 500 concurrency, keepalive, 2000 endpoint), the CPU consumption of `VNSWRR` algorithm accounts for `0.27%` ( `ngx_http_upstream_get_vnswrr`).
Compared with `VNSWRR` algorithm, the CPU consumption of `SWRR` (`ngx_http_upstream_get_peer` `39%`) is an order of magnitude higher than `VNSWRR`.


![image](/docs/image/vnswrr_vs_swrr_fhot.png)

In the above environment, the QPS of `VNSWRR` increases by `60%` compared with `SWRR` algorithm.


![image](/docs/image/vnswrr_vs_swrr_2000.png)


Observing the changes of QPS and RT in the different back-end number scenarios. 
Under SWRR algorithm, when the number of back-end for every 500 addition, then the QPS of Nginx decreases by about 10% and RT increases by about 1 ms. But under the VNSWRR algorithm, QPS and RT do not change much.


![image](/docs/image/vnswrr_vs_swrr_qps.png)

![image](/docs/image/vnswrr_vs_swrr_rt.png)

