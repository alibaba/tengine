<h1 align="center" style="border-bottom: none">
    <br>Tengine
</h1>

<p align="center">Visit <a href="https://tengine.taobao.org" target="_blank">tengine.taobao.org</a> for the full documentation,
examples and guides.</p>

<div align="center">

[![GitHub license](https://img.shields.io/github/license/alibaba/tengine.svg)](https://github.com/alibaba/tengine/blob/main/LICENSE)
[![GitHub stars](https://img.shields.io/github/stars/alibaba/tengine.svg)](https://github.com/alibaba/tengine/stargazers)
[![GitHub stars](https://img.shields.io/badge/contributions-welcome-orange.svg)](https://github.com/alibaba/tengine/blob/main/CONTRIBUTING.md)
[![Build Status](https://github.com/alibaba/tengine/actions/workflows/ci.yml/badge.svg)](https://github.com/alibaba/tengine/actions/workflows/ci.yml)

</div>


## Introduction
Tengine is a web server originated by [Taobao](http://en.wikipedia.org/wiki/Taobao), the largest e-commerce website in Asia. It is based on the [Nginx](http://nginx.org) HTTP server and has many advanced features. Tengine has proven to be very stable and efficient on some of the top 100 websites in the world, including [taobao.com](http://www.taobao.com) and [tmall.com](http://www.tmall.com).

Tengine has been an open source project since December 2011. It is being actively developed by the Tengine team, whose core members are from Taobao, Sogou and other Internet companies. Tengine is a community effort and everyone is encouraged to [get involved](https://github.com/alibaba/tengine).

## Features
* All features of nginx-1.24.0 are inherited, i.e., it is 100% compatible with nginx.
* Dynamically configure the servers, locations and upstreams without reloading or restarting worker processes with [tengine-ingress](https://github.com/alibaba/tengine-ingress).
* HTTP/3 support (QUIC v1 and draft-29) with [xquic](https://github.com/alibaba/xquic).
* High-speed UDP transmission with kernel-bypass.
* Dynamically configure different TLS protocols for different server names with [tengine-ingress](https://github.com/alibaba/tengine-ingress).
* Dynamically configure timeout setting, SSL Redirects, CORS and enabling/disabling robots for the server and location with [tengine-ingress](https://github.com/alibaba/tengine-ingress).
* Dynamically configure HTTP routing based on multiple values of a specific header, cookie or query parameter with [tengine-ingress](https://github.com/alibaba/tengine-ingress).
* Dynamically configure HTTP routing based on multiple upstream according to weight with [tengine-ingress](https://github.com/alibaba/tengine-ingress).
* Dynamically configure HTTP routing to add/append custom header or add query parameter in the HTTP request to the upstream with [tengine-ingress](https://github.com/alibaba/tengine-ingress).
* Dynamically configure HTTP routing to add custom header in the HTTP response to the client with [tengine-ingress](https://github.com/alibaba/tengine-ingress).
* Support the CONNECT HTTP method for forward proxy.
* Support asynchronous OpenSSL, using hardware such as QAT for HTTPS acceleration.
* Enhanced operations monitoring, such as asynchronous log & rollback, DNS caching, memory usage, etc.
* Support server_name in Stream module.
* More load balancing methods, e.g., consistent hashing, and session persistence.
* Input body filter support. It's quite handy to write Web Application Firewalls using this mechanism.
* Dynamic scripting language (Lua) support, which is very efficient and makes it easy to extend core functionalities.
* Limits retries for upstream servers (proxy, memcached, fastcgi, scgi, uwsgi).
* Includes a mechanism to support standalone processes.
* Protects the server in case system load or memory use goes too high.
* Multiple CSS or JavaScript requests can be combined into one request to reduce download time.
* Removes unnecessary white spaces and comments to reduce the size of a page.
* Proactive health checks of upstream servers can be performed.
* The number of worker processes and CPU affinities can be set automatically.
* The limit_req module is enhanced with whitelist support and more conditions are allowed in a single location.
* Enhanced diagnostic information makes it easier to troubleshoot errors.
* More user-friendly command lines, e.g., showing all compiled-in modules and supported directives.
* Expiration times can be specified for certain MIME types.
* Receives HTTP traffic on the TLS listener with option.
* Debugging HTTP connection usage.
* ...

## Installation
Tengine can be downloaded at [http://tengine.taobao.org/download/tengine.tar.gz](http://tengine.taobao.org/download/tengine.tar.gz). You can also checkout the latest source code from GitHub at [https://github.com/alibaba/tengine](https://github.com/alibaba/tengine)

To install Tengine, just follow these three steps:
```bash
./configure
make
sudo make install
```

By default, it will be installed to _/usr/local/nginx_. You can use the __'--prefix'__ option to specify the root directory.
If you want to know all the _'configure'_ options, you should run __'./configure --help'__ for help.

## Documentation
The homepage of Tengine is at [http://tengine.taobao.org/](http://tengine.taobao.org/)
You can access [http://tengine.taobao.org/documentation.html](http://tengine.taobao.org/documentation.html) for more information.

## Contact
[https://github.com/alibaba/tengine/issues](https://github.com/alibaba/tengine/issues)

Dingtalk user group: 23394285

## License

[BSD-2-Clause License](https://github.com/alibaba/tengine/blob/master/LICENSE)

<h1 align="center" style="border-bottom: none">
    <a href="https://tengine.taobao.org" target="_blank"><img alt="Tengine" src="/docs/image/tengine-logo.png"></a>
</h1>
