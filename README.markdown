
Introduction
============

Tengine is a web server originated by [Taobao](http://en.wikipedia.org/wiki/Taobao), the largest e-commerce website in Asia. It is based on [Nginx](http://nginx.org) HTTP server and has many advanced features. Tengine has been proven very stable and efficient on the top 100 global websites, including [taobao.com](http://www.taobao.com) and [tmall.com](http://www.tmall.com).

Tengine has been an open source project since December 2011. It is now developed and maintained by the Tengine team, whose core members are from [Taobao](http://en.wikipedia.org/wiki/Taobao), [Sogou](http://en.wikipedia.org/wiki/Sogou) and other Internet companies.

Features
========

* All features of nginx-1.2.5 are inherited, i.e. it is 100% compatible with nginx.
* Dynamic module loading support. You don't need to recompile Tengine when adding new modules to it.
* Input body filter support. It's quite handy to write Web Application Firewalls by using this mechanism.
* Dynamic scripting language (Lua) support, which is very efficient and easy to extend core functionalities.
* Logging enhancement. Syslog (local and remote), pipe logging and log sampling are supported.
* A mechanism to support standalone processes.
* Protecting server in case system load or memory use goes too high.
* Multiple CSS or JavaScript requests can be combined into one request to reduce downloading time.
* Proactive health checks of upstream servers can be performed.
* The number of worker processes and CPU affinities can be set automatically.
* The limit_req module is enhanced with white list support and more conditions are allowed in a single location.
* Diagnostic information to tell the server where the error happened.
* More user friendly command lines. e.g. showing all compiled-in modules and supported directives.
* Expiration times can be specified for certain MIME types.
* Error pages can be reset to 'default'.
* ...

Installation
============

Tengine can be downloaded at [http://tengine.taobao.org/download/tengine.tar.gz](http://tengine.taobao.org/download/tengine.tar.gz). You can also checkout the latest source code from GitHub at [https://github.com/taobao/tengine](https://github.com/taobao/tengine)

To install Tengine, just follow these three steps:

    $ ./configure
    $ make
    # make install

By default, it will be installed to _/usr/local/nginx_. You can use the __'--prefix'__ option to specify the root directory.
If you want to know all the _'configure'_ options, you should run __'./configure --help'__ for help.

Documentation
=============

The homepage of Tengine is at [http://tengine.taobao.org/](http://tengine.taobao.org/)
You can access [http://tengine.taobao.org/documentation.html](http://tengine.taobao.org/documentation.html) for more information.

Mailing lists
=============

Mailing lists are usually good places to ask questions. We highly recommend you subscribe Tengine's mailing lists below:
* [http://code.taobao.org/mailman/listinfo/tengine](http://code.taobao.org/mailman/listinfo/tengine) (English)
* [http://code.taobao.org/mailman/listinfo/tengine-cn](http://code.taobao.org/mailman/listinfo/tengine-cn) (Chinese)

