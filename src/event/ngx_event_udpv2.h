#ifndef _NGX_EVENT_UDP_V2_H_INCLUDED_
#define _NGX_EVENT_UDP_V2_H_INCLUDED_
#if (T_NGX_UDPV2)
/**
 * @david.sw
 * udpv2 is extensible
 * it is based on nginx udp
 * */

#ifndef _NGX_EVENT_H_INCLUDED_
#error "do not include ngx_event_udpv2 directly, include ngx_event.h. "
#endif

#include <ngx_core.h>

/**
 * declare for posted event
 * */
extern ngx_queue_t ngx_udpv2_posted_event;

/**
 * marcos
 * */
#define NGX_UDPV2_ALIGN(n)          __attribute__((aligned(n)))
#define NGX_UDPV2_PACK(name,n)      unsigned char name[0] NGX_UDPV2_ALIGN(n)

/**
 * flags for dispatch
 * */
#define NGX_UDPV2_F_DELAY_POSTED    0x1

/**
 * udp packet
 * */
struct ngx_udpv2_packet_st
{
    /* offset to payload   */
    unsigned char*          pkt_payload;
    /* payload size         */
    size_t                  pkt_sz;
    /* microsecond of udp packet generation */
    uint64_t                pkt_micrs;
    /* local sockaddr of udp packet */
    ngx_sockaddr_t          pkt_local_sockaddr;
    /* length of local sockaddr for udp packet */
    socklen_t               pkt_local_socklen;
    /* remote sockaddr of udp packet */
    ngx_sockaddr_t          pkt_sockaddr;
    /* length of remote sockaddr for udp packet */
    socklen_t               pkt_socklen;
    NGX_UDPV2_PACK(property, NGX_CPU_CACHE_LINE);
    /* list node for packet */
    ngx_queue_t             pkt_list;

} NGX_UDPV2_ALIGN(NGX_CPU_CACHE_LINE);

/**
 * udp packets hdr
 * */
struct ngx_udpv2_packets_hdr_st
{
    /**
     * list for pkts
     * */
    ngx_queue_t         pkts;

    /**
    * from where
     * */
    ngx_listening_t    *ls;

    /**
     * capability of pkts
     * */
    size_t              pkts_capability ;

    /**
     * number of pkts ready
     * */
    ssize_t             npkts;

    /**
     * flags for pkts
     * */
    int                 flags ;

};

#define NGX_UDPV2_PACKETS_HDR_INIT(name,...)  {     \
                                                    \
    {&(name.pkts),&(name.pkts)},                    \
    NULL,                                           \
    0,                                              \
    0,                                              \
    0,                                              \
    __VA_ARGS__                                     \
}

#define NGX_UDPV2_PACKETS_HDR_FIRST_PACKET(uhdr) ({                                 \
    ngx_udpv2_packets_hdr_t *__inner_hdr = (ngx_udpv2_packets_hdr_t*) (uhdr);       \
    ngx_queue_data(ngx_queue_head(&__inner_hdr->pkts),ngx_udpv2_packet_t,pkt_list); \
})

#define NGX_UDPV2_PACKETS_HDR_ADD_PACKET(uhdr, upkt)           do {                 \
    ngx_udpv2_packets_hdr_t *__inner_hdr = (ngx_udpv2_packets_hdr_t*) (uhdr);       \
    ngx_queue_insert_tail(&__inner_hdr->pkts, &((upkt)->pkt_list));                 \
    __inner_hdr->pkts_capability++;                                                 \
}while(0)


/**
 *  初始化udpv2所需的数据结构
 * */

void ngx_event_udpv2_init_listening(ngx_listening_t *ls);

/**
 *  分发流量到处理流量的连接
 *  当未找到合适的处理连接时，执行ls->udp_accept_handler(urp) or  ngx_event_udpv2_create_udp_connection
 * */

void ngx_udpv2_dispatch_traffic(ngx_udpv2_packets_hdr_t *uhdr);

/**
 * 通知所有udpv2批处理数据结束。
 * */
void ngx_udpv2_process_posted_traffic(void);

/**
 *  分发单个报文到处理流量的连接
 *  当未找到合适的处理连接时，执行ls->udp_accept_handler(urp) or  ngx_event_udpv2_create_udp_connection
 * */
void ngx_udpv2_dispatch_packet(ngx_listening_t *ls, ngx_udpv2_packet_t *upkt, ngx_uint_t flags);

/**
 * Get writable queue
 * */
ngx_queue_t * ngx_udpv2_writable_queue(ngx_listening_t *ls);

/**
 * Get writable queue  and try to active it
 * */
ngx_queue_t * ngx_udpv2_active_writable_queue(ngx_listening_t *ls);


/**
 * 在accept的udp模型中，模拟可写事件的核心逻辑。
 * */
void ngx_udpv2_write_handler_mainlogic(ngx_event_t *);

/**
 * add filter
 * */
int ngx_udpv2_push_dispatch_filter(ngx_cycle_t *cycle, ngx_listening_t *ls, ngx_udpv2_traffic_filter_handler func);

/**
 *  reset all traffic filter
 * */
ngx_listening_t* ngx_udpv2_reset_dispatch_filter(ngx_listening_t *ls);

/**
 * push new traffic filter as stack
 * */
ngx_listening_t* ngx_udpv2_add_dispatch_filter(ngx_listening_t *ls, ngx_udpv2_traffic_filter_t *filter);

#endif
#endif // _NGX_EVENT_UDP_V2_H_INCLUDED_`