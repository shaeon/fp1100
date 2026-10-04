//============================================================================
// FP-1100: top comun a las placas tipo MiST (calcado del core NewBrain)
//
//   Poseidon  (Cyclone IV GX EP4CGX150)  proyecto en poseidon/, macro POSEIDON
//   Calypso   (Cyclone 10 LP)            proyecto en calypso/
//   SiDi      (Cyclone IV EP4CE22)        proyecto en sidi/, macro SIDI
//
// Solo cambian entre placas el reloj de entrada, los LEDs, los bits de VGA y
// el audio. Cada proyecto trae su PLL con el mismo nombre y salidas: c1 es el
// sistema a 32 MHz y c2 el de video a 25 MHz (puntos de 12,5 MHz, 800 por
// linea: el 640x480 de VGA, ver fp1100_display.v). La relacion 25/32 tiene
// que ser EXACTA: el contador de puntos del video corre libre y solo se
// realinea si se aparta dos puntos de la linea del CRTC. Si la relacion no
// es exacta se aparta en cada linea: con "Video line sync = Locked" cada
// linea dura distinto y el monitor no engancha; con "Free run" la hsync es
// estable pero las lineas del video y las del CRTC se deslizan y la imagen
// salta arriba y abajo.
//
// En Poseidon sale todo de un PLL (50 x 16 = VCO 800 MHz: /25 y /32). Con
// 27 MHz (SiDi) o 12 MHz (Calypso) un VCO de 800 no se alcanza con el
// comparador de fase dentro de rango, asi que su pll.v lleva DOS altpll:
// uno para 32 MHz y otro para 25, exactos los dos y siguiendo el mismo
// cristal, asi que no derivan.
//============================================================================
`default_nettype none

`ifdef SIDI
`define UN_SOLO_LED
`define RELOJ_27
`endif
`ifdef MIST
`define UN_SOLO_LED
`define RELOJ_27
`endif
`ifdef POSEIDON
`define UN_SOLO_LED
`endif
// La SDRAM de la Calypso tiene un bit de direccion menos (A0-A11): no hay
// pin de A12. El controlador nunca pone A12 a 1 (filas de 12 bits), asi que
// alli el puerto es de 12 bits; antes Quartus sacaba A12 por un pin
// cualquiera (Critical Warning 169085).
`ifndef RELOJ_27
`ifndef POSEIDON
`define SDRAM_SIN_A12
`endif
`endif

module fp1100_top(
`ifdef RELOJ_27
    input         CLOCK_27,
`elsif POSEIDON
    input         CLOCK_50,
`else
    input         CLK12M,
`endif
`ifdef UN_SOLO_LED
    output        LED,
`else
    output [7:0]  LED,
`endif

    output [VGA_BITS-1:0] VGA_R,
    output [VGA_BITS-1:0] VGA_G,
    output [VGA_BITS-1:0] VGA_B,
    output        VGA_HS,
    output        VGA_VS,

    input         SPI_SCK,
    inout         SPI_DO,
    input         SPI_DI,
    input         SPI_SS2,
    input         SPI_SS3,
    input         CONF_DATA0,
`ifndef NO_DIRECT_UPLOAD
    input         SPI_SS4,
`endif

`ifdef I2S_AUDIO
    output        I2S_BCK,
    output        I2S_LRCK,
    output        I2S_DATA,
`endif

`ifdef DELTASIGMA_AUDIO
    output        AUDIO_L,
    output        AUDIO_R,
`endif

`ifdef USE_AUDIO_IN
    input         AUDIO_IN,
`endif

`ifdef SDRAM_SIN_A12
    output [11:0] SDRAM_A,
`else
    output [12:0] SDRAM_A,
`endif
    inout  [15:0] SDRAM_DQ,
    output        SDRAM_DQML,
    output        SDRAM_DQMH,
    output        SDRAM_nWE,
    output        SDRAM_nCAS,
    output        SDRAM_nRAS,
    output        SDRAM_nCS,
    output [1:0]  SDRAM_BA,
    output        SDRAM_CLK,
    output        SDRAM_CKE
);

`ifdef NO_DIRECT_UPLOAD
localparam bit DIRECT_UPLOAD = 0;
wire SPI_SS4 = 1;
`else
localparam bit DIRECT_UPLOAD = 1;
`endif

