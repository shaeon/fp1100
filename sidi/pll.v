// PLL de la SiDi: DOS altpll con la misma entrada (27 MHz del cristal).
//
//   altpll_component  c0  32 MHz desfasado -7800 ps (sin usar: SDRAM_CLK
//                         sale de un registro DDR con c1)
//                     c1  32 MHz: reloj del sistema
//                     c3  27 MHz: copia del cristal para pll_vga (VGA_525)
//                     VCO 864 MHz (27 x 32), /27 = 32
//   altpll_vid        c2 (su clk[0]) 25 MHz: reloj de pixel, puntos de
//                         12,5 MHz, 800 por linea
//                     VCO 675 MHz (27 x 25), /27 = 25
//
// Por que dos: el video necesita que c2/c1 sea EXACTAMENTE 25/32 (su
// contador de puntos corre libre, ver fp1100_display.v y fp1100_top.sv).
// En un solo PLL las dos salidas salen del mismo VCO, que tendria que ser
// multiplo de 800 MHz; con 27 MHz de entrada eso pide N = 27 y el comparador de fase se queda en 1 MHz, fuera de rango (minimo 5). Con dos PLL cada uno tiene su VCO, los dos
// salen exactos, y como los dos siguen al mismo cristal la relacion entre
// ellos es exacta: no derivan. La fase entre c1 y c2 da igual (el video
// cruza de dominio por un toggle sincronizado).
//
// locked = los dos enganchados. altpll_vid toma el cristal de c3 del
// primero (copia 1:1), no del pin: desde el pin daba un Critical Warning. Si se regenera con el asistente, hay que conservar los
// nombres de instancia: el .sdc los usa.
`timescale 1 ps / 1 ps
// synopsys translate_on
module pll (
	inclk0,
	c0,
	c1,
	c2,
	c3,
	locked);

	input	  inclk0;
	output	  c0;
	output	  c1;
	output	  c2;
	output	  c3;
	output	  locked;

	wire [4:0] sub_wire0;
	wire  sub_wire3;
	wire [0:0] sub_wire6 = 1'h0;
	wire [1:1] sub_wire2 = sub_wire0[1:1];
	wire [0:0] sub_wire1 = sub_wire0[0:0];
	wire  c0 = sub_wire1;
	wire  c1 = sub_wire2;
	wire [4:0] vid_clk;
	wire  vid_locked;
	wire  c2 = vid_clk[0];
	wire  c3 = sub_wire0[3];
	wire  locked = sub_wire3 & vid_locked;
	wire  sub_wire4 = inclk0;
	wire [1:0] sub_wire5 = {sub_wire6, sub_wire4};

	altpll	altpll_component (
				.inclk (sub_wire5),
				.clk (sub_wire0),
				.locked (sub_wire3),
				.activeclock (),
				.areset (1'b0),
				.clkbad (),
				.clkena ({6{1'b1}}),
				.clkloss (),
				.clkswitch (1'b0),
				.configupdate (1'b0),
				.enable0 (),
				.enable1 (),
				.extclk (),
				.extclkena ({4{1'b1}}),
				.fbin (1'b1),
				.fbmimicbidir (),
				.fbout (),
				.fref (),
				.icdrclk (),
				.pfdena (1'b1),
				.phasecounterselect ({4{1'b1}}),
				.phasedone (),
				.phasestep (1'b1),
				.phaseupdown (1'b1),
				.pllena (1'b1),
				.scanaclr (1'b0),
				.scanclk (1'b0),
				.scanclkena (1'b1),
				.scandata (1'b0),
				.scandataout (),
				.scandone (),
				.scanread (1'b0),
				.scanwrite (1'b0),
				.sclkout0 (),
				.sclkout1 (),
				.vcooverrange (),
				.vcounderrange ());
	defparam
		altpll_component.bandwidth_type = "AUTO",
		altpll_component.clk0_divide_by = 27,
		altpll_component.clk0_duty_cycle = 50,
		altpll_component.clk0_multiply_by = 32,
		altpll_component.clk0_phase_shift = "-7800",
		altpll_component.clk1_divide_by = 27,
		altpll_component.clk1_duty_cycle = 50,
		altpll_component.clk1_multiply_by = 32,
		altpll_component.clk1_phase_shift = "0",
		altpll_component.clk3_divide_by = 1,
		altpll_component.clk3_duty_cycle = 50,
		altpll_component.clk3_multiply_by = 1,
		altpll_component.clk3_phase_shift = "0",
		altpll_component.compensate_clock = "CLK0",
		altpll_component.inclk0_input_frequency = 37037,
		altpll_component.intended_device_family = "Cyclone IV E",
		altpll_component.lpm_hint = "CBX_MODULE_PREFIX=pll",
		altpll_component.lpm_type = "altpll",
		altpll_component.operation_mode = "NORMAL",
		altpll_component.pll_type = "AUTO",
		altpll_component.port_activeclock = "PORT_UNUSED",
		altpll_component.port_areset = "PORT_UNUSED",
		altpll_component.port_clkbad0 = "PORT_UNUSED",
		altpll_component.port_clkbad1 = "PORT_UNUSED",
		altpll_component.port_clkloss = "PORT_UNUSED",
		altpll_component.port_clkswitch = "PORT_UNUSED",
		altpll_component.port_configupdate = "PORT_UNUSED",
		altpll_component.port_fbin = "PORT_UNUSED",
		altpll_component.port_inclk0 = "PORT_USED",
		altpll_component.port_inclk1 = "PORT_UNUSED",
		altpll_component.port_locked = "PORT_USED",
		altpll_component.port_pfdena = "PORT_UNUSED",
		altpll_component.port_phasecounterselect = "PORT_UNUSED",
		altpll_component.port_phasedone = "PORT_UNUSED",
		altpll_component.port_phasestep = "PORT_UNUSED",
		altpll_component.port_phaseupdown = "PORT_UNUSED",
		altpll_component.port_pllena = "PORT_UNUSED",
		altpll_component.port_scanaclr = "PORT_UNUSED",
		altpll_component.port_scanclk = "PORT_UNUSED",
		altpll_component.port_scanclkena = "PORT_UNUSED",
		altpll_component.port_scandata = "PORT_UNUSED",
		altpll_component.port_scandataout = "PORT_UNUSED",
		altpll_component.port_scandone = "PORT_UNUSED",
		altpll_component.port_scanread = "PORT_UNUSED",
		altpll_component.port_scanwrite = "PORT_UNUSED",
		altpll_component.port_clk0 = "PORT_USED",
		altpll_component.port_clk1 = "PORT_USED",
		altpll_component.port_clk2 = "PORT_UNUSED",
		altpll_component.port_clk3 = "PORT_USED",
		altpll_component.port_clk4 = "PORT_UNUSED",
		altpll_component.port_clk5 = "PORT_UNUSED",
		altpll_component.port_clkena0 = "PORT_UNUSED",
		altpll_component.port_clkena1 = "PORT_UNUSED",
		altpll_component.port_clkena2 = "PORT_UNUSED",
		altpll_component.port_clkena3 = "PORT_UNUSED",
		altpll_component.port_clkena4 = "PORT_UNUSED",
		altpll_component.port_clkena5 = "PORT_UNUSED",
		altpll_component.port_extclk0 = "PORT_UNUSED",
		altpll_component.port_extclk1 = "PORT_UNUSED",
		altpll_component.port_extclk2 = "PORT_UNUSED",
		altpll_component.port_extclk3 = "PORT_UNUSED",
		altpll_component.self_reset_on_loss_lock = "OFF",
		altpll_component.width_clock = 5;


	// Entrada: los 27 MHz por c3 del PLL principal (copia del cristal), no
	// del pin: el pin de reloj es el de altpll_component, y llevarlo a otro
	// PLL daba el Critical Warning 176598 (remote clock pin)
	altpll	altpll_vid (
				.inclk ({1'b0, sub_wire0[3]}),
				.clk (vid_clk),
				.locked (vid_locked),
				.activeclock (),
				.areset (1'b0),
				.clkbad (),
				.clkena ({6{1'b1}}),
				.clkloss (),
				.clkswitch (1'b0),
				.configupdate (1'b0),
				.enable0 (),
				.enable1 (),
				.extclk (),
				.extclkena ({4{1'b1}}),
				.fbin (1'b1),
				.fbmimicbidir (),
				.fbout (),
				.fref (),
				.icdrclk (),
				.pfdena (1'b1),
				.phasecounterselect ({4{1'b1}}),
				.phasedone (),
				.phasestep (1'b1),
				.phaseupdown (1'b1),
				.pllena (1'b1),
				.scanaclr (1'b0),
				.scanclk (1'b0),
				.scanclkena (1'b1),
				.scandata (1'b0),
				.scandataout (),
				.scandone (),
				.scanread (1'b0),
				.scanwrite (1'b0),
				.sclkout0 (),
				.sclkout1 (),
				.vcooverrange (),
				.vcounderrange ());
	defparam
		altpll_vid.bandwidth_type = "AUTO",
		altpll_vid.clk0_divide_by = 27,
		altpll_vid.clk0_duty_cycle = 50,
		altpll_vid.clk0_multiply_by = 25,
		altpll_vid.clk0_phase_shift = "0",
		altpll_vid.compensate_clock = "CLK0",
		altpll_vid.inclk0_input_frequency = 37037,
		altpll_vid.intended_device_family = "Cyclone IV E",
		altpll_vid.lpm_hint = "CBX_MODULE_PREFIX=pll_vid",
		altpll_vid.lpm_type = "altpll",
		altpll_vid.operation_mode = "NORMAL",
		altpll_vid.pll_type = "AUTO",
		altpll_vid.port_activeclock = "PORT_UNUSED",
		altpll_vid.port_areset = "PORT_UNUSED",
		altpll_vid.port_clkbad0 = "PORT_UNUSED",
		altpll_vid.port_clkbad1 = "PORT_UNUSED",
		altpll_vid.port_clkloss = "PORT_UNUSED",
		altpll_vid.port_clkswitch = "PORT_UNUSED",
		altpll_vid.port_configupdate = "PORT_UNUSED",
		altpll_vid.port_fbin = "PORT_UNUSED",
		altpll_vid.port_inclk0 = "PORT_USED",
		altpll_vid.port_inclk1 = "PORT_UNUSED",
		altpll_vid.port_locked = "PORT_USED",
		altpll_vid.port_pfdena = "PORT_UNUSED",
		altpll_vid.port_phasecounterselect = "PORT_UNUSED",
		altpll_vid.port_phasedone = "PORT_UNUSED",
		altpll_vid.port_phasestep = "PORT_UNUSED",
		altpll_vid.port_phaseupdown = "PORT_UNUSED",
		altpll_vid.port_pllena = "PORT_UNUSED",
		altpll_vid.port_scanaclr = "PORT_UNUSED",
		altpll_vid.port_scanclk = "PORT_UNUSED",
		altpll_vid.port_scanclkena = "PORT_UNUSED",
		altpll_vid.port_scandata = "PORT_UNUSED",
		altpll_vid.port_scandataout = "PORT_UNUSED",
		altpll_vid.port_scandone = "PORT_UNUSED",
		altpll_vid.port_scanread = "PORT_UNUSED",
		altpll_vid.port_scanwrite = "PORT_UNUSED",
		altpll_vid.port_clk0 = "PORT_USED",
		altpll_vid.port_clk1 = "PORT_UNUSED",
		altpll_vid.port_clk2 = "PORT_UNUSED",
		altpll_vid.port_clk3 = "PORT_UNUSED",
		altpll_vid.port_clk4 = "PORT_UNUSED",
		altpll_vid.port_clk5 = "PORT_UNUSED",
		altpll_vid.port_clkena0 = "PORT_UNUSED",
		altpll_vid.port_clkena1 = "PORT_UNUSED",
		altpll_vid.port_clkena2 = "PORT_UNUSED",
		altpll_vid.port_clkena3 = "PORT_UNUSED",
		altpll_vid.port_clkena4 = "PORT_UNUSED",
		altpll_vid.port_clkena5 = "PORT_UNUSED",
		altpll_vid.port_extclk0 = "PORT_UNUSED",
		altpll_vid.port_extclk1 = "PORT_UNUSED",
		altpll_vid.port_extclk2 = "PORT_UNUSED",
		altpll_vid.port_extclk3 = "PORT_UNUSED",
		altpll_vid.self_reset_on_loss_lock = "OFF",
		altpll_vid.width_clock = 5;



endmodule
