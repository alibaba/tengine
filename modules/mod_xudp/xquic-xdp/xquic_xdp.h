#ifndef  __XQUIC_H__
#define __XQUIC_H__

struct kern_xquic {
    /* 是否由xudp捕获，若capture为0，则交由系统分发*/
    u8  capture;
    /* worker id 在 cid中的偏移*/
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


