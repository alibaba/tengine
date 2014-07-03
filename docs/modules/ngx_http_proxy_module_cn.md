# proxy 模块

## 介绍

proxy_set_header指令，在多级block中出现时，官方nginx的merge规则是：如果低级别的block配置了该指令，则高级别block配置的该指令将全部失效。

tengine对该merge规则进行了优化，低级别block中配置的该指令，将作为高级别block中配置的该指令的补充或替换，并将继承高级别block中set的header。

## 配置

	http {
		proxy_header_merge_method  append_not_set;
		server {
			proxy_set_header  AA aa;
			proxy_set_header  BB bb;
			location / {
				proxy_set_header BB newbb;
				proxy_set_header CC cc;
				proxy_pass http://localhost:8080;
			}	
		}
	}

## 指令

**proxy_header_merge_method** default|append_not_set

**默认** default

**上下文** http

1，当设置为default时，在多个block level配置的proxy_set_header指令，将采用nginx默认的merge规则。

2，当设置为append_not_set时，在多个block level配置的proxy_set_header指令，将采用新的merge规则。
