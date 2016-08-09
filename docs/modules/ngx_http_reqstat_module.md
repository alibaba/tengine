Name
====

* ngx_http_reqstat_module

Description
===========

This module will help monitor running status of Tengine.

* It can provide running status information of Tengine.

* The information is divided into different zones, and each zone is independent.

* The status information is about connections, requests, response status codes, input and output flows,
  rt, upstreams, and so on.

* It shows all the results by default, and can be set to show part of them by specifying zones.

* It supports for user-defined status by using nginx variables. The maximum of all the status is 50.

* It recycles out-of-date running status information.

* It supports for defining output format.

* It follows the request processing flow, so internal redirect will not affect monitoring.

* Do not use variables of response as a condition, eg., $status.

Compilation
===========

The module is compiled into Tengine by default. It can be disabled with '--without-http_reqstat_module'
configuration parameter, or it can be compiled as a '.so' with '--with-http_reqstat_module=shared'.

If you use this module as a '.so', please make sure it is after 'ngx_http_lua_module'. Please refer to
'nginx -m'.


Example
===========

    http {

        req_status_zone server "$host,$server_addr:$server_port" 10M;
        req_status_zone_add_indicator server $limit;

        server {
            location /us {
                req_status_show;
                req_status_show_field req_total $limit;
            }

            set $limit 0;

            if ($arg_limit = '1') {
                set $limit 1;
            }

            req_status server;
        }
    }

* when you call '/us', you will get the results like this:

            www.example.com,127.0.0.1:80,162,6242,1,1,1,0,0,0,0,10,1,10,1....

    * Each line shows the status infomation of a "$host,$server_addr:$server_port".

    * Default line format:

            kv,bytes_in,bytes_out,conn_total,req_total,http_2xx,http_3xx,http_4xx,http_5xx,http_other_status,rt,ups_req,ups_rt,ups_tries,http_200,http_206,http_302,http_304,http_403,http_404,http_416,http_499,http_500,http_502,http_503,http_504,http_508,http_other_detail_status,http_ups_4xx,http_ups_5xx

        * **kv**                value of the variable defined by the directive 'req_status_zone'. The maximun key length is configurable, 152B by default, and overlength will be cut off
        * **bytes_in**          total number of bytes received from client
        * **bytes_out**         total number of bytes sent to client
        * **conn_total**        total number of accepted connections
        * **req_total**         total number of processed requests
        * **http_2xx**          total number of 2xx requests
        * **http_3xx**          total number of 3xx requests
        * **http_4xx**          total number of 4xx requests
        * **http_5xx**          total number of 5xx requests
        * **http_other_status** total number of other requests
        * **rt**                accumulation or rt
        * **ups_req**           total number of requests calling for upstream
        * **ups_rt**            accumulation or upstream rt
        * **ups_tries**         total number of times calling for upstream
        * **http_200**          total number of 200 requests
        * **http_206**          total number of 206 requests
        * **http_302**          total number of 302 requests
        * **http_304**          total number of 304 requests
        * **http_403**          total number of 403 requests
        * **http_404**          total number of 404 requests
        * **http_416**          total number of 416 requests
        * **http_499**          total number of 499 requests
        * **http_500**          total number of 500 requests
        * **http_502**          total number of 502 requests
        * **http_503**          total number of 503 requests
        * **http_504**          total number of 504 requests
        * **http_508**          total number of 508 requests
        * **http_other_detail_status**      total number of requests of other status codes 
        * **http_ups_4xx**      total number of requests of upstream 4xx
        * **http_ups_5xx**      total number of requests of upstream 5xx

    * You can use names in the left column to define output format, with directive 'req_status_show_field'

    * Some fields will be removed in future, because user-defined status has been supported.

* tsar can parse the result and monitor, see also https://github.com/alibaba/tsar

Directives
==========

req_status_zone
-------------------------

**Syntax**: *req_status_zone zone_name value size*

**Default**: *none*

**Context**: *http*

create shared memory for this module. 'zone_name' is the name of memory block.
'value' defines the key, in which variables can be used.
'size' defines the size of shared memory.

Example:

    req_status_zone server "$host,$server_addr:$server_port" 10M;

    the memory is 10MB, the key is "$host,$server_addr:$server_port", and the name is "server".

* Notice, if you want to use tsar to monitor, you should not use comma in the key.


req_status
-------------------------

**Syntax**: *req_status zone_name1 [zone_name2 [zone_name3 [...]]]*

**Default**: *none*

**Context**: *http、srv、loc*

Enable monitoring. You can specify multiple zones to monitor.

req_status_show
-------------------------

**Syntax**: *req_status_show [zone_name1 [zone_name2 [...]]]*

**Default**: *all the targets defined by 'req_status_zone'*

**Context**: *loc*

Display the status information. You can specify zones to display.


req_status_show_field
-------------------------------
**Syntax**: *req_status_show_field field_name1 [field_name2 [field_name3 [...]]]*

**Default**: *all the fields, including user defined fields*

**Context**: *loc*

Define output format, used with the directive 'req_status_show'. You can use names
to define internal supported fields, see it above. And also you can use variables
to define user defined fields. 'kv' is always the first field in a line.


req_status_zone_add_indicator
--------------------------------

**Syntax**: *req_status_zone_add_indecator zone_name $var1 [$var2 [...]]*

**Default**: *none*

**Context**: *http*

Add user-defined status by using nginx variables. The status will be appended at the end of each line on display.


req_status_zone_key_length
-------------------------------

**Syntax**: *req_status_zone_key_length zone_name length*

**Default**: *none*

**Context**: *http*

Define the maximun length of key for a zone. The default is 104.


req_status_zone_recycle
-------------------------------

**Syntax**: *req_status_zone_recycle zone_name times seconds*

**Default**: *none*

**Context**: *http*

Define the recycle threshold for a zone. Recycle will be switched on when the shared memory is exhausted,
and will only take effect on imformation whose visit frequency is lower than the setting.
The setting frequency is defined by 'times' and 'seconds', and it is 10r/min by default.
     req_status_zone_recycle demo_zone 10 60;
