
/*
 * Copyright (C) lhanjian (lhjay1@gmail.com)
 */

#ifndef _NGX_GETAFFINITY_H_INCLUDED_
#define _NGX_GETAFFINITY_H_INCLUDED_


#if (T_NGX_HAVE_SCHED_GETAFFINITY)

typedef cpu_set_t  ngx_cpuset_t;

void ngx_getaffinity(ngx_cpuset_t *cpu_affinity, ngx_log_t *log);

#else

#define ngx_getaffinity(cpu_affinity, log)

typedef uint64_t  ngx_cpuset_t;

#endif


#endif /* _NGX_SETAFFINITY_H_INCLUDED_ */
