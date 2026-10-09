// udp_stream.c
//
// Fire-and-forget UDP frame streaming: splits a 76800-byte Y8 frame buffer
// into fixed 1016-byte-payload packets (8-byte header + up to 1016-byte
// payload = 1024 bytes total, under standard Ethernet MTU, no fragmentation).
//
// Packet count correction: 76800 / 1016 = 75.59, not an integer -- so this
// is 75 full packets of 1016 bytes (75*1016=76200 bytes) plus one final,
// shorter packet carrying the remaining 600 bytes (76800-76200), for 76
// packets total. An earlier draft of this design assumed all 76 packets
// would carry a uniform 1016-byte payload, which doesn't add up to the
// actual frame size -- fixed here by handling the last packet's shorter
// length explicitly rather than assuming uniform packet sizes.
#include "udp_stream.h"
#include "lwip/pbuf.h"
#include "netif/xadapter.h"
#include "netif/xemacpsif.h"
#include "xil_printf.h"
#include <string.h>

struct cam_udp_header {
    u32_t frame_id;
    u16_t packet_index;
    u16_t total_packets;
};

/* Root-caused via a real hardware/network probe: udp_send() was failing
 * with err=-1 (ERR_MEM) starting around packet ~71 of every 76-packet
 * frame burst, so essentially every frame arrived at the PC incomplete
 * and never got displayed. This app never sets up the interrupt
 * controller anywhere (whole design is deliberately polling-based, see
 * vdma.c), so emacps_send_handler -- the TX-done ISR that normally
 * reclaims TX buffer descriptors -- never runs, and the small, fixed-size
 * TX BD ring permanently exhausts partway through each tight, back-to-back
 * 76-packet burst. xemacps_process_sent_bds is the same reclaim function
 * the ISR would have called; calling it directly after every packet here
 * keeps the ring drained via polling instead, consistent with the rest of
 * this app's polling-only design. */
static void CamUdpStream_ReclaimTx(struct netif *netif)
{
    struct xemac_s *xemac = (struct xemac_s *)(netif->state);
    xemacpsif_s *xemacpsif = (xemacpsif_s *)(xemac->state);
    XEmacPs_BdRing *txring = &(XEmacPs_GetTxRing(&xemacpsif->emacps));
    xemacps_process_sent_bds(xemacpsif, txring);
}

struct udp_pcb *CamUdpStream_Init(void)
{
    struct udp_pcb *pcb = udp_new();
    if (pcb == NULL) {
        xil_printf("CamUdpStream: udp_new failed\r\n");
        return NULL;
    }

    ip_addr_t dest_ip;
    IP4_ADDR(&dest_ip, CAM_UDP_DEST_IP_A, CAM_UDP_DEST_IP_B, CAM_UDP_DEST_IP_C, CAM_UDP_DEST_IP_D);

    err_t err = udp_connect(pcb, &dest_ip, CAM_UDP_DEST_PORT);
    if (err != ERR_OK) {
        xil_printf("CamUdpStream: udp_connect failed (err=%d)\r\n", (int)err);
        udp_remove(pcb);
        return NULL;
    }

    xil_printf("CamUdpStream: ready, streaming to %d.%d.%d.%d:%d\r\n",
               CAM_UDP_DEST_IP_A, CAM_UDP_DEST_IP_B, CAM_UDP_DEST_IP_C, CAM_UDP_DEST_IP_D,
               CAM_UDP_DEST_PORT);
    return pcb;
}

void CamUdpStream_SendFrame(struct udp_pcb *pcb, struct netif *netif, const u8_t *frame_buf, u32_t frame_len, u32_t frame_id)
{
    u16_t total_packets = (u16_t)((frame_len + CAM_UDP_PAYLOAD_MAX - 1) / CAM_UDP_PAYLOAD_MAX);
    u32_t offset = 0;

    for (u16_t idx = 0; idx < total_packets; idx++) {
        CamUdpStream_ReclaimTx(netif);
        u32_t remaining = frame_len - offset;
        u16_t this_payload_len = (remaining > CAM_UDP_PAYLOAD_MAX) ? CAM_UDP_PAYLOAD_MAX : (u16_t)remaining;

        struct pbuf *p = pbuf_alloc(PBUF_TRANSPORT, sizeof(struct cam_udp_header) + this_payload_len, PBUF_RAM);
        if (p == NULL) {
            xil_printf("CamUdpStream: pbuf_alloc failed at packet %u/%u (frame %u) -- dropping rest of frame\r\n",
                       (unsigned)idx, (unsigned)total_packets, (unsigned)frame_id);
            return;
        }

        struct cam_udp_header hdr;
        hdr.frame_id      = frame_id;
        hdr.packet_index  = idx;
        hdr.total_packets = total_packets;

        memcpy(p->payload, &hdr, sizeof(hdr));
        memcpy((u8_t *)p->payload + sizeof(hdr), frame_buf + offset, this_payload_len);

        err_t err = udp_send(pcb, p);
        if (err != ERR_OK) {
            xil_printf("CamUdpStream: udp_send failed at packet %u/%u (err=%d)\r\n",
                       (unsigned)idx, (unsigned)total_packets, (int)err);
        }
        pbuf_free(p);

        offset += this_payload_len;
    }
}
