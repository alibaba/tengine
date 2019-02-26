# log pipe
Syntax: **pipe:rollback** [logpath] **interval=**[interval] **baknum=**[baknum] **maxsize=**[maxsize] **adjust=**[adjust]
Default: none
Context: http, server, location

log pipe module write log use special log proccess, it may not block worker, worker communicate with log proccess use pipe, rollback depend on log pipe module, it support log file auto rollback by tengine self. it support rollback by time and file size, also can configure backup file number. log rollback module will rename log file to backup filename, then reopen the log file and write again

rollback configurge is built-in access_log and error_log：
```
access_log "pipe:rollback [logpath] interval=[interval] baknum=[baknum] maxsize=[maxsize] adjust=[adjust]" proxyformat;

error_log  "pipe:rollback [logpath] interval=[interval] baknum=[baknum] maxsize=[maxsize] adjust=[adjust]" info;
```

logpath: log output file path and name

interval：log rollback interval, default 0 (never)

baknum：backup file number, default 1 (keep 1 backup file)

maxsize：log file max size, default 0 (never)

adjust: delay random rollback time when rollback by interval, to avoid all server focus on rollback default 60 (60s)

example：
```
error_log  "pipe:rollback logs/error_log interval=60m baknum=5 maxsize=2048M" info;

http {
	log_format  main  '$remote_addr - $remote_user [$time_local] "$request" '
                      '$status $body_bytes_sent "$http_referer" '
                      '"$http_user_agent" "$http_x_forwarded_for"';
	access_log  "pipe:rollback logs/access_log interval=1h baknum=5 maxsize=2G"  main;
}
```
