## Description
This module is able to limit the concurrent number and frequency with each ip address when accepting new connections, and supports black and white lists for specific IPs. It's useful and flexible to protect https or mail applications.
### Config Sample

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
                return 200;
            }
        }

        server {
            listen 8089;
            location / {
                return 200;
            }
        }

        server {
            listen 8080;
            location / {
                return 200;
            }
        }
    }


## Directives

Syntax: **limit_tcp name:size addr:port [rate= burst= nodelay] [concurrent=]**

Default: `none`

Context: `main`

Sets a shared memory zone and the maximum of requests' rate. If the rate exceeds the configured value, excessive requests are delayed so that server is able to process at defined rate. If the number of delayed requests exceeds "burst" value, requests will be closed immediately after accepted.

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
