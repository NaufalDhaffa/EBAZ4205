#ifndef UDP_STREAM_H
#define UDP_STREAM_H

#include "lwip/netif.h"
#include "lwip/udp.h"
#include "xstatus.h"

#define CAM_UDP_DEST_PORT   12345
/* PC receiver IP: the laptop's dedicated wired link, same one eth_test
 * already proved reachable (see docs/BOARD_CONFIG.md Ethernet section). */
#define CAM_UDP_DEST_IP_A   192
#define CAM_UDP_DEST_IP_B   168
#define CAM_UDP_DEST_IP_C   2
#define CAM_UDP_DEST_IP_D   1

#define CAM_UDP_PAYLOAD_MAX 1016  /* bytes; header(8) + payload(<=1016) <= 1024 total */

struct udp_pcb *CamUdpStream_Init(void);
void CamUdpStream_SendFrame(struct udp_pcb *pcb, struct netif *netif, const u8_t *frame_buf, u32_t frame_len, u32_t frame_id);

#endif
