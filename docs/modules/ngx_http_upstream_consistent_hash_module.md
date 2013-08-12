Name
====

*  consistent hash module

Description
===========

* This module provides consistent hashing algorithm for upstream load-balancing.

* If one of backend servers is down, the request of this client will be transferred to another server.

* `server` *id* field: Id field can be used as server flag. If id field is not set, ip address and port are used to identify server. You can use id field to set server flag mannually. In that case, although ip address or port of a server is changed, id can still identify the server. BTW, it can reduce remapping keys effectively to use id field.

* `server` *weight* field: server weight, the number of virtual peers

* Algorithm: It supposes that 1 server is mapped to m virtual peers, so n servers correspond to n*m virtual peers. All these peers will be mapped to hash ring on average. Every time request comes, it calculates a hash key via configuration parameter, and finds a peer on the hash ring nearest to the location specified by the hash key.

* It can dispatch requests to backend servers on average according to nginx configuration parameter.

    `consistent_hash $remote_addr`: mapping via client ip address

    `consistent_hash $request_uri`: mapping via request-uri

    `consistent_hash $args`: mapping via url query string


Example
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


Directives
==========

consistent_hash
------------------------

**Syntax**: *consistent_hash variable_name*

**Default**: *none*

**Context**: *upstream*

This directive causes requests to be distributed between upstreams based on consistent hashing alogrithm. And it uses nginx variables, specified by variable_name, as input data of hash function.


Installation
===========

* This module is built by default, it can be disabled with the `--without-http_upstream_consistent_hash_module` configuration parameter.

    $ ./configure

* compile

    $ make

* install

    $ make install
