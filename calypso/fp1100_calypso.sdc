create_clock -name "CLK12M" -period 83.333 [get_ports {CLK12M}]
create_clock -name {SPI_SCK}  -period 41.666 [get_ports {SPI_SCK}]

# Automatically constrain PLL and other generated clocks
derive_pll_clocks -create_base_clocks

# SDRAM. SDRAM_CLK sale de un registro DDR del pin (sdramclk_ddr en
# fp1100_top.sv) que da clk_sys invertido, o sea el reloj del sistema
# adelantado medio periodo. Va antes de
# cualquier otra restriccion que lo nombre. c0 ya no se usa y Quartus lo
# quita, por eso no aparece en los grupos.
create_generated_clock -name sdram_clk -source [get_pins {pll|altpll_component|auto_generated|pll1|clk[1]}] -invert [get_ports {SDRAM_CLK}]

# Automatically calculate clock uncertainty to jitter and other effects.
derive_clock_uncertainty

set_clock_groups -asynchronous -group [get_clocks {SPI_SCK}] -group [get_clocks {pll|altpll_component|auto_generated|pll1|clk[*] pll|altpll_vid|auto_generated|pll1|clk[0] sdram_clk pll_vga|*|clk[0]}]


# SDRAM: los retardos van contra sdram_clk, definido arriba.

set_input_delay -clock [get_clocks {sdram_clk}] -max 6.4 [get_ports SDRAM_DQ[*]]
set_input_delay -clock [get_clocks {sdram_clk}] -min 3.2 [get_ports SDRAM_DQ[*]]

set_output_delay -clock [get_clocks {sdram_clk}] -max 1.5 [get_ports {SDRAM_D* SDRAM_A* SDRAM_BA* SDRAM_n* SDRAM_CKE}]
set_output_delay -clock [get_clocks {sdram_clk}] -min -0.8 [get_ports {SDRAM_D* SDRAM_A* SDRAM_BA* SDRAM_n* SDRAM_CKE}]

# El video va con c2 (25 MHz), que sale del segundo PLL (altpll_vid, ver
# pll.v), y cruza de c1 por un toggle sincronizado y valores que solo
# cambian con el (fp1100_display)
set_clock_groups -asynchronous \
    -group [get_clocks {pll|altpll_component|auto_generated|pll1|clk[1] sdram_clk}] \
    -group [get_clocks {pll|altpll_vid|auto_generated|pll1|clk[0]}]

# VGA_525: fp1100_vga va con el c0 de pll_vga|b (25,1436 MHz; pll_vga|a da
# los 41,67 MHz intermedios, que solo alimentan a pll_vga|b) y, como
# fp1100_display, toma del CRTC un toggle sincronizado y valores que solo
# cambian con el; el anillo de lineas de fp1100_vfetch se escribe con c1 y
# se lee con este
set_clock_groups -asynchronous \
    -group [get_clocks {pll|altpll_component|auto_generated|pll1|clk[1] sdram_clk}] \
    -group [get_clocks {pll_vga|*|clk[0]}]
set_clock_groups -asynchronous \
    -group [get_clocks {pll|altpll_vid|auto_generated|pll1|clk[0]}] \
    -group [get_clocks {pll_vga|*|clk[0]}]
