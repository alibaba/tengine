Background
===========================================
We use Apache with mpm-itk as our upstream server and tengine as frontend proxy with caching of static resources.

Apache with mpm-itk means that apache preforks processes that listens for connections, and when it knows what vhost the connection will use, it changes its user and group to that vhosts settings. This thus drops root privileges and means that the connection cannot be re-used for another vhost. It can however be reused within the same vhost. If a keepalive connection attempts to access another vhost than the process can handle, then the connection is reset and the client will have to start a new connection.

If tengine could keep a small cache of upstream keepalive connections, since reusing existing connections would be beneficial for performance and scalability, and especially latency.
But for this to work with mpm-itk, I request the possibility to set those connections to be vhost-local, thus only re-using a connection if one exists for the same vhost. This could be solved either by setting a key to differentiate them (like how proxy cache is solved), or by just comparing the hostname and domain parts of the url (less flexible, but still a lot better than nothing.

This could also have limits on how many connections to cache per vhost, to avoid one vhost dominating the cache. And a upper time limit for each connection, to override keepalive timeout sent by the upstream server if it is too long. (it could be out of the control of the tengine user and could thus potentially be set too long).


INSTALL
===========================================
This module is enabled by the configuration parameter '--without-http_upstream_keepalive_module --add-module=modules/ngx_http_upstream_keepalive_module/'. It is the substitution of the origin, and compatible with it.

Example
===========================================

    upstream {
        server 127.0.0.1;
        keepalive 30 slice_key=$host slice_conn=2;
    }

or

    map $host $conn {
        hostnames;
        default 0;
        *.allow.com 2;
    }
    
    upstream {
        server 127.0.0.1;
        keepalive 30 slice_key=$host slice_dyn=$conn;
    }

Directive
===========================================

**Syntax**: *keepalive connections [slice_key=key] [slice_conn=sconn] [slice_dyn=$dyn] [slice_poolsize=poolsize] [slice_keylen=keylength]*

**Default**: *none*

**Context**: *ups*

Activates the cache for connections to upstream servers.

The `connections` parameter sets the maximum number of idle keepalive connections to upstream servers that are preserved in the cache of each worker process. When this number is exceeded, the least recently used connections are closed.

The keep-alive connections will be saved into buckets based on values of server address and `slice_key`. If you want to keep some connections for each virtual vhost, you can set `slice_key=$host` or `slice_key=$server_name:$server_port`.

The maximum number of connections held by each bucket is defined by `slice_conn` as a whole, or by `slice_dyn` more specifically.

The maximum number of bucket is defined by `slice_poolsize`, which means the maximum number of slice_key. The default value is 20.

For each key defined by `slice_key`, the module cuts them off if the key length is greater than the length defined by `slice_keylen`. The default length is 40.


**Syntax**: *keepalive_timeout timeout*

**Default**: *none*

**Context**: *ups*

Set a timeout during which a keep-alive upstream connection will stay open.
