## Description
This module can be used for limiting accept events and concurrent.

### Config Sample

    daemon off;
    error_log logs/error.log debug;
    worker_processes 1;

    events {
        accept_mutex off;
    }

    limit_tcp 8088 8089 rate=1r/m burst=1000 nodelay;
    limit_tcp 8080 rate=1r/m burst=100 name=8080:1M concurrent=1;

    limit_tcp_deny 127.10.0.2/32;
    limit_tcp_deny 127.0.0.1;
    limit_tcp_allow 127.10.0.3;

    http {
        server {
            listen 8088;
            location / {
                echo 8088;
            }
        }

        server {
            listen 8089;
            location / {
                echo 8089;
            }
        }

        server {
            listen 8080;
            location / {
                echo 8080;
            }
        }
    }


## Directives

Syntax: **limit_tcp name:size addr:port [rate= burst= nodelay] [concurrent=]**

Default: `none`

Context: `main`

Sets a shared memory zone and the maximum burst size of requests. If the rate of requests exceeds the rate configured for a zone, their processing is delayed such that requests are processed at a defined rate. Excessive requests are delayed until their number exceeds the maximum burst size or out of maximum concurrent in which case the request is closed after accepted.

For example, the directives

    limit_tcp 8080 8081 rate=1r/m burst=100 name=share_mem:10M concurrent=10;


Syntax: **limit_tcp_allow address | CIDR | all**

Default: `none`

Context: `main`

Allows access for the specified network or address.


Syntax: **limit_tcp_deny address | CIDR | all**

Default: `none`

Context: `main`

Denies access for the specified network or address.
