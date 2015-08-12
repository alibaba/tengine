
/*
 * Copyright (C) 2010-2014 Alibaba Group Holding Limited
 */


#include <ngx_tfs_common.h>
#include <ngx_http_tfs_protocol.h>
#include <ngx_http_tfs_errno.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <net/if.h>
#include <netinet/in.h>
#include <net/if_arp.h>
#include <ngx_md5.h>
#include <ngx_http_tfs_peer_connection.h>


static char  *week[] = { "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" };
static char  *months[] = { "Jan", "Feb", "Mar", "Apr", "May", "Jun",
                           "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" };


ngx_int_t
ngx_http_tfs_test_connect(ngx_connection_t *c)
{
    int        err;
    socklen_t  len;

#if (NGX_HAVE_KQUEUE)

    if (ngx_event_flags & NGX_USE_KQUEUE_EVENT)  {
        if (c->write->pending_eof) {
            c->log->action = "connecting to upstream";
            (void) ngx_connection_error(c, c->write->kq_errno,
                "kevent() reported that connect() failed");
            return NGX_ERROR;
        }

    } else
#endif
    {
        err = 0;
        len = sizeof(int);

        /*
         * BSDs and Linux return 0 and set a pending error in err
         * Solaris returns -1 and sets errno
         */

        if (getsockopt(c->fd, SOL_SOCKET, SO_ERROR, (void *) &err, &len)
            == -1)
        {
            err = ngx_errno;
        }

        if (err) {
            c->log->action = "connecting to upstream";
            (void) ngx_connection_error(c, err, "connect() failed");
            return NGX_ERROR;
        }
    }

    return NGX_OK;
}


uint64_t
ngx_http_tfs_generate_packet_id(void)
{
    static uint64_t id = 2;

    if (id >= INT_MAX - 1) {
        id = 1;
    }

    return ++id;
}


ngx_chain_t *
ngx_http_tfs_alloc_chains(ngx_pool_t *pool, size_t count)
{
    ngx_uint_t               i;
    ngx_chain_t             *cl, **ll;

    ll = &cl;

    for (i = 0; i < count; i++) {
        *ll = ngx_alloc_chain_link(pool);
        if (*ll == NULL) {
            return NULL;
        }

        ll = &(*ll)->next;
    }

    (*ll) = NULL;

    return cl;
}


ngx_chain_t *
ngx_http_tfs_chain_get_free_buf(ngx_pool_t *p,
    ngx_chain_t **free, size_t size)
{
    ngx_chain_t  *cl;

    if (*free) {
        cl = *free;
        if ((size_t) (cl->buf->end - cl->buf->start) >= size) {
            *free = cl->next;
            cl->next = NULL;
            return cl;
        }
    }

    cl = ngx_alloc_chain_link(p);
    if (cl == NULL) {
        return NULL;
    }

    cl->buf = ngx_create_temp_buf(p, size);
    if (cl->buf == NULL) {
        return NULL;
    }

    cl->next = NULL;

    return cl;
}


void
ngx_http_tfs_free_chains(ngx_chain_t **free, ngx_chain_t **out)
{
    ngx_chain_t              *cl;

    cl = *out;

    while(cl) {
        cl->buf->pos = cl->buf->start;
        cl->buf->last = cl->buf->start;
        cl->buf->file_pos = 0;

        cl->next = *free;
        *free = cl;
    }
}


ngx_int_t
ngx_http_tfs_parse_headerin(ngx_http_request_t *r, ngx_str_t *header_name,
    ngx_str_t *value)
{
    ngx_uint_t        i;
    ngx_list_part_t  *part;
    ngx_table_elt_t  *header;

    part = &r->headers_in.headers.part;
    header = part->elts;

    for (i = 0; /* void */; i++) {

        if (i >= part->nelts) {
            if (part->next == NULL) {
                break;
            }

            part = part->next;
            header = part->elts;
            i = 0;
        }

        if (header[i].hash == 0) {
            continue;
        }

        if (header_name->len ==  header[i].key.len
            && ngx_strncasecmp(header[i].key.data, header_name->data,
                               header_name->len) == 0)
        {
            *value = header[i].value;
            return NGX_OK;
        }
    }

    return NGX_DECLINED;
}


