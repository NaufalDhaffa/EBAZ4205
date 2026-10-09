// ov7670.c
//
// SCCB register configuration for OV7670 QVGA (320x240) Y8-over-YUV422
// output. Register addresses/bit meanings verified against the official
// OmniVision OV7670/OV7171 datasheet (v1.01, Table 5) -- not from memory.
//
// COM3 = 0x04 here (DCW enable only), not 0x08 (Scale enable only) as an
// earlier draft of this register set specified: this design uses manual
// scaling (COM14 bit[3]=1) via the SCALING_* registers directly rather than
// COM7's pre-defined-format path (COM7 here is 0x00, none of its CIF/QVGA/
// QCIF bits set), and DCW-enable is what the widely-replicated working
// OV7670 manual-QVGA register set uses in that mode.
#include "ov7670.h"
#include "sleep.h"
#include "xil_printf.h"

#define COM7             0x12
#define CLKRC            0x11
#define COM15            0x40
#define COM3             0x0C
#define COM14            0x3E
#define HSTART           0x17
#define HSTOP            0x18
#define VSTART           0x19
#define VSTOP            0x1A
#define SCALING_XSC      0x70
#define SCALING_YSC      0x71
#define SCALING_DCW_CTR  0x72
#define SCALING_PCLK_DIV 0x73
#define COM8             0x13

#define COM7_SOFT_RESET  0x80

static s32 OV7670_WriteReg(XIicPs *IicInstancePtr, u8 RegAddr, u8 RegVal)
{
    u8 buf[2] = { RegAddr, RegVal };
    s32 Status = XIicPs_MasterSendPolled(IicInstancePtr, buf, 2, OV7670_I2C_ADDR);
    if (Status != XST_SUCCESS) {
        xil_printf("OV7670: SCCB write reg 0x%02x=0x%02x FAILED (status=%d)\r\n",
                   RegAddr, RegVal, (int)Status);
        return XST_FAILURE;
    }
    /* SCCB, like I2C, needs the bus genuinely idle before the next START --
     * poll BusIsBusy rather than a fixed guess. */
    while (XIicPs_BusIsBusy(IicInstancePtr)) {
    }
    return XST_SUCCESS;
}

#define REG_PID 0x0A  /* read-only, expected 0x76 per datasheet */
#define REG_VER 0x0B  /* read-only, expected 0x70 per datasheet */

static s32 OV7670_ReadReg(XIicPs *IicInstancePtr, u8 RegAddr, u8 *OutVal)
{
    s32 Status = XIicPs_MasterSendPolled(IicInstancePtr, &RegAddr, 1, OV7670_I2C_ADDR);
    if (Status != XST_SUCCESS) {
        return XST_FAILURE;
    }
    while (XIicPs_BusIsBusy(IicInstancePtr)) {
    }
    Status = XIicPs_MasterRecvPolled(IicInstancePtr, OutVal, 1, OV7670_I2C_ADDR);
    if (Status != XST_SUCCESS) {
        return XST_FAILURE;
    }
    while (XIicPs_BusIsBusy(IicInstancePtr)) {
    }
    return XST_SUCCESS;
}

/* Sanity check before trusting a stream of blind writes: read back the
 * read-only silicon ID registers and compare against the datasheet's
 * documented values. This is the first, isolated thing to check on new
 * hardware -- confirms the I2C wiring and 7-bit slave address (0x21) are
 * actually correct before any video-timing registers are touched. */
s32 OV7670_CheckId(XIicPs *IicInstancePtr)
{
    u8 pid = 0, ver = 0;
    s32 Status = OV7670_ReadReg(IicInstancePtr, REG_PID, &pid);
    if (Status == XST_SUCCESS) {
        Status = OV7670_ReadReg(IicInstancePtr, REG_VER, &ver);
    }
    if (Status != XST_SUCCESS) {
        xil_printf("OV7670: ID read FAILED -- no SCCB response (check wiring/address)\r\n");
        return XST_FAILURE;
    }
    xil_printf("OV7670: PID=0x%02x VER=0x%02x (expected 0x76/0x70)\r\n", pid, ver);
    if (pid != 0x76 || ver != 0x70) {
        xil_printf("OV7670: WARNING -- ID mismatch, proceeding anyway for diagnostic purposes\r\n");
        return XST_FAILURE;
    }
    return XST_SUCCESS;
}

