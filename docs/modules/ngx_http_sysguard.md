# ngx_http_sysguard_module

## Description

This module monitors memory usage (including the swap partition), load of CPUs and average response time of requests of the system. If any guideline that is monitored exceeds the threshold set by user, the current request will be redirected to a specific url. To be clarified, this module can only be full functional when the system supports sysinfo function and loadavg function. The sysguard module also need to read memory information from /proc file system.

## Configuration

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

## Directives

**sysguard** `on` | `off`

**Default:** `sysguard off`

**Context:** `http, server, location` 
     
Enable or disable the sysguard module.

<br/>
<br/>

**sysguard_load** `load=[ncpu*]number [action=/url]`

**Default:** `none`

**Context:** `http, server, location`

This directive tells the module to protect the system by monitoring the load of CPUs. If the system's loads reach the value that is specified by 'number' in one minute, the incoming request will be redirected to the url specified by 'action' parameter. If 'action' is not specified, tengine will respond with 503 error directly. It's also possible to use ncpu\* to make the configuration, in which case, ncpu stands for the number of the CPU cores. For instance, load = ncpu*1.5.

<br/>
<br/>

**sysguard_mem** `[swapratio=ratio%] [free=size] [action=/url]`

**Default:** `-`

**Context:** `http, server, location`

This directive is used to tell the module to protect the system by monitoring memroy usage. 'swapratio' is used to specify how many percent of the swap partition of the system, and 'free' is used to specify the miminum size of current memory. If any condition is fulfilled, the incoming request will be redirected to specified url, which is defined by parameter 'action'. If 'action' is not specified, the request will be responded with 503 error directly. Besides, if the user disables the swap partition in the system, this directive will not be functional. 'free' is calculated by /proc/meminfo, the algorithm is 'memfree = free + buffered + cached'. 

<br/>
<br/>

**sysguard_rt** `[rt=seconds] [period=time] [action=/url]`

**Default:** `-`
                
**Context:** `http, server, location`

This directive is used to tell the module to protect the system by monitoring average response time of requests in a specified period. Parameter rt is used to set a threshold of the average response time, in second. Parameter period is used to specifiy the period of the statistics cycle. If the average response time of the system exceeds the threshold specified by the user, the incoming request will be redirected to a specified url which is defined by parameter 'action'. If no 'action' is presented, the request will be responded with 503 error directly.

<br/>
<br/>

**sysguard_mode** `and` | `or`

**Default:**  'sysguard_mode or' 

**Context** 'http, server, location'

If there are more than one type of monitor, this directive is used to specified the relations among all the monitors which are: 'and' for all matching and 'or' for any matching.

<br/>
<br/>

**sysguard_interval** 'time'
       
**Default** 'sysguard_interval 1s'
         
**Context** 'http, server, location'
       
Specify the time interval to update your system information.

<br/>
<br/>

**sysguard_log_level** '[info | notice | warn | error]'
       
**Default** 'sysguard_log_level error'
         
**Context** 'http, server, location'
       
Specify the log level of sysguard.

## Installation

 1. Compile sysguard module
         
    configure  [--with-http_sysguard_module | --with-http_sysguard_module=shared]

    --with-http_sysguard_module, sysguard module will be compiled statically into tengine.

    --with-http_sysguard_module=shared, sysguard module will be compiled dynamically into tengine.

 2. Build and install

    make&make install
 
 3. Make sysguard configuration
 
 4. Run
