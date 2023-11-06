
/*
 * Copyright (C) lhanjian (lhjay1@gmail.com)
 */

#ifndef _NGX_SETAFFINITY_H_INCLUDED_
#define _NGX_SETAFFINITY_H_INCLUDED_


#if (NGX_HAVE_SCHED_SETAFFINITY)

#define NGX_HAVE_CPU_AFFINITY 1

typedef cpu_set_t  ngx_cpuset_t;

void ngx_setaffinity(ngx_cpuset_t *cpu_affinity, ngx_log_t *log);

#else

#define ngx_setaffinity(cpu_affinity, log)

typedef uint64_t  ngx_cpuset_t;

#endif


#endif /* _NGX_SETAFFINITY_H_INCLUDED_ */