ngx_int_t
ngx_http_tfs_compute_buf_crc(ngx_http_tfs_crc_t *t_crc, ngx_buf_t *b,
    size_t size, ngx_log_t *log)
{
    u_char  *dst;
    ssize_t  n;

    if (ngx_buf_in_memory(b)) {
        t_crc->crc = ngx_http_tfs_crc(t_crc->crc,
                                      (const char *) (b->pos), size);
        t_crc->data_crc = ngx_http_tfs_crc(t_crc->data_crc,
                                           (const char *) (b->pos), size);
        b->last = b->pos + size;
        return NGX_OK;
    }

    dst = ngx_alloc(size, log);
    if (dst == NULL) {
        return 0;
    }

    n = ngx_read_file(b->file, dst, (size_t) size, b->file_pos);

    if (n == NGX_ERROR) {
        goto crc_error;
    }

    if (n != (ssize_t) size) {
        ngx_log_error(NGX_LOG_ALERT, log, 0,
                      ngx_read_file_n " read only %z of %O from \"%s\"",
                      n, size, b->file->name.data);
        goto crc_error;
    }

    t_crc->crc = ngx_http_tfs_crc(t_crc->crc, (const char *) dst, size);
    t_crc->data_crc = ngx_http_tfs_crc(t_crc->data_crc,
                                       (const char *) dst, size);
    free(dst);

    b->file_last = b->file_pos + n;
    return NGX_OK;

crc_error:
    free(dst);
    return NGX_ERROR;
}


ngx_int_t
ngx_http_tfs_peer_set_addr(ngx_pool_t *pool, ngx_http_tfs_peer_connection_t *p,
    ngx_http_tfs_inet_t *addr)
{
    struct sockaddr_in     *in;
    ngx_peer_connection_t  *peer;

    if (addr == NULL) {
        return NGX_ERROR;
    }

    in = ngx_pcalloc(pool, sizeof(struct sockaddr_in));
    if (in == NULL) {
        return NGX_ERROR;
    }

    in->sin_family = AF_INET;
    in->sin_port = htons(addr->port);
    in->sin_addr.s_addr = addr->ip;

    peer = &p->peer;
    peer->sockaddr = (struct sockaddr *) in;
    peer->socklen = sizeof(struct sockaddr_in);

    ngx_sprintf(p->peer_addr_text, "%s:%d",
                inet_ntoa(in->sin_addr),
                ntohs(in->sin_port));

    return NGX_OK;
}


uint32_t
ngx_http_tfs_murmur_hash(u_char *data, size_t len)
{
    uint32_t  h, k;

    h = NGX_HTTP_TFS_MUR_HASH_SEED ^ len;

    while (len >= 4) {
        k  = data[0];
        k |= data[1] << 8;
        k |= data[2] << 16;
        k |= data[3] << 24;

        k *= 0x5bd1e995;
        k ^= k >> 24;
        k *= 0x5bd1e995;

        h *= 0x5bd1e995;
        h ^= k;

        data += 4;
        len -= 4;
    }

    switch (len) {
    case 3:
        h ^= data[2] << 16;
    case 2:
        h ^= data[1] << 8;
    case 1:
        h ^= data[0];
        h *= 0x5bd1e995;
    }

    h ^= h >> 13;
    h *= 0x5bd1e995;
    h ^= h >> 15;

    return h;
}


ngx_int_t
ngx_http_tfs_parse_inet(ngx_str_t *u, ngx_http_tfs_inet_t *addr)
{
    u_char    *port, *last;
    size_t     len;
    ngx_int_t  n;

    last = u->data + u->len;

    port = ngx_strlchr(u->data, last, ':');

    if (port) {
        port++;

        len = last - port;

        if (len == 0) {
            return NGX_ERROR;
        }

        n = ngx_atoi(port, len);

        if (n < 1 || n > 65535) {
            return NGX_ERROR;
        }

        addr->port = n;

        addr->ip = ngx_inet_addr(u->data, u->len - len - 1);
        if (addr->ip == INADDR_NONE) {
            return NGX_ERROR;
        }

    } else {
        return NGX_ERROR;
    }

    return NGX_OK;
}


int32_t
ngx_http_tfs_raw_fsname_hash(const u_char *str, const int32_t len)
{
    int32_t  h, i;

    h = 0;

    if (str == NULL || len <=0) {
        return 0;
    }

    for (i = 0; i < len; ++i) {
        h += str[i];
        h *= 7;
    }

    return (h | 0x80000000);
}


