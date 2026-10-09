#!/usr/bin/env python3
# Generates hw/rtl/generated/litescope_top.v (analyzer + CSR bus, no
# Wishbone/UART/CPU -- axilite_to_csr_bridge.v drives the CSR bus from
# AXI-Lite) plus hw/build/litescope/{csr,analyzer}.csv for the host tools.
# Re-run via gen_litescope.sh whenever the probe list changes.

import os

from migen import Module, Signal, ClockDomain, If
from migen.fhdl import verilog
from migen.genlib.cdc import MultiReg

from litex.gen import LiteXModule
from litex.soc.interconnect.csr import CSRStatus
from litex.soc.interconnect import csr_bus
from litex.soc.integration.export import get_csr_csv, MockCSRRegion
from litex.build.xilinx.common import xilinx_special_overrides

from litescope import LiteScopeAnalyzer

# Bare verilog.convert() (no Xilinx platform) drops CDC synthesis attributes
# by default -- without these, Vivado is free to place/retime MultiReg
# flops apart, which showed up as a real hold violation once BRAM usage
# grew (analyzer depth bump). Reused from litex's own Vivado toolchain.
XILINX_ATTR_TRANSLATE = {
    "keep":             ("dont_touch", "true"),
    "no_retiming":      ("dont_touch", "true"),
    "async_reg":        ("async_reg",  "true"),
    "mr_ff":            ("mr_ff",      "true"),
    "ars_ff1":          ("ars_ff1",    "true"),
    "ars_ff2":          ("ars_ff2",    "true"),
    "no_shreg_extract": None,
}


class FrameCounters(LiteXModule):
    def __init__(self, tvalid, tlast, tuser):
        self.bytes_last_row = CSRStatus(16)
        self.rows_last_frame = CSRStatus(16)

        byte_cnt = Signal(16)
        row_cnt = Signal(16)
        bytes_last_row_pclk = Signal(16)
        rows_last_frame_pclk = Signal(16)

        self.sync.cam_pclk += [
            If(tlast,
                bytes_last_row_pclk.eq(byte_cnt + tvalid),
                byte_cnt.eq(0),
            ).Elif(tvalid,
                byte_cnt.eq(byte_cnt + 1),
            ),
            If(tuser,
                rows_last_frame_pclk.eq(row_cnt),
                row_cnt.eq(tlast),
            ).Elif(tlast,
                row_cnt.eq(row_cnt + 1),
            ),
        ]

        self.specials += MultiReg(bytes_last_row_pclk, self.bytes_last_row.status)
        self.specials += MultiReg(rows_last_frame_pclk, self.rows_last_frame.status)

OUT_RTL_DIR   = os.path.join(os.path.dirname(__file__), "..", "rtl", "generated")
OUT_BUILD_DIR = os.path.join(os.path.dirname(__file__), "..", "build", "litescope")

CSR_DATA_WIDTH = 32
CSR_ADDR_WIDTH = 14  # word-addressed -> 16-bit byte address space (64KiB)
ANALYZER_DEPTH = 32768
ANALYZER_NAME  = "analyzer"
CAM_PCLK_HZ    = 24_000_000  # worst-case bound, matches hw/constraints/camera.xdc


