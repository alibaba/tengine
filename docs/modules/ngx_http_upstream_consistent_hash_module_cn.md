模块名
====

*  一致性hash模块

描述
===========

* 这个模块提供一致性hash作为负载均衡算法。

* 该模块通过使用客户端信息(如：$ip, $uri, $args等变量)作为参数，使用一致性hash算法将客户端映射到后端机器

* 如果后端机器宕机，这请求会被迁移到其他机器

* `server` *id* 字段，如果配置id字段，则使用id字段作为server标识，否则使用server ip和端口作为server标识，

    使用id字段可以手动设置server的标识，比如一台机器的ip或者端口变化，id仍然可以表示这台机器。使用id字段

    可以减低增减服务器时hash的波动。

* `server` *wegiht* 字段，作为server权重，对应虚拟节点数目

* 具体算法，假设每个server对应n个虚拟节点，那m个server就对应n×m个虚拟节点，这些节点被均匀分布到hash环上。

    每次请求进入时，模块根据配置的参数计算出一个hash值，在hash环上查找离这个hash值最近的虚拟节点，并将此

    节点对应的server作为该次请求的后端机器。

* 该模块可以根据配置参数采取不同的方式将请求均匀映射到后端机器，比如：

    `consistent_hash $remote_addr`：可以根据客户端ip映射

    `consistent_hash $request_uri`： 根据客户端请求的uri映射

    `consistent_hash $args`：根据客户端携带的参数进行映射


例子
===========

    worker_processes  1;

    http {
        upstream test {
            consistent_hash $request_uri;

            server 127.0.0.1:9001 id=1001 weight=3;
            server 127.0.0.1:9002 id=1002 weight=10;
            server 127.0.0.1:9003 id=1003 weight=20;
        }
    }


指令
==========

consistent_hash
------------------------

**Syntax**: *consistent_hash variable_name*

**Default**: *none*

**Context**: *upstream*

配置upstream采用一致性hash作为负载均衡算法，variable_name作为hash输入，可以使用nginx变量。

编译安装
===========

* configure默认打开一致性hash模块，若要关闭请使用选项`--without-http_upstream_consistent_hash_module`。

      $ ./configure

* 编译

    $ make

* 安装模块

    $ make install