ngx_int_t
ngx_http_tfs_get_local_ip(ngx_str_t device, struct sockaddr_in *addr)
{
    int           sock;
    struct ifreq  ifr;

    if((sock = socket(AF_INET, SOCK_DGRAM, 0)) < 0) {
        return NGX_ERROR;
    }

    ngx_memcpy(ifr.ifr_name, device.data, device.len);
    ifr.ifr_name[device.len] ='\0';

    if(ioctl(sock, SIOCGIFADDR, &ifr) < 0) {
        close(sock);
        return NGX_ERROR;
    }

    *addr = *((struct sockaddr_in *) &ifr.ifr_addr);

    close(sock);
    return NGX_OK;
}


ngx_buf_t *
ngx_http_tfs_copy_buf_chain(ngx_pool_t *pool, ngx_chain_t *in)
{
    ngx_int_t    len;
    ngx_buf_t   *buf;
    ngx_chain_t *cl;

    if (in->next == NULL) {
        return in->buf;
    }

    len = 0;

    for (cl = in; cl; cl = cl->next) {
        len += ngx_buf_size(cl->buf);
    }

    buf = ngx_create_temp_buf(pool, len);

    if (buf == NULL) {
        return NULL;
    }

    for (cl = in; cl; cl = cl->next) {
        buf->last = ngx_copy(buf->last, cl->buf->pos, ngx_buf_size(cl->buf));
    }
    return buf;
}


ngx_int_t
ngx_http_tfs_sum_md5(ngx_chain_t *data, u_char *md5_final,
    ssize_t *data_len, ngx_log_t *log)
{
    u_char    *buf;
    ssize_t    n, buf_size;
    ngx_md5_t  md5;

    ngx_md5_init(&md5);

    while(data) {
        if (ngx_buf_in_memory(data->buf)) {
            ngx_md5_update(&md5, data->buf->pos, ngx_buf_size(data->buf));
            *data_len += ngx_buf_size(data->buf);

        } else {
            /* two buf */
            buf_size = ngx_buf_size(data->buf);
            buf = ngx_alloc(buf_size, log);
            if (buf == NULL) {
                return NGX_ERROR;
            }

            n = ngx_read_file(data->buf->file, buf,
                              buf_size, data->buf->file_pos);
            if (n == NGX_ERROR) {
                free(buf);
                return NGX_ERROR;
            }

            if (n != buf_size) {
                ngx_log_error(NGX_LOG_ALERT, log, 0,
                              ngx_read_file_n " read only %z of %O from \"%s\"",
                              n, buf_size, data->buf->file->name.data);
                free(buf);
                return NGX_ERROR;
            }

            ngx_md5_update(&md5, buf, n);
            free(buf);
            *data_len += buf_size;
        }

        data = data->next;
    }

    ngx_md5_final(md5_final, &md5);

    return NGX_OK;
}


u_char *
ngx_http_tfs_time(u_char *buf, time_t t)
{
    ngx_tm_t  tm;

    ngx_gmtime(t, &tm);

    return ngx_sprintf(buf, "%s, %02d %s %4d %02d:%02d:%02d GMT",
                       week[tm.ngx_tm_wday],
                       tm.ngx_tm_mday,
                       months[tm.ngx_tm_mon - 1],
                       tm.ngx_tm_year,
                       tm.ngx_tm_hour,
                       tm.ngx_tm_min,
                       tm.ngx_tm_sec);
}


ngx_int_t
ngx_http_tfs_status_message(ngx_buf_t *b, ngx_str_t *action, ngx_log_t *log)
{
    int32_t                     code, err_len;
    ngx_str_t                   err;
    ngx_http_tfs_status_msg_t  *res;

    res = (ngx_http_tfs_status_msg_t *) b->pos;
    err.len = 0;
    code = res->code;

    if (code != NGX_HTTP_TFS_STATUS_MESSAGE_OK) {
        err_len = res->error_len;
        if (err_len > 0) {
            err.data = res->error_str;
            err.len = err_len;
        }

        ngx_log_error(NGX_LOG_ERR, log, 0,
                      "%V failed error code (%d) err_msg(%V)",
                      action, code, &err);
        if (code <= NGX_HTTP_TFS_EXIT_GENERAL_ERROR) {
            return code;
        }

        return NGX_HTTP_TFS_EXIT_GENERAL_ERROR;
    }

    ngx_log_error(NGX_LOG_INFO, log, 0, "%V success ", action);
    return NGX_OK;
}


