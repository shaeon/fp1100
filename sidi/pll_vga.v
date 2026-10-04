// PLL del video de 31 kHz de la SiDi (fp1100_vga, macro VGA_525): 25,14368
// MHz EXACTOS respecto al sistema, para que 800 x 525 puntos de VGA duren
// justo un cuadro de la maquina. Respecto a los 27 MHz del cristal la
// relacion es 4375/4698 (= 32 MHz x 4375/5568): como el cristal no tiene el
// factor 5, el producto de las M de la cascada tiene que ser multiplo de
// 4375, y una de ellas sale grande. Dos PLL en cascada, con un intermedio
// de 41,667 MHz (el mismo que en la Calypso):
//   a: 27 x 125 / 81 = 41,6667 MHz   (M = 125, N = 3, VCO 1125, C = 27)
//   b: 41,6667 x 35 / 58 = 25,14368 MHz   (M = 35, N = 2, VCO 729, C = 29)
// Quartus puede aproximar en vez de dar la relacion exacta (en la Poseidon
// lo hizo con M grandes): mirar SIEMPRE la tabla "PLL Usage" del fitter.
// Los 27 MHz llegan por c3 de pll (copia del cristal), no del pin: el pin
// es el del PLL principal y llevarlo a otro da un Critical Warning.
`timescale 1 ps / 1 ps
module pll_vga (
	input  wire inclk0,     // 27 MHz: c3 de pll, copia del cristal
	output wire c0,         // 25,14368 MHz
	output wire locked);

	wire [4:0] clk_a, clk_b;
	wire a_locked, b_locked;
	assign c0 = clk_b[0];
	assign locked = a_locked & b_locked;

	altpll a (
		.inclk ({1'b0, inclk0}),
		.clk (clk_a),
		.locked (a_locked),
		.activeclock (), .areset (1'b0), .clkbad (), .clkena ({6{1'b1}}),
		.clkloss (), .clkswitch (1'b0), .configupdate (1'b0), .enable0 (),
		.enable1 (), .extclk (), .extclkena ({4{1'b1}}), .fbin (1'b1),
		.fbmimicbidir (), .fbout (), .fref (), .icdrclk (), .pfdena (1'b1),
		.phasecounterselect ({4{1'b1}}), .phasedone (), .phasestep (1'b1),
		.phaseupdown (1'b1), .pllena (1'b1), .scanaclr (1'b0), .scanclk (1'b0),
		.scanclkena (1'b1), .scandata (1'b0), .scandataout (), .scandone (),
		.scanread (1'b0), .scanwrite (1'b0), .sclkout0 (), .sclkout1 (),
		.vcooverrange (), .vcounderrange ());
	defparam
		a.bandwidth_type = "AUTO",
		a.clk0_divide_by = 81,
		a.clk0_duty_cycle = 50,
		a.clk0_multiply_by = 125,
		a.clk0_phase_shift = "0",
		a.compensate_clock = "CLK0",
		a.inclk0_input_frequency = 37037,
		a.intended_device_family = "Cyclone IV E",
		a.lpm_hint = "CBX_MODULE_PREFIX=pll_vga_a",
		a.lpm_type = "altpll",
		a.operation_mode = "NORMAL",
		a.pll_type = "AUTO",
		a.port_activeclock = "PORT_UNUSED",
		a.port_areset = "PORT_UNUSED",
		a.port_clkbad0 = "PORT_UNUSED",
		a.port_clkbad1 = "PORT_UNUSED",
		a.port_clkloss = "PORT_UNUSED",
		a.port_clkswitch = "PORT_UNUSED",
		a.port_configupdate = "PORT_UNUSED",
		a.port_fbin = "PORT_UNUSED",
		a.port_inclk0 = "PORT_USED",
		a.port_inclk1 = "PORT_UNUSED",
		a.port_locked = "PORT_USED",
		a.port_pfdena = "PORT_UNUSED",
		a.port_phasecounterselect = "PORT_UNUSED",
		a.port_phasedone = "PORT_UNUSED",
		a.port_phasestep = "PORT_UNUSED",
		a.port_phaseupdown = "PORT_UNUSED",
		a.port_pllena = "PORT_UNUSED",
		a.port_scanaclr = "PORT_UNUSED",
		a.port_scanclk = "PORT_UNUSED",
		a.port_scanclkena = "PORT_UNUSED",
		a.port_scandata = "PORT_UNUSED",
		a.port_scandataout = "PORT_UNUSED",
		a.port_scandone = "PORT_UNUSED",
		a.port_scanread = "PORT_UNUSED",
		a.port_scanwrite = "PORT_UNUSED",
		a.port_clk0 = "PORT_USED",
		a.port_clk1 = "PORT_UNUSED",
		a.port_clk2 = "PORT_UNUSED",
		a.port_clk3 = "PORT_UNUSED",
		a.port_clk4 = "PORT_UNUSED",
		a.port_clk5 = "PORT_UNUSED",
		a.port_clkena0 = "PORT_UNUSED",
		a.port_clkena1 = "PORT_UNUSED",
		a.port_clkena2 = "PORT_UNUSED",
		a.port_clkena3 = "PORT_UNUSED",
		a.port_clkena4 = "PORT_UNUSED",
		a.port_clkena5 = "PORT_UNUSED",
		a.port_extclk0 = "PORT_UNUSED",
		a.port_extclk1 = "PORT_UNUSED",
		a.port_extclk2 = "PORT_UNUSED",
		a.port_extclk3 = "PORT_UNUSED",
		a.self_reset_on_loss_lock = "OFF",
		a.width_clock = 5;

	altpll b (
		.inclk ({1'b0, clk_a[0]}),
		.clk (clk_b),
		.locked (b_locked),
		.activeclock (), .areset (1'b0), .clkbad (), .clkena ({6{1'b1}}),
		.clkloss (), .clkswitch (1'b0), .configupdate (1'b0), .enable0 (),
		.enable1 (), .extclk (), .extclkena ({4{1'b1}}), .fbin (1'b1),
		.fbmimicbidir (), .fbout (), .fref (), .icdrclk (), .pfdena (1'b1),
		.phasecounterselect ({4{1'b1}}), .phasedone (), .phasestep (1'b1),
		.phaseupdown (1'b1), .pllena (1'b1), .scanaclr (1'b0), .scanclk (1'b0),
		.scanclkena (1'b1), .scandata (1'b0), .scandataout (), .scandone (),
		.scanread (1'b0), .scanwrite (1'b0), .sclkout0 (), .sclkout1 (),
		.vcooverrange (), .vcounderrange ());
	defparam
		b.bandwidth_type = "AUTO",
		b.clk0_divide_by = 58,
		b.clk0_duty_cycle = 50,
		b.clk0_multiply_by = 35,
		b.clk0_phase_shift = "0",
		b.compensate_clock = "CLK0",
		b.inclk0_input_frequency = 24000,
		b.intended_device_family = "Cyclone IV E",
		b.lpm_hint = "CBX_MODULE_PREFIX=pll_vga_b",
		b.lpm_type = "altpll",
		b.operation_mode = "NORMAL",
		b.pll_type = "AUTO",
		b.port_activeclock = "PORT_UNUSED",
		b.port_areset = "PORT_UNUSED",
		b.port_clkbad0 = "PORT_UNUSED",
		b.port_clkbad1 = "PORT_UNUSED",
		b.port_clkloss = "PORT_UNUSED",
		b.port_clkswitch = "PORT_UNUSED",
		b.port_configupdate = "PORT_UNUSED",
		b.port_fbin = "PORT_UNUSED",
		b.port_inclk0 = "PORT_USED",
		b.port_inclk1 = "PORT_UNUSED",
		b.port_locked = "PORT_USED",
		b.port_pfdena = "PORT_UNUSED",
		b.port_phasecounterselect = "PORT_UNUSED",
		b.port_phasedone = "PORT_UNUSED",
		b.port_phasestep = "PORT_UNUSED",
		b.port_phaseupdown = "PORT_UNUSED",
		b.port_pllena = "PORT_UNUSED",
		b.port_scanaclr = "PORT_UNUSED",
		b.port_scanclk = "PORT_UNUSED",
		b.port_scanclkena = "PORT_UNUSED",
		b.port_scandata = "PORT_UNUSED",
		b.port_scandataout = "PORT_UNUSED",
		b.port_scandone = "PORT_UNUSED",
		b.port_scanread = "PORT_UNUSED",
		b.port_scanwrite = "PORT_UNUSED",
		b.port_clk0 = "PORT_USED",
		b.port_clk1 = "PORT_UNUSED",
		b.port_clk2 = "PORT_UNUSED",
		b.port_clk3 = "PORT_UNUSED",
		b.port_clk4 = "PORT_UNUSED",
		b.port_clk5 = "PORT_UNUSED",
		b.port_clkena0 = "PORT_UNUSED",
		b.port_clkena1 = "PORT_UNUSED",
		b.port_clkena2 = "PORT_UNUSED",
		b.port_clkena3 = "PORT_UNUSED",
		b.port_clkena4 = "PORT_UNUSED",
		b.port_clkena5 = "PORT_UNUSED",
		b.port_extclk0 = "PORT_UNUSED",
		b.port_extclk1 = "PORT_UNUSED",
		b.port_extclk2 = "PORT_UNUSED",
		b.port_extclk3 = "PORT_UNUSED",
		b.self_reset_on_loss_lock = "OFF",
		b.width_clock = 5;
endmodule
