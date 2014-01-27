# Name #

**limit upstream retries**

Limits retries for upstream servers (proxy, memcached, fastcgi, scgi, uwsgi).
Using one of the directives below will enable this feature.

# Example #

    http {
        upstream test {
            server 127.0.0.1:8081;
            server 127.0.0.2:8081;
            server 127.0.0.3:8081;
            server 127.0.0.4:8081;
        }
    
        server {
            proxy_upstream_tries 2;
            proxy_set_header Host $host;
    
            location / {
                proxy_pass test;
            }
        }
    }

# Directives #

## fastcgi\_upstream\_tries ##

Syntax: **fastcgi\_upstream\_tries** num

Default: -

Context: http, server, locatioon

Limit the maximum number of tries for fastcgi proxy. Nginx tries to connect different server each time.

## proxy\_upstream\_tries ##

Syntax: **proxy\_upstream\_tries** num

Default: -

Context: http, server, locatioon

Limit the maximum number of tries for http proxy. Nginx tries to connect different server each time.

## memcached\_upstream\_tries ##

Syntax: **memcached\_upstream\_tries** num

Default: -

Context: http, server, locatioon

Limit the maximum number of tries for memcached proxy. Nginx tries to connect different server each time.

## scgi\_upstream\_tries ##

Syntax: **scgi\_upstream\_tries** num

Default: -

Context: http, server, locatioon

Limit the maximum number of tries for scgi proxy. Nginx tries to connect different server each time.

## uwsgi\_upstream\_tries ##

Syntax: **uwsgi\_upstream\_tries** num

Default: -

Context: http, server, locatioon

Limit the maximum number of tries for uwsgi proxy. Nginx tries to connect different server each time.
