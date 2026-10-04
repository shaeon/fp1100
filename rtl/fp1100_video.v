//============================================================================
// FP-1100 - HD46505SP (6845): la temporizacion de la maquina
//
// Reloj de puntos 16 MHz (ce_dot en clk_sys de 32 MHz). Un caracter del
// CRTC son 8 puntos en 80 columnas y 16 en 40 (PA3 = 1: el reloj del CRTC se
// divide por 16 en vez de por 8). Con la geometria que carga la ROM (128
// caracteres de linea a 2 MHz, 261 lineas) sale una linea de 64 us y 59,8
// Hz: video de 15 kHz normal.
//
// Este modulo lleva los contadores del 6845 tal cual, porque de ellos
// dependen el WAIT del sub (HSYNC), la posicion vertical, el cursor y el
// parpadeo. Los pixeles NO se sacan de aqui: los dibuja fp1100_display con
// su propio reloj de 12,5 MHz a partir de lo que este modulo le da al
// principio de cada linea (MA de la fila, RA, visible, vsync...). Ver la
// cabecera de fp1100_display.v para el porque.
//
// El CRTC trabaja en modo grafico puro: cada "caracter" son 8 bytes
// consecutivos de VRAM, uno por linea de raster:
//
//     direccion = {MA[10:0], RA[2:0]}      (14 bits, por plano)
//============================================================================
`default_nettype none

module fp1100_video (
    input  wire        clk,
    input  wire        reset,
    input  wire        ce_dot,          // 16 MHz

    // registros del CRTC, desde el sub
    input  wire        crtc_cs,
    input  wire        crtc_a0,
    input  wire        crtc_wr,
    input  wire [7:0]  crtc_din,
    output reg  [7:0]  crtc_dout,

    input  wire [7:0]  pa,

    output reg         hsync,           // activo a nivel alto (WAIT del sub)
    output wire        vblank,          // para el registro de estado

    // Lo que necesita fp1100_display, valido durante toda la linea. Cambia
    // solo en el ultimo punto de cada linea, cuando conmuta linea_tgl.
    output reg         linea_tgl,       // cambia al empezar cada linea
    output wire [13:0] lin_ma,          // MA del primer caracter de la linea
    output wire [8:0]  lin_n,           // numero de linea en la trama (0 = primera visible)
    output wire [4:0]  lin_ra,          // raster
    output wire        lin_visible,     // dentro de las filas de display
    output wire        lin_vsync,
    output wire [7:0]  lin_chars,       // R1: caracteres visibles por linea
    output wire        lin_col40,       // PA3
    output wire        lin_display_on,  // R8 y PA2-0 lo permiten
    output wire        lin_screen1,     // 16 rasters por fila: pagina mono
    output wire [13:0] lin_cursor,      // R14/R15
    output wire        lin_cursor_on    // parpadeo y rasters del cursor
);
    //------------------------------------------------------------------
    // Registros del 6845
    //------------------------------------------------------------------
    reg [4:0] sel;
    reg [7:0] r0, r1, r2, r3, r4, r5, r6, r7, r8, r9, r10, r11, r12, r13, r14, r15;

    always @(posedge clk) begin
        if (reset) begin
            sel <= 5'd0;
            // Valores del arranque de la ROM del sub (80 columnas), por si el
            // video se mira antes de que el sub los cargue
            r0 <= 8'd127; r1 <= 8'd80; r2 <= 8'd94;  r3 <= 8'h08;
            r4 <= 8'd31;  r5 <= 8'd5;  r6 <= 8'd25;  r7 <= 8'd28;
            r8 <= 8'd0;   r9 <= 8'd7;  r10 <= 8'h60; r11 <= 8'd7;
            r12 <= 8'd0;  r13 <= 8'd0; r14 <= 8'd0;  r15 <= 8'd0;
        end else if (crtc_wr) begin
            if (!crtc_a0) sel <= crtc_din[4:0];
            else case (sel)
                5'd0:  r0  <= crtc_din;
                5'd1:  r1  <= crtc_din;
                5'd2:  r2  <= crtc_din;
                5'd3:  r3  <= crtc_din;
                5'd4:  r4  <= crtc_din;
                5'd5:  r5  <= crtc_din;
                5'd6:  r6  <= crtc_din;
                5'd7:  r7  <= crtc_din;
                5'd8:  r8  <= crtc_din;
                5'd9:  r9  <= crtc_din;
                5'd10: r10 <= crtc_din;
                5'd11: r11 <= crtc_din;
                5'd12: r12 <= crtc_din;
                5'd13: r13 <= crtc_din;
                5'd14: r14 <= crtc_din;
                5'd15: r15 <= crtc_din;
                default: ;
            endcase
        end
    end

    // Lectura: estado (a0=0) y los registros legibles del HD46505 (12-17)
    always @* begin
        if (!crtc_a0) crtc_dout = {2'b00, vblank, 5'b00000};
        else case (sel)
            5'd12: crtc_dout = r12;
            5'd13: crtc_dout = r13;
            5'd14: crtc_dout = r14;
            5'd15: crtc_dout = r15;
            default: crtc_dout = 8'h00;
        endcase
    end

    //------------------------------------------------------------------
    // Contadores
    //
    // MA se incrementa en cada caracter a lo largo de toda la linea (tambien
    // fuera de la zona visible), y al empezar cada raster se recarga con el
    // principio de la fila. Al acabar la ultima raster de una fila, el
    // principio de fila avanza R1. Al empezar la trama, R12/R13.
    //------------------------------------------------------------------
    wire       col40  = pa[3];
    wire [3:0] dot_max = col40 ? 4'd15 : 4'd7;
    wire       interlace_v = (r8[1:0] == 2'b11);   // entrelazado con video
    wire [4:0] ra_max = r9[4:0];
    wire [4:0] ra_paso = interlace_v ? 5'd2 : 5'd1;

    reg [3:0]  dot;                 // punto dentro del caracter
    reg [7:0]  hcc;                 // caracter horizontal
    reg [6:0]  vcc;                 // fila de caracteres
    reg [4:0]  ra;                  // raster dentro de la fila
    reg        ajuste;              // en las lineas de ajuste vertical (R5)
    reg [4:0]  ajuste_cnt;
    reg [13:0] ma, ma_row;          // direccion actual y de principio de fila
    reg [3:0]  hs_cnt;
    reg [3:0]  vs_cnt;
    reg        vs_on;
    reg        field;               // trama par/impar
    reg [4:0]  frames;              // para el parpadeo del cursor
    reg [8:0]  nlin;                // linea dentro de la trama

    wire fin_char  = ce_dot & (dot == dot_max);
    wire fin_linea = fin_char & (hcc == r0);
    // En entrelazado con video (R8 = 3, el Screen 1 de 400 lineas) R9 es el
    // numero de rasters de la fila MENOS DOS (HD46505: filas de R9+2
    // rasters): con R9 = 14, 16 rasters, 8 por trama; la par hace 0, 2 ... 14
    // y la impar 1, 3 ... 15. Antes la impar paraba en 13: una trama de 261
    // lineas y otra de 229, y el monitor no enganchaba (pantalla negra, sin
    // OSD siquiera).
    wire ultima_raster = interlace_v ? ((ra + 5'd2) > (ra_max + 5'd1))
                                     : ((ra + 5'd1) > ra_max);
    wire hay_ajuste = (r5[4:0] != 5'd0);
    wire ultima_fila = (vcc == r4[6:0]);
    // Tras la ultima raster de la ultima fila: o ajuste, o trama nueva
    wire entra_ajuste = ultima_raster & ultima_fila & hay_ajuste & ~ajuste;
    wire fin_trama = ajuste ? (ajuste_cnt + 5'd1 == r5[4:0])
                            : (ultima_raster & ultima_fila & ~hay_ajuste);
    wire fila_nueva = ~ajuste & ultima_raster & ~ultima_fila;

    wire [13:0] ma_inicio = {r12[5:0], r13};
    wire [13:0] ma_row_sig = ma_row + {6'd0, r1};
    // Primera raster de una fila: 0, o 1 en la trama impar entrelazada
    wire [4:0]  ra_primera = (interlace_v & field) ? 5'd1 : 5'd0;

    // Lo que valdran MA y RA al empezar la linea siguiente
    wire [13:0] ma_linea_sig = fin_trama  ? ma_inicio :
                               fila_nueva ? ma_row_sig : ma_row;
    wire [4:0]  ra_linea_sig = fin_trama  ? ((interlace_v & ~field) ? 5'd1 : 5'd0) :
                               (ajuste | entra_ajuste | fila_nueva) ? ra_primera :
                               (ra + ra_paso);

    always @(posedge clk) begin
        if (reset) begin
            dot <= 4'd0; hcc <= 8'd0; vcc <= 7'd0; ra <= 5'd0;
            ajuste <= 1'b0; ajuste_cnt <= 5'd0;
            ma <= 14'd0; ma_row <= 14'd0;
            hs_cnt <= 4'd0; vs_cnt <= 4'd0; vs_on <= 1'b0; field <= 1'b0;
            frames <= 5'd0; hsync <= 1'b0; nlin <= 9'd0;
        end else if (ce_dot) begin
            // puntos y caracteres
            if (dot == dot_max) begin
                dot <= 4'd0;
                if (hcc == r0) hcc <= 8'd0; else hcc <= hcc + 8'd1;
                if (hcc != r0) ma <= ma + 14'd1;
            end else dot <= dot + 4'd1;

            // hsync: R3[3:0] caracteres a partir de R2
            if (fin_char) begin
                if ((hcc + 8'd1) == r2 && r3[3:0] != 4'd0) begin
                    hsync  <= 1'b1;
                    hs_cnt <= 4'd1;
                end else if (hsync) begin
                    if (hs_cnt == r3[3:0]) hsync <= 1'b0;
                    else hs_cnt <= hs_cnt + 4'd1;
                end
            end

            // lineas, filas y tramas
            if (fin_linea) begin
                // vsync: R3[7:4] lineas desde la fila R7 (0 = 16 lineas)
                if (vs_on) begin
                    vs_cnt <= vs_cnt + 4'd1;
                    if (vs_cnt + 4'd1 == r3[7:4]) vs_on <= 1'b0;
                end

                ma <= ma_linea_sig;
                ra <= ra_linea_sig;
                nlin <= fin_trama ? 9'd0 : nlin + 9'd1;

                if (fin_trama) begin
                    vcc        <= 7'd0;
                    ajuste     <= 1'b0;
                    ajuste_cnt <= 5'd0;
                    field      <= interlace_v ? ~field : 1'b0;
                    ma_row     <= ma_inicio;
                    frames     <= frames + 5'd1;
                end else if (ajuste) begin
                    ajuste_cnt <= ajuste_cnt + 5'd1;
                end else if (entra_ajuste) begin
                    ajuste <= 1'b1;
                end else if (fila_nueva) begin
                    vcc    <= vcc + 7'd1;
                    ma_row <= ma_row_sig;
                    if (vcc + 7'd1 == r7[6:0]) begin
                        vs_on  <= 1'b1;
                        vs_cnt <= 4'd0;
                    end
                end
            end
        end
    end

    //------------------------------------------------------------------
    // Salidas para fp1100_display
    //------------------------------------------------------------------
    wire visible_v  = (vcc < r6[6:0]) & ~ajuste;
    wire display_on = (r8[5:4] != 2'b11) & (pa[2:0] != 3'b000);
    wire blink_on   = (r10[6:5] == 2'b00) |
                      ((r10[6:5] == 2'b10) & frames[3]) |
                      ((r10[6:5] == 2'b11) & frames[4]);

    reg [13:0] ma_lin_r;
    always @(posedge clk) begin
        if (reset) begin
            linea_tgl <= 1'b0;
            ma_lin_r  <= 14'd0;
        end else if (fin_linea) begin
            linea_tgl <= ~linea_tgl;
            ma_lin_r  <= ma_linea_sig;     // constante toda la linea (ma va contando)
        end
    end

    assign vblank         = ~visible_v;
    assign lin_ma         = ma_lin_r;
    assign lin_ra         = ra;
    assign lin_n          = nlin;
    assign lin_visible    = visible_v;
    assign lin_vsync      = vs_on;
    assign lin_chars      = r1;
    assign lin_col40      = col40;
    assign lin_display_on = display_on;
    assign lin_screen1    = (ra_max >= 5'd8);
    assign lin_cursor     = {r14[5:0], r15};
    assign lin_cursor_on  = blink_on & (ra >= r10[4:0]) & (ra <= r11[4:0]);

endmodule

`default_nettype wire
