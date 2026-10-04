//============================================================================
// Banco de pruebas del camino de video, sin la maquina (no hace falta ROM):
// fp1100_video (CRTC con los registros de arranque, 80 columnas) +
// fp1100_vfetch + fp1100_display / fp1100_vga + mist_video, como en el top,
// con una VRAM de prueba:
//
//   - marco blanco: lineas y = 0 e y = 199, columnas x = 0 y x = 639
//   - en cada raster y, el caracter 2 lleva y en el plano B y el 3 en el R
//     (bit 0 = punto de la izquierda), para saber que linea es cada una
//   - para mirarla: rejilla cada 80 puntos y 25 lineas, cruz central, barras
//     de color (y 30-69) y rayas verticales de 1 y 2 puntos (y 130-169)
//
// Vuelca la salida VGA (por ciclo del reloj de video) a vga.hex, una linea
// de texto por linea VGA (de flanco de bajada de VGA_HS a flanco de bajada),
// y analiza_sd.py la interpreta.
//
//   (nada)        31 kHz con fp1100_vga (VGA_525: 800 x 525 a 25,1436 MHz)
//   +SCANDOUBLER  31 kHz con el scandoubler de mist_video (522 lineas)
//   +SD_OFF       15 kHz
//   +SCREEN1      Screen 1 (640x400 entrelazado) a 400 lineas por fp1100_vga:
//                 cada raster r (0..399) de la pagina mono lleva r en los
//                 caracteres 2 (bits 7-0) y 3 (bit 8); analiza_sd.py --s1
//   +HOFF=n +VOFF=n   h_off / v_off (por defecto los del top en cada modo)
//   +TRAMAS=n     tramas de salida a volcar tras la de arranque (def. 3)
//============================================================================
`timescale 1ns/1fs

module tb_sd;
    reg clk = 0;
    always #15.625 clk = ~clk;          // 32 MHz
    reg clk_pix = 0;
    always #20 clk_pix = ~clk_pix;      // 25 MHz
    // 25,1436 MHz: medio periodo 139,2/7 ns, que no es exacto en ninguna
    // resolucion; cada flanco se pone en su instante absoluto (n x 139,2/7)
    // para que no derive respecto a clk, como en la placa (mismo cristal)
    reg clk_vga = 0;
    initial begin : reloj_vga
        longint n; real t;
        n = 0;
        forever begin
            n = n + 1;
            t = n * 139.2 / 7.0;
            #(t - $realtime) clk_vga = ~clk_vga;
        end
    end

    reg reset = 1;
    reg [3:0] clkdiv = 0;
    always @(posedge clk) clkdiv <= clkdiv + 4'd1;
    wire ce_dot = clkdiv[0];

    bit sd_disable = 0, scandoubler = 0, vga525 = 0, screen1 = 0;
    integer hoff_i, voff_i, tramas;
    reg signed [5:0] h_off;
    reg signed [4:0] v_off;
    initial begin
        sd_disable = $test$plusargs("SD_OFF");
        scandoubler = $test$plusargs("SCANDOUBLER");
        screen1 = $test$plusargs("SCREEN1");
        vga525 = ~sd_disable & ~scandoubler;
        if (!$value$plusargs("HOFF=%d", hoff_i)) hoff_i = sd_disable ? -20 : 0;
        if (!$value$plusargs("VOFF=%d", voff_i)) voff_i = 0;
        if (!$value$plusargs("TRAMAS=%d", tramas)) tramas = 3;
        h_off = hoff_i[5:0];
        v_off = voff_i[4:0];
        $display("modo %s  h_off %0d  v_off %0d", sd_disable ? "15 kHz" : scandoubler ? "31 kHz (scandoubler)" : "31 kHz (fp1100_vga, 525 lineas)", h_off, v_off);
    end

    wire [7:0] pa = 8'h07;              // tres planos, 80 columnas, color

    wire        linea_tgl, lin_visible, lin_vsync, lin_col40, lin_display_on, lin_screen1, lin_cursor_on;
    wire [13:0] lin_ma, lin_cursor;
    wire [4:0]  lin_ra;
    wire [7:0]  lin_chars;
    wire [8:0]  lin_n;
    wire        hsync_crtc;
    reg         crtc_a0 = 0, crtc_wr = 0;
    reg  [7:0]  crtc_din = 0;

    // Los registros que programa la ROM del sub al arrancar (80 columnas,
    // ver docs §13): R2 = 96 y R3 = 3Ah (hsync de 10 caracteres, vsync de 3
    // lineas) no son los de reset del core
    task crtc_esc(input [4:0] r, input [7:0] v);
        begin
            @(posedge clk); crtc_a0 <= 0; crtc_din <= {3'd0, r}; crtc_wr <= 1;
            @(posedge clk); crtc_a0 <= 1; crtc_din <= v;
            @(posedge clk); crtc_wr <= 0;
        end
    endtask

    fp1100_video crtc (
        .clk(clk), .reset(reset), .ce_dot(ce_dot),
        .crtc_cs(1'b0), .crtc_a0(crtc_a0), .crtc_wr(crtc_wr), .crtc_din(crtc_din), .crtc_dout(),
        .pa(pa), .hsync(hsync_crtc), .vblank(),
        .linea_tgl(linea_tgl), .lin_ma(lin_ma), .lin_ra(lin_ra), .lin_n(lin_n),
        .lin_visible(lin_visible), .lin_vsync(lin_vsync), .lin_chars(lin_chars),
        .lin_col40(lin_col40), .lin_display_on(lin_display_on), .lin_screen1(lin_screen1),
        .lin_cursor(lin_cursor), .lin_cursor_on(lin_cursor_on)
    );

    //------------------------------------------------------------------
    // VRAM de prueba (por plano, 16K): direccion {MA[10:0], RA[2:0]}
    //------------------------------------------------------------------
    reg [7:0] vb [0:16383], vr [0:16383], vg [0:16383];
    initial begin : llenar
        integer a, y, c, f, ra, adr;
        reg [8:0] r9;
        for (a = 0; a < 16384; a = a + 1) begin vb[a] = 0; vr[a] = 0; vg[a] = 0; end
        #1;
        // Screen 1: filas de 16 rasters, las 0-7 en el plano B y las 8-15 en
        // el R, en {MA, RA[2:0]}; marco en las rasters 0 y 399 y x = 0 y 639
        if (screen1) for (y = 0; y < 400; y = y + 1) begin
            f = y / 16; ra = y % 16; r9 = y[8:0];
            for (c = 0; c < 80; c = c + 1) begin
                adr = ((f * 80 + c) << 3) | (ra % 8);
                if (y == 0 || y == 399) begin if (ra < 8) vb[adr] = 8'hFF; else vr[adr] = 8'hFF; end
                if (c == 0)  begin if (ra < 8) vb[adr] = vb[adr] | 8'h01; else vr[adr] = vr[adr] | 8'h01; end
                if (c == 79) begin if (ra < 8) vb[adr] = vb[adr] | 8'h80; else vr[adr] = vr[adr] | 8'h80; end
                if (c == 2 && y != 0 && y != 399) begin if (ra < 8) vb[adr] = r9[7:0]; else vr[adr] = r9[7:0]; end
                if (c == 3 && y != 0 && y != 399) begin if (ra < 8) vb[adr] = {7'd0, r9[8]}; else vr[adr] = {7'd0, r9[8]}; end
            end
        end
        else for (y = 0; y < 200; y = y + 1) begin
            f = y / 8; ra = y % 8;
            for (c = 0; c < 80; c = c + 1) begin
                adr = ((f * 80 + c) << 3) | ra;
                if (y == 0 || y == 199) begin vb[adr] = 8'hFF; vr[adr] = 8'hFF; vg[adr] = 8'hFF; end
                if (c == 0)  begin vb[adr] = vb[adr] | 8'h01; vr[adr] = vr[adr] | 8'h01; vg[adr] = vg[adr] | 8'h01; end
                if (c == 79) begin vb[adr] = vb[adr] | 8'h80; vr[adr] = vr[adr] | 8'h80; vg[adr] = vg[adr] | 8'h80; end
                // a partir del caracter 4, para no tocar el codigo de linea:
                if (c >= 4 && c <= 78 && y != 0 && y != 199) begin
                    // rejilla cada 80 puntos y cada 25 lineas, cruz central
                    if (y % 25 == 0 || y == 99 || y == 100) begin
                        vb[adr] = 8'hFF; vr[adr] = 8'hFF; vg[adr] = 8'hFF;
                    end
                    if (c % 10 == 0) begin vb[adr] = vb[adr] | 8'h01; vr[adr] = vr[adr] | 8'h01; vg[adr] = vg[adr] | 8'h01; end
                    // barras de color (y 30..69): negro, azul, rojo, magenta, verde, cian, amarillo, blanco
                    if (y >= 30 && y < 70 && c >= 8 && c < 72) begin
                        vb[adr] = vb[adr] | ((((c - 8) / 8) & 1) ? 8'hFF : 8'h00);
                        vr[adr] = vr[adr] | ((((c - 8) / 8) & 2) ? 8'hFF : 8'h00);
                        vg[adr] = vg[adr] | ((((c - 8) / 8) & 4) ? 8'hFF : 8'h00);
                    end
                    // rayas verticales de 1 punto (y 130..169): blanco/negro alternos,
                    // y de 2 puntos a la derecha
                    if (y >= 130 && y < 170 && c >= 8 && c < 40) begin
                        vb[adr] = 8'h55; vr[adr] = 8'h55; vg[adr] = 8'h55;
                    end
                    if (y >= 130 && y < 170 && c >= 40 && c < 72) begin
                        vb[adr] = 8'h33; vr[adr] = 8'h33; vg[adr] = 8'h33;
                    end
                end
                if (c == 2 && y != 0 && y != 199) vb[adr] = y[7:0];
                if (c == 3 && y != 0 && y != 199) vr[adr] = y[7:0];
            end
        end
    end

    wire        vf_rd, vf_par;
    wire [13:0] vf_addr;
    reg         vf_ack = 0;
    reg  [31:0] vf_q = 0;
    reg  [2:0]  vf_cnt = 0;
    reg  [13:0] vf_a;
    reg         vf_p;
    always @(posedge clk) begin
        vf_ack <= 1'b0;
        if (vf_rd) begin vf_cnt <= 3'd3; vf_a <= vf_addr; vf_p <= vf_par; end
        else if (vf_cnt != 0) begin
            vf_cnt <= vf_cnt - 3'd1;
            if (vf_cnt == 3'd1) begin
                vf_ack <= 1'b1;
                // con par (Screen 1 a 400 lineas) dos rasters, como la SDRAM:
                // {R(addr+1), B(addr+1), R(addr), B(addr)}
                vf_q   <= vf_p ? {vr[vf_a | 14'd1], vb[vf_a | 14'd1], vr[vf_a], vb[vf_a]}
                               : {8'h00, vg[vf_a], vr[vf_a], vb[vf_a]};
            end
        end
    end

    wire [7:0]  lb_addr;
    wire [23:0] lb_q;
    wire [9:0]  lb31_addr;
    wire [23:0] lb31_q;
    fp1100_vfetch vfetch (
        .clk(clk), .reset(reset),
        .linea_tgl(linea_tgl), .lin_ma(lin_ma), .lin_ra(lin_ra), .lin_n(lin_n),
        .lin_visible(lin_visible), .lin_display_on(lin_display_on), .lin_chars(lin_chars),
        .lin_screen1(lin_screen1), .vga400(screen1),
        .rd(vf_rd), .par(vf_par), .addr(vf_addr), .ack(vf_ack), .q(vf_q),
        .clk_pix(clk_pix), .lb_addr(lb_addr), .lb_q(lb_q),
        .clk_vga(clk_vga), .lb31_addr(lb31_addr), .lb31_q(lb31_q)
    );

    wire        ce_pix, vid_31k;
    wire [7:0]  R, G, B;
    wire        hs, hs_cs, vs, hb, vb_;
    fp1100_display display (
        .clk_pix(clk_pix), .reset(reset), .ce_pix(ce_pix),
        .vga400(1'b0), .modo31(vid_31k),
        .h_off(h_off), .v_off(v_off), .tv15(sd_disable | vga525),
        .linea_tgl(linea_tgl), .lin_ma(lin_ma), .lin_ra(lin_ra),
        .lin_visible(lin_visible), .lin_vsync(lin_vsync), .lin_chars(lin_chars),
        .lin_col40(lin_col40), .lin_display_on(lin_display_on), .lin_screen1(lin_screen1),
        .lin_cursor(lin_cursor), .lin_cursor_on(1'b0),
        .libre(1'b0),
        .pa(pa), .color_reg(8'h00),
        .lb_addr(lb_addr), .lb_q(lb_q),
        .R(R), .G(G), .B(B),
        .hsync(hs), .hsync_cs(hs_cs), .vsync(vs),
        .hblank(hb), .vblank(vb_)
    );

    wire [7:0]  vga_r, vga_g, vga_b;
    wire        vga_hs, vga_vs, vga_hb, vga_vb;
    fp1100_vga vga (
        .clk(clk_vga), .reset(reset),
        .h_off(h_off), .v_off(v_off), .vga400(screen1), .scanlines(2'b00),
        .linea_tgl(linea_tgl), .lin_n(lin_n), .lin_ma(lin_ma), .lin_ra(lin_ra),
        .lin_visible(lin_visible), .lin_chars(lin_chars), .lin_col40(lin_col40),
        .lin_display_on(lin_display_on), .lin_screen1(lin_screen1),
        .lin_cursor(lin_cursor), .lin_cursor_on(1'b0),
        .pa(pa), .color_reg(8'h00),
        .lb_addr(lb31_addr), .lb_q(lb31_q),
        .R(vga_r), .G(vga_g), .B(vga_b),
        .hsync(vga_hs), .vsync(vga_vs), .hblank(vga_hb), .vblank(vga_vb)
    );

    //------------------------------------------------------------------
    // mist_video como en el top (sin csync: H y V separadas, para medir).
    // mv: 15 kHz o scandoubler, con clk_pix; mv31: fp1100_vga, con clk_vga
    //------------------------------------------------------------------
    wire [5:0] A_R, A_G, A_B, B_R, B_G, B_B;
    wire A_HS, A_VS, A_DE, B_HS, B_VS, B_DE;
    mist_video #(.COLOR_DEPTH(8), .SD_HCNT_WIDTH(11), .USE_BLANKS(1'b1), .OSD_COLOR(3'b001),
                 .OUT_COLOR_DEPTH(6), .BIG_OSD(1'b0)) mv (
        .clk_sys(clk_pix), .SPI_SCK(1'b0), .SPI_SS3(1'b1), .SPI_DI(1'b0),
        .scanlines(2'b00), .ce_divider(3'd1),
        .scandoubler_disable(~scandoubler), .no_csync(1'b1), .ypbpr(1'b0),
        .rotate(2'b00), .blend(1'b0),
        .R(R), .G(G), .B(B), .HBlank(hb), .VBlank(vb_),
        .HSync(~hs), .VSync(~vs),
        .osd_enable(),
        .VGA_R(A_R), .VGA_G(A_G), .VGA_B(A_B),
        .VGA_VS(A_VS), .VGA_HS(A_HS), .VGA_HB(), .VGA_VB(), .VGA_DE(A_DE)
    );
    mist_video #(.COLOR_DEPTH(8), .SD_HCNT_WIDTH(11), .USE_BLANKS(1'b1), .OSD_COLOR(3'b001),
                 .OUT_COLOR_DEPTH(6), .BIG_OSD(1'b0)) mv31 (
        .clk_sys(clk_vga), .SPI_SCK(1'b0), .SPI_SS3(1'b1), .SPI_DI(1'b0),
        .scanlines(2'b00), .ce_divider(3'd1),
        .scandoubler_disable(1'b1), .no_csync(1'b1), .ypbpr(1'b0),
        .rotate(2'b00), .blend(1'b0),
        .R(vga_r), .G(vga_g), .B(vga_b), .HBlank(vga_hb), .VBlank(vga_vb),
        .HSync(~vga_hs), .VSync(~vga_vs),
        .osd_enable(),
        .VGA_R(B_R), .VGA_G(B_G), .VGA_B(B_B),
        .VGA_VS(B_VS), .VGA_HS(B_HS), .VGA_HB(), .VGA_VB(), .VGA_DE(B_DE)
    );
    wire [5:0] VGA_R = vga525 ? B_R : A_R;
    wire [5:0] VGA_G = vga525 ? B_G : A_G;
    wire [5:0] VGA_B = vga525 ? B_B : A_B;
    wire VGA_HS = vga525 ? B_HS : A_HS;
    wire VGA_VS = vga525 ? B_VS : A_VS;
    wire VGA_DE = vga525 ? B_DE : A_DE;
    wire clk_vol = vga525 ? clk_vga : clk_pix;

    //------------------------------------------------------------------
    // Volcado: un caracter (base 32) por ciclo de clk_pix:
    //   bit 0 B, bit 1 R, bit 2 G, bit 3 DE (activo, sin blanking), bit 4 HS
    // y una linea de texto por linea VGA, con "S" delante si VGA_VS (activa
    // a nivel bajo) esta activa al empezar la linea.
    //------------------------------------------------------------------
    function automatic [7:0] digito(input [4:0] v);
        digito = (v < 10) ? 8'd48 + {3'd0, v} : 8'd87 + {3'd0, v};   // 0-9, a-v
    endfunction
    integer fo, nvs = 0, vs_ini = 2;
    reg vhs_d = 1, vvs_d = 1;
    bit volcando = 0;
    always @(posedge clk_vol) begin
        vhs_d <= VGA_HS; vvs_d <= VGA_VS;
        if (vvs_d & ~VGA_VS) begin
            nvs = nvs + 1;
            if (nvs == vs_ini) begin volcando = 1; $fwrite(fo, "#trama\n"); end
            else if (nvs > vs_ini && nvs <= vs_ini + tramas) $fwrite(fo, "#trama\n");
            else if (nvs > vs_ini + tramas) volcando = 0;
        end
        if (volcando) begin
            if (vhs_d & ~VGA_HS) $fwrite(fo, "\n%s", VGA_VS ? "-" : "S");
            // base 32: bit 4 = VGA_HS activa (a nivel bajo)
            $fwrite(fo, "%c", digito({~VGA_HS, VGA_DE, VGA_G[5], VGA_R[5], VGA_B[5]}));
        end
    end

    // cada vez que fp1100_vga se realinea con la trama del CRTC
    always @(posedge clk_vga)
        if (vga525 && vga.nueva && vga.lin_n == 9'd0)
            $display("%0t trama del CRTC: vga en linea %0d punto %0d%s", $time, vga.vcnt, vga.hcnt,
                     vga.alineado ? "" : "  -> REALINEA");

    initial begin
        fo = $fopen("vga.hex", "w");
        repeat (20) @(posedge clk);
        reset = 0;
        crtc_esc(0, 127); crtc_esc(1, 80); crtc_esc(2, 96); crtc_esc(3, 8'h3A); crtc_esc(4, 31); crtc_esc(5, 5);
        crtc_esc(6, 25); crtc_esc(7, 28); crtc_esc(9, 7); crtc_esc(10, 8'h27); crtc_esc(11, 7);
        // Screen 1, como lo programa la ROM: entrelazado con video, filas de
        // R9 + 2 = 16 rasters (8 por trama)
        if (screen1) begin crtc_esc(8, 3); crtc_esc(9, 14); end
        wait (nvs > vs_ini + tramas);
        repeat (10) @(posedge clk);
        $fclose(fo);
        $display("hecho: %0d vsyncs", nvs);
        $finish;
    end
endmodule
