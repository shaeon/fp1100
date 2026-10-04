//============================================================================
// Banco de pruebas de la maquina completa (Verilator --binary --timing)
//
// Carga FP1100.ROM por el mismo camino que data_io, arranca, y cada cierto
// tiempo vuelca la trama visible a un PPM (trama_N.ppm). Traza ademas lo
// que pasa por los latches main<->sub y los registros del CRTC.
//
//   +CICLOS=N   ciclos de sistema a simular (32 MHz)
//   +ROM=fich   fichero de ROM (por defecto ../roms/fp1100.rom)
//============================================================================
`timescale 1ns/1ps

module tb_fp1100;
    reg clk = 0;
    always #15.625 clk = ~clk;          // 32 MHz
    reg clk_pix = 0;
    always #20 clk_pix = ~clk_pix;      // 25 MHz

    reg reset = 1, mem_reset = 1;

    // +VGAHEX: la salida pasa por mist_video (scandoubler, como en el top)
    // y se vuelca a vga.hex para analiza_sd.py; +VGADESDE=ms (def. 0): no
    // empieza hasta entonces; +VGATRAMAS=n (def. 3); +SD_OFF: 15 kHz
    bit tb_sd_off = 0, vgahex = 0;
    integer vga_desde_ms = 0, vga_tramas = 3;
    initial begin
        tb_sd_off = $test$plusargs("SD_OFF");
        vgahex = $test$plusargs("VGAHEX");
        if (!$value$plusargs("VGADESDE=%d", vga_desde_ms)) vga_desde_ms = 0;
        if (!$value$plusargs("VGATRAMAS=%d", vga_tramas)) vga_tramas = 3;
    end
    wire signed [5:0] tb_hoff = tb_sd_off ? -6'sd20 : 6'sd0;   // los del top con H centre 0

    // SDRAM
    wire [12:0] SDRAM_A;
    wire [15:0] SDRAM_DQ;
    wire SDRAM_DQML, SDRAM_DQMH, SDRAM_nWE, SDRAM_nCAS, SDRAM_nRAS, SDRAM_nCS, SDRAM_CKE;
    wire [1:0] SDRAM_BA;

    // carga
    reg  [23:0] dl_addr = 0;
    reg  [7:0]  dl_data = 0;
    reg         dl_wr = 0, rom1_wr = 0, rom2_wr = 0, cg_wr = 0;
    reg  [11:0] rom_wr_addr = 0;
    wire        sdram_free;

    wire        ce_pix;
    wire [7:0]  R, G, B;
    wire        hs, hs_cs, vs, hb, vb;
    wire        beeper, cmt_motor, cmt_mic, led_shift, led_caps, tape_lista, tape_play, cmt_rec;
    reg         ear_in = 0, tape_externa = 1, tape_cargada = 0;
    reg  [23:0] tape_tamano = 0;
    wire [15:0] dbg_pc, dbg_sub_a;
    wire        dbg_sdram_ready, dbg_int_req, dbg_int_ack;
    reg  [10:0] ps2_key = 0;

    // disquetera
    reg  [1:0]  img_mounted = 2'b00;
    reg  [31:0] img_size = 0;
    wire [31:0] sd_lba;
    wire [1:0]  sd_rd, sd_wr;
    reg         sd_ack = 0;
    reg  [8:0]  sd_buff_addr = 0;
    reg  [7:0]  sd_buff_dout = 0;
    wire [7:0]  sd_buff_din;
    reg         sd_buff_wr = 0;
    wire        fdc_motor;

    fp1100 dut (
        .clk_sys(clk), .clk_pix(clk_pix), .clk_vga(clk_pix), .vga525(1'b0), .vga_scanlines(2'b00),
        .vga_r(), .vga_g(), .vga_b(), .vga_hs(), .vga_vs(), .vga_hb(), .vga_vb(),
        .h_off(tb_hoff), .v_off(5'sd0), .vid_15k(tb_sd_off), .reset(reset), .sdram_antes(captura_antes), .vga400(vga400_tb), .vid_31k(), .mem_reset(mem_reset),
        .dip(dip_tb), .vid_libre(1'b0),
        .dl_addr(dl_addr), .dl_data(dl_data), .dl_wr(dl_wr), .sdram_free(sdram_free),
        .rom1_wr(rom1_wr), .rom2_wr(rom2_wr), .cg_wr(cg_wr), .rom_wr_addr(rom_wr_addr),
        .SDRAM_A(SDRAM_A), .SDRAM_DQ(SDRAM_DQ), .SDRAM_DQML(SDRAM_DQML), .SDRAM_DQMH(SDRAM_DQMH),
        .SDRAM_nWE(SDRAM_nWE), .SDRAM_nCAS(SDRAM_nCAS), .SDRAM_nRAS(SDRAM_nRAS),
        .SDRAM_nCS(SDRAM_nCS), .SDRAM_BA(SDRAM_BA), .SDRAM_CKE(SDRAM_CKE),
        .ce_pix(ce_pix), .vid_r(R), .vid_g(G), .vid_b(B),
        .vid_hs(hs), .vid_hs_cs(hs_cs), .vid_vs(vs), .vid_hb(hb), .vid_vb(vb),
        .ps2_key(ps2_key), .kbd_soltar(1'b0), .kbd_alguna(), .led_shift(led_shift), .led_caps(led_caps),
        .beeper(beeper), .cmt_motor(cmt_motor), .cmt_mic(cmt_mic),
        .ear_in(ear_in), .tape_externa(tape_externa),
        .tape_cargada(tape_cargada), .tape_tamano(tape_tamano),
        .tape_rebobinar(1'b0), .tape_pausa(1'b0),
        .tape_lista(tape_lista), .tape_play(tape_play),
        .cmt_rec(cmt_rec), .ear_mon(),
        .fdc_enable(1'b1),
        .img_mounted(img_mounted), .img_size(img_size),
        .sd_lba(sd_lba), .sd_rd(sd_rd), .sd_wr(sd_wr), .sd_ack(sd_ack),
        .sd_buff_addr(sd_buff_addr), .sd_buff_dout(sd_buff_dout),
        .sd_buff_din(sd_buff_din), .sd_buff_wr(sd_buff_wr),
        .fdc_motor(fdc_motor),
        .dbg_pc(dbg_pc), .dbg_sub_a(dbg_sub_a), .dbg_sdram_ready(dbg_sdram_ready),
        .dbg_int_req(dbg_int_req), .dbg_int_ack(dbg_int_ack)
    );

    sdram_model sdram (
        .clk(clk), .A(SDRAM_A), .DQ(SDRAM_DQ), .DQML(SDRAM_DQML), .DQMH(SDRAM_DQMH),
        .nWE(SDRAM_nWE), .nCAS(SDRAM_nCAS), .nRAS(SDRAM_nRAS), .nCS(SDRAM_nCS),
        .BA(SDRAM_BA), .CKE(SDRAM_CKE)
    );

    //------------------------------------------------------------------
    // Carga de la ROM (48K): igual que data_io, un byte cuando sdram_free
    //------------------------------------------------------------------
    reg [7:0] rom [0:49151];
    integer i, fd, n;
    string romfile;
    longint ciclos, t0, t1;

    task cargar;
        begin
            for (i = 0; i < 49152; i = i + 1) begin
                @(posedge clk);
                if (i < 'h9000) begin
                    while (!sdram_free) @(posedge clk);
                    dl_addr <= i; dl_data <= rom[i]; dl_wr <= 1;
                    @(posedge clk); dl_wr <= 0;
                end else begin
                    rom_wr_addr <= i[11:0]; dl_data <= rom[i];
                    rom1_wr <= (i[15:12] == 4'h9);
                    rom2_wr <= (i[15:12] == 4'hA);
                    cg_wr   <= (i[15:12] == 4'hB);
                    @(posedge clk);
                    rom1_wr <= 0; rom2_wr <= 0; cg_wr <= 0;
                end
            end
        end
    endtask

    //------------------------------------------------------------------
    // Modelo de la SD: sirve la imagen EDSK en bloques de 512 bytes por el
    // protocolo de user_io (sd_rd -> sd_ack + rafaga de sd_buff_wr)
    //------------------------------------------------------------------
    reg [7:0] dsk [0:1048575];
    integer dsk_bytes = 0;
    reg sd_es_lectura = 0;
    string dskfile;
    integer k;
    always @(posedge clk) begin
        if ((sd_rd[0] | sd_wr[0]) && !sd_ack) begin
            sd_es_lectura = sd_rd[0];
            sd_ack <= 1;
            repeat (20) @(posedge clk);
            for (k = 0; k < 512; k = k + 1) begin
                sd_buff_addr <= k;
                sd_buff_dout <= dsk[sd_lba * 512 + k];
                sd_buff_wr   <= sd_es_lectura;
                @(posedge clk);
                sd_buff_wr <= 0;
                if (!sd_es_lectura) dsk[sd_lba * 512 + k] = sd_buff_din;
                repeat (3) @(posedge clk);
            end
            repeat (20) @(posedge clk);
            sd_ack <= 0;
            $display("%0t SD %s lba %0d", $time, sd_es_lectura ? "lee" : "escribe", sd_lba);
            @(posedge clk);
        end
    end

    // +DSKOUT=fichero: al acabar, guarda la imagen de disco tal como la ha
    // dejado la simulacion (con lo que se haya grabado)
    final begin : dskout
        string nomo; integer fo, j;
        if ($value$plusargs("DSKOUT=%s", nomo) && dsk_bytes > 0) begin
            fo = $fopen(nomo, "wb");
            for (j = 0; j < dsk_bytes; j = j + 1) $fwrite(fo, "%c", dsk[j]);
            $fclose(fo);
            $display("DSKOUT: %s, %0d bytes", nomo, dsk_bytes);
        end
    end

    // Trazas del FDC
    reg drq_d = 0, intb_d = 0;
    reg rd765_d = 0;
    wire rd765 = dut.main.io_rd_lvl && dut.fdc.fdc_sel && dut.fdc.a0 && (dut.cpu_addr[2:0] == 3'd5);
    wire rd765_p = ~rd765 & rd765_d;
    always @(posedge clk) rd765_d <= rd765;
    integer bytes765 = 0;
    always @(posedge clk) begin
        drq_d  <= dut.inta;
        intb_d <= dut.intb;
        if (dut.fdc.io_wr_p && dut.fdc.fdc_sel && dut.fdc.a0 && !dut.fdc.fdc765.m_status[5])
            $display("%0t 765 <- %02x", $time, dut.cpu_dout);
        if (dut.fdc.io_wr_p && dut.fdc.reg_sel && dut.cpu_addr[2:1] == 2'b01)
            $display("%0t 765 TC (bytes %0d)", $time, bytes765);
        if (dut.fdc.io_wr_p && dut.fdc.reg_sel && dut.cpu_addr[2:1] == 2'b00)
            $display("%0t 765 motor", $time);
        if (dut.inta & ~drq_d) bytes765 = bytes765 + 1;
        
        if (rd765_p) $display("%0t 765 -> %02x (msr %02x listo %b img_ready %b)", $time, dut.fdc.dout765, dut.fdc.fdc765.m_status, dut.fdc.listo, {dut.fdc.fdc765.fdc.image_ready[0], dut.fdc.fdc765.fdc.pcn[0], dut.fdc.fdc765.fdc.ncn[0], dut.fdc.fdc765.fdc.image_scan_state[0]});
        if (dut.intb & ~intb_d) $display("%0t 765 INT", $time);
        if (dut.main.io_wr_p && dut.main.sel_ff00) $display("%0t slot_exp[%0d] = %0d", $time, dut.slot_sel, dut.cpu_dout[3:0]);
    end

    //------------------------------------------------------------------
    // Trazas
    //------------------------------------------------------------------
    always @(posedge clk) begin
        if (dut.main.io_wr_p && dut.main.sel_ffc0)
            $display("%0t main->sub %02x", $time, dut.cpu_dout);
        if (dut.main.io_wr_p && dut.main.sel_ff80)
            $display("%0t mascara %02x", $time, dut.cpu_dout);
        if (dut.main.io_wr_p && dut.main.sel_ffa0)
            $display("%0t bancos %02x", $time, dut.cpu_dout);
        if (dut.sub.cpu.core.intp[3] != intp2_d) $display("%0t INTF2 = %b (sub PC %04x)", $time, dut.sub.cpu.core.intp[3], dut.sub.cpu.core_a);
        intp2_d <= dut.sub.cpu.core.intp[3];
        if (dut.sub.pc_o[3] != dut.main.ints_d) $display("%0t PC3 = %b", $time, dut.sub.pc_o[3]);
        if (dut.sub.s2m_wr)
            $display("%0t sub->main %02x", $time, dut.sub.s2m_data);
        // Lecturas del Z80 del latch sub->main (IN de FFC0..), con +LEELATCH
        in_d <= ~dut.iorq_n & ~dut.rd_n & dut.m1_n;
        if (leelatch && (~dut.iorq_n & ~dut.rd_n & dut.m1_n) && !in_d && dut.cpu_addr[15:7] == 9'h1FF)
            $display("%0t Z80 lee latch %02x pc %04x", $time, dut.io_dout, dbg_pc);
        if (dut.sub.crtc_wr && dut.sub.crtc_a0)
            $display("%0t crtc R%0d = %0d", $time, dut.crtc.sel, dut.sub.crtc_din);
        if (dut.main.int_ack_p)
            $display("%0t Z80 int ack vector_c %02x pend %b mask %02x ints %b", $time, dut.main.vector_c, dut.main.pendiente, dut.main.mask, dut.sub.ints);
        if (vramlog && dut.sub.vram_cs && dut.sub.rd_n && !dut.sub.rd_n_d)
            $display("%0t VRAM lee %04x = %02x (sub PC %04x)", $time, dut.sub.a, dut.sub.db_i, dut.sub.cpu.core_a);
        if (vramlog && dut.sub.wr_p && dut.sub.vram_cs && $time < 64'd100000000000)
            $display("%0t VRAM escribe %04x = %02x", $time, dut.sub.a, dut.sub.db_o);
        if (dut.sub.wr_p && dut.sub.vram_cs) vram_esc[dut.sub.a_vram[15:14]] = vram_esc[dut.sub.a_vram[15:14]] + 1;
        if (dut.sub.wr_p && dut.sub.color_sel)
            $display("%0t color %02x", $time, dut.sub.db_o);
    end

    reg intp2_d = 0;
    reg [7:0] pa_d;
    always @(posedge clk) begin
        pa_d <= dut.sub.pa_o;
        if (pa_d != dut.sub.pa_o) $display("%0t PA = %02x", $time, dut.sub.pa_o);
    end

    //------------------------------------------------------------------
    // Volcado de trama: pixeles con ce_pix fuera de blanking. Se numeran
    // las lineas por hsync y los pixeles por hblank.
    //------------------------------------------------------------------
    reg [2:0] trama [0:399][0:639];
    integer px = 0, ln = 0, vueltas = 0, nvol = 0;
    reg hb_d = 1, vb_d = 1, hs_d = 0;
    reg [2:0] pixmax [0:399];

    task volcar;
        integer x, y, f;
        string nombre;
        begin
            $sformat(nombre, "trama_%0d.ppm", nvol);
            f = $fopen(nombre, "w");
            $fwrite(f, "P3\n640 400\n1\n");
            for (y = 0; y < 400; y = y + 1) begin
                for (x = 0; x < 640; x = x + 1)
                    $fwrite(f, "%0d %0d %0d ", trama[y][x][1], trama[y][x][2], trama[y][x][0]);
                $fwrite(f, "\n");
            end
            $fclose(f);
            $display("%0t volcada %s (lineas visibles %0d)", $time, nombre, ln);
            nvol = nvol + 1;
        end
    endtask

    always @(posedge clk_pix) if (ce_pix) begin
        hb_d <= hb; vb_d <= vb; hs_d <= hs;
        if (hs & ~hs_d) begin
            if (~vb) ln <= ln + 1;
            px <= 0;
        end
        if (vb & ~vb_d) begin
            if (ln > 0) begin
                if (vueltas % 60 == 30) volcar();
                vueltas = vueltas + 1;
            end
            ln <= 0;
        end
        if (~hb & ~vb) begin
            if (px < 640 && ln < 400) trama[ln][px] <= {G[7], R[7], B[7]};
            px <= px + 1;
        end
    end

    //------------------------------------------------------------------
    // mist_video y volcado VGA (+VGAHEX), igual que en tb_sd
    //------------------------------------------------------------------
    wire [5:0] VGA_R, VGA_G, VGA_B;
    wire VGA_HS, VGA_VS, VGA_HB, VGA_VB, VGA_DE;
    mist_video #(.COLOR_DEPTH(8), .SD_HCNT_WIDTH(11), .USE_BLANKS(1'b1), .OSD_COLOR(3'b001),
                 .OUT_COLOR_DEPTH(6), .BIG_OSD(1'b0)) mv (
        .clk_sys(clk_pix), .SPI_SCK(1'b0), .SPI_SS3(1'b1), .SPI_DI(1'b0),
        .scanlines(2'b00), .ce_divider(3'd1),
        .scandoubler_disable(tb_sd_off), .no_csync(1'b1), .ypbpr(1'b0),
        .rotate(2'b00), .blend(1'b0),
        .R(R), .G(G), .B(B), .HBlank(hb), .VBlank(vb),
        .HSync(~hs), .VSync(~vs), .osd_enable(),
        .VGA_R(VGA_R), .VGA_G(VGA_G), .VGA_B(VGA_B),
        .VGA_VS(VGA_VS), .VGA_HS(VGA_HS), .VGA_HB(VGA_HB), .VGA_VB(VGA_VB), .VGA_DE(VGA_DE)
    );
    function automatic [7:0] digito(input [4:0] v);
        digito = (v < 10) ? 8'd48 + {3'd0, v} : 8'd87 + {3'd0, v};
    endfunction
    integer vfo = 0, vnvs = 0, vnvs0 = -1;
    reg vvhs_d = 1, vvvs_d = 1;
    bit vvolcando = 0;
    always @(posedge clk_pix) if (vgahex) begin
        vvhs_d <= VGA_HS; vvvs_d <= VGA_VS;
        if (vvvs_d & ~VGA_VS) begin
            vnvs = vnvs + 1;
            if (vnvs0 < 0 && $time >= longint'(vga_desde_ms) * 1000000) begin
                vnvs0 = vnvs; vfo = $fopen("vga.hex", "w"); vvolcando = 1;
                $display("%0t VGA: volcando %0d tramas a vga.hex", $time, vga_tramas);
            end
            if (vvolcando) begin
                if (vnvs > vnvs0 + vga_tramas) begin vvolcando = 0; $fclose(vfo); $display("%0t VGA: vga.hex hecho", $time); end
                else $fwrite(vfo, "#trama\n");
            end
        end
        if (vvolcando) begin
            if (vvhs_d & ~VGA_HS) $fwrite(vfo, "\n%s", VGA_VS ? "-" : "S");
            $fwrite(vfo, "%c", digito({~VGA_HS, VGA_DE, VGA_G[5], VGA_R[5], VGA_B[5]}));
        end
    end

    // Ultimos M1 del Z80 y del sub, para ver donde se quedan
    reg [15:0] z80_m1 [0:63];
    reg [15:0] sub_m1 [0:63];
    integer zi = 0, si = 0;
    reg m1z_d = 1, m1s_d = 0;
    always @(posedge clk) begin
        m1z_d <= dut.m1_n | dut.mreq_n;
        if (~(dut.m1_n | dut.mreq_n) & m1z_d) begin
            z80_m1[zi % 64] = dut.cpu_addr; zi = zi + 1;
            if ($time > t0 && $time < t1) $display("%0t Z80 M1 %04x  int_n=%b", $time, dut.cpu_addr, dut.int_n);
        end
        m1s_d <= dut.sub.m1;
        if (dut.sub.m1 & ~m1s_d) begin
            sub_m1[si % 64] = dut.sub.cpu.core_a; si = si + 1;
            if ($time > t0 && $time < t1) $display("%0t sub M1 %04x", $time, dut.sub.cpu.core_a);
        end
    end
    longint cen_tot = 0, cen_ok = 0, m1_tot = 0;
    always @(posedge clk) begin
        if (dut.clkdiv[2:0] == 3'd0 && !reset) begin cen_tot = cen_tot + 1; if (!dut.cpu_stall) cen_ok = cen_ok + 1; end
    end
    // Pulsa y suelta una tecla (modo: 0 pulsar y soltar, 1 solo pulsar, 2 solo soltar)
    integer tecla_ciclos = 1600000;
    initial begin : tms integer ms; if ($value$plusargs("TECLA_MS=%d", ms)) tecla_ciclos = ms * 32000; end
    task tecla(input [7:0] code, input integer modo);
        begin
            if (modo != 2) begin
                ps2_key <= {~ps2_key[10], 1'b1, 1'b0, code};
                repeat (tecla_ciclos) @(posedge clk);     // 50 ms (+TECLA_MS)
            end
            if (modo != 1) begin
                ps2_key <= {~ps2_key[10], 1'b0, 1'b0, code};
                repeat (tecla_ciclos) @(posedge clk);
            end
        end
    endtask
    integer teclear;
    // periodo de la hsync en ciclos de clk_pix: tiene que ser siempre 1600
    integer hs_ciclos = 0, hs_min = 99999, hs_max = 0; reg hs_prev = 0;
    always @(posedge clk_pix) begin
        hs_ciclos = hs_ciclos + 1; hs_prev <= hs;
        if (hs & ~hs_prev) begin
            if (!reset && $time > 200000000) begin
                if (hs_ciclos < hs_min) hs_min = hs_ciclos;
                if (hs_ciclos > hs_max) hs_max = hs_ciclos;
            end
            hs_ciclos = 0;
        end
    end
    task ultimos;
        integer k;
        begin
            $write("Z80 M1:");
            for (k = 0; k < 64; k = k + 1) $write(" %04x", z80_m1[(zi + k) % 64]);
            $write("\nsub M1:");
            for (k = 0; k < 64; k = k + 1) $write(" %04x", sub_m1[(si + k) % 64]);
            $write("\n");
        end
    endtask

    //------------------------------------------------------------------
    // Cinta: grabadora de MIC y reproductor hacia EAR (ida y vuelta).
    // El "tiempo de cinta" solo corre con el motor: SAVE para y arranca el
    // motor entre la cabecera y el cuerpo, y la cinta no debe llevar ese
    // hueco. En modo grabar se apuntan los flancos de MIC con ese tiempo;
    // en modo reproducir se recorren y EAR conmuta en cada uno.
    //------------------------------------------------------------------
    longint  cinta_t [0:1048575];      // instantes de cambio de MIC (tiempo de cinta, ns)
    integer  cinta_n = 0, cinta_i = 0;
    longint  t_cinta = 0;              // tiempo de cinta acumulado
    reg      mic_d = 0, motor_d = 0, modo_load = 0;
    integer  motor_vueltas = 0;
    reg      in_d = 0;
    bit      leelatch = 0;
    initial leelatch = $test$plusargs("LEELATCH");
    // +VGA400: Screen 1 en 400 lineas a 31 kHz
    bit      vga400_tb = 0;
    initial vga400_tb = $test$plusargs("VGA400");
    // +CAPTURA_ANTES: el controlador recoge el dato un paso antes (SiDi)
    bit      captura_antes = 0;
    initial captura_antes = $test$plusargs("CAPTURA_ANTES");
    reg [7:0] dip_tb = 8'hF5;   // el de la placa con el OSD por defecto
    initial if (!$value$plusargs("DIP=%h", dip_tb)) dip_tb = 8'hF5;
    // +VRAMLOG: lecturas del sub en la VRAM; y cuenta de escrituras por plano
    bit      vramlog = 0;
    integer  vram_esc [0:3];
    initial begin vram_esc[0] = 0; vram_esc[1] = 0; vram_esc[2] = 0; vram_esc[3] = 0;
                  if ($test$plusargs("VRAMLOG")) vramlog = 1; end
    final $display("VRAM escrituras: B %0d  R %0d  G %0d", vram_esc[0], vram_esc[1], vram_esc[2]);
    always @(posedge clk) begin
        mic_d <= cmt_mic; motor_d <= cmt_motor;
        if (cmt_motor) t_cinta = t_cinta + 31;      // 31,25 ns por ciclo
        if (cmt_motor & ~motor_d) begin
            motor_vueltas = motor_vueltas + 1;
            $display("%0t CINTA: motor ON (%s, flancos %0d, pos %0d)", $time, modo_load ? "reproduciendo" : "grabando", cinta_n, cinta_i);
        end
        if (~cmt_motor & motor_d) $display("%0t CINTA: motor OFF (flancos %0d, pos %0d)", $time, cinta_n, cinta_i);
        if (!modo_load && cmt_motor && cmt_mic != mic_d && cinta_n < 1048576) begin
            cinta_t[cinta_n] = t_cinta; cinta_n = cinta_n + 1;
        end
        if (modo_load && cmt_motor && cinta_i < cinta_n && t_cinta >= cinta_t[cinta_i]) begin
            ear_in <= ~ear_in; cinta_i = cinta_i + 1;
        end
    end

    // Vuelca la cinta grabada a un WAV de 8 bits y 22050 Hz (lo que se
    // le da al reproductor del core)
    task escribe_wav(input string nombre);
        integer f, k, ns; longint t; reg nivel;
        begin
            f = $fopen(nombre, "wb");
            ns = (t_cinta / 1000000) * 22050 / 1000 + 22050;
            // %u escribe 32 bits en binario (con los ceros, que %c se come)
            $fwrite(f, "%u%u%u", 32'h46464952, ns + 36, 32'h45564157);          // RIFF, tamaño, WAVE
            $fwrite(f, "%u%u%u%u%u%u", 32'h20746d66, 32'd16, 32'h00010001,        // "fmt ", 16, PCM mono
                    32'd22050, 32'd22050, 32'h00080001);                         // rate, byterate, 8 bits / align 1
            $fwrite(f, "%u%u", 32'h61746164, ns);                                 // "data", tamaño
            k = 0; nivel = 0;
            for (t = 0; t < ns; t = t + 1) begin
                while (k < cinta_n && cinta_t[k] <= t * 1000000000 / 22050) begin nivel = ~nivel; k = k + 1; end
                $fwrite(f, "%c", nivel ? 8'hD0 : 8'h30);
            end
            $fclose(f);
            $display("%0t CINTA: %s escrito, %0d muestras", $time, nombre, ns);
        end
    endtask

    // Carga un WAV en la SDRAM como lo haria data_io (indice 2)
    task carga_wav(input string nombre);
        integer f, n, k; reg [7:0] wbuf [0:4194303];
        begin
            f = $fopen(nombre, "rb"); n = $fread(wbuf, f); $fclose(f);
            for (k = 0; k < n; k = k + 1) begin
                @(posedge clk);
                while (!sdram_free) @(posedge clk);
                dl_addr <= 24'h010000 + k; dl_data <= wbuf[k]; dl_wr <= 1;
                @(posedge clk); dl_wr <= 0;
            end
            tape_tamano <= n; tape_cargada <= 1; @(posedge clk); tape_cargada <= 0;
            $display("%0t CINTA: WAV cargado, %0d bytes", $time, n);
        end
    endtask

    // Vuelca la grabacion a un WAV de 22050 Hz, 8 bits, mono (para probar el
    // reproductor de fp1100_tape). Entre flanco y flanco el nivel es constante.
    task volcar_wav(input string nombre);
        integer f, k, i, nmuestras; longint t; reg nivel; reg [7:0] hdr [0:43];
        begin
            nmuestras = (cinta_t[cinta_n - 1] / 1000000) * 22050 / 1000 + 22050;
            f = $fopen(nombre, "wb");
            hdr[0]="R"; hdr[1]="I"; hdr[2]="F"; hdr[3]="F";
            {hdr[7],hdr[6],hdr[5],hdr[4]} = nmuestras + 36;
            hdr[8]="W"; hdr[9]="A"; hdr[10]="V"; hdr[11]="E"; hdr[12]="f"; hdr[13]="m"; hdr[14]="t"; hdr[15]=" ";
            {hdr[19],hdr[18],hdr[17],hdr[16]} = 32'd16;
            {hdr[21],hdr[20]} = 16'd1; {hdr[23],hdr[22]} = 16'd1;
            {hdr[27],hdr[26],hdr[25],hdr[24]} = 32'd22050; {hdr[31],hdr[30],hdr[29],hdr[28]} = 32'd22050;
            {hdr[33],hdr[32]} = 16'd1; {hdr[35],hdr[34]} = 16'd8;
            hdr[36]="d"; hdr[37]="a"; hdr[38]="t"; hdr[39]="a";
            {hdr[43],hdr[42],hdr[41],hdr[40]} = nmuestras;
            for (k = 0; k < 44; k = k + 1) $fwrite(f, "%c", hdr[k]);
            i = 0; nivel = 0;
            for (k = 0; k < nmuestras; k = k + 1) begin
                t = k; t = t * 1000000000 / 22050;             // ns
                while (i < cinta_n && cinta_t[i] <= t) begin nivel = ~nivel; i = i + 1; end
                $fwrite(f, "%c", nivel ? 8'd200 : 8'd56);
            end
            $fclose(f);
            $display("WAV: %s, %0d muestras", nombre, nmuestras);
        end
    endtask

    // Carga un WAV en la SDRAM por el mismo camino que data_io (indice 2)
    reg [7:0] wav [0:4194303];
    task cargar_wav(input string nombre);
        integer f, nb, k;
        begin
            f = $fopen(nombre, "rb"); nb = $fread(wav, f); $fclose(f);
            for (k = 0; k < nb; k = k + 1) begin
                @(posedge clk);
                while (!sdram_free) @(posedge clk);
                dl_addr <= 24'h010000 + k; dl_data <= wav[k]; dl_wr <= 1;
                @(posedge clk); dl_wr <= 0;
            end
            repeat (100) @(posedge clk);
            tape_tamano <= nb; tape_cargada <= 1; @(posedge clk); tape_cargada <= 0;
            tape_externa = 0;
            $display("%0t WAV cargado: %0d bytes", $time, nb);
        end
    endtask

    // espera a que el motor lleve un tiempo parado
    task espera_motor_parado(input integer ciclos_quieto);
        integer q;
        begin
            q = 0;
            while (q < ciclos_quieto) begin
                @(posedge clk);
                if (cmt_motor) q = 0; else q = q + 1;
            end
        end
    endtask

    // traza del reproductor
    reg [3:0] tst_d;
    always @(posedge clk) begin
        tst_d <= dut.tape.st;
        if (dut.tape.byte_ok) $display("%0t TAPE: leido %06x -> %02x (palabra %04x) n=%0d st=%0d", $time, dut.tape.a_addr, dut.tape.dato, dut.ta_dout, dut.tape.n, dut.tape.st);
        if (dut.tape.st != tst_d) $display("%0t TAPE: estado %0d pos %0d id %08x chunk %0d rate %0d bits %0d canales %0d", $time, dut.tape.st, dut.tape.pos, dut.tape.id, dut.tape.chunk_size, dut.tape.rate, dut.tape.bits, dut.tape.canales);
    end

    // teclea una cadena ASCII (mayusculas, digitos, espacio, comillas, RETURN)
    task escribe(input string txt);
        integer k; reg [7:0] c;
        begin
            for (k = 0; k < txt.len(); k = k + 1) begin
                c = txt[k];
                case (c)
                    "A": tecla(8'h1C,0); "B": tecla(8'h32,0); "C": tecla(8'h21,0); "D": tecla(8'h23,0);
                    "E": tecla(8'h24,0); "F": tecla(8'h2B,0); "G": tecla(8'h34,0); "H": tecla(8'h33,0);
                    "I": tecla(8'h43,0); "J": tecla(8'h3B,0); "K": tecla(8'h42,0); "L": tecla(8'h4B,0);
                    "M": tecla(8'h3A,0); "N": tecla(8'h31,0); "O": tecla(8'h44,0); "P": tecla(8'h4D,0);
                    "Q": tecla(8'h15,0); "R": tecla(8'h2D,0); "S": tecla(8'h1B,0); "T": tecla(8'h2C,0);
                    "U": tecla(8'h3C,0); "V": tecla(8'h2A,0); "W": tecla(8'h1D,0); "X": tecla(8'h22,0);
                    "Y": tecla(8'h35,0); "Z": tecla(8'h1A,0);
                    "0": tecla(8'h45,0); "1": tecla(8'h16,0); "2": tecla(8'h1E,0); "3": tecla(8'h26,0);
                    "4": tecla(8'h25,0); "5": tecla(8'h2E,0); "6": tecla(8'h36,0); "7": tecla(8'h3D,0);
                    "8": tecla(8'h3E,0); "9": tecla(8'h46,0);
                    " ": tecla(8'h29,0); ":": tecla(8'h52,0); ".": tecla(8'h49,0);
                    // simbolos en la disposicion JIS del FP-1100
                    ",": tecla(8'h41,0); "-": tecla(8'h4E,0); "/": tecla(8'h4A,0); ";": tecla(8'h4C,0);
                    "(": begin tecla(8'h12,1); tecla(8'h3E,0); tecla(8'h12,2); end
                    ")": begin tecla(8'h12,1); tecla(8'h46,0); tecla(8'h12,2); end
                    "=": begin tecla(8'h12,1); tecla(8'h4E,0); tecla(8'h12,2); end
                    "+": begin tecla(8'h12,1); tecla(8'h4C,0); tecla(8'h12,2); end
                    "$": begin tecla(8'h12,1); tecla(8'h25,0); tecla(8'h12,2); end
                    "*": begin tecla(8'h12,1); tecla(8'h52,0); tecla(8'h12,2); end
                    "<": begin tecla(8'h12,1); tecla(8'h41,0); tecla(8'h12,2); end
                    ">": begin tecla(8'h12,1); tecla(8'h49,0); tecla(8'h12,2); end
                    "\"": begin tecla(8'h12,1); tecla(8'h1E,0); tecla(8'h12,2); end
                    "\n": tecla(8'h5A,0);
                    default: ;
                endcase
            end
        end
    endtask

    //------------------------------------------------------------------
    // Secuencia
    //------------------------------------------------------------------
    initial begin
        if (!$value$plusargs("ROM=%s", romfile)) romfile = "../roms/fp1100.rom";
        if (!$value$plusargs("CICLOS=%d", ciclos)) ciclos = 64000000;
        if (!$value$plusargs("T0=%d", t0)) t0 = 0;
        if (!$value$plusargs("TECLEAR=%d", teclear)) teclear = 0;
        if (!$value$plusargs("T1=%d", t1)) t1 = 0;
        fd = $fopen(romfile, "rb");
        if (fd == 0) begin $display("no se puede abrir %s", romfile); $finish; end
        n = $fread(rom, fd);
        $fclose(fd);
        $display("ROM: %0d bytes", n);
        if ($value$plusargs("DSK=%s", dskfile)) begin
            fd = $fopen(dskfile, "rb");
            if (fd == 0) begin $display("no se puede abrir %s", dskfile); $finish; end
            dsk_bytes = $fread(dsk, fd);
            $fclose(fd);
            $display("DSK: %0d bytes", dsk_bytes);
        end

        repeat (10) @(posedge clk);
        mem_reset = 0;
        repeat (20000) @(posedge clk);     // arranque de la SDRAM
        cargar();
        $display("%0t ROM cargada", $time);
        repeat (100) @(posedge clk);
        reset = 0;
        // +DSKTARDE: el disco se mete despues del arranque (sin que arranque
        // de el), como meterlo en la disquetera con el BASIC ya en marcha
        if (dsk_bytes > 0 && !$test$plusargs("DSKTARDE")) begin
            repeat (10) @(posedge clk);
            img_size <= dsk_bytes; img_mounted <= 2'b01;
            @(posedge clk); img_mounted <= 2'b00;
        end
        repeat (ciclos) @(posedge clk);
        if (dsk_bytes > 0 && $test$plusargs("DSKTARDE")) begin
            img_size <= dsk_bytes; img_mounted <= 2'b01;
            @(posedge clk); img_mounted <= 2'b00;
        end
        // Teclear PRINT 1+2 y RETURN por el PS/2 (formato MiSTer: conmuta,
        // pulsada, extendida, codigo)
        if (teclear == 3) begin
            // ida y vuelta por la cinta
            escribe("10 PRINT \"HOLA\"\n");
            escribe("SAVE \"CAS0:A\"\n");
            while (motor_vueltas == 0) @(posedge clk);
            espera_motor_parado(48000000);                   // 1,5 s sin motor: SAVE acabado
            $display("%0t CINTA: SAVE terminado, %0d flancos, %0d ms de cinta", $time, cinta_n, t_cinta / 1000000);
            volcar_wav("hola.wav");
            modo_load = 1; t_cinta = 0; cinta_i = 0;
            escribe("NEW\n");
            escribe("LOAD \"CAS0:A\"\n");
            while (motor_vueltas < 3) @(posedge clk);
            espera_motor_parado(48000000);
            $display("%0t CINTA: LOAD terminado, reproducidos %0d de %0d", $time, cinta_i, cinta_n);
            escribe("LIST\n");
            repeat (32000000) @(posedge clk);
        end else if (teclear == 4) begin
            // el reproductor del core: LOAD desde el WAV que dejo la prueba 3
            tape_externa = 0;
            carga_wav("hola.wav");
            while (!tape_lista) @(posedge clk);
            $display("%0t CINTA: reproductor listo", $time);
            escribe("LOAD \"CAS0:A\"\n");
            while (motor_vueltas < 1) @(posedge clk);
            espera_motor_parado(48000000);
            escribe("LIST\n");
            repeat (32000000) @(posedge clk);
        end else if (teclear == 7) begin
            // +GUION=fichero: teclea cada linea del fichero (con RETURN) y
            // espera +ESPERA ms (def. 1500) antes de volcar la pantalla
            begin : guion
                integer fg, esp; string lin; reg [8*256-1:0] buf_l; integer r;
                string nomg;
                if (!$value$plusargs("GUION=%s", nomg)) nomg = "guion.txt";
                if (!$value$plusargs("ESPERA=%d", esp)) esp = 1500;
                fg = $fopen(nomg, "r");
                while (!$feof(fg)) begin
                    r = $fgets(lin, fg);
                    if (r > 0) begin
                        $display("%0t GUION: %s", $time, lin);
                        escribe(lin);
                        repeat (48000000) @(posedge clk);     // 1,5 s: que acabe la linea
                    end
                end
                $fclose(fg);
                repeat (esp * 32000) @(posedge clk);
                volcar();
            end
        end else if (teclear == 6) begin
            // GAMDEMO2: en el menu, N cinco veces y O (VEGCRA); luego
            // derecha + espacio un segundo, se sueltan y se mira si el juego
            // sigue moviendose y disparando
            begin : juego_veg
                integer n;
                for (n = 0; n < 5; n = n + 1) begin
                    tecla(8'h31, 0);                          // N
                    repeat (16000000) @(posedge clk);         // 0,5 s
                end
                tecla(8'h44, 0);                              // O
                $display("%0t VEG: elegido", $time);
                repeat (448000000) @(posedge clk);            // 14 s: portada
                volcar();
                tecla(8'h29, 0);                              // ESPACIO: empieza
                $display("%0t VEG: empieza", $time);
                repeat (128000000) @(posedge clk);            // 4 s
                volcar();
                $display("%0t VEG: pulsa 6 (teclado numerico) y espacio", $time);
                ps2_key <= {~ps2_key[10], 1'b1, 1'b0, 8'h74};  // KP6
                repeat (1600000) @(posedge clk);
                ps2_key <= {~ps2_key[10], 1'b1, 1'b0, 8'h29};  // espacio
                repeat (32000000) @(posedge clk);             // 1 s
                volcar();
                ps2_key <= {~ps2_key[10], 1'b0, 1'b0, 8'h74};
                repeat (1600000) @(posedge clk);
                ps2_key <= {~ps2_key[10], 1'b0, 1'b0, 8'h29};
                repeat (100) @(posedge clk);
                $display("%0t VEG: sueltas; matriz fila5 %02x fila6 %02x", $time,
                         dut.kbd.matriz[5], dut.kbd.matriz[6]);
                for (n = 0; n < 12; n = n + 1) begin
                    repeat (8000000) @(posedge clk);          // 0,25 s
                    volcar();
                end
            end
        end else if (teclear == 5) begin
            // +WAV=fichero: LOAD "CAS0:" desde un WAV cualquiera por el
            // reproductor del core. Informa cada segundo de maquina de la
            // posicion de la cinta, y acaba 3 s despues de que el motor se
            // pare (o a los 90 s).
            begin : cinta_wav
                string wavf; integer seg, quieto;
                if (!$value$plusargs("WAV=%s", wavf)) wavf = "cinta.wav";
                cargar_wav(wavf);
                while (!tape_lista) @(posedge clk);
                $display("%0t CINTA: reproductor listo (datos %0d-%0d, %0d Hz, %0d bits)", $time,
                         dut.tape.data_ini, dut.tape.data_fin, dut.tape.rate, dut.tape.bits);
                escribe("LOAD \"CAS0:\"\n");
                quieto = 0;
                for (seg = 0; seg < 90 && !(motor_vueltas > 0 && quieto >= 3); seg = seg + 1) begin
                    repeat (32000000) @(posedge clk);
                    if (cmt_motor) quieto = 0; else quieto = quieto + 1;
                    $display("%0t CINTA: s=%0d motor=%b pos=%0d/%0d ear=%b PC Z80 %04x sub %04x", $time, seg,
                             cmt_motor, dut.tape.pos, dut.tape.data_fin, dut.tape.ear, dbg_pc, dbg_sub_a);
                end
            end
        end else if (teclear == 2) begin
            tecla(8'h23, 0); tecla(8'h43, 0); tecla(8'h2D, 0); tecla(8'h5A, 0);   // DIR
            repeat (24000000) @(posedge clk);
        end else if (teclear) begin
            tecla(8'h4D, 0); tecla(8'h2D, 0); tecla(8'h43, 0); tecla(8'h31, 0); tecla(8'h2C, 0);
            tecla(8'h29, 0); tecla(8'h16, 0);
            tecla(8'h12, 1); tecla(8'h4C, 0); tecla(8'h12, 2);   // SHIFT + ;
            tecla(8'h1E, 0); tecla(8'h5A, 0);
            repeat (8000000) @(posedge clk);
        end
        volcar();
        ultimos();
        $display("HSYNC: periodo min %0d max %0d ciclos de 25 MHz", hs_min, hs_max);
        $display("Z80: %0d ciclos de reloj, %0d ejecutados (%0d%% parado)", cen_tot, cen_ok, (cen_tot-cen_ok)*100/cen_tot);
        $display("fin: PC Z80 %04x, sub A %04x, tramas %0d", dbg_pc, dbg_sub_a, vueltas);
        $finish;
    end
    // Periodo de la vsync en lineas (hsync) de la salida, tras el arranque
    integer vs_lin = 0, vs_min = 99999, vs_max = 0, vs_n = 0; reg vs_d = 0, hs_d2 = 0;
    always @(posedge clk_pix) if (ce_pix) begin
        hs_d2 <= hs; vs_d <= vs;
        if (hs & ~hs_d2) vs_lin = vs_lin + 1;
        if (vs & ~vs_d) begin
            vs_n = vs_n + 1;
            if (vs_n > 20) begin
                if (vs_lin < vs_min) vs_min = vs_lin;
                if (vs_lin > vs_max) vs_max = vs_lin;
            end
            vs_lin = 0;
        end
    end
    final $display("VSYNC: periodo min %0d max %0d lineas", vs_min, vs_max);
endmodule
