// vdma.c
//
// AXI VDMA S2MM (capture-only) setup: ping-pong buffers in DDR3, circular
// mode, TUSER-qualified Start-of-Frame sync (c_s2mm_sof_enable=1, the
// installed axi_vdma:6.3 IP's default -- confirmed by direct probe before
// use, see hw/scripts/build_bd.tcl comment). Exact DmaConfig ->
// DmaSetBufferAddr -> DmaStart call order verified against Xilinx's own
// xaxivdma_example_intr.c (axivdma_v6_17/examples), not assumed.
//
// Frame-completion detection is polling-based (CamVdma_PollForNewFrame),
// not interrupt-driven, even though the hardware supports S2MM frame-count
// interrupts: lwIP's raw API is documented as expecting to run from a
// single main-loop context, and driving udp_sendto() from inside a VDMA
// ISR would add reentrancy concerns with no benefit at this frame rate
// (30fps = one new frame roughly every 33ms, far slower than a tight poll
// loop needs to react).
#include "vdma.h"
#include "xil_cache.h"
#include "xil_printf.h"
#include "xparameters.h"

#define CAM_VDMA_BASEADDR 0x43000000UL

/* EOLLateErr (bit 15, "actual bytes-per-line came out MORE than the
 * configured Horizontal Size" per AMD's PG020 "Line and Frame Errors"
 * page) is a REAL, documented S2MM status bit that this installed
 * driver's XAXIVDMA_SR_ERR_ALL_MASK (0x00000FF0, bits 4-11 only) never
 * covers -- confirmed by reading xaxivdma_hw.h directly. That means
 * XAxiVdma_GetDmaChannelErrors()/ClearDmaChannelErrors() have been
 * completely blind to this specific error the whole time: never read,
 * never cleared. Given our TLAST is self-correcting off real HREF timing
 * (not a fixed byte count), a real-world timing-jitter-lengthened row is
 * exactly the kind of thing that would trip this. Cleared explicitly here
 * alongside the documented mask. */
#define CAM_VDMA_SR_ERR_EOL_LATE_MASK  0x00008000U
#define CAM_VDMA_SR_ERR_FULL_MASK      (XAXIVDMA_SR_ERR_ALL_MASK | CAM_VDMA_SR_ERR_EOL_LATE_MASK)

static XAxiVdma_DmaSetup WriteCfg;
static int LastFrameIndex = -1;
static u32 LastLoggedStatus = 0xFFFFFFFFU; /* force the very first status to log */

/* Edge-triggered (log only on change) full bit-level decode of the raw
 * S2MM status register -- catches transient stalls precisely, including
 * bits CamVdma_PrintDiag's periodic snapshot could miss between its
 * every-2000000-loop-iterations prints. Bit meanings/names cross-checked
 * against AMD's PG020 "Line and Frame Errors" page, not guessed. */
static void CamVdma_LogStatusIfChanged(u32 status)
{
    if (status == LastLoggedStatus) {
        return;
    }
    LastLoggedStatus = status;

    xil_printf("CamVdma STATUS CHANGE: raw=0x%x", (unsigned)status);
    if (status & XAXIVDMA_SR_HALTED_MASK)       xil_printf(" HALTED");
    if (status & XAXIVDMA_SR_IDLE_MASK)         xil_printf(" IDLE");
    if (status & XAXIVDMA_SR_ERR_INTERNAL_MASK) xil_printf(" ERR_INTERNAL(DataMover)");
    if (status & XAXIVDMA_SR_ERR_SLAVE_MASK)    xil_printf(" ERR_SLAVE");
    if (status & XAXIVDMA_SR_ERR_DECODE_MASK)   xil_printf(" ERR_DECODE");
    if (status & XAXIVDMA_SR_ERR_FSZ_LESS_MASK) xil_printf(" SOFEarly(actual<configured lines)");
    if (status & XAXIVDMA_SR_ERR_LSZ_LESS_MASK) xil_printf(" EOLEarly(actual<configured bytes/line)");
    if (status & XAXIVDMA_SR_ERR_SG_SLV_MASK)   xil_printf(" ERR_SG_SLV");
    if (status & XAXIVDMA_SR_ERR_SG_DEC_MASK)   xil_printf(" ERR_SG_DEC");
    if (status & XAXIVDMA_SR_ERR_FSZ_MORE_MASK) xil_printf(" SOFLate(actual>configured lines)");
    if (status & CAM_VDMA_SR_ERR_EOL_LATE_MASK) xil_printf(" EOLLate(actual>configured bytes/line)");
    xil_printf("\r\n");
}

