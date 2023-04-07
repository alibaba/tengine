/*
 * Copyright (C) 2020-2023 Alibaba Group Holding Limited
 */

#include "xudp.h"
#include <sys/epoll.h>
#include <malloc.h>
#include <stdio.h>
#include <stdlib.h>
#include <signal.h>

#include <sys/types.h>
#include <sys/stat.h>
#include <unistd.h>
#include <stdio.h>
#include <fcntl.h>

#include "xquic_xdp.h"

struct connect{
	xudp *x;
	xudp_channel *ch;
	void (*handler)(struct connect *);
	int gid;
};

static xudp *gx;

void handler(struct connect *c)
{
	xudp_msg *m;
	xudp_channel *ch = c->ch;
	int n, i, ret;

    	xudp_def_msg(hdr, 100);

	while (true) {
        	hdr->used = 0;

		n = xudp_recv_channel(ch, hdr, 0);
		if (n < 0)
			break;

		for (i = 0; i < hdr->used; ++i) {
            		m = hdr->msg + i;

			printf("usec: %lld gid: %d recv msg: %.*s",
			       m->usec, c->gid, m->size, m->p);

			ret = xudp_send_channel(ch, m->p, m->size, &m->peer_addr, 0);

			if (ret < 0) {
				printf("xudp_send_one fail. %d\n", ret);
			}
		}


		xudp_recycle(hdr);

		xudp_commit_channel(ch);
	}
}

static int epoll_add(xudp *x, int efd, int gid)
{
	struct epoll_event e;
	struct connect *c;
	xudp_channel *ch;
	xudp_group *g;
	int fd, key;

	key = '0' + gid;

	e.events = EPOLLIN;

	g = xudp_group_get(x, 0);

	xudp_group_channel_foreach(ch, g) {

		fd = xudp_channel_get_fd(ch);

		c = malloc(sizeof(*c));
		c->ch = ch;
		c->x = x;
		c->handler = handler;
		c->gid = gid;

		e.data.ptr = c;


		epoll_ctl(efd, EPOLL_CTL_ADD, fd, &e);
	}

	xudp_dict_set_group_key(g, key);

	return 0;
}

static int loop(int efd)
{
	struct connect *c;
	struct epoll_event e[1024];
	int n, i;

	while (1) {
		n = epoll_wait(efd, e, sizeof(e)/sizeof(e[0]), -1);

		if (n == 0)
			continue;

		if (n < 0) {
			continue;
		}

		for (i = 0; i < n; ++i) {
			c = e[i].data.ptr;
			c->handler(c);
		}
	}
}

static void int_exit(int sig)
{
	(void)sig;
	xudp_free(gx);
	exit(EXIT_SUCCESS);
}

static int xquic_xdp_load(xudp_conf *conf)
{
	int xdp_custom_size;
	void *xdp_custom;
	struct stat stat;
	int fd, err, n;

	fd = open("kern_xquic.o", O_RDONLY);
	if (fd < 0)
		return -1;

	err = fstat(fd, &stat);
	if (err)
		return -1;

	xdp_custom_size = stat.st_size;
	xdp_custom = malloc(xdp_custom_size);

	n = read(fd, xdp_custom, xdp_custom_size);
	if (n != xdp_custom_size)
		return -1;

	conf->flow_dispatch = XUDP_FLOW_DISPATCH_TYPE_CUSTOM;
	conf->xdp_custom = xdp_custom;
	conf->xdp_custom_size = xdp_custom_size;

	// config this by the key type
	// xquic may set this config to true: map_dict_n_max_pid
	conf->map_dict_n = 100;

	return 0;
}

static int xquic_args(xudp *x)
{
	struct kern_xquic kern_xquic = {};
	int key = 0;

	kern_xquic.offset = 0;
	kern_xquic.mask = (1 << 8) - 1;

	return xudp_bpf_map_update(x, XUDP_XQUIC_MAP_NAME, &key, &kern_xquic);
}

int main(int argc, char *argv[])
{
	struct sockaddr_in in = {};
	xudp *x;
	int efd, ret;
	char *addr; int port;

	xudp_conf conf = {};

	if (argc != 3) {
		addr = "0.0.0.0";
		port = 8080;
	} else {
		addr = argv[1];
		port = atoi(argv[2]);
	}

	printf("bind %s:%d\n", addr, port);

	conf.group_num     = 2;
	conf.log_with_time = true;

	/* for xquic */
	if (xquic_xdp_load(&conf)) {
		printf("xquic xdp load fail\n");
		return -1;
	}
	/* for xquic end */

	x = xudp_init(&conf, sizeof(conf));
	if (!x) {
		printf("xudp init fail\n");
		return -1;
	}
	gx = x;

	in.sin_family      = AF_INET;
	in.sin_addr.s_addr = inet_addr(addr);
	in.sin_port        = htons(port);
	ret = xudp_bind(x, &in, 1);

	if (ret) {
		printf("xudp bind fail %d\n", ret);
		return -1;
	}

	/* for xquic */
	if (xquic_args(x)) {
		printf("xquic xdp config fail\n");
		return -1;
	}
	/* for xquic end */

	efd = epoll_create(1024);

	epoll_add(x, efd, 0);
	epoll_add(x, efd, 1);

	signal(SIGINT, int_exit);
	signal(SIGTERM, int_exit);
	signal(SIGABRT, int_exit);

	loop(efd);
}
