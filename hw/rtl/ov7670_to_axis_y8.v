// ov7670_to_axis_y8.v
//
// Extracts Y (luma) bytes from an OV7670 YUV422 pixel stream and presents
// them as an 8-bit AXI4-Stream master. U/V bytes are dropped entirely (no
// beat emitted) since only Y8 grayscale is needed.
//
// Timing model — OV7670 datasheet (OmniVision OV7670/OV7171, Table 5 /
// signal description): D[7:0] is meaningless whenever VSYNC=1 or HREF=0;
// valid pixel data exists only while VSYNC=0 AND HREF=1, sampled on the
// PCLK rising edge. VSYNC's falling edge marks the start of a frame, HREF's
// rising edge the start of a row and its falling edge the end of a row
// (HREF is asserted only when there is real output data).
//
// YUV422 byte order within a row is Y0 U0 Y1 V0 Y2 U1 ... i.e. Y samples
// sit at even byte-in-row positions, U/V at odd positions.
//
// AXI4-Stream (AMBA IHI 0051) compliance: a beat transfers only when
// TVALID=1 AND TREADY=1 on the same clock edge. This module does not
// sample m_axis_tready — the sensor emits pixels at a fixed PCLK rate with
// no way to be paused, so backpressure is absorbed by the downstream CDC
// FIFO, not by stalling here (a stalled beat here would just desync from
// the sensor's own HREF/VSYNC timing, which is worse than relying on the
// FIFO having enough depth/drain rate).
//
// TLAST generation — root-caused via a real hardware probe during bring-up:
// an earlier version decided TLAST by comparing a row byte counter against
// a fixed constant (byte_in_row == BYTES_PER_ROW-2). That's fragile by
// construction: if the sensor's real per-row byte count ever deviates from
// that exact constant for even a single row (HREF timing jitter, signal
// noise on the header wiring, a scaling-register configuration that
// doesn't produce precisely the assumed row width), the counter never
// lands on that exact value again and TLAST silently stops firing
// forever, with no self-correction. Confirmed on real hardware: a
// free-running toggle counter on m_axis_tlast showed it pulsing normally
// for the first ~12 frames, then going completely flat for the rest of
// the run while VSYNC/HREF kept toggling normally the whole time.
//
// Fixed by deciding TLAST with one cycle of hindsight instead: a captured
// Y-beat is staged for one cycle, and is only tagged TLAST when we
// subsequently observe HREF has actually fallen — i.e. it's derived from
// the real HREF boundary every single row, not predicted from an assumed
// row width. This is self-correcting regardless of the real per-row byte
// count.
//
// KNOWN OPEN BUG: on real hardware TLAST still never fires (see
// ov7670_to_axis_y8_oversample.v for the in-progress rewrite).
module ov7670_to_axis_y8 (
    input  wire       pclk,
    input  wire       vsync,   // OV7670 VSYNC (active-high, default polarity)
    input  wire       href,    // OV7670 HREF
    input  wire [7:0] d,       // OV7670 D[7:0]

    output reg  [7:0] m_axis_tdata,
    output reg        m_axis_tvalid,
    output reg        m_axis_tlast,
    output reg        m_axis_tuser,  // Start-of-frame, for VDMA s_axis_s2mm_tuser(0)
    input  wire       m_axis_tready  // intentionally not sampled, see header
);

    reg        vsync_d       = 1'b0;
    reg        href_d        = 1'b0;
    reg        byte_parity   = 1'b0;    // toggles each captured byte within a row; resets on href_fall
    reg        frame_active  = 1'b0;    // true from first VSYNC falling edge onward
    reg        pending_sof   = 1'b0;    // set on VSYNC falling edge, cleared by first Y beat

    // One-cycle staging so TLAST can be decided with hindsight (see header
    // comment): a captured beat is only known to be a row's LAST beat once
    // we observe, one cycle later, that HREF has already fallen.
    reg        stage_valid   = 1'b0;
    reg [7:0]  stage_data    = 8'd0;
    reg        stage_sof     = 1'b0;

    wire href_fall  = ~href & href_d;
    wire vsync_fall = ~vsync & vsync_d;

    // Sampling on the FALLING edge of pclk, not rising -- root-caused via
    // real hardware probing: with rising-edge sampling, TLAST would
    // freeze permanently at a DIFFERENT byte count on every single power
    // cycle/reprogram (318 one run, 576 the next, 5954 before that) even
    // though VSYNC/HREF/PDATA kept toggling at a consistent high rate the
    // whole time -- a run-to-run-varying, eventually-permanent lockup is
    // the classic signature of input metastability, not a deterministic
    // logic bug (which would fail at the same point every time). There's
    // also no set_input_delay constraint anywhere in camera.xdc tying
    // href/vsync/pdata's real timing to cam_pclk, so Vivado's reported
    // timing closure never actually covered this relationship. Sampling
    // on the falling edge instead lands in the middle of the data-valid
    // window from the previous rising edge rather than right at its
    // boundary -- a well-known OV7670-specific fix for exactly this class
    // of marginal-timing symptom over unbuffered header wiring.
    always @(negedge pclk) begin
        vsync_d <= vsync;
        href_d  <= href;

        // Release last cycle's staged beat (if any) now, tagging TLAST if
        // HREF has since fallen -- meaning that staged beat really was
        // the row's final Y-byte.
        m_axis_tvalid <= stage_valid;
        m_axis_tdata  <= stage_data;
        m_axis_tuser  <= stage_sof;
        m_axis_tlast  <= stage_valid && !href;
        stage_valid   <= 1'b0;

        if (vsync_fall) begin
            frame_active <= 1'b1;
            pending_sof  <= 1'b1;
        end

        if (href_fall) begin
            byte_parity <= 1'b0;
        end

        if (frame_active && href && !vsync) begin
            if (byte_parity == 1'b0) begin
                // Even position within the row -> Y sample.
                stage_data  <= d;
                stage_valid <= 1'b1;
                stage_sof   <= pending_sof;
                pending_sof <= 1'b0;
            end
            byte_parity <= ~byte_parity;
        end
    end

endmodule
