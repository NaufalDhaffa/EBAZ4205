#include "litescope_bridge.h"
#include "xil_printf.h"

#define CMD_WRITE_BURST_INCR  0x01
#define CMD_READ_BURST_INCR   0x02
#define CMD_WRITE_BURST_FIXED 0x03
#define CMD_READ_BURST_FIXED  0x04

/* GPIO_O bank2: [15:2]=csr_adr, [16]=write-req toggle, [17]=read-req
 * toggle. Shadowed so a toggle flip doesn't disturb the other or the
 * address field -- see hw/rtl/csr_gpio_bridge.v for the full protocol. */
static u32 GpioOBank2 = 0;

static u32 ReadBE32(void)
{
    u32 v = 0;
    for (int i = 0; i < 4; i++) {
        v = (v << 8) | (u8)inbyte();
    }
    return v;
}

static void WriteBE32(u32 v)
{
    outbyte((char)((v >> 24) & 0xFF));
    outbyte((char)((v >> 16) & 0xFF));
    outbyte((char)((v >> 8) & 0xFF));
    outbyte((char)(v & 0xFF));
}

static void CsrWrite(XGpioPs *Gpio, u16 WordAddr, u32 Data)
{
    XGpioPs_Write(Gpio, XGPIOPS_BANK3, Data);
    u8 want = !((GpioOBank2 >> 16) & 1);
    GpioOBank2 = ((u32)WordAddr << 2) | ((u32)want << 16) | (GpioOBank2 & (1u << 17));
    XGpioPs_Write(Gpio, XGPIOPS_BANK2, GpioOBank2);
    while (((XGpioPs_Read(Gpio, XGPIOPS_BANK3) >> 0) & 1) != want) {
    }
}

static u32 CsrRead(XGpioPs *Gpio, u16 WordAddr)
{
    u8 want = !((GpioOBank2 >> 17) & 1);
    GpioOBank2 = ((u32)WordAddr << 2) | (GpioOBank2 & (1u << 16)) | ((u32)want << 17);
    XGpioPs_Write(Gpio, XGPIOPS_BANK2, GpioOBank2);
    while (((XGpioPs_Read(Gpio, XGPIOPS_BANK3) >> 1) & 1) != want) {
    }
    return XGpioPs_Read(Gpio, XGPIOPS_BANK2);
}

void LitescopeBridge_Run(XGpioPs *Gpio)
{
    xil_printf("\r\n=== litescope bridge: relay mode (reset board to exit) ===\r\n");

    XGpioPs_SetDirection(Gpio, XGPIOPS_BANK3, 0xFFFFFFFF);
    XGpioPs_SetOutputEnable(Gpio, XGPIOPS_BANK3, 0xFFFFFFFF);

    while (1) {
        u8 cmd = (u8)inbyte();
        u8 length = (u8)inbyte();
        u16 addr = (u16)ReadBE32();

        switch (cmd) {
        case CMD_WRITE_BURST_INCR:
            for (u8 i = 0; i < length; i++) {
                CsrWrite(Gpio, addr, ReadBE32());
                addr++;
            }
            break;
        case CMD_WRITE_BURST_FIXED:
            for (u8 i = 0; i < length; i++) {
                CsrWrite(Gpio, addr, ReadBE32());
            }
            break;
        case CMD_READ_BURST_INCR:
            for (u8 i = 0; i < length; i++) {
                WriteBE32(CsrRead(Gpio, addr));
                addr++;
            }
            break;
        case CMD_READ_BURST_FIXED:
            for (u8 i = 0; i < length; i++) {
                WriteBE32(CsrRead(Gpio, addr));
            }
            break;
        default:
            break;
        }
    }
}
