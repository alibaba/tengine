# sysguard 模块

## 介绍

该模块监控内存（含swap分区）、CPU和请求的响应时间，当某些监控指标达到设定的阈值时，跳转到指定的url。注意，目前该模块仅对系统支持sysinfo函数时，才支持基于load与内存信息的保护，以及系统支持loadavg函数时支持基于load进行保护。模块需要从/proc文件系统中读取内存信息。

## 配置

    server {
        sysguard on;
        sysguard_mode or;

        sysguard_load load=10.5 action=/loadlimit;
        sysguard_mem swapratio=20% action=/swaplimit;
        sysguard_mem free=100M action=/freelimit;
        sysguard_rt rt=0.01 period=5s action=/rtlimit;

        location /loadlimit {
            return 503;
        }

        location /swaplimit {
            return 503;
        }

        location /freelimit {
            return 503;
        }

        location /rtlimit {
            return 503;
        }
    }

## 指令

**sysguard** `on` | `off`

**默认:** `sysguard off`

**上下文:** `http, server, location` 
     
打开或者关闭这个模块

<br/>
<br/>

**sysguard_load** `load=[ncpu*]number [action=/url]`

**默认:** `none`

**上下文:** `http, server, location`

该指令用于配置根据系统的load来限制用户的请求，以保护系统。当系统在一分钟内的load达到number时，将进来的请求转到action所指定的url。如果action没有配置，则直接返回503错误。load的数值还支持使用ncpu\*系数的方式来配置，ncpu表示cpu核数，乘以固定的系数得出期望限制的load值，如: load=ncpu\*1.5。

<br/>
<br/>

**sysguard_mem** `[swapratio=ratio%] [free=size] [action=/url]`

**默认:** `-`

**上下文:** `http, server, location`

该指令用于配置根据系统的内存使用状态来限制用户请求，以保护系统。swapratio用于配置当当前交换空间的已使用ratio%时，或者剩下的内存少于size时，就将进来的请求跳转到指定的url。如果action没有配置，则直接返回503错误。另外，如果用户自己禁用了交换区间，则配置该指定是不起作用的。free是根据/proc/meminfo的内容来计算的，计算公式是"memfree= free + buffered + cached"

<br/>
<br/>

**sysguard_rt** `[rt=seconds] [period=time] [action=/url]`

**默认:** `-`
                
**上下文:** `http, server, location`

该指令用于配置根据系统的请求平均响应时间来限制用户请求，以保护系统。rt参数用于设置请求的平均响应时间的阈值，单位为秒，平均响应时间的统计周期使用period参数设置。当系统的请求平均响应时间大于阈值时，将当前请求跳转到action参数配置的url，如果action没有配置，则直接返回503。

<br/>
<br/>

**sysguard_mode** `and` | `or`

**默认:**  'sysguard_mode or' 

**上下文** 'http, server, location'

如果设置了多个监控指标，此参数用于指定指标间的判断关系，and为全部满足，or为任一满足。

<br/>
<br/>

**sysguard_interval** 'time'
       
**默认** 'sysguard_interval 1s'
         
**上下文** 'http, server, location'
       
该指定用于配置获取系统信息时的缓存时间。默认为1s，则表示在这1s内，只调用一次系统函数来获取系统的当前状况。

<br/>
<br/>

**sysguard_log_level** '[info | notice | warn | error]'
       
**默认** 'sysguard_log_level error'
         
**上下文** 'http, server, location'
       
该指令用于配置，当保护系统的操作执行时，记录日志时的日志级别。

## 安装

 1. 编译sysguard模块
         
    configure  [--with-http_sysguard_module | --with-http_sysguard_module=shared]

    --with-http_sysguard_module选项，sysguard模块将被静态编译到tengine中

    --with-http_sysguard_module=shared, sysguard模块将被编译成动态文件，采用动态模块的方式添加到tengine中

 2. 编译,安装

    make&make install
 
 3. 配置sysguard的配置项
 
 4. 运行
