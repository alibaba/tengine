
/*
 * Copyright (C) Igor Sysoev
 * Copyright (C) Nginx, Inc.
 */


#ifndef _NGINX_H_INCLUDED_
#define _NGINX_H_INCLUDED_


#define nginx_version      1017003
#define NGINX_VERSION      "1.17.3"
#define NGINX_VER          "nginx/" NGINX_VERSION

#define TENGINE            "Tengine"
#define tengine_version    2003002
#define TENGINE_VERSION    "2.3.2"
#define TENGINE_VER        TENGINE "/" TENGINE_VERSION

#ifdef NGX_BUILD
#define NGINX_VER_BUILD    NGINX_VER " (" NGX_BUILD ")"
#define TENGINE_VER_BUILD  TENGINE_VER " (" NGX_BUILD ")"
#else
#define NGINX_VER_BUILD    NGINX_VER
#define TENGINE_VER_BUILD  TENGINE_VER
#endif

#define NGINX_VAR          "NGINX"
#define NGX_OLDPID_EXT     ".oldbin"


#endif /* _NGINX_H_INCLUDED_ */
