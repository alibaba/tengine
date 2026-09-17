/*
 * Copyright (C) 2010-2015 Alibaba Group Holding Limited
 * Copyright (C) 2010-2013 Weibin Yao (yaoweibin@gmail.com)
 */


#ifndef _NGX_UPSTREAM_CHECK_MODULE_H_INCLUDED_
#define _NGX_UPSTREAM_CHECK_MODULE_H_INCLUDED_


#include <ngx_config.h>
#include <ngx_core.h>


/*
 * The health-check core (timer scheduling, shared peer state, the
 * connect/send/recv state machine, rise/fall accounting) is protocol
 * agnostic: it only ever needs a peer address and a check configuration.
 * This header holds everything both the HTTP and the stream side need, so
 * that neither one has to duplicate the core.
 *
 * The masks below say which side a checked peer was registered by. They are
 * used to reject check types that make no sense for a side (an HTTP request
 * probe against a stream upstream) and to label peers on the status page.
 */
#define NGX_UPSTREAM_CHECK_HTTP              0x0001
#define NGX_UPSTREAM_CHECK_STREAM            0x0002


typedef struct ngx_upstream_check_peer_s      ngx_upstream_check_peer_t;
typedef struct ngx_upstream_check_srv_conf_s  ngx_upstream_check_srv_conf_t;


typedef ngx_int_t (*ngx_upstream_check_packet_init_pt)
    (ngx_upstream_check_peer_t *peer);
typedef ngx_int_t (*ngx_upstream_check_packet_parse_pt)
    (ngx_upstream_check_peer_t *peer);
typedef void (*ngx_upstream_check_packet_clean_pt)
    (ngx_upstream_check_peer_t *peer);


typedef struct {
    ngx_uint_t                            type;

    ngx_str_t                             name;

    ngx_str_t                             default_send;

    /* HTTP */
    ngx_uint_t                            default_status_alive;

    ngx_event_handler_pt                  send_handler;
    ngx_event_handler_pt                  recv_handler;

    ngx_upstream_check_packet_init_pt      init;
    ngx_upstream_check_packet_parse_pt     parse;
    ngx_upstream_check_packet_clean_pt     reinit;

    unsigned need_pool;
    unsigned need_keepalive;

    /* sides this type may be configured on, NGX_UPSTREAM_CHECK_* mask */
    ngx_uint_t                            protocols;

    /*
     * Socket type of the probe connection: 0 (meaning SOCK_STREAM) for every
     * type but "udp". A datagram probe has no handshake, so it can only judge
     * a peer by what comes back -- see the "udp" entry in ngx_check_types.
     */
    int                                   pc_type;
} ngx_check_conf_t;


struct ngx_upstream_check_srv_conf_s {
    ngx_uint_t                            port;
    ngx_uint_t                            fall_count;
    ngx_uint_t                            rise_count;
    ngx_msec_t                            check_interval;
    ngx_msec_t                            check_timeout;
    ngx_uint_t                            check_keepalive_requests;

    ngx_check_conf_t                     *check_type_conf;
    ngx_str_t                             send;

    /* the "send" type: response bytes that mean the peer is alive */
    ngx_str_t                             expect;

    union {
        ngx_uint_t                        return_code;
        ngx_uint_t                        status_alive;
    } code;

    ngx_array_t                          *fastcgi_params;

    ngx_uint_t                            default_down;
    ngx_uint_t                            unique;
};


/*
 * Protocol-agnostic core, implemented by ngx_http_upstream_check_module.c.
 * The HTTP and stream modules are thin shells on top of these: they resolve
 * their own upstream configuration and then hand over a check configuration,
 * an upstream name and a peer address.
 */

/*
 * The container of checked peers is a single cross-protocol instance that is
 * rebuilt once per cycle. Both sides call this from create_main_conf; the
 * first call for a cycle creates the container, later ones get the same one.
 */
void *ngx_upstream_check_get_peers(ngx_conf_t *cf);

/*
 * Creates the shared memory zone backing the peer state. Idempotent per
 * cycle: whichever side runs its init_main_conf first creates the zone, the
 * other only contributes its "check_shm_size". Calling it twice for one cycle
 * would bump the shm generation twice and break the reload path, which finds
 * the previous zone by "generation - 1" to inherit peer health.
 */
char *ngx_upstream_check_init_shm(ngx_conf_t *cf, ngx_uint_t shm_size);

/* parses the arguments of a "check" directive into ucscf */
char *ngx_upstream_check_parse_directive(ngx_conf_t *cf,
    ngx_upstream_check_srv_conf_t *ucscf, ngx_uint_t protocol);

/*
 * "check_send" and "check_expect_response" of the protocol-independent "send"
 * type. Both take a byte string: on top of the \r, \n, \t and \\ escapes the
 * configuration parser already understands, \xHH is accepted so that binary
 * heartbeats can be spelled out.
 */
char *ngx_upstream_check_parse_send(ngx_conf_t *cf,
    ngx_upstream_check_srv_conf_t *ucscf);
char *ngx_upstream_check_parse_expect(ngx_conf_t *cf,
    ngx_upstream_check_srv_conf_t *ucscf);

/* fills in the defaults left unset by the "check" directive */
char *ngx_upstream_check_init_srv_conf(ngx_conf_t *cf,
    ngx_upstream_check_srv_conf_t *ucscf, ngx_uint_t protocol);

ngx_upstream_check_srv_conf_t *ngx_upstream_check_create_srv_conf(
    ngx_conf_t *cf);

ngx_uint_t ngx_upstream_check_add_peer(ngx_conf_t *cf,
    ngx_upstream_check_srv_conf_t *ucscf, ngx_str_t *upstream_name,
    ngx_addr_t *peer_addr, ngx_uint_t protocol);

ngx_uint_t ngx_upstream_check_add_dynamic_peer(ngx_pool_t *pool,
    ngx_upstream_check_srv_conf_t *ucscf, ngx_str_t *upstream_name,
    ngx_addr_t *peer_addr, ngx_uint_t protocol);

void ngx_upstream_check_delete_dynamic_peer(ngx_str_t *name,
    ngx_addr_t *peer_addr);

ngx_uint_t ngx_upstream_check_peer_down(ngx_uint_t index);
ngx_uint_t ngx_upstream_check_upstream_down(ngx_str_t *upstream);

void ngx_upstream_check_get_peer(ngx_uint_t index);
void ngx_upstream_check_free_peer(ngx_uint_t index);


#endif /* _NGX_UPSTREAM_CHECK_MODULE_H_INCLUDED_ */
