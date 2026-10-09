// WIP, NOT used by build_bd.tcl: oversampling rewrite (needs a new `clk` port + a faster FCLK, BD rewiring, and a re-simulation after the 2-stage TLAST change). Same module name as ov7670_to_axis_y8.v, so never add both to one project.
// Extracts Y (luma) bytes from an OV7670 YUV422 stream as an 8-bit AXI4-
// Stream master. pclk/href/vsync/d are oversampled as plain async data by
// `clk` (a stable FPGA clock, not the camera's own pclk) via 2-flop sync +
// one extra delay stage for edge detection -- same technique as
// github.com/vogma/OV7670_ArtyA7's ov7670_capture.vhd. TLAST/TUSER are
// decided with two real PCLK periods of hindsight off HREF/VSYNC falling
// edges (self-correcting to the real per-row byte count) -- one PCLK period
// alone isn't enough: HREF stays high through a Y byte's paired U/V byte,
// so it hasn't fallen yet by the very next PCLK edge even when that Y byte
// was the row's last.
module ov7670_to_axis_y8 (
    input  wire       clk,
    input  wire       pclk,
    input  wire       vsync,
    input  wire       href,
    input  wire [7:0] d,

    output reg  [7:0] m_axis_tdata  = 8'd0,
    output reg        m_axis_tvalid = 1'b0,
    output reg        m_axis_tlast  = 1'b0,
    output reg        m_axis_tuser  = 1'b0,
    input  wire       m_axis_tready
);

    reg pclk_r0=0, pclk_r1=0, pclk_r2=0;
    reg vsync_r0=0, vsync_r1=0, vsync_r2=0;
    reg href_r0=0, href_r1=0, href_r2=0;
    reg [7:0] d_r0=0, d_r1=0;

    always @(posedge clk) begin
        pclk_r0  <= pclk;  pclk_r1  <= pclk_r0;  pclk_r2  <= pclk_r1;
        vsync_r0 <= vsync; vsync_r1 <= vsync_r0; vsync_r2 <= vsync_r1;
        href_r0  <= href;  href_r1  <= href_r0;  href_r2  <= href_r1;
        d_r0     <= d;     d_r1     <= d_r0;
    end

    wire pclk_rise  = pclk_r1 & ~pclk_r2;
    wire href_fall  = ~href_r1 & href_r2;
    wire vsync_fall = ~vsync_r1 & vsync_r2;

    reg byte_parity  = 1'b0;
    reg frame_active = 1'b0;
    reg pending_sof  = 1'b0;

    reg       stage1_valid = 1'b0;
    reg [7:0] stage1_data  = 8'd0;
    reg       stage1_sof   = 1'b0;

    reg       stage2_valid = 1'b0;
    reg [7:0] stage2_data  = 8'd0;
    reg       stage2_sof   = 1'b0;

    reg       beat_valid = 1'b0;
    reg [7:0] beat_data  = 8'd0;
    reg       beat_last  = 1'b0;
    reg       beat_sof   = 1'b0;

    always @(posedge clk) begin
        m_axis_tvalid <= beat_valid;
        m_axis_tdata  <= beat_data;
        m_axis_tlast  <= beat_last;
        m_axis_tuser  <= beat_sof;
        beat_valid    <= 1'b0;

        if (vsync_fall) begin
            frame_active <= 1'b1;
            pending_sof  <= 1'b1;
        end

        if (href_fall) begin
            byte_parity <= 1'b0;
        end

        if (pclk_rise) begin
            if (stage2_valid) begin
                beat_valid <= 1'b1;
                beat_data  <= stage2_data;
                beat_last  <= !href_r1;
                beat_sof   <= stage2_sof;
            end
            stage2_valid <= stage1_valid;
            stage2_data  <= stage1_data;
            stage2_sof   <= stage1_sof;
            stage1_valid <= 1'b0;

            if (frame_active && href_r1 && !vsync_r1) begin
                if (byte_parity == 1'b0) begin
                    stage1_data  <= d_r1;
                    stage1_valid <= 1'b1;
                    stage1_sof   <= pending_sof;
                    pending_sof  <= 1'b0;
                end
                byte_parity <= ~byte_parity;
            end
        end
    end

endmodule
