Name
====

* ngx_http_upstream_dynamic_module

Description
===========

* This module provides the functionality to resolve domain names into IP addresses in an upstream at run-time.

Examples
========

    upstream backend {
        dynamic_resolve fallback=stale fail_timeout=30s;

        server a.com;
        server b.com;
    }

    server {
        ...

        proxy_pass http://backend;
    }

Directives
==========

dynamic_resolve
---------------

**Syntax**: *dynamic_resolve [fallback=stale|next|shutdown] [fail_timeout=time]*

**Default**: *-*

**Context**: *upstream*

Enable dynamic DNS resolving functionality in an upstream.

The 'fallback' parameter specifies what action to take if a domain name can not be resolved into an IP address:

* stale, use the original IP addresses resolved when tengine starts.
* next, go to next availiable server in the upstream.
* shutdown, finalize current request.

The 'fail_timeout' parameter specifies how long time tengine considers the DNS server as unavailiable if a DNS query fails for a server in the upstream. In this period of time, all requests comming will follow what 'fallback' specifies.
