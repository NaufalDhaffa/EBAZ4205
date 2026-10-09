#ifndef CAM_VDMA_H
#define CAM_VDMA_H

#include "xaxivdma.h"
#include "xstatus.h"

/* HEIGHT=480, not 240 -- root-caused via VDMA's own S2MM status register
 * (SOFLateErr: "actual lines > configured 240") after fixing the row-
 * width mismatch (see ov7670.c's HSTART/HSTOP/VSTART/VSTOP comment): the
 * crop window spans the full 480-row sensor array (OV7670 VSTART/VSTOP
 * are in 4-row units: (0x7B-0x03)*4 = 480), and the vertical DCW/SCALING
 * downscale doesn't appear to actually be taking effect on real hardware
 * (row WIDTH scaling does work -- EOLLateErr cleared once the crop window
 * was added -- but height doesn't), so the sensor is really outputting
 * 480 raw rows, not the intended scaled-down 240. Matching VDMA's
 * configured height to this actual real height directly, rather than
 * continuing to fight the OV7670's vertical scaler register combination
 * -- the RTL/VDMA pipeline doesn't care what the real resolution is
 * (self-correcting TLAST, no hardcoded row-count assumption), so this is
 * a low-risk, easily-reverted way to unblock frame completion first,
 * with the option to revisit true QVGA scaling later if desired. */
#define CAM_FRAME_WIDTH   320   /* bytes/row -- Y8, 1 byte/pixel */
#define CAM_FRAME_HEIGHT  480   /* rows */
#define CAM_FRAME_STRIDE  320
#define CAM_FRAME_SIZE    (CAM_FRAME_WIDTH * CAM_FRAME_HEIGHT)  /* 153600 bytes */

/*
 * Ping-pong buffer physical addresses in DDR3.
 *
 * NOTE: an earlier draft of this design used 0x10000000/0x10040000 as
 * example addresses -- those are OUTSIDE the valid DDR3 range on this board
 * (PCW_DDR_RAM_HIGHADDR=0x0FFFFFFF, i.e. 256MB, so 0x10000000 is exactly
 * one byte past the end of physical DDR3) and would have caused a bus
 * error / memory corruption on real hardware. Corrected to addresses
 * safely inside the 256MB range, well clear of the low region a baremetal
 * app's own code/stack/heap occupies.
 */
#define CAM_VDMA_BUF0_ADDR 0x03000000UL
#define CAM_VDMA_BUF1_ADDR 0x03100000UL

s32 CamVdma_Init(XAxiVdma *VdmaInstancePtr);
s32 CamVdma_Start(XAxiVdma *VdmaInstancePtr);

/* Returns 1 and sets *CompletedBufAddr to the buffer that just finished
 * capturing (i.e. the one no longer being written to) when the hardware's
 * current-framestore index has advanced since the last call; returns 0
 * (no new frame yet) otherwise. Polling-based rather than interrupt-driven
 * -- see main.c for why. */
s32 CamVdma_PollForNewFrame(XAxiVdma *VdmaInstancePtr, UINTPTR *CompletedBufAddr);
void CamVdma_PrintDiag(XAxiVdma *VdmaInstancePtr);

#endif