ngx_int_t
ngx_http_tfs_get_parent_dir(ngx_str_t *file_path, ngx_int_t *dir_level)
{
    ngx_uint_t  i, last_slash_pos;

    last_slash_pos = 0;

    if (dir_level != NULL) {
        *dir_level = 0;
    }

    for (i = 0; i < (file_path->len - 1); i++) {
        if (file_path->data[i] == '/'
            && (file_path->data[i + 1]) != '/')
        {
            last_slash_pos = i;
            if (dir_level != NULL) {
                (*dir_level)++;
            }
        }
    }

    return last_slash_pos + 1;
}


ngx_int_t
ngx_http_tfs_set_output_file_name(ngx_http_tfs_t *t)
{
    ngx_chain_t  *cl, **ll;

    if (t->json_output == NULL) {
        t->json_output = ngx_http_tfs_json_init(t->log, t->pool);
        if (t->json_output == NULL) {
            return NGX_ERROR;
        }
    }

    for (cl = t->out_bufs, ll = &t->out_bufs; cl; cl = cl->next) {
        ll = &cl->next;
    }

    /* set final return file name */
    if (t->r_ctx.fsname.cluster_id == 0) {
        t->r_ctx.fsname.cluster_id = t->file.cluster_id;
    }
    t->file_name.len = NGX_HTTP_TFS_FILE_NAME_LEN;
    if (t->r_ctx.simple_name) {
        t->file_name.len += t->r_ctx.file_suffix.len;
    }
    t->file_name.data = ngx_palloc(t->pool, t->file_name.len);
    ngx_memcpy(t->file_name.data,
               ngx_http_tfs_raw_fsname_get_name(&t->r_ctx.fsname,
                                                t->is_large_file,
                                                t->r_ctx.simple_name),
               NGX_HTTP_TFS_FILE_NAME_LEN);

    if (t->r_ctx.simple_name) {
        if (t->r_ctx.file_suffix.data != NULL) {
            ngx_memcpy(t->file_name.data + NGX_HTTP_TFS_FILE_NAME_LEN,
                       t->r_ctx.file_suffix.data, t->r_ctx.file_suffix.len);
        }
    }

    /* set dup_file_name(put to tair) */
    if (t->use_dedup) {
        t->dedup_ctx.dup_file_name.len =
            NGX_HTTP_TFS_FILE_NAME_LEN + t->r_ctx.file_suffix.len;
        t->dedup_ctx.dup_file_name.data =
            ngx_palloc(t->pool, t->dedup_ctx.dup_file_name.len);
        if (t->dedup_ctx.dup_file_name.data == NULL) {
            return NGX_ERROR;
        }
        ngx_memcpy(t->dedup_ctx.dup_file_name.data,
                   ngx_http_tfs_raw_fsname_get_name(&t->r_ctx.fsname, 0, 0),
                   NGX_HTTP_TFS_FILE_NAME_LEN);
        if (t->r_ctx.file_suffix.data != NULL) {
            ngx_memcpy(t->dedup_ctx.dup_file_name.data
                       + NGX_HTTP_TFS_FILE_NAME_LEN,
                       t->r_ctx.file_suffix.data, t->r_ctx.file_suffix.len);
        }
    }

    cl = ngx_http_tfs_json_file_name(t->json_output, &t->file_name);
    if (cl == NULL) {
        return NGX_ERROR;
    }

    *ll = cl;
    return NGX_OK;
}


long long
ngx_http_tfs_atoll(u_char *line, size_t n)
{
    long long value;

    if (n == 0) {
        return NGX_ERROR;
    }

    for (value = 0; n--; line++) {
        if (*line < '0' || *line > '9') {
            return NGX_ERROR;
        }

        value = value * 10 + (*line - '0');
    }

    if (value < 0) {
        return NGX_ERROR;

    } else {
        return value;
    }
}


ngx_int_t
ngx_http_tfs_atoull(u_char *line, size_t n, unsigned long long *value)
{
    unsigned long long res;

    for (res = 0; n--; line++) {
        unsigned int val;

        if (*line < '0' || *line > '9') {
            return NGX_ERROR;
        }

        val = *line - '0';

        /*
         * Check for overflow
         */

        if (res & (~0ull << 60)) {

            if (res > ((ULLONG_MAX - val) / 10)) {
                return NGX_ERROR;
            }
        }

        res = res * 10 + val;
    }

    *value = res;

    return NGX_OK;
}


