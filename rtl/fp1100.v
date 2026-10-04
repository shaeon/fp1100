//============================================================================
// Casio FP-1100 - maquina
//
// Reparto de la SDRAM (como en el NewBrain: la ROM del Z80 y la RAM viven
// en la SDRAM, la placa sub entera en block RAM):
//
//   000000-008FFF   ROM del Z80, 36K (IPL 32K + BASIC 4K)     banco 0
//   010000-3FFFFF   cinta (WAV cargado por el OSD)             bancos 0-1
//   400000-40FFFF   RAM, 64K                                  banco 2
//   600000-60FFFF   VRAM, solo con VRAM_SDRAM                 banco 3
//                   4 bytes por byte de VRAM: B, R, G y uno libre, para
//                   que el video lea los tres planos con un ACTIVE
//
// Relojes, todos de clk_sys = 32 MHz (la maquina lleva 15,9744 MHz x 2):
//
//   Z80        4 MHz          clkdiv[2:0]: cen_p en 0, cen_n en 4
//   uPD7801    2 MHz (4 fases a 8 MHz)   clkdiv[3:0]: 3, 7, 11, 15
//   puntos    16 MHz          clkdiv[0]
//
// El sub y el video van en block RAM: VRAM 48K, ROM sub2 4K, generador de
// caracteres 4K y la ROM interna 4K. En Poseidon sobra; en la SiDi
// (EP4CE22, 66 M9K) no cabe, y con la macro VRAM_SDRAM la VRAM pasa a la
// SDRAM. En los dos casos el video la lee linea a linea por fp1100_vfetch.
//============================================================================
`default_nettype none

module fp1100 #(
    parameter CLK_HZ = 32_000_000
) (
    input  wire        clk_sys,
    input  wire        clk_pix,         // 25 MHz: la salida de video
    input  wire        clk_vga,         // 25,1436 MHz: la salida de 31 kHz propia (VGA_525)
    input  wire        vga525,          // 31 kHz por fp1100_vga: fp1100_display solo hace 15 kHz
    input  wire [1:0]  vga_scanlines,   // scanlines de fp1100_vga
    input  wire signed [5:0] h_off,     // centrado horizontal (puntos, -16..+12)
    input  wire signed [4:0] v_off,     // centrado vertical (lineas)
    input  wire        vid_15k,         // salida a 15 kHz (sin scandoubler): sincronismos de TV
    input  wire        reset,
    input  wire        sdram_antes,     // recoger el dato de la SDRAM un paso antes (SiDi)
    input  wire        vga400,          // Screen 1 en 400 lineas a 31 kHz (OSD)
    output wire        vid_31k,         // el video esta sacando 31 kHz: sin scandoubler
    input  wire        mem_reset,       // solo cuando el PLL pierde el enganche

    // configuracion
    input  wire [7:0]  dip,             // DIP switches del sub (E400)
    input  wire        vid_libre,       // contador de video sin realinear (diagnostico)

    // carga desde data_io: fichero FP1100.ROM (ver roms/README.md)
    input  wire [23:0] dl_addr,         // direccion de SDRAM
    input  wire [7:0]  dl_data,
    input  wire        dl_wr,           // va a la SDRAM
    output wire        sdram_free,
    input  wire        rom1_wr,         // sub1.rom
    input  wire        rom2_wr,         // sub2.rom
    input  wire        cg_wr,           // sub3.rom
    input  wire [11:0] rom_wr_addr,

    // pines de SDRAM
    output wire [12:0] SDRAM_A,
    inout  wire [15:0] SDRAM_DQ,
    output wire        SDRAM_DQML,
    output wire        SDRAM_DQMH,
    output wire        SDRAM_nWE,
    output wire        SDRAM_nCAS,
    output wire        SDRAM_nRAS,
    output wire        SDRAM_nCS,
    output wire [1:0]  SDRAM_BA,
    output wire        SDRAM_CKE,

    // video (en clk_pix, un punto cada dos ciclos: 12,5 MHz)
    output wire        ce_pix,
    output wire [7:0]  vid_r,
    output wire [7:0]  vid_g,
    output wire [7:0]  vid_b,
    output wire        vid_hs,
    output wire        vid_hs_cs,
    output wire        vid_vs,
    output wire        vid_hb,
    output wire        vid_vb,

    // video de 31 kHz propio (fp1100_vga, en clk_vga, un punto por ciclo)
    output wire [7:0]  vga_r,
    output wire [7:0]  vga_g,
    output wire [7:0]  vga_b,
    output wire        vga_hs,
    output wire        vga_vs,
    output wire        vga_hb,
    output wire        vga_vb,

    // teclado
    input  wire [10:0] ps2_key,
    input  wire        kbd_soltar,      // soltar todas las teclas (OSD)
    output wire        kbd_alguna,      // hay alguna tecla pulsada (LED)
    output wire        led_shift,
    output wire        led_caps,

    // sonido y cinta
    output wire        beeper,
    output wire        cmt_motor,      // rele del casete (PC5)
    output wire        cmt_mic,        // audio FSK hacia la cinta (SO)
    input  wire        ear_in,         // audio de entrada externo, en digital
    input  wire        tape_externa,   // 1: EAR = ear_in; 0: el reproductor
    input  wire        tape_cargada,   // pulso: fin de la descarga del WAV
    input  wire [23:0] tape_tamano,
    input  wire        tape_rebobinar,
    input  wire        tape_pausa,
    output wire        tape_lista,
    output wire        tape_play,
    output wire        cmt_rec,        // PA7: grabando
    output wire        ear_mon,        // EAR que esta viendo el circuito

    // disquetera (FDC pack, imagenes EDSK)
    input  wire        fdc_enable,
    input  wire [1:0]  img_mounted,
    input  wire [31:0] img_size,
    output wire [31:0] sd_lba,
    output wire [1:0]  sd_rd,
    output wire [1:0]  sd_wr,
    input  wire        sd_ack,
    input  wire [8:0]  sd_buff_addr,
    input  wire [7:0]  sd_buff_dout,
    output wire [7:0]  sd_buff_din,
    input  wire        sd_buff_wr,
    output wire        fdc_motor,

    // depuracion
    output wire [15:0] dbg_pc,
    output wire [15:0] dbg_sub_a,
    output wire        dbg_sdram_ready,
    output wire        dbg_int_req,
    output wire        dbg_int_ack
);
    localparam [23:0] RAM_BASE  = 24'h400000;
    localparam [23:0] VRAM_BASE = 24'h600000;

    //------------------------------------------------------------------
    // Relojes
    //------------------------------------------------------------------
    reg [3:0] clkdiv = 4'd0;
    always @(posedge clk_sys) clkdiv <= clkdiv + 4'd1;

    wire cpu_stall;
    wire cen_p = (clkdiv[2:0] == 3'd0) & ~cpu_stall;
    wire cen_n = (clkdiv[2:0] == 3'd4) & ~cpu_stall;

    wire cp2n = (clkdiv == 4'd3);
    wire cp1p = (clkdiv == 4'd7);
    wire cp1n = (clkdiv == 4'd11);
    wire cp2p = (clkdiv == 4'd15);

    wire ce_dot = clkdiv[0];            // 16 MHz: el CRTC

    //------------------------------------------------------------------
    // Z80
    //------------------------------------------------------------------
    wire [15:0] cpu_addr;
    wire [7:0]  cpu_dout;
    reg  [7:0]  cpu_din;
    wire        mreq_n, iorq_n, rd_n, wr_n, m1_n, rfsh_n;
    wire        int_n;

    assign dbg_pc      = cpu_addr;
    assign dbg_int_req = ~int_n;
    assign dbg_int_ack = ~iorq_n & ~m1_n;

    T80pa cpu (
        .RESET_n(~reset), .CLK(clk_sys), .CEN_p(cen_p), .CEN_n(cen_n),
        .WAIT_n(1'b1), .INT_n(int_n), .NMI_n(1'b1), .BUSRQ_n(1'b1),
        .M1_n(m1_n), .MREQ_n(mreq_n), .IORQ_n(iorq_n), .RD_n(rd_n),
        .WR_n(wr_n), .RFSH_n(rfsh_n), .HALT_n(), .BUSAK_n(),
        .A(cpu_addr), .DI(cpu_din), .DO(cpu_dout)
    );

    wire mem_cyc = ~mreq_n & rfsh_n;
    wire mem_rd  = mem_cyc & ~rd_n;
    wire mem_wr  = mem_cyc & ~wr_n;

    //------------------------------------------------------------------
    // Placa principal: E/S, interrupciones y latches
    //------------------------------------------------------------------
    wire [7:0] io_dout;
    wire       io_dout_oe;
    wire       rom_sel, slot_sel;
    wire [3:0] slot_exp0, slot_exp1;
    wire       io_rd_lvl, io_wr_lvl, io_wr_pulse;
    wire [7:0] m2s_data, s2m_data;
    wire       m2s_rd, s2m_wr, int2, ints;
    wire       inta, intb;

    fp1100_main main (
        .clk(clk_sys), .reset(reset),
        .addr(cpu_addr), .din(cpu_dout), .dout(io_dout), .dout_oe(io_dout_oe),
        .iorq_n(iorq_n), .m1_n(m1_n), .rd_n(rd_n), .wr_n(wr_n), .int_n(int_n),
        .rom_sel(rom_sel), .slot_sel(slot_sel),
        .slot_exp0(slot_exp0), .slot_exp1(slot_exp1),
        .io_rd_lvl(io_rd_lvl), .io_wr_lvl(io_wr_lvl), .io_wr_pulse(io_wr_pulse),
        .m2s_data(m2s_data), .int2(int2), .m2s_rd(m2s_rd),
        .s2m_data(s2m_data), .ints(ints),
        .slot_int({2'b00, intb, inta})
    );

    //------------------------------------------------------------------
    // FDC pack en el slot 1
    //------------------------------------------------------------------
    wire [7:0] fdc_dout;
    wire       fdc_dout_oe;

    fp1100_fdc fdc (
        .clk(clk_sys), .reset(reset), .enable(fdc_enable),
        .slot_sel(slot_sel), .slot_exp0(slot_exp0),
        .addr(cpu_addr), .din(cpu_dout), .dout(fdc_dout), .dout_oe(fdc_dout_oe),
        .io_rd(io_rd_lvl), .io_wr(io_wr_lvl), .io_wr_p(io_wr_pulse),
        .inta(inta), .intb(intb),
        .img_mounted(img_mounted), .img_size(img_size),
        .sd_lba(sd_lba), .sd_rd(sd_rd), .sd_wr(sd_wr), .sd_ack(sd_ack),
        .sd_buff_addr(sd_buff_addr), .sd_buff_dout(sd_buff_dout),
        .sd_buff_din(sd_buff_din), .sd_buff_wr(sd_buff_wr),
        .motor_led(fdc_motor)
    );

    //------------------------------------------------------------------
    // Placa sub
    //------------------------------------------------------------------
    wire [3:0]  kbd_row;
    wire [7:0]  kbd_col;
    wire        crtc_cs, crtc_a0, crtc_wr;
    wire [7:0]  crtc_din, crtc_dout;
    wire [7:0]  pa, color_reg;
    wire        hsync;
    wire        vf_rd, vf_par, vf_ack_sub, vr_req, vr_wr, vr_w16, vr_ack;
    wire [13:0] vf_addr;
    wire [31:0] vf_q_sub;
    wire [15:0] vr_addr, vr_din;
    wire [7:0]  vr_dout;
    wire        cmt_so, cmt_si, cmt_sck;

    fp1100_sub sub (
        .clk(clk_sys), .reset(reset),
        .cp1p(cp1p), .cp1n(cp1n), .cp2p(cp2p), .cp2n(cp2n),
        .rom1_wr(rom1_wr), .rom2_wr(rom2_wr), .cg_wr(cg_wr),
        .rom_wr_addr(rom_wr_addr), .rom_wr_data(dl_data),
        .m2s_data(m2s_data), .m2s_rd(m2s_rd),
        .s2m_data(s2m_data), .s2m_wr(s2m_wr),
        .int2(int2), .ints(ints),
        .kbd_row(kbd_row), .kbd_col(kbd_col),
        .led_shift(led_shift), .led_caps(led_caps), .beeper(beeper),
        .dip(dip),
        .crtc_cs(crtc_cs), .crtc_a0(crtc_a0), .crtc_wr(crtc_wr),
        .crtc_din(crtc_din), .crtc_dout(crtc_dout), .hsync(hsync),
        .pa(pa), .color_reg(color_reg),
        .vf_rd(vf_rd), .vf_par(vf_par), .vf_addr(vf_addr), .vf_ack(vf_ack_sub), .vf_q(vf_q_sub),
        .vr_req(vr_req), .vr_addr(vr_addr), .vr_wr(vr_wr), .vr_w16(vr_w16),
        .vr_din(vr_din), .vr_ack(vr_ack), .vr_dout(vr_dout),
        .cmt_so(cmt_so), .cmt_si(cmt_si), .cmt_sck(cmt_sck), .cmt_motor(cmt_motor),
        .dbg_a(dbg_sub_a), .dbg_m1()
    );

    //------------------------------------------------------------------
    // Casete: circuito de la placa y reproductor de WAV
    //------------------------------------------------------------------
    wire ear_tape, ear;
    wire [23:0] ta_addr;
    wire        ta_rd, ta_ack;
    wire [15:0] ta_dout;

    assign ear = tape_externa ? ear_in : ear_tape;
    assign cmt_rec = pa[7];
    assign ear_mon = ear;

    fp1100_cmt cmt (
        .clk(clk_sys), .reset(reset),
        .pa6(pa[6]), .pa7(pa[7]), .so(cmt_so), .ear(ear),
        .sck(cmt_sck), .si(cmt_si), .mic(cmt_mic), .ck76(), .dbg_clock()
    );

    fp1100_tape #(.CLK_HZ(CLK_HZ)) tape (
        .clk(clk_sys), .reset(reset),
        .cargada(tape_cargada), .tamano(tape_tamano), .rebobinar(tape_rebobinar),
        .motor(cmt_motor), .pausa(tape_pausa),
        .a_addr(ta_addr), .a_rd(ta_rd), .a_dout(ta_dout), .a_ack(ta_ack),
        .ear(ear_tape), .reproduciendo(tape_play), .lista(tape_lista)
    );

    // pulso de 1 ms para el teclado (suelta la ultima tecla si no se repite)
    reg [15:0] ms_cnt;
    reg        tic_ms;
    always @(posedge clk_sys) begin
        tic_ms <= 1'b0;
        if (ms_cnt == CLK_HZ / 1000 - 1) begin ms_cnt <= 16'd0; tic_ms <= 1'b1; end
        else ms_cnt <= ms_cnt + 16'd1;
    end

    fp1100_kbd kbd (
        .clk(clk_sys), .reset(reset), .ps2_key(ps2_key), .soltar(kbd_soltar), .tic_ms(tic_ms),
        .alguna(kbd_alguna),
        .row(kbd_row), .col(kbd_col)
    );

    //------------------------------------------------------------------
    // Video: el CRTC lleva la temporizacion en clk_sys; fp1100_display
    // dibuja en clk_pix (ver su cabecera)
    //------------------------------------------------------------------
    wire        linea_tgl, lin_visible, lin_vsync, lin_col40, lin_display_on, lin_screen1, lin_cursor_on;
    wire [13:0] lin_ma, lin_cursor;
    wire [4:0]  lin_ra;
    wire [7:0]  lin_chars;
    wire [8:0]  lin_n;

    fp1100_video crtc (
        .clk(clk_sys), .reset(reset), .ce_dot(ce_dot),
        .crtc_cs(crtc_cs), .crtc_a0(crtc_a0), .crtc_wr(crtc_wr),
        .crtc_din(crtc_din), .crtc_dout(crtc_dout),
        .pa(pa),
        .hsync(hsync), .vblank(),
        .linea_tgl(linea_tgl), .lin_ma(lin_ma), .lin_ra(lin_ra), .lin_n(lin_n),
        .lin_visible(lin_visible), .lin_vsync(lin_vsync), .lin_chars(lin_chars),
        .lin_col40(lin_col40), .lin_display_on(lin_display_on), .lin_screen1(lin_screen1),
        .lin_cursor(lin_cursor), .lin_cursor_on(lin_cursor_on)
    );

    // Lector de linea: la VRAM del sub (block RAM) o la de la SDRAM
    wire        vf_ack;
    wire [31:0] vf_q;
    wire        sd_v_ack;
    wire [31:0] sd_v_dout;
    wire [7:0]  lb_addr;
    wire [23:0] lb_q;
    wire [9:0]  lb31_addr;
    wire [23:0] lb31_q;
`ifdef VRAM_SDRAM
    assign vf_ack = sd_v_ack;
    assign vf_q   = sd_v_dout;
