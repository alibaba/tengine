#include <ngx_event.h>
#include <ngx_event_udpv2.h>
#if (T_NGX_UDPV2)
/**
 * for udpv2 posted event
 * */
ngx_queue_t         ngx_udpv2_posted_event;

typedef struct ngx_udpv2_msg_control_st ngx_udpv2_msg_control_t;

struct ngx_udpv2_msg_control_st
{
    union {
#if (NGX_HAVE_MSGHDR_MSG_CONTROL)
        #if (NGX_HAVE_IP_RECVDSTADDR)
        u_char             msg_control[CMSG_SPACE(sizeof(struct in_addr))];
#elif (NGX_HAVE_IP_PKTINFO)
        u_char             msg_control[CMSG_SPACE(sizeof(struct in_pktinfo))];
#endif // NGX_HAVE_IP_RECVDSTADDR

#if (NGX_HAVE_INET6 && NGX_HAVE_IPV6_RECVPKTINFO)
        u_char             msg_control6[CMSG_SPACE(sizeof(struct in6_pktinfo))];
#endif // NGX_HAVE_INET6 && NGX_HAVE_IPV6_RECVPKTINFO

#endif // NGX_HAVE_MSGHDR_MSG_CONTROL
    } __ipinfo;

    u_char                 ts[CMSG_SPACE(sizeof(struct timespec))]  ;
};

void
ngx_event_udpv2_init_listening(ngx_listening_t *ls) {

    ls->udpv2_current_processing = NULL;
    ngx_queue_init(&ls->udpv2_filter);

    ls->udpv2_traffic_filter.func = NULL;
    ngx_udpv2_add_dispatch_filter(ls, &ls->udpv2_traffic_filter);
}

void
ngx_udpv2_write_handler_mainlogic(ngx_event_t *wev)
{
    ngx_listening_t *ls;
    ngx_connection_t *lc;

    lc  = (ngx_connection_t*)(wev->data) ;
    ls = lc->listening ;

    /* 不管是何种触发方式，删除写事件 */
    ngx_del_event(wev, NGX_WRITE_EVENT, 0);

    /* 处理posted的写事件 */
    ngx_event_process_posted((ngx_cycle_t *) ngx_cycle, ngx_udpv2_writable_queue(ls));
}

ngx_inline ngx_queue_t *
ngx_udpv2_writable_queue(ngx_listening_t *ls)
{
    return &ls->writable_queue;
}

ngx_queue_t *
ngx_udpv2_active_writable_queue(ngx_listening_t *ls)
{
    ngx_event_t         *wev;
    ngx_connection_t    *c;

    if (!ls) {
        return NULL;
    }

    c   = ls->connection;
    wev = c->write;

    if (!wev->active) {
        // active writable event
        ngx_handle_write_event(wev, 0);
    }

    return ngx_udpv2_writable_queue(ls);
}

int
ngx_udpv2_push_dispatch_filter(ngx_cycle_t *cycle, ngx_listening_t *ls, ngx_udpv2_traffic_filter_handler func)
{
    ngx_udpv2_traffic_filter_t  *tf;
    tf = ngx_pcalloc(cycle->pool, sizeof(*tf));
    if (!tf) {
        return NGX_ERROR;
    }
    tf->func = func;
    ngx_udpv2_add_dispatch_filter(ls, tf);
    return NGX_OK;
}


ngx_listening_t*
ngx_udpv2_reset_dispatch_filter(ngx_listening_t *ls)
{
    ngx_queue_init(&ls->udpv2_filter);
    return ls;
}

ngx_listening_t*
ngx_udpv2_add_dispatch_filter(ngx_listening_t *ls,ngx_udpv2_traffic_filter_t *filter)
{
    ngx_queue_insert_tail(&ls->udpv2_filter,&filter->sk);
    return ls;
}

ngx_inline void
ngx_udpv2_process_posted_traffic() {
    /* trigger posted event if nessary */
    ngx_event_process_posted((ngx_cycle_t *) ngx_cycle, &ngx_udpv2_posted_event);
}

ngx_inline void
ngx_udpv2_dispatch_traffic(ngx_udpv2_packets_hdr_t *uhdr)
{
    ngx_listening_t *ls ;
    ngx_udpv2_traffic_filter_t *filter;
    ngx_queue_t *head ;
    ngx_queue_t  *f;
    ngx_queue_t  *p, *n;
    size_t i;
    ngx_udpv2_packet_t *upkt , *prev;

    /* validate */
    if (uhdr == NULL || uhdr->ls == NULL) {
        return;
    }

    size_t sz = uhdr->npkts;

    ls      = uhdr->ls;
    head    = &(uhdr->ls->udpv2_filter);
    prev    = ls->udpv2_current_processing;

    for(f = ngx_queue_head(head); sz > 0 && f != head ; f = ngx_queue_next(f)) {

        filter = ngx_queue_data(f, ngx_udpv2_traffic_filter_t, sk);
        if (!filter->func) {
            continue;
        }

        for(i = 0 , p = ngx_queue_head(&uhdr->pkts) ; i < sz ; i++ ){

            upkt = ngx_queue_data(p, ngx_udpv2_packet_t, pkt_list);
            n = ngx_queue_next(p);

            ls->udpv2_current_processing = upkt;
            ngx_memory_barrier();

            switch(filter->func(ls, upkt)) {
                case NGX_UDPV2_DONE:
                case NGX_UDPV2_DROP:
                {
                    if (--uhdr->npkts > 0) {
                        ngx_queue_remove(p);
                        ngx_queue_insert_tail(&uhdr->pkts, p);
                    }
                }
                default:
                    break;
            }

            p = n ;
        }

        /* update sz */
        sz = uhdr->npkts ;
    }

    /* reset current processing */
    ls->udpv2_current_processing = prev;
}

void
ngx_udpv2_dispatch_packet(ngx_listening_t* ls, ngx_udpv2_packet_t *upkt, ngx_uint_t flags)
{
    ngx_udpv2_packets_hdr_t uhdr = NGX_UDPV2_PACKETS_HDR_INIT(uhdr);

    uhdr.ls = ls;
    NGX_UDPV2_PACKETS_HDR_ADD_PACKET(&uhdr, upkt);
    uhdr.npkts = 1;

    ngx_udpv2_dispatch_traffic(&uhdr);
    ngx_udpv2_process_posted_traffic();
}

#endif