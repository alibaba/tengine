模块名
====

* ngx_http_reqstat_module，监控模块

描述
===========

* 这个模块计算定义的变量，根据变量值分别统计Tengine的运行状况。

* 可以监视的运行状况有：连接数、请求数、各种响应码范围的请求数、输入输出流量、rt、upstream访问等。

* 可以指定获取所有监控结果或者一部分监控结果。

* 利用变量添加自定义监控状态。总的监控状态最大个数为50个。

* 回收过期的监控数据。

* 设置输出格式

* 跟踪请求，不受内部跳转的影响

* 不要使用与响应相关的变量作为条件，比如"$status"

编译
===========

默认编入Tengine，可通过--without-http_reqstat_module不编译此模块，或通过--with-http_reqstat_module=shared编译为so模块。
使用so模块加载的话，请确保其顺序在"ngx_http_lua_module"之后。可以借助"nginx -m"来确认。

例子
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

* 以上例，通过访问/us得到统计结果

    * 每行对应一个server

    * 每行的默认格式

            kv,bytes_in,bytes_out,conn_total,req_total,http_2xx,http_3xx,http_4xx,http_5xx,http_other_status,rt,ups_req,ups_rt,ups_tries,http_200,http_206,http_302,http_304,http_403,http_404,http_416,http_499,http_500,http_502,http_503,http_504,http_508,http_other_detail_status,http_ups_4xx,http_ups_5xx

        * kv                计算得到的req_status_zone指令定义变量的值，最大长度可配置，默认104B，超长的部分截断
        * bytes_in          从客户端接收流量总和
        * bytes_out         发送到客户端流量总和
        * conn_total        处理过的连接总数
        * req_total         处理过的总请求数
        * http_2xx          2xx请求的总数
        * http_3xx          3xx请求的总数
        * http_4xx          4xx请求的总数
        * http_5xx          5xx请求的总数
        * http_other_status 其他请求的总数
        * rt                rt的总数
        * ups_req           需要访问upstream的请求总数
        * ups_rt            访问upstream的总rt
        * ups_tries         upstram总访问次数
        * http_200          200请求的总数
        * http_206          206请求的总数
        * http_302          302请求的总数
        * http_304          304请求的总数
        * http_403          403请求的总数
        * http_404          404请求的总数
        * http_416          416请求的总数
        * http_499          499请求的总数
        * http_500          500请求的总数
        * http_502          502请求的总数
        * http_503          503请求的总数
        * http_504          504请求的总数
        * http_508          508请求的总数
        * http_other_detail_status    非以上13种status code的请求总数
        * http_ups_4xx      upstream返回4xx响应的请求总数
        * http_ups_5xx      upstream返回5xx响应的请求总数

    * 可以用"req_status_show_field"指令定义输出格式。左侧栏是字段的名字。

    * 注，后续会清理这些状态，因为已经支持了自定义状态。

* tsar可解析输出结果，具体见https://github.com/alibaba/tsar

指令
==========

req_status_zone
-------------------------

**Syntax**: *req_status_zone zone_name value size*

**Default**: *none*

**Context**: *main*

创建统计使用的共享内存。zone_name是共享内存的名称，value用于定义key，支持变量。size是共享内存的大小。

例子：

    req_status_zone server "$host,$server_addr:$server_port" 10M;

    创建名为“server”的共享内存，大小10M，使用“$host,$server_addr:$server_port”计算key。

* 注意，如果希望用tsar来监控的话，key的定义中请不要使用逗号。


req_status
-------------------------

**Syntax**: *req_status zone_name1 [zone_name2 [zone_name3 [...]]]*

**Default**: *none*

**Context**: *http、srv、loc*

开启统计，可以指定同时统计多个目标，每一个zone_name对应一个目标。


req_status_show
-------------------------

**Syntax**: *req_status_show [zone_name1 [zone_name2 [...]]]*

**Default**: *所有建立的共享内存目标*

**Context**: *loc*

按格式返回统计结果。可指定返回部分目标的统计结果。


req_status_show_field
-------------------------------
**Syntax**: *req_status_show_field field_name1 [field_name2 [field_name3 [...]]]*

**Default**: *all the fields, including user defined fields*

**Context**: *loc*

定义输出格式。可以使用的字段：内置字段，以上面的名字来表示；自定义字段，用变量表示。
'kv'总是每行的第一个字段。


req_status_zone_add_indicator
--------------------------------

**Syntax**: *req_status_zone_add_indecator zone_name $var1 [$var2 [...]]*

**Default**: *none*

**Context**: *http*

通过变量增加自定义字段，新增加的字段目前会展现在每行的末尾。


req_status_zone_key_length
-------------------------------

**Syntax**: *req_status_zone_key_length zone_name length*

**Default**: *none*

**Context**: *http*

定义某个共享内存块中key的最大长度，默认值104。key中超出的部分会被截断。


req_status_zone_recycle
-------------------------------

**Syntax**: *req_status_zone_recycle zone_name times seconds*

**Default**: *none*

**Context**: *http*

定义某个共享内存块过期数据的回收。回收在共享内存耗尽时自动开启。只会回收访问频率低于设置值的监控数据。
频率定义为 times / seconds，默认值为10r/min，即
     req_status_zone_recycle demo_zone 10 60;
