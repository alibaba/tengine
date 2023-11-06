
/*
 * Copyright (C) lhanjian (lhjay1@gmail.com)
 */


#include <ngx_config.h>
#include <ngx_core.h>


#if (T_NGX_HAVE_SCHED_GETAFFINITY)

void
ngx_getaffinity(ngx_cpuset_t *cpu_affinity, ngx_log_t *log)
{
    if (sched_getaffinity(0, sizeof(cpu_set_t), cpu_affinity) == -1) {
        ngx_log_error(NGX_LOG_ALERT, log, ngx_errno,
                      "sched_setaffinity() failed");
    }
}

#endif