class LitescopeTop(Module):
    def __init__(self):
        self.clock_domains.cd_sys      = ClockDomain("sys")
        self.clock_domains.cd_cam_pclk = ClockDomain("cam_pclk")
        # 7-series FFs load their reset value from the bitstream at
        # power-up/reconfiguration -- same convention already used by
        # hw/rtl/ov7670_to_axis_y8.v and axis_byte_packer32.v in this repo
        # (no explicit reset network), so no runtime reset is needed here.
        self.comb += self.cd_sys.rst.eq(0)
        self.comb += self.cd_cam_pclk.rst.eq(0)

        # ov7670_to_axis_y8.v evaluates tvalid/tlast/tuser on negedge pclk;
        # Migen's self.sync.cam_pclk is always posedge, so cd_cam_pclk.clk
        # is driven from the inverted raw pin -- posedge-of-inverted ==
        # negedge-of-real, matching the DUT's own sampling instant instead
        # of sampling it a half-cycle late.
        self.cam_pclk_raw = Signal()
        self.comb += self.cd_cam_pclk.clk.eq(~self.cam_pclk_raw)

        # --- Probe signals (cam_pclk domain, driven from the BD) ---
        self.cam_vsync    = Signal()
        self.cam_href     = Signal()
        self.cam_pdata    = Signal(8)
        self.axis_tvalid  = Signal()
        self.axis_tlast   = Signal()
        self.axis_tuser   = Signal()
        self.axis_tdata   = Signal(8)

        probes = [
            self.cam_vsync,
            self.cam_href,
            self.cam_pdata,
            self.axis_tvalid,
            self.axis_tlast,
            self.axis_tuser,
            self.axis_tdata,
        ]

        self.submodules.analyzer = LiteScopeAnalyzer(
            probes,
            depth        = ANALYZER_DEPTH,
            clock_domain = "cam_pclk",
            samplerate   = CAM_PCLK_HZ,
            register     = True,
            csr_csv      = None,
        )

        self.submodules.framecounters = FrameCounters(
            self.axis_tvalid, self.axis_tlast, self.axis_tuser,
        )

        # --- CSR bus (word-addressed, sys/FCLK0 domain) ---
        self.csr_bus = csr_bus.Interface(
            data_width    = CSR_DATA_WIDTH,
            address_width = CSR_ADDR_WIDTH,
        )
        bank_addr = {}
        def address_map(name, memory):
            if name not in bank_addr:
                bank_addr[name] = len(bank_addr)
            return bank_addr[name]
        self.submodules.csr_bankarray = csr_bus.CSRBankArray(
            self, address_map,
            data_width    = CSR_DATA_WIDTH,
            address_width = CSR_ADDR_WIDTH,
        )
        self.submodules.csr_con = csr_bus.Interconnect(
            self.csr_bus, self.csr_bankarray.get_buses(),
        )


def main():
    os.makedirs(OUT_RTL_DIR, exist_ok=True)
    os.makedirs(OUT_BUILD_DIR, exist_ok=True)

    top = LitescopeTop()

    ios = {
        top.cd_sys.clk, top.cam_pclk_raw,
        top.cam_vsync, top.cam_href, top.cam_pdata,
        top.axis_tvalid, top.axis_tlast, top.axis_tuser, top.axis_tdata,
        top.csr_bus.adr, top.csr_bus.we, top.csr_bus.re,
        top.csr_bus.dat_w, top.csr_bus.dat_r,
    }

    conv = verilog.convert(top, ios=ios, name="litescope_top",
                            create_clock_domains=False,
                            special_overrides=xilinx_special_overrides,
                            attr_translate=XILINX_ATTR_TRANSLATE)

    # LiteScopeAnalyzer.do_exit() writes analyzer.csv (config+signal
    # layout) -- a Migen Module convention (module.py: do_exit()
    # recurses into submodules), normally invoked by litex's own
    # Builder.build() step; called by hand here since there's no
    # full SoC build for this bare integration.
    top.analyzer.csr_csv = os.path.join(OUT_BUILD_DIR, "analyzer.csv")
    top.do_exit(vns=conv.ns)

    verilog_path = os.path.join(OUT_RTL_DIR, "litescope_top.v")
    conv.write(verilog_path)

    # SoC-wide register address map (csr.csv), built the same way real
    # litex SoCs build it (litex.soc.integration.export.get_csr_csv) so
    # the host-side CommUART/CSRBuilder parses it identically.
    csr_regions = {
        name: MockCSRRegion(origin=mapaddr * 0x800, obj=csrs)
        for (name, csrs, mapaddr, rmap) in top.csr_bankarray.banks
    }
    assert ANALYZER_NAME in csr_regions, (
        f"expected a CSR bank named '{ANALYZER_NAME}' -- driver/analyzer.py "
        f"and the firmware relay both assume this name"
    )
    constants = {
        "CONFIG_CSR_DATA_WIDTH":    CSR_DATA_WIDTH,
        # Wire-protocol address width (CommUART/Etherbone convention) --
        # unrelated to CSR_ADDR_WIDTH, which is the internal Migen CSR
        # bus's word-address width wired to csr_gpio_bridge.v.
        "CONFIG_BUS_ADDRESS_WIDTH": 32,
    }
    csr_csv_path = os.path.join(OUT_BUILD_DIR, "csr.csv")
    with open(csr_csv_path, "w") as f:
        f.write(get_csr_csv(csr_regions, constants))

    print(f"BUILD_OK: wrote {verilog_path}")
    print(f"BUILD_OK: wrote {csr_csv_path}")
    print(f"BUILD_OK: wrote {top.analyzer.csr_csv}")


if __name__ == "__main__":
    main()
