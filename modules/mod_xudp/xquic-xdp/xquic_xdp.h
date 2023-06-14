/*
 * Copyright (C) 2020-2023 Alibaba Group Holding Limited
 */

#ifndef  __XQUIC_H__
#define __XQUIC_H__

struct kern_xquic {
    /* capturing network traffic in xudp */
    /* system will control traffic for capture=0 */
    u8  capture;
    /* offset of worker id in cid */
    u8  offset;
    /* just padding */
    u16 padding;
    /* secret for worker id*/
    u32 mask;
    /* salt range for worker id*/
    u32 salt_range;
};

#define XUDP_XQUIC_MAP_DEFAULT_KEY  (0)

#define XUDP_XQUIC_MAP_NAME "map_xquic"

#endif


