Name
====

* Nginx SSL/TLS asynchronous mode

Description
===========

Provide information about how to enable SSL/TLS asynchronous in Nginx.
* SSL/TLS asynchronous mode is provided by OpenSSL 1.1.0+ version

Compilation
===========

Build Nginx with configuration item '--with-openssl-async'

Directives
===========

**Syntax**:     ssl_async on | off;

**Default**:  ssl_async off;

**Context**:    http, server

Enables SSL/TLS asynchronous mode for the given virtual server.

Example
==========

file: conf/nginx.conf
'''
    http {
        ssl_async  on;
        server {
            ...
            }
        }
    }
'''
OR
'''
    http {
        server {
            ssl_async  on;
            }
        }
    }
'''

Note
========================
To demostrate the asynchronous mode of SSL/TLS, it needs an asynchronous enabled
engine support. As a reference implementation, OpenSSL 1.1.0+ version provides
an 'dasync' engine which support the asynchronous working flow.
'dasync' engine will be built as a shared library 'dasync.so' in engines/
Please use below reference openssl.cnf file to enable it for RSA offloading.

    openssl_conf = openssl_def
    [openssl_def]
    engines = engine_section
    [engine_section]
    dasync = dasync_section
    [dasync_section]
    engine_id = dasync
    dynamic_path = /path/to/openssl/source/engines/dasync.so
    default_algorithms = RSA

For more details information, please refer to https://www.openssl.org
