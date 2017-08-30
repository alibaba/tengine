ngx_slab_stat
==============

该模块可以提供NGINX/Tengine共享内存的状态信息。

示例
=======

获取NGINX/Tengine共享内存池的slab和空闲页状态信息
---------------------------------

```
 http {
    server {
        listen 80;

        location = /slab_stat {
            slab_stat;
        }
    }
 }
```

请求URI /slab_stat，可以获取到该NGINX/Tengine实例的共享内存使用情况统计。
页面输出如下：

```
$ curl http://localhost:80/slab_stat
* shared memory: one
total:      102400(KB) free:      101792(KB) size:           4(KB)
pages:      101792(KB) start:0000000003496000 end:0000000009800000
slot:           8(Bytes) total:           0 used:           0 reqs:           0 fails:           0
slot:          16(Bytes) total:           0 used:           0 reqs:           0 fails:           0
slot:          32(Bytes) total:         127 used:           1 reqs:           1 fails:           0
slot:          64(Bytes) total:           0 used:           0 reqs:           0 fails:           0
slot:         128(Bytes) total:          32 used:           1 reqs:           1 fails:           0
slot:         256(Bytes) total:           0 used:           0 reqs:           0 fails:           0
slot:         512(Bytes) total:           0 used:           0 reqs:           0 fails:           0
slot:        1024(Bytes) total:           0 used:           0 reqs:           0 fails:           0
slot:        2048(Bytes) total:           0 used:           0 reqs:           0 fails:           0
```

共享内存使用情况统计
-----------------------------------

数据说明
====

每个数据段落的前三行表明共享内存的总使用信息及空闲页(free pages)信息，剩余行表明slab的使用信息，数据项意义如下：

* __shared memory__: 共享内存池的名称信息

* __total__: 该共享内存池总内存占用
* __free__: 该共享内存池空闲内存
* __size__: 该共享内存池的页大小

* __pages__: 可供分配的连续页
* __start__: 可供分配的连续页起始地址
* __end__: 可供分配的连续页末尾地址

* __slot__: 可供分配的slot(不同大小代表不同的slot队列)
* __total__: 总的slot个数
* __used__: 已使用的slot个数
* __reqs__: 申请分配次数
* __fails__: 申请失败次数

NGINX兼容性
===================

* 1.13.4 (stable version of 1.13.x)

NGINX版本低于 1.13.x 需要补丁支持（参考安装说明）

Tengine兼容性
=====================

* 2.1.1 (stable version of 2.1.x)

Tengine版本低于 2.1.x 需要补丁支持（参考安装说明）

安装说明
=======

源码安装，执行如下命令：

```
$ wget http://nginx.org/download/nginx-1.13.4.tar.gz
$ tar -xzvf nginx-1.13.4.tar.gz
$ cd nginx-1.13.4/
$ ./configure --add-module=/path/to/ngx_slab_stat
$ make -j4 && make install
```

注意：若NGINX版本低于 1.13.x 或者 Tengine版本低于 2.1.1，请安装补丁文件`slab_stat.patch`后再编译二进制版本，该补丁文件可以自行比对NGINX 1.13.4 版本生成。

```
$ patch -p1 < /path/to/ngx_slab_stat/slab_stat.patch
```

配置指令
=========

语法: **slab_stat**

默认: `none`

位置: `server, location`

NGINX/Tenigne实例的共享内存状态信息可以通过该location访问得到。

注意信息
=========

仅支持NGINX官方指令分配的共享内存和[lua-nginx-module](https://github.com/openresty/lua-nginx-module)分配的共享内存。