void *
ngx_http_tfs_prealloc(ngx_pool_t *pool, void *p,
    size_t old_size, size_t new_size)
{
    void *new;

    if (p == NULL) {
        return ngx_palloc(pool, new_size);
    }

    if (new_size == 0) {
        if ((u_char *) p + old_size == pool->d.last) {
           pool->d.last = p;
        } else {
           ngx_pfree(pool, p);
        }

        return NULL;
    }

    if ((u_char *) p + old_size == pool->d.last
        && (u_char *) p + new_size <= pool->d.end)
    {
        pool->d.last = (u_char *) p + new_size;
        return p;
    }

    new = ngx_palloc(pool, new_size);
    if (new == NULL) {
        return NULL;
    }

    ngx_memcpy(new, p, old_size);

    ngx_pfree(pool, p);

    return new;
}


uint64_t
ngx_http_tfs_get_chain_buf_size(ngx_chain_t *data)
{
    uint64_t      size;
    ngx_chain_t  *cl;

    size = 0;
    cl = data;
    while (cl) {
        size += ngx_buf_size(cl->buf);
        cl = cl->next;
    }

    return size;
}


void
ngx_http_tfs_dump_segment_data(ngx_http_tfs_segment_data_t *segment,
    ngx_log_t *log)
{
    ngx_log_debug7(NGX_LOG_DEBUG_HTTP, log, 0,
                   "=========dump segment data=========\n"
                   "block id: %uD, file id: %uL, "
                   "offset: %L, size: %uL, crc: %uD, "
                   "oper_offset: %uD, oper_size: %uL",
                   segment->segment_info.block_id,
                   segment->segment_info.file_id,
                   segment->segment_info.offset,
                   segment->segment_info.size,
                   segment->segment_info.crc,
                   segment->oper_offset,
                   segment->oper_size);
}


ngx_http_tfs_t *
ngx_http_tfs_alloc_st(ngx_http_tfs_t *t)
{
    ngx_buf_t       *b;
    ngx_http_tfs_t  *st;

    st = t->free_sts;

    if (st) {
        t->free_sts = st->next;
        return st;
    }

    st = ngx_palloc(t->pool, sizeof(ngx_http_tfs_t));
    if (st == NULL) {
        return NULL;
    }
    ngx_memcpy(st, t, sizeof(ngx_http_tfs_t));
    st->parent = t;

    /* each st should have independent send/recv buf/peer/out_bufs,
     * and we only care about data server and name server(retry need)
     */

    /* recv(from upstream servers) bufs */
    st->recv_chain = ngx_http_tfs_alloc_chains(t->pool, 2);
    if (st->recv_chain == NULL) {
        return NULL;
    }
    st->header_buffer.start = NULL;

    /* peers */
    st->tfs_peer_servers = ngx_pcalloc(t->pool,
        sizeof(ngx_http_tfs_peer_connection_t) * NGX_HTTP_TFS_SERVER_COUNT);
    if (st->tfs_peer_servers == NULL) {
        return NULL;
    }

    /* name server related */
    ngx_memcpy(&st->tfs_peer_servers[NGX_HTTP_TFS_NAME_SERVER],
               &t->tfs_peer_servers[NGX_HTTP_TFS_NAME_SERVER],
               sizeof(ngx_http_tfs_peer_connection_t));
    st->tfs_peer_servers[NGX_HTTP_TFS_NAME_SERVER].body_buffer.start = NULL;
    st->tfs_peer_servers[NGX_HTTP_TFS_NAME_SERVER].peer.connection = NULL;

    /* data server related */
    ngx_memcpy(&st->tfs_peer_servers[NGX_HTTP_TFS_DATA_SERVER],
               &t->tfs_peer_servers[NGX_HTTP_TFS_DATA_SERVER],
               sizeof(ngx_http_tfs_peer_connection_t));
    b = &st->tfs_peer_servers[NGX_HTTP_TFS_DATA_SERVER].body_buffer;
    if (t->r_ctx.action.code == NGX_HTTP_TFS_ACTION_WRITE_FILE) {
        b->start = NULL;

    } else if (t->r_ctx.action.code == NGX_HTTP_TFS_ACTION_READ_FILE){
        /* alloc buf that can hold all segment's data,
         * so that ngx_http_tfs_process_buf_overflow would not happen
         */
        b->start = ngx_palloc(t->pool, NGX_HTTP_TFS_MAX_FRAGMENT_SIZE);
        if (b->start == NULL) {
            return NULL;
        }

        b->pos = b->start;
        b->last = b->start;
        b->end = b->start + NGX_HTTP_TFS_MAX_FRAGMENT_SIZE;
        b->temporary = 1;
    }

    st->output.filter_ctx = &st->writer;

    st->is_large_file = NGX_HTTP_TFS_NO;
    st->file.segment_count = 1;

    return st;
}


