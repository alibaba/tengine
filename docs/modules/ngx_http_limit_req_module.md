Name
====

* limit_req module

Description
===========

* This is the enhanced version of nginx's limit_req module with white list support, and more limit conditions are allowed in a single location.


Directives
==========

limit_req_zone
-------------

**Syntax**: *limit_req_zone $session_variable1 $session_variable2 ... zone=name_of_zone:size rate=rate*

**Default**: *none*

**Context**: *http*

Support more than one limit variables. For example:

    limit_req_zone $binary_remote_addr $uri zone=one:3m rate=1r/s;
    limit_req_zone $binary_remote_addr $request_uri zone=two:3m rate=1r/s;
    
The last line of the above example indicates a client can access a specific URI only once in a second.

limit_req
------------------------

**Syntax**: *limit_req [off] | zone=zone_name [burst=burst] \[forbid_action=action\] \[nodelay\]*

**Default**: *none*

**Context**: *http, server, location*

Multiple limit conditions are allowed in a single block. And all the conditions are examined in order.
You can turn this directive on or off (default is on).
'forbid_action' specifies the action URL to redirect. It can be a named location. By default, tengine will return 503.

For example:

    limit_req_zone $binary_remote_addr zone=one:3m rate=1r/s;
    limit_req_zone $binary_remote_addr $uri zone=two:3m rate=1r/s;
    limit_req_zone $binary_remote_addr $request_uri zone=three:3m rate=1r/s;

    location / {
        limit_req zone=one burst=5;
        limit_req zone=two forbid_action=@test1;
        limit_req zone=three burst=3 forbid_action=@test2;
    }

    location /off {
        limit_req off;
    }

    location @test1 {
        rewrite ^ /test1.html;
    }

    location @test2 {
        rewrite ^  /test2.html;
    }


limit_req_whitelist
------------------------

**Syntax**: *limit_req_whitelist geo_var_name=var_name geo_var_value=var_value*

**Default**: *none*

**Context**: *http, server, location*

Set the whitelist.
This directive needs work with the geo module. The 'geo_var_name' is the variable name declared in the geo module, 'geo_var_value' is its value. For example:

    geo $white_ip {
        ranges;
        default 0;
        127.0.0.1-127.0.0.255 1;
    }

    limit_req_whitelist geo_var_name=white_ip geo_var_value=1;
    
It means requests from IP (127.0.0.1 to 127.0.0.255) will be considered safe and let pass.