s32 CamVdma_Init(XAxiVdma *VdmaInstancePtr)
{
    XAxiVdma_Config *Config = XAxiVdma_LookupConfig(CAM_VDMA_BASEADDR);
    if (Config == NULL) {
        xil_printf("CamVdma: LookupConfig failed for base 0x%x\r\n", (unsigned)CAM_VDMA_BASEADDR);
        return XST_FAILURE;
    }

    s32 Status = XAxiVdma_CfgInitialize(VdmaInstancePtr, Config, Config->BaseAddress);
    if (Status != XST_SUCCESS) {
        xil_printf("CamVdma: CfgInitialize failed (status=%d)\r\n", (int)Status);
        return XST_FAILURE;
    }

    WriteCfg.VertSizeInput     = CAM_FRAME_HEIGHT;
    WriteCfg.HoriSizeInput     = CAM_FRAME_WIDTH;
    WriteCfg.Stride            = CAM_FRAME_STRIDE;
    WriteCfg.FrameDelay        = 0;
    WriteCfg.EnableCircularBuf = 1;
    WriteCfg.EnableSync        = 0;   /* no Gen-Lock -- single camera, TUSER SOF handles frame sync */
    WriteCfg.PointNum          = 0;
    WriteCfg.EnableFrameCounter = 0;
    WriteCfg.FixedFrameStoreAddr = 0;
    WriteCfg.EnableVFlip       = 0;

    Status = XAxiVdma_DmaConfig(VdmaInstancePtr, XAXIVDMA_WRITE, &WriteCfg);
    if (Status != XST_SUCCESS) {
        xil_printf("CamVdma: DmaConfig (S2MM) failed (status=%d)\r\n", (int)Status);
        return XST_FAILURE;
    }

    WriteCfg.FrameStoreStartAddr[0] = CAM_VDMA_BUF0_ADDR;
    WriteCfg.FrameStoreStartAddr[1] = CAM_VDMA_BUF1_ADDR;

    Status = XAxiVdma_DmaSetBufferAddr(VdmaInstancePtr, XAXIVDMA_WRITE, WriteCfg.FrameStoreStartAddr);
    if (Status != XST_SUCCESS) {
        xil_printf("CamVdma: DmaSetBufferAddr (S2MM) failed (status=%d)\r\n", (int)Status);
        return XST_FAILURE;
    }

    xil_printf("CamVdma: configured, buffers at 0x%x / 0x%x, %dx%d\r\n",
               (unsigned)CAM_VDMA_BUF0_ADDR, (unsigned)CAM_VDMA_BUF1_ADDR,
               CAM_FRAME_WIDTH, CAM_FRAME_HEIGHT);
    return XST_SUCCESS;
}

s32 CamVdma_Start(XAxiVdma *VdmaInstancePtr)
{
    s32 Status = XAxiVdma_DmaStart(VdmaInstancePtr, XAXIVDMA_WRITE);
    if (Status != XST_SUCCESS) {
        xil_printf("CamVdma: DmaStart (S2MM) failed (status=%d)\r\n", (int)Status);
        return XST_FAILURE;
    }
    LastFrameIndex = XAxiVdma_CurrFrameStore(VdmaInstancePtr, XAXIVDMA_WRITE);
    return XST_SUCCESS;
}

s32 CamVdma_PollForNewFrame(XAxiVdma *VdmaInstancePtr, UINTPTR *CompletedBufAddr)
{
    /* Root-caused via a real hardware probe: a transient error (e.g.
     * ERR_FSZ_MORE from one real-world HREF-noise-lengthened row exceeding
     * the configured 320-byte line size) makes the DataMover stop
     * accepting further AXI-Stream beats (s_axis_s2mm_tready never
     * asserts again) until the error status is explicitly cleared --
     * confirmed HALTED stays 0 throughout, so clearing is enough, no
     * DmaStart restart needed. Previously this code only ever read
     * errors, never cleared them, so a single transient event permanently
     * wedged the whole capture pipeline. Clearing every poll (cheap: one
     * register read + one write) keeps a one-off glitch from being fatal.
     * Cleared using CAM_VDMA_SR_ERR_FULL_MASK (not just the driver's own
     * ERR_ALL_MASK) so EOLLateErr -- a real, documented error bit outside
     * that mask -- can't silently accumulate uncleared either. */
    u32 RawStatus = XAxiVdma_GetStatus(VdmaInstancePtr, XAXIVDMA_WRITE);
    CamVdma_LogStatusIfChanged(RawStatus);
    if (RawStatus & CAM_VDMA_SR_ERR_FULL_MASK) {
        XAxiVdma_ClearDmaChannelErrors(VdmaInstancePtr, XAXIVDMA_WRITE, CAM_VDMA_SR_ERR_FULL_MASK);
    }

    int CurIndex = (int)XAxiVdma_CurrFrameStore(VdmaInstancePtr, XAXIVDMA_WRITE);

    if (CurIndex == LastFrameIndex) {
        return 0;
    }

    /* The engine has moved on to CurIndex, which means the PREVIOUS index
     * (LastFrameIndex) just finished capturing a complete frame. */
    UINTPTR completed = (LastFrameIndex == 0) ? CAM_VDMA_BUF0_ADDR : CAM_VDMA_BUF1_ADDR;
    LastFrameIndex = CurIndex;

    /* VDMA is a DMA master and does not go through the CPU's data cache --
     * invalidate before the CPU (via udp_stream.c) reads this buffer, or a
     * stale cached copy could be sent instead of the fresh frame. */
    Xil_DCacheInvalidateRange(completed, CAM_FRAME_SIZE);

    *CompletedBufAddr = completed;
    return 1;
}

void CamVdma_PrintDiag(XAxiVdma *VdmaInstancePtr)
{
    int errors = XAxiVdma_GetDmaChannelErrors(VdmaInstancePtr, XAXIVDMA_WRITE);
    u32 status = XAxiVdma_GetStatus(VdmaInstancePtr, XAXIVDMA_WRITE);
    u32 cur = XAxiVdma_CurrFrameStore(VdmaInstancePtr, XAXIVDMA_WRITE);
    xil_printf("CamVdma diag: errors=0x%x status=0x%x curframe=%u\r\n",
               (unsigned)errors, (unsigned)status, (unsigned)cur);
}