`else
    assign vf_ack = vf_ack_sub;
    assign vf_q   = vf_q_sub;
`endif

    fp1100_vfetch vfetch (
        .clk(clk_sys), .reset(reset),
        .linea_tgl(linea_tgl), .lin_ma(lin_ma), .lin_ra(lin_ra), .lin_n(lin_n),
        .lin_visible(lin_visible), .lin_display_on(lin_display_on), .lin_chars(lin_chars),
        .lin_screen1(lin_screen1), .vga400(vga400),
        .rd(vf_rd), .par(vf_par), .addr(vf_addr), .ack(vf_ack), .q(vf_q),
        .clk_pix(clk_pix), .lb_addr(lb_addr), .lb_q(lb_q),
        .clk_vga(clk_vga), .lb31_addr(lb31_addr), .lb31_q(lb31_q)
    );

    fp1100_display display (
        .clk_pix(clk_pix), .reset(reset), .ce_pix(ce_pix),
        .vga400(vga400 & ~vga525), .modo31(vid_31k),
        .h_off(h_off), .v_off(v_off), .tv15(vid_15k | vga525),
        .linea_tgl(linea_tgl), .lin_ma(lin_ma), .lin_ra(lin_ra),
        .lin_visible(lin_visible), .lin_vsync(lin_vsync), .lin_chars(lin_chars),
        .lin_col40(lin_col40), .lin_display_on(lin_display_on), .lin_screen1(lin_screen1),
        .lin_cursor(lin_cursor), .lin_cursor_on(lin_cursor_on),
        .libre(vid_libre),
        .pa(pa), .color_reg(color_reg),
        .lb_addr(lb_addr), .lb_q(lb_q),
        .R(vid_r), .G(vid_g), .B(vid_b),
        .hsync(vid_hs), .hsync_cs(vid_hs_cs), .vsync(vid_vs),
        .hblank(vid_hb), .vblank(vid_vb)
    );

    // 31 kHz propio: VGA 640x480 de 525 lineas (macro VGA_525 del top)
    fp1100_vga vga (
        .clk(clk_vga), .reset(reset),
        .h_off(h_off), .v_off(v_off), .vga400(vga400), .scanlines(vga_scanlines),
        .linea_tgl(linea_tgl), .lin_n(lin_n), .lin_ma(lin_ma), .lin_ra(lin_ra),
        .lin_visible(lin_visible), .lin_chars(lin_chars), .lin_col40(lin_col40),
        .lin_display_on(lin_display_on), .lin_screen1(lin_screen1),
        .lin_cursor(lin_cursor), .lin_cursor_on(lin_cursor_on),
        .pa(pa), .color_reg(color_reg),
        .lb_addr(lb31_addr), .lb_q(lb31_q),
        .R(vga_r), .G(vga_g), .B(vga_b),
        .hsync(vga_hs), .vsync(vga_vs), .hblank(vga_hb), .vblank(vga_vb)
    );

    //------------------------------------------------------------------
    // SDRAM: ROM y RAM del Z80, y la carga desde data_io
    //------------------------------------------------------------------
    reg  [23:0] b_addr;
    reg  [7:0]  b_din;
    reg  [15:0] b_din16;
    reg         b_rd, b_wr, b_w16;
    wire [7:0]  b_dout;
    wire        b_ack, b_free;

    fp1100_sdram #(.CLK_HZ(CLK_HZ)) sdram (
        .clk(clk_sys), .reset(mem_reset),
        .SDRAM_A(SDRAM_A), .SDRAM_DQ(SDRAM_DQ),
        .SDRAM_DQML(SDRAM_DQML), .SDRAM_DQMH(SDRAM_DQMH),
        .SDRAM_nWE(SDRAM_nWE), .SDRAM_nCAS(SDRAM_nCAS),
        .SDRAM_nRAS(SDRAM_nRAS), .SDRAM_nCS(SDRAM_nCS),
        .SDRAM_BA(SDRAM_BA), .SDRAM_CKE(SDRAM_CKE),
        .a_addr(ta_addr), .a_rd(ta_rd), .a_dout(ta_dout), .a_ack(ta_ack),
