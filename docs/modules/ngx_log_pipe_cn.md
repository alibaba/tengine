# log pipe
Syntax: **pipe:rollback** [logpath] **interval=**[interval] **baknum=**[baknum] **maxsize=**[maxsize] **adjust=**[adjust]
Default: none
Context: http, server, location

日志pipe功能使用独立进程打印日志，不会阻塞worker进程，worker进程与独立日志进程间通过pipe进行通讯，rollback功能依赖日志pipe功能，提供基于tengine自身的日志回滚功能，支持，按照时间间隔、文件大小进行回滚，并支持配置，backup文件的个数。日志回滚模块会按照配置的条件将log文件rename成backup文件，然后重新写新日志文件

该功能配置集成在access_log和error_log指令中：类似如下配置
```
access_log "pipe:rollback [logpath] interval=[interval] baknum=[baknum] maxsize=[maxsize] adjust=[adjust]" proxyformat;

error_log  "pipe:rollback [logpath] interval=[interval] baknum=[baknum] maxsize=[maxsize] adjust=[adjust]" info;
```

logpath: 日志输出路径

interval：日志回滚间隔，默认0（永不回滚）

baknum：backup文件保留个数，默认1（保留1个）

maxsize：log文件最大size，默认0（永不回滚）

adjust: 按时间回滚时，回滚时间随机延后，用于规避集群同时触发回滚动作，默认60 （60s）

使用示例：
```
error_log  "pipe:rollback logs/error_log interval=60m baknum=5 maxsize=2048M" info;

http {
	log_format  main  '$remote_addr - $remote_user [$time_local] "$request" '
                      '$status $body_bytes_sent "$http_referer" '
                      '"$http_user_agent" "$http_x_forwarded_for"';
	access_log  "pipe:rollback logs/access_log interval=1h baknum=5 maxsize=2G"  main;
}
```
