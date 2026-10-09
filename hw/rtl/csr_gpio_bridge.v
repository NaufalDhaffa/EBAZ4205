// Relays the LiteScope CSR bus (hw/rtl/generated/litescope_top.v) over
// PS7 GPIO_O/GPIO_I EMIO, since GP0 already carries VDMA's AXI-Lite and a
// second AXI-Lite slave would need IP packaging to get an interface pin
// Vivado's connection automation can target.
//
// Bank-aligned so firmware (XGpioPs, 32 bits/bank) never splits a field:
//   gpio_o bank2 (bits [31:0]): [15:2]=csr_adr, [16]=write-request toggle,
//     [17]=read-request toggle.
//   gpio_o bank3 (bits [63:32]): csr_dat_w, whole bank.
//   gpio_i bank2 (bits [31:0]): csr_dat_r, whole bank.
//   gpio_i bank3 (bits [63:32]): [0]=write ack, [1]=read ack (mirrors the
//     request toggle once processed; software polls this).
module csr_gpio_bridge (
    input  wire        clk,
    input  wire [63:0] gpio_o,
    output wire [63:0] gpio_i,

    output reg  [13:0] csr_adr   = 14'd0,
    output reg         csr_we    = 1'b0,
    output reg         csr_re    = 1'b0,
    output reg  [31:0] csr_dat_w = 32'd0,
    input  wire [31:0] csr_dat_r
);

    reg we_req_s0 = 1'b0, we_req_s1 = 1'b0, we_req_s2 = 1'b0;
    reg re_req_s0 = 1'b0, re_req_s1 = 1'b0, re_req_s2 = 1'b0;
    always @(posedge clk) begin
        we_req_s0 <= gpio_o[16]; we_req_s1 <= we_req_s0; we_req_s2 <= we_req_s1;
        re_req_s0 <= gpio_o[17]; re_req_s1 <= re_req_s0; re_req_s2 <= re_req_s1;
    end
    wire we_req_edge = we_req_s1 ^ we_req_s2;
    wire re_req_edge = re_req_s1 ^ re_req_s2;

    reg we_ack = 1'b0, re_ack = 1'b0;
    reg [31:0] dat_r_latched = 32'd0;

    localparam IDLE = 2'd0, WE_PULSE = 2'd1, RE_PULSE = 2'd2, RE_CAPTURE = 2'd3;
    reg [1:0] state = IDLE;

    always @(posedge clk) begin
        csr_we <= 1'b0;
        csr_re <= 1'b0;
        case (state)
            IDLE: begin
                if (we_req_edge) begin
                    csr_adr   <= gpio_o[15:2];
                    csr_dat_w <= gpio_o[63:32];
                    csr_we    <= 1'b1;
                    state     <= WE_PULSE;
                end else if (re_req_edge) begin
                    csr_adr <= gpio_o[15:2];
                    csr_re  <= 1'b1;
                    state   <= RE_PULSE;
                end
            end
            WE_PULSE: begin
                we_ack <= we_req_s1;
                state  <= IDLE;
            end
            RE_PULSE: begin
                state <= RE_CAPTURE;
            end
            RE_CAPTURE: begin
                dat_r_latched <= csr_dat_r;
                re_ack        <= re_req_s1;
                state         <= IDLE;
            end
            default: state <= IDLE;
        endcase
    end

    assign gpio_i = {30'b0, re_ack, we_ack, dat_r_latched};

endmodule