`ifdef VGA_8BIT
localparam VGA_BITS = 8;
`elsif RELOJ_27
localparam VGA_BITS = 6;
`elsif POSEIDON
localparam VGA_BITS = 6;
`else
localparam VGA_BITS = 4;
`endif

`ifdef RELOJ_27
wire clk_entrada = CLOCK_27;
`elsif POSEIDON
wire clk_entrada = CLOCK_50;
`else
wire clk_entrada = CLK12M;
`endif

`ifdef BIG_OSD
localparam bit BIG_OSD = 1;
`define SEP "-;",
`else
localparam bit BIG_OSD = 0;
`define SEP
`endif

`ifdef USE_AUDIO_IN
wire TAPE_IN = AUDIO_IN;
`else
wire TAPE_IN = 1'b0;
`endif

`include "build_id.v"
parameter CONF_STR = {
    "FP1100;;",
    // Indice 0: el firmware la carga sola al arrancar, buscando FP1100.ROM
    "F0,ROM,Reload ROM;",
    "S0U,DSK,Drive A:;",
    "S1U,DSK,Drive B:;",
    "OB,FDC pack,On,Off;",
    `SEP
    "F2,WAV,Load tape;",
    "OC,Tape input,WAV file,Audio in;",
    "OD,Tape,Play,Pause;",
    "OLM,Tape monitor,Motor on,Always,Off;",
    "T1,Rewind tape;",
    `SEP
    "O45,Scanlines,Off,25%,50%,75%;",
    "OEG,H centre,0,+4,+8,+12,-16,-12,-8,-4;",
    "OHJ,V centre,0,+2,+4,+6,-8,-6,-4,-2;",
    // DIP switches de la placa sub
    "O6,Text width,80,40;",
    "O7,Screen,0,1;",
    "ON,Screen 1 display,400 lines,Fields;",
    "O8,Model,FP-1100,FP-1000;",
    "O9,CMT baud,1200,300;",
    "OA,Green mode colour,Green,White;",
    "OO,LED,Activity,Keyboard;",
    `SEP
    "T0,Reset;",
    "V,",`BUILD_VERSION,"-",`BUILD_DATE
};

/////////////////  RELOJES  ///////////////////////
wire clk_sys, clk_sdram, clk_pix, clk_c3, clk_vga;
wire pll_locked;

pll pll(
    .inclk0(clk_entrada),
    .c0(clk_sdram),     // sin usar
    .c1(clk_sys),       // 32 MHz
    .c2(clk_pix),       // 25 MHz: video, exactamente clk_sys x 25/32
    .c3(clk_c3),        // con VGA_525, copia del cristal para pll_vga; si no, sin usar
    .locked(pll_locked)
);

// VGA_525 (las tres placas): la salida de 31 kHz es un 640x480 de
// 525 lineas hecho por fp1100_vga con su propio reloj, 25,1436 MHz (ver
// pll_vga.v), en vez del scandoubler, que solo puede dar 522 (261 x 2).
`ifdef VGA_525
localparam bit VGA525 = 1;
// pll_vga toma el cristal de c3 y no del pin: el pin de reloj es el del
// PLL principal, y llevarlo a otro PLL da un Critical Warning (176598).
pll_vga pll_vga(
    .inclk0(clk_c3),
    .c0(clk_vga),       // 25,1436 MHz
    .locked()
);
`else
localparam bit VGA525 = 0;
assign clk_vga = clk_pix;
`endif

`ifdef MIST
localparam FAMILIA = "Cyclone III";
`elsif SIDI
localparam FAMILIA = "Cyclone IV E";
`elsif POSEIDON
localparam FAMILIA = "Cyclone IV GX";
`else
localparam FAMILIA = "Cyclone 10 LP";
`endif

// Reloj de la SDRAM: clk_sys invertido por un registro DDR del pin, como
// en el NewBrain (ver su doc/08-sdram.md)
altddio_out #(
    .extend_oe_disable("OFF"),
    .intended_device_family(FAMILIA),
    .invert_output("OFF"),
    .lpm_hint("UNUSED"),
    .lpm_type("altddio_out"),
    .oe_reg("UNREGISTERED"),
    .power_up_high("OFF"),
    .width(1)
) sdramclk_ddr (
    .datain_h(1'b0),
    .datain_l(1'b1),
    .outclock(clk_sys),
    .dataout(SDRAM_CLK),
    .aclr(1'b0),
    .aset(1'b0),
    .oe(1'b1),
    .outclocken(1'b1),
    .sclr(1'b0),
    .sset(1'b0)
);

/////////////////  IO  ////////////////////////////
wire [63:0] status;
wire [1:0]  buttons;
wire        scandoubler_disable, no_csync, ypbpr;

wire        ioctl_download;
wire [7:0]  ioctl_index;
wire        ioctl_wr;
wire [26:0] ioctl_addr;
wire [7:0]  ioctl_dout;

wire        ps2_kbd_clk, ps2_kbd_data;
wire [10:0] ps2_key;

wire [31:0] sd_lba;
wire [1:0]  sd_rd, sd_wr;
wire        sd_ack;
wire [8:0]  sd_buff_addr;
wire [7:0]  sd_buff_dout, sd_buff_din;
wire        sd_buff_wr;
wire [1:0]  img_mounted;
wire [63:0] img_size;

// FEAT_PS2REP (1000h): que el firmware repita la tecla pulsada (~15/s):
// fp1100_kbd suelta sola la ultima tecla si deja de repetirse, por si se
// perdio su "soltar" (ver ahi). Cola PS/2 de 32 bytes en vez de 16, por si
// llegan rafagas.
// PS2_16KHZ (macro del .qsf): reloj PS/2 de user_io hacia el core a
// 32 MHz / (2 x 1001) = ~16 kHz, el de un teclado PS/2 de verdad (como el
// C64 de MiST). Sin la macro, el valor por defecto de user_io (100): ~158
// kHz. Nuestro receptor funciona igual a las dos velocidades. OJO: el
// firmware no espera a que salgan los bytes; a 16 kHz cada byte tarda
// ~0,75 ms (a 158 kHz, 76 us), asi que la cola de user_io (32 bytes) se
// vacia diez veces mas despacio y, si llegan rafagas, se llena antes.
`ifdef PS2_16KHZ
localparam PS2_DIV = 1000;
`else
localparam PS2_DIV = 100;
`endif

user_io #(
    .STRLEN($size(CONF_STR)>>3),
    .SD_IMAGES(2),
    .FEATURES(32'h1000 | (BIG_OSD << 13)),
    // Reloj PS/2 hacia el core (ver PS2_DIV arriba)
    .PS2DIV(PS2_DIV),
    .PS2_KBD_FIFO_BITS(5))
user_io(
    .clk_sys(clk_sys),
    .clk_sd(clk_sys),
    .SPI_SS_IO(CONF_DATA0),
    .SPI_CLK(SPI_SCK),
    .SPI_MOSI(SPI_DI),
    .SPI_MISO(SPI_DO),
    .conf_str(CONF_STR),
    .status(status),
    .scandoubler_disable(scandoubler_disable),
    .ypbpr(ypbpr),
    .no_csync(no_csync),
    .buttons(buttons),
    .key_strobe(),
    .key_code(),
    .key_pressed(),
    .key_extended(),
    .ps2_kbd_clk(ps2_kbd_clk),
    .ps2_kbd_data(ps2_kbd_data),
    .ps2_kbd_clk_i(1'b1),
    .ps2_kbd_data_i(1'b1),
    .sd_lba(sd_lba),
    .sd_rd(sd_rd),
    .sd_wr(sd_wr),
    .sd_ack(sd_ack),
    .sd_ack_conf(),
    .sd_ack_x(),
    .sd_conf(1'b0),
    .sd_sdhc(1'b1),
    .sd_dout(sd_buff_dout),
    .sd_dout_strobe(sd_buff_wr),
    .sd_din(sd_buff_din),
    .sd_din_strobe(),
    .sd_buff_addr(sd_buff_addr),
    .img_mounted(img_mounted),
    .img_size(img_size)
);

data_io data_io(
    .clk_sys(clk_sys),
    .SPI_SCK(SPI_SCK),
    .SPI_SS2(SPI_SS2),
`ifdef NO_DIRECT_UPLOAD
    .SPI_SS4(1'b1),
`else
    .SPI_SS4(SPI_SS4),
`endif
    .SPI_DI(SPI_DI),
    .SPI_DO(SPI_DO),
    .ioctl_download(ioctl_download),
    .ioctl_index(ioctl_index),
    .ioctl_wr(ioctl_wr),
    .ioctl_addr(ioctl_addr),
    .ioctl_dout(ioctl_dout),
    .clkref_n(~sdram_free)
);

// La maquina se reinicia al cargar la ROM (no al cargar una cinta); la SDRAM
// solo cuando el PLL pierde el enganche (si estuviera en reset mientras
// data_io escribe, la ROM no llegaria nunca).
wire reset     = status[0] | buttons[1] | ~pll_locked | (ioctl_download & (ioctl_index[5:0] == 6'd0));
wire mem_reset = ~pll_locked;

// Reparto del fichero FP1100.ROM (48K, ver roms/README.md):
//
//   0000-8FFF   36K  basic.rom  ROM del Z80       -> SDRAM 000000
//   9000-9FFF    4K  sub1.rom   ROM interna 7801  -> block RAM (fp1100_upd7801)
//   A000-AFFF    4K  sub2.rom   ROM sub 1000      -> block RAM (fp1100_sub)
//   B000-BFFF    4K  sub3.rom   chargen F000      -> block RAM (fp1100_sub)
wire sdram_free;
wire rom_dl   = ioctl_download & (ioctl_index[5:0] == 6'd0);
wire in_z80   = ioctl_addr < 27'h9000;
wire in_sub1  = (ioctl_addr[26:12] == 15'h9);
wire in_sub2  = (ioctl_addr[26:12] == 15'hA);
wire in_sub3  = (ioctl_addr[26:12] == 15'hB);

// Indice 2: el WAV de la cinta, a la SDRAM desde 010000h
wire tape_dl = ioctl_download & (ioctl_index[5:0] == 6'd2);
wire dl_wr = (rom_dl & ioctl_wr & in_z80) | (tape_dl & ioctl_wr & (ioctl_addr < 27'h3F0000));
wire [23:0] dl_sdram_addr = tape_dl ? (24'h010000 + ioctl_addr[23:0]) : {3'd0, ioctl_addr[20:0]};

reg  tape_dl_d, tape_cargada;
reg  [23:0] tape_tamano;
always @(posedge clk_sys) begin
    tape_dl_d    <= tape_dl;
    tape_cargada <= tape_dl_d & ~tape_dl;
    if (tape_dl & ioctl_wr) tape_tamano <= ioctl_addr[23:0] + 24'd1;
end

// Rebobinar: la opcion T1 llega como un pulso en status[1]
reg  st1_d, tape_rebobinar;
always @(posedge clk_sys) begin
    st1_d <= status[1];
    tape_rebobinar <= status[1] & ~st1_d;
end

// AUDIO_IN de la placa ya viene en digital (comparador). Sin la entrada, 0.
// La polaridad importa: la maquina mide el periodo de flanco de subida a
// flanco de subida, y con la senal invertida un 0 seguido de un 1 da 625 us,
// justo el umbral entre 2400 y 1200 Hz: la carga falla. La entrada de audio
// de las placas llega invertida (probado en la SiDi con una cinta real: solo
// carga dandole la vuelta), asi que se invierte siempre. Hubo una opcion del
// OSD para esto (status[23]); ya no.
wire ear_in = ~TAPE_IN;

/////////////////  MAQUINA  ///////////////////////
wire [15:0] dbg_pc, dbg_sub_a;
wire        dbg_sdram_ready, dbg_int_req, dbg_int_ack;
wire        ce_pix;
wire        vid_31k;         // Screen 1 a 400 lineas: 31 kHz del core
wire [7:0]  R, G, B;
wire [7:0]  vga_r, vga_g, vga_b;
wire        vga_hs, vga_vs, vga_hb, vga_vb;
wire        hs, hs_cs, vs, hblank, vblank;
wire        beeper, cmt_motor, cmt_mic, fdc_motor, tape_lista, tape_play, cmt_rec, ear_mon;
wire        led_shift, led_caps;

// DIP switches: b0 80 col, b1 Screen 1, b2 FP-1100, b3 300 baud, b4
// impresora FP-1012PR, b5 siempre a uno
wire [7:0] dip = {2'b11, 1'b1, 1'b1, status[9], ~status[8], status[7], ~status[6]};

// Centrado horizontal. Por defecto, con H centre a 0:
//   15 kHz: imagen en el punto 28 tras la hsync (h_off -20): empieza a
//           10,0 us del flanco de la hsync y su centro cae a 35,6 us, el de
//           la imagen activa de la television (con -16, el de antes, iba
//           ~0,3 us a la derecha: se veia escorada).
//   31 kHz: imagen en el punto 48 (h_off 0, el porche de VGA)
// El menu (-16..+12) suma encima: 12..40 a 15 kHz (h_off no baja de -32:
// -16 en el menu da lo mismo que -12), 32..60 a 31 kHz; por la derecha la
// imagen acaba como mucho a 2 puntos de la hsync (704).
wire signed [5:0] h_off_menu = {status[16], status[16:14], 2'b00};
wire signed [6:0] h_off_15k  = {h_off_menu[5], h_off_menu} - 7'sd20;
wire signed [5:0] h_off = ~scandoubler_disable ? h_off_menu :
                          (h_off_15k < -7'sd32) ? 6'b100000 : h_off_15k[5:0];   // -32

// Centrado vertical (menu -8..+6 lineas de la maquina). A 31 kHz
// (scandoubler, o el modo de 400 lineas) fp1100_display saca la vsync de VGA
// (2 lineas de salida) con la imagen centrada en las 480 lineas; antes iba
// la vsync de 16 lineas del CRTC, doblada a 32, y el OSSC, que cuenta el
// porche desde el final de la vsync, se comia la fila de arriba.
wire signed [5:0] v_off_menu = {status[19], status[19:17], 1'b0};
wire signed [4:0] v_off = v_off_menu[4:0];

localparam CLK_HZ = 32_000_000;

// Al abrir y al cerrar el OSD se sueltan todas las teclas: mientras esta
// abierto el teclado no llega al core, y lo que estuviera pulsado al abrirlo
// se quedaria pegado (ver fp1100_kbd). osd_enable viene del dominio de video.
wire       osd_enable;
wire       kbd_alguna, ps2_rx_byte, ps2_rx_error;
reg  [2:0] osd_s;
always @(posedge clk_sys) osd_s <= {osd_s[1:0], osd_enable};
wire kbd_soltar = osd_s[2] ^ osd_s[1];

// Momento en que se recoge el dato de la SDRAM (ver fp1100_sdram, 'antes'):
// en la SiDi llega un ciclo antes que en la Poseidon. SDRAM_ANTES en el .qsf
// da el valor de la placa (doc §23-24). En la SiDi funcionan las dos formas
// (la normal gracias a que el bus retiene el dato); se queda la captura
// antes, que no depende de eso.
`ifdef SDRAM_ANTES
wire sdram_antes = 1'b1;
`else
wire sdram_antes = 1'b0;
`endif

wire [12:0] sdram_a;
`ifdef SDRAM_SIN_A12
assign SDRAM_A = sdram_a[11:0];
`else
assign SDRAM_A = sdram_a;
`endif

fp1100 #(.CLK_HZ(CLK_HZ)) fp1100(
    .clk_sys(clk_sys),
    .clk_pix(clk_pix),
    .clk_vga(clk_vga),
    .vga525(VGA525),
    .vga_scanlines(status[5:4]),
    // Centrado: en complemento a dos dentro de tres bits (las cuatro
    // primeras posiciones del menu positivas, las cuatro ultimas negativas),
    // x4 puntos en horizontal y x2 lineas en vertical
    .h_off(h_off),
    .v_off(v_off),
    .vid_15k(scandoubler_disable),
    .reset(reset),
    .sdram_antes(sdram_antes),
    // Screen 1 (400 lineas entrelazadas): "Fields" = cada trama por el
    // scandoubler, alternandose; "400 lines" = las dos juntas, 640x400 a
    // 31 kHz sacados por el propio core (ver fp1100_display). Solo si el
    // scandoubler esta activo: con salida de 15 kHz no tiene sentido.
    .vga400(~status[23] & ~scandoubler_disable),
    .vid_31k(vid_31k),
    .mem_reset(mem_reset),
    .dip(dip),
    // "Video line sync" (Locked / Free run) fue una opcion de diagnostico
    // (status[20]); se queda fijo en Locked: en Free run se pierde un punto
    // de vez en cuando.
    .vid_libre(1'b0),
    .dl_addr(dl_sdram_addr),
    .dl_data(ioctl_dout),
    .dl_wr(dl_wr),
    .sdram_free(sdram_free),
    .rom1_wr(rom_dl & ioctl_wr & in_sub1),
    .rom2_wr(rom_dl & ioctl_wr & in_sub2),
    .cg_wr(rom_dl & ioctl_wr & in_sub3),
    .rom_wr_addr(ioctl_addr[11:0]),
    .SDRAM_A(sdram_a), .SDRAM_DQ(SDRAM_DQ),
    .SDRAM_DQML(SDRAM_DQML), .SDRAM_DQMH(SDRAM_DQMH),
    .SDRAM_nWE(SDRAM_nWE), .SDRAM_nCAS(SDRAM_nCAS),
    .SDRAM_nRAS(SDRAM_nRAS), .SDRAM_nCS(SDRAM_nCS),
    .SDRAM_BA(SDRAM_BA), .SDRAM_CKE(SDRAM_CKE),
    .ce_pix(ce_pix),
    .vid_r(R), .vid_g(G), .vid_b(B),
    .vid_hs(hs), .vid_hs_cs(hs_cs), .vid_vs(vs), .vid_hb(hblank), .vid_vb(vblank),
    .vga_r(vga_r), .vga_g(vga_g), .vga_b(vga_b),
    .vga_hs(vga_hs), .vga_vs(vga_vs), .vga_hb(vga_hb), .vga_vb(vga_vb),
    .ps2_key(ps2_key),
    .kbd_soltar(kbd_soltar),
    .kbd_alguna(kbd_alguna),
    .led_shift(led_shift), .led_caps(led_caps),
    .beeper(beeper), .cmt_motor(cmt_motor), .cmt_mic(cmt_mic),
    .ear_in(ear_in), .tape_externa(status[12]),
    .tape_cargada(tape_cargada), .tape_tamano(tape_tamano),
    .tape_rebobinar(tape_rebobinar), .tape_pausa(status[13]),
    .tape_lista(tape_lista), .tape_play(tape_play),
    .cmt_rec(cmt_rec), .ear_mon(ear_mon),
    .fdc_enable(~status[11]),
    .img_mounted(img_mounted), .img_size(img_size[31:0]),
    .sd_lba(sd_lba), .sd_rd(sd_rd), .sd_wr(sd_wr), .sd_ack(sd_ack),
    .sd_buff_addr(sd_buff_addr), .sd_buff_dout(sd_buff_dout),
    .sd_buff_din(sd_buff_din), .sd_buff_wr(sd_buff_wr),
    .fdc_motor(fdc_motor),
    .dbg_pc(dbg_pc), .dbg_sub_a(dbg_sub_a),
    .dbg_sdram_ready(dbg_sdram_ready),
    .dbg_int_req(dbg_int_req), .dbg_int_ack(dbg_int_ack)
);

fp1100_ps2 teclado_ps2 (
    .clk(clk_sys),
    .reset(reset),
    .ps2_clk(ps2_kbd_clk),
    .ps2_data(ps2_kbd_data),
    .ps2_key(ps2_key),
    .rx_byte(ps2_rx_byte),
    .rx_error(ps2_rx_error)
);

/////////////////  LEDS  //////////////////////////
reg [24:0] hb_cnt;
reg        heartbeat;
always @(posedge clk_sys) begin
    if (hb_cnt >= 25'd15_999_999) begin
        hb_cnt    <= 25'd0;
        heartbeat <= ~heartbeat;
    end else hb_cnt <= hb_cnt + 1'b1;
end

reg [21:0] req_stretch, ack_stretch;
always @(posedge clk_sys) begin
    if (dbg_int_req) req_stretch <= 22'h3FFFFF;
    else if (req_stretch != 0) req_stretch <= req_stretch - 1'b1;
    if (dbg_int_ack) ack_stretch <= 22'h3FFFFF;
    else if (ack_stretch != 0) ack_stretch <= ack_stretch - 1'b1;
end

// "LED = Keyboard" (status[24]), para cazar teclas pegadas: encendido
// mientras la matriz del core tiene alguna tecla pulsada; cada byte PS/2 que
// llega lo invierte un instante (~30 ms), y una trama mala (inicio, parada o
// paridad) lo invierte medio segundo. Con una tecla "pegada": si el LED
// sigue encendido, se perdio el soltar por el camino PS/2; si esta apagado,
// la matriz esta bien y el problema es otro.
reg [19:0] byte_stretch;
reg [23:0] err_stretch;
always @(posedge clk_sys) begin
    if (ps2_rx_byte) byte_stretch <= 20'hFFFFF;
    else if (byte_stretch != 0) byte_stretch <= byte_stretch - 1'b1;
    if (ps2_rx_error) err_stretch <= 24'hFFFFFF;
    else if (err_stretch != 0) err_stretch <= err_stretch - 1'b1;
end
wire led_teclado = kbd_alguna ^ (|byte_stretch) ^ (|err_stretch);

`ifdef UN_SOLO_LED
assign LED = ~(status[24] ? led_teclado
                          : (ioctl_download | tape_play | (|sd_rd) | (|sd_wr)));
`else
assign LED = {|ack_stretch, |req_stretch, led_caps, led_shift,
              dbg_sdram_ready, heartbeat, |byte_stretch, kbd_alguna};
`endif

/////////////////  VIDEO  /////////////////////////
// Modo verde (PA4): el generador saca solo verde; con la opcion del menu
// se convierte en blanco
wire [7:0] G_mix = G;
wire [7:0] R_mix = status[10] ? G : R;
wire [7:0] B_mix = status[10] ? G : B;

`ifdef VGA_525
// Dos mist_video, los dos sin scandoubler: el de 15 kHz con clk_pix
// (fp1100_display) y el de 31 kHz con clk_vga (fp1100_vga, VGA de 525
// lineas, sincronismos separados). Cada uno lleva su OSD (los dos reciben
// el mismo SPI) y a los pines va el del modo elegido. El selector solo
// cambia al tocar el modo de video del firmware.
wire [7:0] vga_g_mix = vga_g;
wire [7:0] vga_r_mix = status[10] ? vga_g : vga_r;
wire [7:0] vga_b_mix = status[10] ? vga_g : vga_b;
wire       usa_csync15 = ~no_csync | ypbpr;
wire [VGA_BITS-1:0] r15, g15, b15, r31, g31, b31;
wire       hs15, vs15, hs31, vs31, osd15, osd31;
wire       sel31 = ~scandoubler_disable;

mist_video #(
    .COLOR_DEPTH(8),
    .SD_HCNT_WIDTH(11),
    .USE_BLANKS(1'b1),
    .OSD_COLOR(3'b001),
    .OUT_COLOR_DEPTH(VGA_BITS),
    .BIG_OSD(BIG_OSD))
mist_video(
    .clk_sys(clk_pix),
    .SPI_SCK(SPI_SCK),
    .SPI_SS3(SPI_SS3),
    .SPI_DI(SPI_DI),
    .R(R_mix), .G(G_mix), .B(B_mix),
    .HBlank(hblank), .VBlank(vblank),
    .HSync(usa_csync15 ? ~hs_cs : ~hs), .VSync(~vs),
    .VGA_R(r15), .VGA_G(g15), .VGA_B(b15),
    .VGA_VS(vs15), .VGA_HS(hs15),
    .ce_divider(3'd1),          // pixel = clk_pix / 2: 12,5 MHz
    .scandoubler_disable(1'b1),
    .no_csync(no_csync),
    .scanlines(2'b00),
    .ypbpr(ypbpr),
    .osd_enable(osd15)
);

mist_video #(
    .COLOR_DEPTH(8),
    .SD_HCNT_WIDTH(11),
    .USE_BLANKS(1'b1),
    .OSD_COLOR(3'b001),
    .OUT_COLOR_DEPTH(VGA_BITS),
    .BIG_OSD(BIG_OSD))
mist_video31(
    .clk_sys(clk_vga),
    .SPI_SCK(SPI_SCK),
    .SPI_SS3(SPI_SS3),
    .SPI_DI(SPI_DI),
    .R(vga_r_mix), .G(vga_g_mix), .B(vga_b_mix),
    .HBlank(vga_hb), .VBlank(vga_vb),
    .HSync(~vga_hs), .VSync(~vga_vs),
    .VGA_R(r31), .VGA_G(g31), .VGA_B(b31),
    .VGA_VS(vs31), .VGA_HS(hs31),
    .ce_divider(3'd1),
    .scandoubler_disable(1'b1),
    .no_csync(1'b1),
    .scanlines(2'b00),
    .ypbpr(ypbpr),
    .osd_enable(osd31)
);

assign VGA_R  = sel31 ? r31 : r15;
assign VGA_G  = sel31 ? g31 : g15;
assign VGA_B  = sel31 ? b31 : b15;
assign VGA_HS = sel31 ? hs31 : hs15;
assign VGA_VS = sel31 ? vs31 : vs15;
assign osd_enable = sel31 ? osd31 : osd15;
`else
// Sincronismo compuesto a 15 kHz: mist_video lo forma con ~(hs ^ vs) cuando
// el scandoubler esta desactivado y no se piden H y V separadas (o YPbPr);
// para ese caso va hs_cs (ver fp1100_display). Con el scandoubler, la hsync
// normal.
// En modo 31 kHz propio (Screen 1 a 400 lineas) el scandoubler se salta y
// los sincronismos van separados, como en VGA.
wire sd_off  = scandoubler_disable | vid_31k;
wire sin_cs  = no_csync | vid_31k;
wire usa_csync = sd_off & (~sin_cs | ypbpr);

mist_video #(
    .COLOR_DEPTH(8),
    .SD_HCNT_WIDTH(11),
    .USE_BLANKS(1'b1),
    .OSD_COLOR(3'b001),
    .OUT_COLOR_DEPTH(VGA_BITS),
    .BIG_OSD(BIG_OSD))
mist_video(
    .clk_sys(clk_pix),          // la salida de video va con el reloj de pixel
    .SPI_SCK(SPI_SCK),
    .SPI_SS3(SPI_SS3),
    .SPI_DI(SPI_DI),
    .R(R_mix), .G(G_mix), .B(B_mix),
    .HBlank(hblank), .VBlank(vblank),
    .HSync(usa_csync ? ~hs_cs : ~hs), .VSync(~vs),
    .VGA_R(VGA_R), .VGA_G(VGA_G), .VGA_B(VGA_B),
    .VGA_VS(VGA_VS), .VGA_HS(VGA_HS),
    .ce_divider(3'd1),          // pixel = clk_pix / 2: 12,5 MHz
    .scandoubler_disable(sd_off),
    .no_csync(sin_cs),
    .scanlines(status[5:4]),
    .ypbpr(ypbpr),
    .osd_enable(osd_enable)
);
`endif

/////////////////  AUDIO  ////////////////////////
// El beeper del teclado: onda cuadrada de ~950 Hz mientras esta activo
// (32 MHz / 1900 = 16842 ciclos por semiperiodo)
reg [14:0] beep_cnt;
reg        beep_osc;
always @(posedge clk_sys) begin
    if (beep_cnt == 15'd16841) begin
        beep_cnt <= 15'd0;
        beep_osc <= ~beep_osc;
    end else beep_cnt <= beep_cnt + 1'b1;
end

// Se oye tambien la cinta, bajito, como el altavoz de un casete: lo que se
// graba (MIC) y lo que se carga (EAR, el WAV o la entrada de audio segun
// "Tape input"). Opcion "Tape monitor" (status[22:21]):
//   0 Motor on   solo con el motor del casete en marcha (PC5), como antes
//   1 Always     EAR siempre, con motor o sin el: sirve para oir lo que
//                entra por la entrada de audio y ajustar el volumen del
//                reproductor antes de hacer LOAD. MIC solo mientras graba.
//   2 Off        sin sonido de cinta
// La entrada de audio de la placa llega ya digitalizada por un comparador:
// lo que se oye es la onda cuadrada que ve el FP-1100, no el audio original.
localparam signed [15:0] NIVEL = 16'sd6144;
localparam signed [15:0] NIVEL_CINTA = 16'sd1536;
wire [1:0] tape_monitor = status[22:21];
wire       oye_mic = cmt_motor & cmt_rec & (tape_monitor != 2'd2);
wire       oye_ear = ~(cmt_motor & cmt_rec) &
                     ((tape_monitor == 2'd1) | ((tape_monitor == 2'd0) & cmt_motor));
wire signed [15:0] audio_beep  = beeper ? (beep_osc ? NIVEL : -NIVEL) : 16'sd0;
wire signed [15:0] audio_cinta = oye_mic ? (cmt_mic ? NIVEL_CINTA : -NIVEL_CINTA) :
                                 oye_ear ? (ear_mon ? NIVEL_CINTA : -NIVEL_CINTA) :
                                           16'sd0;
wire signed [15:0] audio = audio_beep + audio_cinta;

`ifdef I2S_AUDIO
i2s i2s (
    .reset(1'b0),
    .clk(clk_sys),
    .clk_rate(CLK_HZ),
    .sclk(I2S_BCK),
    .lrclk(I2S_LRCK),
    .sdata(I2S_DATA),
    .left_chan(audio),
    .right_chan(audio)
);
`endif

`ifdef DELTASIGMA_AUDIO
wire [15:0] audio_sin_signo = {~audio[15], audio[14:0]};
dac #(.C_bits(16)) dac_l (.clk_i(clk_sys), .res_n_i(1'b1), .dac_i(audio_sin_signo), .dac_o(AUDIO_L));
dac #(.C_bits(16)) dac_r (.clk_i(clk_sys), .res_n_i(1'b1), .dac_i(audio_sin_signo), .dac_o(AUDIO_R));
`endif

endmodule

`default_nettype wire
