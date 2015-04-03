Name
====

* ngx_http_reqstat_module

Description
===========

This module will help monitor running status of Tengine.

* It can provide running status information of Tengine.

* The information is divided into different zones, and each zone is independent.

* The status information is about connections, requests, response status codes, input and output flows,
  rt, and upstreams.

* It shows all the results by default, and can be set to show part of them by specifying zones.

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

            kv,bytes_in_total,bytes_out_total,conn_total,req_total,2xx,3xx,4xx,5xx,other,rt_total,upstream_req,upstream_rt,upstream_tries

        * **kv**                value of the variable defined by the directive 'req_status_zone'
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