`ifdef VRAM_SDRAM
        .v_addr(VRAM_BASE + {8'd0, vf_addr, 2'b00}), .v_rd(vf_rd), .v_par(vf_par),
`else
        .v_addr(24'd0), .v_rd(1'b0), .v_par(1'b0),
`endif
        .v_dout(sd_v_dout), .v_ack(sd_v_ack),
        .b_addr(b_addr), .b_din(b_din), .b_rd(b_rd), .b_wr(b_wr),
        .b_w16(b_w16), .b_din16(b_din16),
        .b_dout(b_dout), .b_ack(b_ack), .b_free(b_free),
        .antes(sdram_antes)
    );
    assign dbg_sdram_ready = b_free;

    // Mapa del Z80: con rom_sel = 0 las lecturas de 0000-8FFF van a la ROM;
    // las escrituras van siempre a la RAM.
    wire rom_rd = mem_rd & ~rom_sel & (cpu_addr < 16'h9000);
    wire [23:0] cpu_sd_addr = rom_rd ? {8'd0, cpu_addr} : RAM_BASE + {8'd0, cpu_addr};
    wire use_sdram = mem_rd | mem_wr;

    // Arbitro del puerto B: la carga primero, luego el sub (VRAM en SDRAM) y
    // luego el Z80 (como en el NewBrain: un dueño a la vez, que se suelta con
    // b_ack)
    localparam [1:0] OWN_NADIE = 2'd0, OWN_CPU = 2'd1, OWN_CARGA = 2'd2, OWN_SUB = 2'd3;
    reg  [1:0]  b_own;
    reg         dl_pend;
    reg  [23:0] dl_a;
    reg  [7:0]  dl_d;
    reg  [7:0]  mem_data;
    reg         mem_done;

    wire b_puede = b_free && (b_own == OWN_NADIE);
    assign sdram_free = b_puede && !dl_pend && !dl_wr;
    // El Z80 solo se para cuando de verdad hace falta. Antes se paraba en
    // cuanto empezaba cada acceso a memoria y cada uno le costaba un estado
    // T de mas (~20% del tiempo parado): el Z80 iba bastante mas lento que
    // el real, que lee la RAM sin esperas. VEGCRA (GAMDEMO2) lee la
    // respuesta del sub tras un bucle de espera fijo y, con el Z80 lento,
    // llegaba justo cuando el sub ya habia puesto FFh encima, que el juego
    // toma como derecha y disparo a la vez (doc §30).
    //
    // MREQ baja en el cen_n de T1. Contando cen desde ahi (pasos_mem): 1 =
    // cen_p de T2, 2 = cen_n de T2, 3 = cen_p de T3, cuando el T80 toma el
    // opcode (el dato de las lecturas lo registra en el cen_n de T3, mas
    // tarde). Las lecturas se paran antes de ese cen_p si la SDRAM no ha
    // contestado; como tarda ~10 ciclos de los 12 que hay, casi nunca.
    // Las escrituras se dan por hechas en cuanto se le pasan al
    // controlador (este las guarda y las hace en orden); solo se paran si
    // no se han podido pasar antes de ese mismo cen, para no perderlas.
    reg [2:0] pasos_mem;
    always @(posedge clk_sys)
        if (!mem_cyc) pasos_mem <= 3'd0;
        else if ((cen_p | cen_n) && pasos_mem != 3'd7) pasos_mem <= pasos_mem + 3'd1;
    reg cpu_wr_pend;          // la peticion en curso del Z80 es una escritura
`ifdef Z80_ESPERA_CLASICA
    // Para aislar problemas: la parada de siempre (desde el principio del
    // ciclo) y las escrituras sin adelantar. El Z80 va un 20% mas lento.
    assign cpu_stall  = use_sdram & ~mem_done;
`else
    assign cpu_stall  = use_sdram & ~mem_done & (pasos_mem >= 3'd2);
`endif

`ifdef VRAM_SDRAM
    wire sub_pide = vr_req;
`else
    wire sub_pide = 1'b0;
`endif
    assign vr_ack  = b_ack & (b_own == OWN_SUB);
    assign vr_dout = b_dout;

    always @(posedge clk_sys) begin
        b_rd  <= 1'b0;
        b_wr  <= 1'b0;
        b_w16 <= 1'b0;

        if (dl_wr) begin
            dl_pend <= 1'b1;
            dl_a    <= dl_addr;
            dl_d    <= dl_data;
        end

        if (b_ack) begin
            if (b_own == OWN_CPU && !cpu_wr_pend) begin
                mem_data <= b_dout;
                mem_done <= 1'b1;
            end
            cpu_wr_pend <= 1'b0;
            b_own <= OWN_NADIE;
        end

        if (b_puede) begin
            if (dl_pend) begin
                b_addr  <= dl_a;
                b_din   <= dl_d;
                b_wr    <= 1'b1;
                b_own   <= OWN_CARGA;
                dl_pend <= dl_wr;
                if (dl_wr) begin dl_a <= dl_addr; dl_d <= dl_data; end
            end else if (sub_pide) begin
                b_addr  <= VRAM_BASE + {8'd0, vr_addr};
                b_din   <= vr_din[7:0];
                b_din16 <= vr_din;
                b_w16   <= vr_w16;
                b_rd    <= ~vr_wr;
                b_wr    <= vr_wr;
                b_own   <= OWN_SUB;
            end else if (!reset && use_sdram && !mem_done) begin
                b_addr <= cpu_sd_addr;
                b_din  <= cpu_dout;
                b_rd   <= mem_rd;
                b_wr   <= mem_wr;
                b_own  <= OWN_CPU;
                // escritura: hecha en cuanto el controlador la tiene
`ifndef Z80_ESPERA_CLASICA
                cpu_wr_pend <= mem_wr;
                if (mem_wr) mem_done <= 1'b1;
`endif
            end
        end

        if (reset || !mem_cyc) mem_done <= 1'b0;

        if (mem_reset) begin
            b_own   <= OWN_NADIE;
            dl_pend <= 1'b0;
            cpu_wr_pend <= 1'b0;
        end
    end

    //------------------------------------------------------------------
    // Lectura hacia el Z80
    //------------------------------------------------------------------
    always @* begin
        if (~iorq_n)         cpu_din = io_dout_oe  ? io_dout  :
                                       fdc_dout_oe ? fdc_dout : 8'hFF;
        else if (use_sdram)  cpu_din = mem_data;
        else                 cpu_din = 8'hFF;
    end

endmodule

`default_nettype wire