s32 OV7670_Init(XIicPs *IicInstancePtr)
{
    s32 Status;

    Status = OV7670_WriteReg(IicInstancePtr, COM7, COM7_SOFT_RESET);
    if (Status != XST_SUCCESS) { return XST_FAILURE; }
    usleep(100000); /* datasheet-recommended settle time after soft reset */

    Status = OV7670_WriteReg(IicInstancePtr, CLKRC, 0x01);
    if (Status != XST_SUCCESS) { return XST_FAILURE; }

    Status = OV7670_WriteReg(IicInstancePtr, COM7, 0x00);       /* YUV, no pre-defined format bits */
    if (Status != XST_SUCCESS) { return XST_FAILURE; }
    Status = OV7670_WriteReg(IicInstancePtr, COM15, 0xC0);
    if (Status != XST_SUCCESS) { return XST_FAILURE; }

    Status = OV7670_WriteReg(IicInstancePtr, COM3, 0x04);       /* DCW enable (corrected, see header comment) */
    if (Status != XST_SUCCESS) { return XST_FAILURE; }
    Status = OV7670_WriteReg(IicInstancePtr, COM14, 0x19);
    if (Status != XST_SUCCESS) { return XST_FAILURE; }

    /* Root-caused via a real hardware probe (VDMA's own S2MM status
     * register, decoded bit-by-bit): every single row was coming out
     * LONGER than the configured 320-byte QVGA width (EOLLateErr), and
     * every frame was completing with FAR fewer than the configured 240
     * lines (SOFEarlyErr) -- a completely systematic, every-row/every-
     * frame pattern, not intermittent noise. HSTART/HSTOP/VSTART/VSTOP
     * (the sensor's active-window crop registers) were missing from this
     * register set entirely -- COM3/COM14/SCALING_* alone only set the
     * internal downscale RATIO, not the actual output window, so the
     * sensor was staying at its power-on-default (much larger) active
     * window while only partially scaled, producing neither clean VGA nor
     * clean QVGA. Every independently-published working OV7670 QVGA
     * register set includes these 4 registers alongside the exact same
     * COM3/COM14/SCALING_* values already used here -- cross-checked
     * against multiple sources, not from memory.
     */
    Status = OV7670_WriteReg(IicInstancePtr, HSTART, 0x16);
    if (Status != XST_SUCCESS) { return XST_FAILURE; }
    Status = OV7670_WriteReg(IicInstancePtr, HSTOP, 0x04);
    if (Status != XST_SUCCESS) { return XST_FAILURE; }
    Status = OV7670_WriteReg(IicInstancePtr, VSTART, 0x03);
    if (Status != XST_SUCCESS) { return XST_FAILURE; }
    Status = OV7670_WriteReg(IicInstancePtr, VSTOP, 0x7B);
    if (Status != XST_SUCCESS) { return XST_FAILURE; }

    Status = OV7670_WriteReg(IicInstancePtr, SCALING_XSC, 0x3A);
    if (Status != XST_SUCCESS) { return XST_FAILURE; }
    Status = OV7670_WriteReg(IicInstancePtr, SCALING_YSC, 0x35);
    if (Status != XST_SUCCESS) { return XST_FAILURE; }
    Status = OV7670_WriteReg(IicInstancePtr, SCALING_DCW_CTR, 0x11);
    if (Status != XST_SUCCESS) { return XST_FAILURE; }
    Status = OV7670_WriteReg(IicInstancePtr, SCALING_PCLK_DIV, 0xF1);
    if (Status != XST_SUCCESS) { return XST_FAILURE; }

    Status = OV7670_WriteReg(IicInstancePtr, COM8, 0xE7);       /* AGC+AEC+AWB auto */
    if (Status != XST_SUCCESS) { return XST_FAILURE; }

    xil_printf("OV7670: register configuration complete\r\n");
    return XST_SUCCESS;
}
