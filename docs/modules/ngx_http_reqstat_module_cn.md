模块名
====

* ngx_http_reqstat_module，监控模块

描述
===========

* 这个模块计算定义的变量，根据变量值分别统计Tengine的运行状况。

* 可以监视的运行状况有：连接数、请求数、各种响应码范围的请求数、输入输出流量、rt、upstream访问。

* 可以指定获取所有监控结果或者一部分监控结果。

编译
===========

默认编入Tengine，可通过--without-http_reqstat_module不编译此模块，或通过--with-http_reqstat_module=shared编译为so模块。


例子
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

* 以上例，通过访问/us得到统计结果

    * 每行对应一个server

    * 每行的格式

            kv,bytes_in_total,bytes_out_total,conn_total,req_total,2xx,3xx,4xx,5xx,other,rt_total

        * kv                计算得到的req_status_zone指令定义变量的值
        * bytes_in_total    从客户端接收流量总和
        * bytes_out_total   发送到客户端流量总和
        * conn_total        处理过的连接总数
        * req_total         处理过的总请求数
        * 2xx               2xx请求的总数
        * 3xx               3xx请求的总数
        * 4xx               4xx请求的总数
        * 5xx               5xx请求的总数
        * other             其他请求的总数
        * rt_total          rt的总数
        * upstream_req      需要访问upstream的请求总数
        * upstream_rt       访问upstream的总rt
        * upstream_tries    upstram总访问次数

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

**Syntax**: *req_status zone_name1 [zone_name2 [zone_name3]]*

**Default**: *none*

**Context**: *main、srv、loc*

开启统计，可以指定同时统计多个目标，每一个zone_name对应一个目标。


req_status_show
-------------------------

**Syntax**: *req_status_show [zone_name1 [zone_name2 [...]]]*

**Default**: *所有建立的共享内存目标*

**Context**: *loc*

按格式返回统计结果。可指定返回部分目标的统计结果。
