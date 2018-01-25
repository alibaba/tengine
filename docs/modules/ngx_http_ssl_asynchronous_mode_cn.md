名称
====

* Nginx SSL/TLS 异步模式

Description
===========

本文档提供关于如何在Nginx开启异步SSL/TLS支持的说明.
* 异步SSL/TLS模式是OpenSSL 1.1.0版本之后引入的新的模式

编译支持
===========

启用--with-openssl-async编译选项

配置项
===========

**语法**:     ssl_async on | off;

**默认值**:  ssl_async off;

**作用域**:    http, server

在给定的http块或者虚拟server块中配置启用异步SSL/TLS模式

配置示例
==========

配置文件: conf/nginx.conf
'''
    http {
        ssl_async  on;
        server {
            ...
            }
        }
    }
'''
或
'''
    http {
        server {
            ssl_async  on;
            }
        }
    }
'''

说明
========================
为了展示Nginx启用异步SSL/TLS的效果，需要OpenSSL在算法层提供支持异步的引擎模块
在OpenSSL 1.1.0之后的版本中，默认提供了名为'dasync'的参考异步引擎
在完成OpenSSL编译后,异步引擎'dasync'会以共享库'dasync.so'的形式出现在engines/
目录下,使用如下openssl.cnf配置文件中的配置可以使能'dasync'异步引擎用于RSA算法

    openssl_conf = openssl_def
    [openssl_def]
    engines = engine_section
    [engine_section]
    dasync = dasync_section
    [dasync_section]
    engine_id = dasync
    dynamic_path = /path/to/openssl/source/engines/dasync.so
    default_algorithms = RSA

更多详细信息请参考https://www.openssl.org
