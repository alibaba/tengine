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

* It support for user-defined status by using nginx variables. The maximum of all the status is 50.

* It recycles out-of-date running status information.

Compilation
===========

The module is compiled into Tengine by default. It can be disabled with '--without-http_reqstat_module'
configuration parameter, or it can be compiled as a '.so' with '--with-http_reqstat_module=shared'.


Example
===========

    http {
        req_status_zone server "$host,$server_addr:$server_port" 10M;

        server {
            location /us {
                req_status_show;
            }

            req_status server;
        }
    }

* when you call '/us', you will get the results like this:

            www.taobao.com,127.0.0.1:80,162,6242,1,1,1,0,0,0,0,10,1,10,1

    * Each line shows the status infomation of a "$host,$server_addr:$server_port".

    * Line format:

            kv,bytes_in_total,bytes_out_total,conn_total,req_total,2xx,3xx,4xx,5xx,other,rt_total,upstream_req,upstream_rt,upstream_tries,200,206,302,304,403,404,416,499,500,502,503,504,508,detail_other,ups_4xx,ups_5xx

        * **kv**                value of the variable defined by the directive 'req_status_zone'. The maximun key length is configurable, 104B by default, and overlength will be cut off
        * **bytes_in_total**    total number of bytes received from client
        * **bytes_out_total**   total number of bytes sent to client
        * **conn_total**        total number of accepted connections
        * **req_total**         total number of processed requests
        * **2xx**               total number of 2xx requests
        * **3xx**               total number of 3xx requests
        * **4xx**               total number of 4xx requests
        * **5xx**               total number of 5xx requests
        * **other**             total number of other requests
        * **rt_total**          accumulation or rt
        * **upstream_req**      total number of requests calling for upstream
        * **upstream_rt**       accumulation or upstream rt
        * **upstream_tries**    total number of times calling for upstream
        * **200**               total number of 200 requests
        * **206**               total number of 206 requests
        * **302**               total number of 302 requests
        * **304**               total number of 304 requests
        * **403**               total number of 403 requests
        * **404**               total number of 404 requests
        * **416**               total number of 416 requests
        * **499**               total number of 499 requests
        * **500**               total number of 500 requests
        * **502**               total number of 502 requests
        * **503**               total number of 503 requests
        * **504**               total number of 504 requests
        * **508**               total number of 508 requests
        * **detail_other**      total number of requests of other status codes 
        * **ups_4xx**           total number of requests of upstream 4xx
        * **ups_5xx**           total number of requests of upstream 5xx

    * some fields will be removed in future, because user-defined status has been supported.

* tsar can parse the result and monitor, see also https://github.com/alibaba/tsar

Directives
==========

req_status_zone
-------------------------

**Syntax**: *req_status_zone zone_name value size*

**Default**: *none*

**Context**: *main*

create shared memory for this module. 'zone_name' is the name of memory block.
'value' defines the key, in which variables can be used.
'size' defines the size of shared memory.

Example:

    req_status_zone server "$host,$server_addr:$server_port" 10M;

    the memory is 10MB, the key is "$host,$server_addr:$server_port", and the name is "server".

* Notice, if you want to use tsar to monitor, you should not use comma in the key.


req_status
-------------------------

**Syntax**: *req_status zone_name1 [zone_name2 [zone_name3]]*

**Default**: *none*

**Context**: *main、srv、loc*

Enable monitoring. You can specify multiple zones to monitor.

req_status_show
-------------------------

**Syntax**: *req_status_show [zone_name1 [zone_name2 [...]]]*

**Default**: *all the targets defined by 'req_status_zone'*

**Context**: *loc*

Display the status information. You can specify zones to display.


req_status_zone_add_indicator
--------------------------------

**Syntax**: *req_status_zone_add_indecator zone_name $var1 [$var2 [...]]*

**Default**: *none*

**Context**: *main*

Add user-defined status by using nginx variables. The status will be appended at the end of each line on display.


req_status_zone_key_length
-------------------------------

**Syntax**: *req_status_zone_key_length zone_name length*

**Default**: *none*

**Context**: *main*

Define the maximun length of key for a zone. The default is 104.


req_status_zone_recycle
-------------------------------

**Syntax**: *req_status_zone_recycle zone_name times seconds*

**Default**: *none*

**Context**: *main*

Define the recycle threshold for a zone. Recycle will be switched on when the shared memory is exhausted, and will only take effect on imformation whose visit frequency is lower than the setting.
The setting frequency is defined by 'times' and 'seconds', and it is 10r/min by default.
     req_status_zone_recycle demo_zone 10 60;
