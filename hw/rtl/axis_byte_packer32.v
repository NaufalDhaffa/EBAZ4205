// axis_byte_packer32.v
//
// Packs 4 consecutive 8-bit AXI4-Stream beats (Y8 samples from
// ov7670_to_axis_y8) into one 32-bit beat: {Byte3, Byte2, Byte1, Byte0}
// where Byte0 is the first byte received (little-endian packing, LSB =
// oldest byte).
//
// TUSER handling: by construction, a Start-of-Frame beat from upstream can
// only ever land on the first byte of a row (byte_idx==0 at that point in
// a well-behaved stream), which is also always the first byte of a packed
// word here — so TUSER is latched only when byte_idx==0 and reused
// unchanged for that word's output beat.
//
// TLAST handling — root-caused via a real hardware probe during bring-up:
// an earlier version only ever forwarded s_axis_tlast when it happened to
// land on byte_idx==3, on the assumption that every row's Y-byte count is
// an exact multiple of 4 (true for a clean 320-byte QVGA row) so TLAST
// would always coincide with the 4th byte of a packing group. That's
// fragile the same way the upstream module's old TLAST logic was: byte_idx
// is a free-running counter with nothing to resync it to row boundaries
// except that assumption, so if it's ever violated even once (upstream
// timing irregularity, a transient glitch), byte_idx silently desyncs
// from real row boundaries forever afterward, and every subsequent
// s_axis_tlast landing off-boundary gets dropped with no forwarding and
// no self-correction. Fixed by always flushing (and resetting byte_idx)
// on s_axis_tlast regardless of byte_idx's current value, not only on the
// normal 4-byte boundary -- this makes byte_idx self-resynchronize to
// real row boundaries every single row instead of drifting permanently
// out of alignment after one irregular row.
//
// AXI4-Stream (AMBA IHI 0051): upstream (ov7670_to_axis_y8) is never
// backpressured, so s_axis_tready is tied high — this module has nowhere
// else to push data anyway (it only ever accumulates and immediately
// forwards). Real flow control against the downstream clock-domain-crossing
// FIFO happens on this module's own m_axis side.
module axis_byte_packer32 (
    input  wire        clk,

    input  wire [7:0]  s_axis_tdata,
    input  wire        s_axis_tvalid,
    input  wire        s_axis_tlast,   // row boundary, from ov7670_to_axis_y8
    input  wire        s_axis_tuser,   // start-of-frame, from ov7670_to_axis_y8
    output wire        s_axis_tready,

    output reg  [31:0] m_axis_tdata,
    output reg         m_axis_tvalid,
    output reg         m_axis_tlast,
    output reg         m_axis_tuser,
    input  wire        m_axis_tready   // intentionally not sampled, see header
);

    assign s_axis_tready = 1'b1;

    reg [1:0] byte_idx   = 2'd0;
    reg       word_tuser = 1'b0;

    always @(posedge clk) begin
        m_axis_tvalid <= 1'b0;
        m_axis_tlast  <= 1'b0;

        if (s_axis_tvalid) begin
            case (byte_idx)
                2'd0: begin
                    m_axis_tdata[7:0] <= s_axis_tdata;
                    word_tuser        <= s_axis_tuser;
                end
                2'd1: m_axis_tdata[15:8]  <= s_axis_tdata;
                2'd2: m_axis_tdata[23:16] <= s_axis_tdata;
                2'd3: m_axis_tdata[31:24] <= s_axis_tdata;
            endcase

            if (byte_idx == 2'd3 || s_axis_tlast) begin
                // Flush on the normal 4-byte boundary, OR immediately on
                // TLAST even if the row's byte count isn't a multiple of
                // 4 (any unfilled upper bytes keep their previous value
                // rather than the row boundary being silently dropped).
                // Either way byte_idx resets to 0, so a short/irregular
                // row can never permanently desync this module from real
                // row boundaries.
                m_axis_tvalid <= 1'b1;
                m_axis_tlast  <= s_axis_tlast;
                m_axis_tuser  <= (byte_idx == 2'd0) ? s_axis_tuser : word_tuser;
                byte_idx      <= 2'd0;
            end else begin
                byte_idx <= byte_idx + 2'd1;
            end
        end
    end

endmodule
