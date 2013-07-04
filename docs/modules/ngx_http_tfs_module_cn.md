模块名
====

* nginx-tfs

描述
====

* 这个模块实现了TFS的客户端，为TFS提供了RESTful API。TFS的全称是Taobao File System，是淘宝开源的一个分布式文件系统。

编译安装
=======

1. TFS模块使用了一个开源的JSON库来支持JSON，请先安装[yajl](http://lloyd.github.com/yajl/)-2.0.1。

2. 下载[nginx](http://www.nginx.org/)或[tengine](http://tengine.taobao.org/)。

3. ./configure --add-module=/path/to/nginx-tfs

4. make && make install

配置
====

    http {
        #tfs_upstream tfs_rc {
        #    server 127.0.0.1:6100;
        #    type rcs;
        #    rcs_zone name=tfs1 size=128M;
        #    rcs_interface eth0;
        #    rcs_heartbeat lock_file=/logs/lk.file interval=10s;
        #}

        tfs_upstream tfs_ns {
            server 127.0.0.1:6100;
            type ns;
        }

        server {
              listen       7500;
              server_name  localhost;

              tfs_keepalive max_cached=100 bucket_count=10;
              tfs_log "pipe:/usr/sbin/cronolog -p 30min /path/to/nginx/logs/cronolog/%Y/%m/%Y-%m-%d-%H-%M-tfs_access.log";

              location / {
                  tfs_pass tfs://tfs_ns;
              }
        }
    }

指令
====

server
------------

**Syntax**： *server address*

**Default**： *none*

**Context**： *tfs_upstream*

指定后端TFS服务器的地址，当指令<i>type</i>为<i>rcs</i>时为RcServer的地址，如果为为<i>ns</i>时为NameServer的地址。此指令必须配置。例如:

	server 10.0.0.1:8108;

type
----------------

**Syntax**： *type [ns | rcs]*

**Default**： *ns*

**Context**： *tfs_upstream*

设置server类型，类型只能为ns或者rcs，如果为ns,则指令<i>server</i>指定的地址为NameServer的地址，如果为rcs,则为RcServer的地址。如需使用自定义文件名功能请设置类型为rcs，使用自定义文件名功能需额外配置MetaServer和RootServer。

rcs\_zone
--------------

**Syntax**： *rcs_zone name=n size=num*

**Default**： *none*

**Context**： *tfs_upstream*

配置TFS应用在RcServer的配置信息。若开启RcServer（配置了<i>type rcs</i>），则必须配置此指令。配置此指令会在共享内存中缓存TFS应用在RcServer的配置信息，并可以通过指令<i>rcs_heartbeat</i>来和RcServer进行keepalive以保证应用的配置信息的及时更新。例如：

	rcs_zone name=tfs1 size=128M;

rcs\_heartbeat
--------------

**Syntax**： *rcs_heartbeat lock_file=/path/to/file interval=time*

**Default**： *none*

**Context**： *tfs_upstream*

配置TFS应用和RcServer的keepalive，应用可通过此功能来和RcServer定期交互，以及时更新其配置信息。若开启RcServer功能（配置了<i>type rcs</i>），则必须配置此指令。例如：

	rcs_heartbeat lock_file=/path/to/nginx/logs/lk.file interval=10s;

rcs\_interface
----------------

**Syntax**： *rcs\_interface interface*

**Default**： *none*

**Context**： *tfs_upstream*

配置TFS模块使用的网卡。若开启RcServer功能（配置了<i>type rcs</i>），则必须配置此指令。例如：

	rcs_interface eth0;

tfs\_upstream
----------------

**Syntax**： *tfs\_upstream name {...}*

**Default**： *none*

**Context**： *http*

配置TFS模块的server信息,这个块包括上面几个命令。例如：

    tfs_upstream tfs_rc {
        server 127.0.0.1:6100;
        type rcs;
        rcs_zone name=tfs1 size=128M;
        rcs_interface eth0;
        rcs_heartbeat lock_file=/logs/lk.file interval=10s;
    }


tfs_pass
--------

**Syntax**： *tfs_pass name*

**Default**： *none*

**Context**： *location*

是否打开TFS模块功能，此指令为关键指令，决定请求是否由TFS模块处理，必须配置。需要注意，这里不支持直接写ip地址或者域名，这里只支持指令<i>tfs_upstream name {...} </i>配置的upstream,并且必须以 tfs:// 开头。例如：


	tfs_upstream tfs_rc {
    };

	location / {
		tfs_pass tfs://tfs_rc;
	}

tfs_keepalive
-------------

**Syntax**： *tfs_keepalive max_cached=num bucket_count=num*

**Default**： *none*

**Context**： *http, server*

配置TFS模块使用的连接池的大小，TFS模块的连接池会缓存TFS模块和后端TFS服务器的连接。可以把这个连接池看作由多个hash桶构成的hash表，其中bucket\_count是桶的个数，max\_cached是桶的容量。此指令必须配置。注意，应该根据机器的内存情况来合理配置连接池的大小。例如：

	tfs_keepalive max_cached=100 bucket_count=15;

tfs\_block\_cache\_zone
-----------------------

**Syntax**： *tfs_block_cache_zone size=num*

**Default**： *none*

**Context**： *http*

配置TFS模块的本地BlockCache。配置此指令会在共享内存中缓存TFS中的Block和DataServer的映射关系。注意，应根据机器的内存情况来合理配置BlockCache大小。例如：

	tfs_block_cache_zone size=256M;

tfs\_log
----------------

**Syntax**： *tfs_log path*

**Default**： *none*

**Context**： *http, server*

是否进行TFS访问记录。配置此指令会以固定格式将访问TFS的请求记录到指定log中，以便进行分析。具体格式参见代码。例如：

	tfs_log "pipe:/usr/sbin/cronolog -p 30min /path/to/nginx/logs/cronolog/%Y/%m/%Y-%m-%d-%H-%M-tfs_access.log";

注：cronolog支持依赖于tengine提供的扩展的日志模块。

tfs\_body\_buffer\_size
-----------------------

**Syntax**： *tfs_body_buffer_size size*

**Default**： *2m*

**Context**： *http, server, location*

配置用于和后端TFS服务器交互时使用的的body_buffer的大小。默认为2m。例如：

	tfs_body_buffer_size 2m;

tfs\_connect\_timeout
---------------------

**Syntax**： *tfs_connect_timeout time*

**Default**： *3s*

**Context**： *http, server, location*

配置连接后端TFS服务器的超时时间。

tfs\_send\_timeout
------------------

**Syntax**： *tfs_send_timeout time*

**Default**： *3s*

**Context**： *http, server, location*

配置向后端TFS服务器发送数据的超时时间。

tfs\_read\_timeout
------------------

**Syntax**： *tfs_read_timeout time*

**Default**： *3s*

**Context**： *http, server, location*

配置从后端TFS服务器接收数据的超时时间。

其他
----
能支持上传文件大小决定于<i>client_max_body_size</i>指令配置的大小。
