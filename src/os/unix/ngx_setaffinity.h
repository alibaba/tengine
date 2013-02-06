
/*
 * Copyright (C) Nginx, Inc.
 */

#ifndef _NGX_SETAFFINITY_H_INCLUDED_
#define _NGX_SETAFFINITY_H_INCLUDED_

#if (NGX_HAVE_SCHED_SETAFFINITY)

#define CPU_SET_T cpu_set_t
#define ngx_setaffinity(pmask) sched_setaffinity(0, sizeof(cpu_set_t), pmask)
#define ngx_setaffinity_n "sched_setaffinity"

#elif (NGX_HAVE_CPUSET_SETAFFINITY)

#include <sys/cpuset.h>

#define CPU_SET_T cpuset_t
#define ngx_setaffinity(pmask) cpuset_setaffinity(CPU_LEVEL_WHICH, \
                              CPU_WHICH_PID, -1, sizeof(cpuset_t), pmask)
#define ngx_setaffinity_n "cpuset_setaffinity"

#endif

#if (NGX_HAVE_SCHED_SETAFFINITY || NGX_HAVE_CPUSET_SETAFFINITY)

#define NGX_HAVE_CPU_AFFINITY 1

#endif


#endif /* _NGX_SETAFFINITY_H_INCLUDED_ */