ngx_int_t
ngx_http_tfs_get_content_type(u_char *data, ngx_str_t *type)
{
    if (memcmp(data, "GIF", 3) == 0) {
        ngx_str_set(type, "image/gif");
        return NGX_OK;
    }

    if (memcmp(data, "\xff\xd8\xff", 3) == 0) {
        ngx_str_set(type, "image/jpeg");
        return NGX_OK;
    }

    if (memcmp(data, "\x89\x50\x4e\x47\x0d\x0a\x1a\x0a", 8) == 0) {
        ngx_str_set(type, "image/png");
        return NGX_OK;
    }

    if ((memcmp(data, "CWS", 3) == 0)
              ||(memcmp(data, "FWS", 3) == 0))
    {
        ngx_str_set(type, "application/x-shockwave-flash");
        return NGX_OK;
    }

    if ((memcmp(data, "BM", 2) == 0)
              ||(memcmp(data, "BA", 2) == 0)
              ||(memcmp(data, "CI", 2) == 0)
              ||(memcmp(data, "CP", 2) == 0)
              ||(memcmp(data, "IC", 2) == 0)
              ||(memcmp(data, "PI", 2) == 0))
    {
        ngx_str_set(type, "image/bmp");
        return NGX_OK;
    }

    if ((memcmp(data, "\115\115\000\052", 4) == 0)
            ||(memcmp(data, "\111\111\052\000", 4) == 0)
            ||(memcmp(data, "\115\115\000\053\000\010\000\000", 8) == 0)
            ||(memcmp(data, "\111\111\053\000\010\000\000\000", 8) == 0))
    {
        ngx_str_set(type, "image/tiff");
        return NGX_OK;
    }

    return NGX_AGAIN;
}


ngx_msec_int_t
ngx_http_tfs_get_request_time(ngx_http_tfs_t *t)
{
    ngx_time_t                *tp;
    ngx_msec_int_t             ms;
    struct timeval             tv;
    ngx_http_request_t        *r;
    ngx_http_core_loc_conf_t  *clcf;

    r = t->data;
    clcf = ngx_http_get_module_loc_conf(r, ngx_http_core_module);
    if (clcf->request_time_cache) {
        tp = ngx_timeofday();
        ms = (ngx_msec_int_t)
                 ((tp->sec - r->start_sec) * 1000 + (tp->msec - r->start_msec));
    } else {
        ngx_gettimeofday(&tv);
        ms = (tv.tv_sec - r->start_sec) * 1000
                 + (tv.tv_usec / 1000 - r->start_msec);
    }

    ms = ngx_max(ms, 0);

    return ms;
}


ngx_int_t
ngx_chain_add_copy_with_buf(ngx_pool_t *pool, ngx_chain_t **chain, ngx_chain_t *in)
{
    ngx_buf_t    *b;
    ngx_chain_t  *cl, **ll;

    ll = chain;
    for (cl = *chain; cl; cl = cl->next) {
        ll = &cl->next;
    }

    while (in) {
        b = ngx_alloc_buf(pool);
        if (b == NULL) {
            return NGX_ERROR;
        }
        ngx_memcpy(b, in->buf, sizeof(ngx_buf_t));
        cl = ngx_alloc_chain_link(pool);
        if (cl == NULL) {
            return NGX_ERROR;
        }
        cl->buf = b;
        *ll = cl;
        ll = &cl->next;
        in = in->next;
    }

    *ll = NULL;

    return NGX_OK;
}


void
ngx_http_tfs_wrap_raw_file_info(ngx_http_tfs_raw_file_info_t *file_info,
    ngx_http_tfs_raw_file_stat_t *file_stat)
{
    if (file_info != NULL && file_stat != NULL) {
        file_stat->id = file_info->id;
        file_stat->offset = file_info->offset;
        file_stat->size = file_info->size;
        file_stat->u_size = file_info->u_size;
        file_stat->modify_time = file_info->modify_time;
        file_stat->create_time = file_info->create_time;
        file_stat->flag = file_info->flag;
        file_stat->crc = file_info->crc;
    }
}
