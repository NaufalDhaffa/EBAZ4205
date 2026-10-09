#include "sleep.h"
#include "xil_cache.h"
#include "xil_printf.h"
#include "xgpiops.h"
#include "xiicps.h"
#include "xiltimer.h"
#include "xparameters.h"
#include "xuartps_hw.h"

#include "lwip/init.h"
#include "lwip/netif.h"
#include "netif/xadapter.h"

#include "litescope_bridge.h"
#include "ov7670.h"
#include "vdma.h"
#include "udp_stream.h"

#define I2C0_BASEADDR 0xe0004000UL
#define GEM0_BASEADDR 0xe000b000UL
#define GPIO_BASEADDR 0xe000a000UL

static XIicPs IicInstance;
static XAxiVdma VdmaInstance;
static XGpioPs GpioInstance;
static struct netif server_netif;

int main(void)
{
    Xil_ICacheEnable();
    Xil_DCacheEnable();
    XilSleepTimer_Init(&TimerInst);

    xil_printf("\r\n=== cam_stream: start ===\r\n");

    XIicPs_Config *i2c_cfg = XIicPs_LookupConfig(I2C0_BASEADDR);
    if (i2c_cfg == NULL) {
        xil_printf("FAIL: XIicPs_LookupConfig\r\n");
        goto done;
    }
    if (XIicPs_CfgInitialize(&IicInstance, i2c_cfg, i2c_cfg->BaseAddress) != XST_SUCCESS) {
        xil_printf("FAIL: XIicPs_CfgInitialize\r\n");
        goto done;
    }
    XIicPs_SetSClk(&IicInstance, 100000);

    if (OV7670_CheckId(&IicInstance) != XST_SUCCESS) {
        xil_printf("WARN: OV7670 ID check failed, continuing anyway\r\n");
    }
    if (OV7670_Init(&IicInstance) != XST_SUCCESS) {
        xil_printf("FAIL: OV7670_Init\r\n");
        goto done;
    }

    if (CamVdma_Init(&VdmaInstance) != XST_SUCCESS) {
        xil_printf("FAIL: CamVdma_Init\r\n");
        goto done;
    }
    if (CamVdma_Start(&VdmaInstance) != XST_SUCCESS) {
        xil_printf("FAIL: CamVdma_Start\r\n");
        goto done;
    }

    XGpioPs_Config *gpio_cfg = XGpioPs_LookupConfig(GPIO_BASEADDR);
    if (gpio_cfg == NULL) {
        xil_printf("FAIL: XGpioPs_LookupConfig\r\n");
        goto done;
    }
    XGpioPs_CfgInitialize(&GpioInstance, gpio_cfg, gpio_cfg->BaseAddr);
    XGpioPs_SetDirection(&GpioInstance, XGPIOPS_BANK2, 0xFFFFFFFF);
    XGpioPs_SetOutputEnable(&GpioInstance, XGPIOPS_BANK2, 0xFFFFFFFF);

    struct netif *netif = &server_netif;
    unsigned char mac[] = { 0x00, 0x0a, 0x35, 0x00, 0x01, 0x02 };
    ip_addr_t ipaddr, netmask, gw;
    IP4_ADDR(&ipaddr,  192, 168, 2, 10);
    IP4_ADDR(&netmask, 255, 255, 255, 0);
    IP4_ADDR(&gw,      192, 168, 2, 1);

    lwip_init();
    if (!xemac_add(netif, &ipaddr, &netmask, &gw, mac, GEM0_BASEADDR)) {
        xil_printf("FAIL: xemac_add\r\n");
        goto done;
    }
    netif_set_default(netif);
    netif_set_up(netif);

    struct udp_pcb *pcb = CamUdpStream_Init();
    if (pcb == NULL) {
        xil_printf("FAIL: CamUdpStream_Init\r\n");
        goto done;
    }

    xil_printf("cam_stream: entering main loop\r\n");
    xil_printf("cam_stream: press 'L' on this console to enter litescope relay mode\r\n");

    u32_t frame_id = 0;
    u32_t loop_count = 0;
    while (1) {
        if (XUartPs_IsReceiveData(STDIN_BASEADDRESS) && (u8)inbyte() == 'L') {
            LitescopeBridge_Run(&GpioInstance);
        }

        xemacif_input(netif);

        UINTPTR buf_addr;
        if (CamVdma_PollForNewFrame(&VdmaInstance, &buf_addr)) {
            if (frame_id < 3) {
                /* Diagnostic: sample the first 8 bytes of several rows
                 * across the whole 320x240 buffer, directly from DDR3,
                 * independent of the network/receiver path entirely --
                 * maps out exactly how far real per-row data extends
                 * before it turns into stale/never-written content. */
                const u8_t *p = (const u8_t *)buf_addr;
                static const int rows[] = {0, 1, 2, 5, 10, 25, 50, 100, 150, 200, 239};
                for (unsigned r = 0; r < sizeof(rows) / sizeof(rows[0]); r++) {
                    int row = rows[r];
                    int base = row * CAM_FRAME_WIDTH;
                    xil_printf("FrameDump[%u] row%d:", (unsigned)frame_id, row);
                    for (int i = 0; i < 8; i++) {
                        xil_printf(" %02x", p[base + i]);
                    }
                    xil_printf("\r\n");
                }
            }
            CamUdpStream_SendFrame(pcb, netif, (const u8_t *)buf_addr, CAM_FRAME_SIZE, frame_id);
            frame_id++;
        }

        loop_count++;
        if (loop_count % 2000000 == 0) {
            CamVdma_PrintDiag(&VdmaInstance);
        }
    }

done:
    xil_printf("=== cam_stream: halted ===\r\n");
    while (1) {
    }
    return 0;
}
