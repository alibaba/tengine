
## Name

ngx_http_upstream_iwrr_module.


## Introduction

The `IWRR` module is an efficient load balancing algorithm with `O(1)` time complexity, but `IWRR` is no need to incremental initialization.

Compared with Nginx's official `SWRR` algorithm and `VNSWRR`, `IWRR` abandons smoothness on the premise of ensuring the correctness of the weighted load balancing algorithm, ensuring that no matter how the total weight of the cluster changes, `IWRR` space The complexity is always `O(n)`. 

## Example

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
    
## Installation

Build Tengine with this module from source:

```

./configure --add-module=./modules/ngx_http_upstream_iwrr_module/
make
make install

```
    

## Directive

iwrr
=======
```
Syntax: iwrr [max_init=number]
Default: none
Context: upstream
```

Enable `iwrr` load balancing algorithm. 
