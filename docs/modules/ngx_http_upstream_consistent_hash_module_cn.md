模块名
====

*  一致性hash模块

描述
===========

* 这个模块提供一致性hash作为负载均衡算法.

* 该模块通过使用客户端信息(如：$ip, $uri, $args等变量)作为参数，使用一致性hash算法将客户端映射到后端机器

* 如果后端机器宕机，这请求会被迁移到其他机器

* `server` *id* 字段，如果配置id字段，则使用id字段作为server标识，否则使用server ip和端口作为server标识

* `server` *wegiht* 字段，作为server权重


例子
===========

    worker_processes  1;
    
    http {
        upstream test {
            consistent_hash $request_uri;
            consistent_hash 10;

            server 127.0.0.1:9001 id=1001 wegiht=3;
            server 127.0.0.1:9002 id=1002 wegiht=10;
            server 127.0.0.1:9003 id=1003 wegiht=20;
        }
    }


指令
==========

consistent_hash 
------------------------

**Syntax**: *consistent_hash variable_name*

**Default**: *none*

**Context**: *upstream*

配置upstream采用一致性hash作为负载均衡算法，并使用配置的变量名作为hash输入


consistent_tries
------------------------

**Syntax**: *consistent_tries number*

**Default**: *none*

**Context**: *upstream*

配置当访问后端返回502后，重试的次数


编译安装
===========

* 在configure的时候打开一致性hash模块，关闭使用选项`--without-http_upstream_consistent_hash_module`.

      $ ./configure
      
* 编译它.

    $ make
    
* 安装模块.

    $ make install
