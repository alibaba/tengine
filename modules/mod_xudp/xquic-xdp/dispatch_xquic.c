/*
 * Copyright (C) 2020-2023 Alibaba Group Holding Limited
 * SPDX-License-Identifier: GPL-2.0
 */

#include "kern_core.c"
#include "xquic_xdp.h"

bpf_map map_xquic = {
    .type = BPF_MAP_TYPE_ARRAY,
    .key_size = sizeof(int),
    .value_size = sizeof(struct kern_xquic),
    .max_entries = 1,
};

#define XQUIC_WORKER_PID(key)	((key) & 0x3fffff)

/**
* source code from nginx , reprogramming for kernel ebpf
*/
static u32
ngx_murmur_hash2(struct xudp_ctx *ctx, u8 *data, u8 len, u8 *err)
{
    u32  h, k;

    h = 0 ^ len;

#define MURMUR_ROUND()                          \
    if (len < 4) break;                         \
    do {                                        \
        if (!access_ok(ctx, (u32*) (data))) {   \
            goto violence;                      \
        }                                       \
        k  = data[0];                           \
        k |= data[1] << 8;                      \
        k |= data[2] << 16;                     \
        k |= data[3] << 24;                     \
        k *= 0x5bd1e995;                        \
        k ^= k >> 24;                           \
        k *= 0x5bd1e995;                        \
        h *= 0x5bd1e995;                        \
        h ^= k;                                 \
        data += 4;                              \
        len -= 4;                               \
    }while(0)

    do {

        /**
         * DCID max length is 20 bytes
         * */
        MURMUR_ROUND();
        MURMUR_ROUND();
        MURMUR_ROUND();
        MURMUR_ROUND();
        MURMUR_ROUND();

    }while(0);

#undef MURMUR_ROUND

    switch (len) {
        case 3:
        {
            if (!access_ok(ctx, data + 2)) {
                goto violence;
            }
            h ^= data[2] << 16;
        }
        case 2:
        {
            if (!access_ok(ctx, data + 1)) {
                goto violence;
            }
            h ^= data[1] << 8;
        }
        case 1:
        {
            if (!access_ok(ctx, data)) {
                goto violence;
            }
            h ^= data[0];
            h *= 0x5bd1e995;
        }
    }

    h ^= h >> 13;
    h *= 0x5bd1e995;
    h ^= h >> 15;
    return h;

violence:
    *err = 1;
    return 0;
}

static int
xskmap_dispatch(struct xudp_ctx *ctx)
{
    struct kern_xquic *xquic;

    int r, xquic_key;
    u32 *cipher_worker, worker, pid, salt;
    u8 *dcid, err;
    u8 *p;

    xquic_key = XUDP_XQUIC_MAP_DEFAULT_KEY;

    xquic = bpf_map_lookup_elem(&map_xquic, (const void *) &xquic_key);

    /* nginx can off xudp */
    if (!xquic || xquic->capture == 0) {
        /* pass to kernel */
        return XDP_PASS;
    }

    /* get UDP payload */
    p = (u8*) (ctx->hdrs.udp + 1);
    if (!access_ok(ctx, p)) {
        goto fail;
    }

    if ((p[0] & 0xC0) != 0x40) {
        /* pass to kernel , all non-short header packets pass to kernel */
        goto fail;
    }

    /* short header |HEADER(1)|DCID| */
    dcid = p + 1;

    err = 0;
    /* calculate salt */
    salt = ngx_murmur_hash2(ctx, dcid, xquic->salt_range, &err);
    if (err) {
        /* invalid quic packet */
        goto fail;
    }

    /* get cipher worker */
    cipher_worker = (u32*)(dcid + xquic->offset);
    if (!access_ok(ctx, cipher_worker)) {
        goto fail;
    }

    /* decrypt */
    worker = (bpf_ntohl(*cipher_worker) ^ xquic->mask) - salt;

    /* get PID */
    pid = XQUIC_WORKER_PID(worker);

    /* try use PID */
    r = xskmap_dict_go(ctx, pid);
    /* success */
    if (r >= 0) {
        return r;
    }

fail:
    // all error should pass to kernel
    return XDP_PASS;
}
