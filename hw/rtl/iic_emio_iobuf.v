// iic_emio_iobuf.v
//
// PS7's I2C0 controller, when routed to EMIO, exposes SCL/SDA as split
// input/output/tristate-control signals (not true bidirectional pins) —
// this wraps two Xilinx IOBUF primitives to turn each I/O/T triple into one
// real bidirectional pin, for the OV7670's SCCB bus (SCCB is electrically
// I2C-compatible: open-drain SCL+SDA with pull-ups).
//
// Port names here are generic on purpose — the actual PS7 I2C0 EMIO pin
// names are verified directly against the installed PS7 IP in
// hw/scripts/build_bd.tcl (same approach used for every other PS7 EMIO
// signal in this repo, e.g. Ethernet's ENET0_GMII_* pins) rather than
// assumed here.
module iic_emio_iobuf (
    // From/to PS7 I2C0 EMIO
    input  wire scl_i_from_ps,   // PS-driven output value (drive when scl_t_from_ps=0)
    output wire scl_o_to_ps,     // value read back into the PS
    input  wire scl_t_from_ps,   // tristate control: 0=drive scl_i_from_ps, 1=high-Z (read)
    input  wire sda_i_from_ps,
    output wire sda_o_to_ps,
    input  wire sda_t_from_ps,

    // Physical bidirectional pins (open-drain SCCB/I2C bus, external pull-ups)
    inout  wire cam_sioc,
    inout  wire cam_siod
);

    IOBUF scl_iobuf (
        .I  (scl_i_from_ps),
        .O  (scl_o_to_ps),
        .T  (scl_t_from_ps),
        .IO (cam_sioc)
    );

    IOBUF sda_iobuf (
        .I  (sda_i_from_ps),
        .O  (sda_o_to_ps),
        .T  (sda_t_from_ps),
        .IO (cam_siod)
    );

endmodule
