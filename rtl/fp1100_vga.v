//============================================================================
// FP-1100 - salida de 31 kHz propia: VGA 640x480 de verdad (macro VGA_525)
//
// El scandoubler dobla cada linea de la maquina, y la maquina hace 261: salen
// 522 lineas, no las 525 del 640x480 de VGA, y no todos los monitores ni
// conversores (OSSC, capturadoras) lo toman por 480p. Este modulo genera su
// propio 640x480 estandar: 800 x 525 puntos a 25,1436 MHz (pll_vga), 31,43
// kHz y 59,87 Hz, dentro de la tolerancia de VESA (25,175 MHz +-0,5 %).
//
// El reloj esta elegido para que 800 x 525 puntos duren EXACTAMENTE un cuadro
// de la maquina (261 lineas de 1024 puntos de 16 MHz): 25,1436 = 16 x
// 420000/267264. Sale del mismo cristal que el sistema (pll_vga.v), asi que
// el cuadro de VGA va enganchado al de la maquina: se alinea una vez y no
// se mueve; solo se realinea si el principio de la trama del CRTC llega a mas
// de dos puntos de donde toca (al arrancar, o si el sub cambia la geometria).
//
// Las lineas no salen del barrido del CRTC sino del anillo de 8 lineas de
// fp1100_vfetch: la linea de salida k de la imagen (0..399) pinta la linea
// k/2 de la maquina. 525 lineas de salida duran lo que 261 de la maquina, asi
// que la salida se adelanta 0,37 us por cada linea de la maquina (1,15 lineas
// en toda la imagen): por eso empieza a leer 6 lineas de salida (3 de la
// maquina) despues de que el CRTC empiece la trama, y el anillo tiene 8.
// Con Screen 1 a 400 lineas (vga400) cada linea del anillo trae la raster
// par y la impar: la linea k pinta la raster k de la pagina mono.
//
// Vertical (VGA): vsync de 2 lineas, 33 de porche, 480 activas y 10 de
// porche; las 400 de la imagen van en medio (40 de borde arriba y abajo),
// y v_off las mueve de 2 en 2 lineas de salida. Horizontal como el 31 kHz de
// siempre: hsync de 96 puntos, 48 de porche, 640 de imagen, 16 de porche.
//
// Los pixeles se dibujan como en fp1100_display (mismos registros de
// desplazamiento, color, verde, Screen 1 y cursor), un punto por ciclo.
// Las scanlines (que antes ponia el scandoubler) oscurecen la segunda de
// las dos lineas de salida de cada linea de la maquina; con Screen 1 a 400
// lineas no se aplican (cada linea es una raster distinta).
//============================================================================
`default_nettype none

module fp1100_vga (
    input  wire        clk,             // 25,1436 MHz
    input  wire        reset,
    input  wire signed [5:0] h_off,     // puntos, + = a la derecha (-16..+12)
    input  wire signed [4:0] v_off,     // lineas de la maquina, + = hacia abajo (-8..+6)
    input  wire        vga400,          // Screen 1 en 400 lineas
    input  wire [1:0]  scanlines,       // 0 no, 1 25 %, 2 50 %, 3 75 % (la segunda linea de cada par)

    // del CRTC (clk_sys), con un toggle por linea
    input  wire        linea_tgl,
    input  wire [8:0]  lin_n,
    input  wire [13:0] lin_ma,
    input  wire [4:0]  lin_ra,
    input  wire        lin_visible,
    input  wire [7:0]  lin_chars,
    input  wire        lin_col40,
    input  wire        lin_display_on,
    input  wire        lin_screen1,
    input  wire [13:0] lin_cursor,
    input  wire        lin_cursor_on,

    input  wire [7:0]  pa,
    input  wire [7:0]  color_reg,

    // anillo de lineas de fp1100_vfetch: {linea[2:0], caracter}
    output reg  [9:0]  lb_addr,
    input  wire [23:0] lb_q,

    output reg  [7:0]  R,
    output reg  [7:0]  G,
    output reg  [7:0]  B,
    output reg         hsync,           // activo a nivel alto
    output reg         vsync,
    output reg         hblank,
    output reg         vblank
);
    localparam H_TOTAL   = 800;
    localparam H_IMG_STD = 48;
    localparam H_SYNC0   = 704;
    localparam V_TOTAL   = 525;
    localparam V_SYNC    = 2;
    localparam V_ACT0    = 35;          // 2 de vsync + 33 de porche
    localparam V_ACT1    = 515;         // 480 activas
    localparam V_IMG_STD = 75;          // 35 + 40 de borde
    localparam V_ADELANTO = 6;          // lineas de salida entre la trama del CRTC y la imagen

    //------------------------------------------------------------------
    // Lo que manda el CRTC en cada linea, guardado por linea (lin_n[2:0])
    //------------------------------------------------------------------
    reg [2:0] tgl_s;
    always @(posedge clk) tgl_s <= {tgl_s[1:0], linea_tgl};
    wire nueva = tgl_s[2] ^ tgl_s[1];

    reg [13:0] m_ma [0:7];
    reg [13:0] m_cursor [0:7];
    reg [4:0]  m_ra [0:7];
    reg [7:0]  m_chars [0:7];
    reg [7:0]  m_flags [0:7];           // {par, cur_on, screen1, col40, disp_on, visible}

    always @(posedge clk) if (nueva) begin
        m_ma[lin_n[2:0]]     <= lin_ma;
        m_cursor[lin_n[2:0]] <= lin_cursor;
        m_ra[lin_n[2:0]]     <= lin_ra;
        m_chars[lin_n[2:0]]  <= lin_chars;
        m_flags[lin_n[2:0]]  <= {2'b00, vga400 & lin_screen1, lin_cursor_on, lin_screen1,
                                 lin_col40, lin_display_on, lin_visible};
    end

    //------------------------------------------------------------------
    // Contadores, enganchados al principio de la trama del CRTC
    //------------------------------------------------------------------
    reg [9:0] hcnt, vcnt;
    wire [9:0] v_img0 = V_IMG_STD + {{4{v_off[4]}}, v_off, 1'b0};     // 59..87
    wire [9:0] v_enganche = v_img0 - V_ADELANTO;                       // vcnt al empezar la trama
    wire alineado = ((vcnt == v_enganche) && (hcnt <= 10'd2)) ||
                    ((vcnt == v_enganche - 10'd1) && (hcnt >= H_TOTAL - 3));

    always @(posedge clk) begin
        if (reset) begin
            hcnt <= 10'd0; vcnt <= 10'd0;
        end else if (nueva && lin_n == 9'd0 && !alineado) begin
            hcnt <= 10'd0; vcnt <= v_enganche;
        end else if (hcnt == H_TOTAL - 1) begin
            hcnt <= 10'd0;
            vcnt <= (vcnt == V_TOTAL - 1) ? 10'd0 : vcnt + 10'd1;
        end else hcnt <= hcnt + 10'd1;
    end

    //------------------------------------------------------------------
    // Linea de la imagen que toca, y lo que dijo el CRTC de ella
    //------------------------------------------------------------------
    wire [9:0] k = vcnt - v_img0;                   // linea de salida en la imagen
    wire       en_imagen = (vcnt >= v_img0) && (vcnt < v_img0 + 10'd400);
    wire [2:0] slot = k[3:1];                       // linea de la maquina k/2, en el anillo

    reg [13:0] ma, cursor;
    reg [4:0]  ra;
    reg [7:0]  chars;
    reg        visible, disp_on, col40, screen1, cur_on, par, media;
    always @(posedge clk) if (hcnt == 10'd0) begin
        ma      <= m_ma[slot];
        cursor  <= m_cursor[slot];
        ra      <= m_ra[slot];
        chars   <= m_chars[slot];
        visible <= en_imagen & m_flags[slot][0];
        disp_on <= m_flags[slot][1];
        col40   <= m_flags[slot][2];
        screen1 <= m_flags[slot][3];
        cur_on  <= m_flags[slot][4];
        par     <= m_flags[slot][5];
        media   <= k[0];
    end

    //------------------------------------------------------------------
    // Direccion del anillo: un punto por ciclo, se pide dos antes
    //------------------------------------------------------------------
    wire [9:0] H_IMG0 = H_IMG_STD + {{4{h_off[5]}}, h_off};
    wire [9:0] H_IMG1 = H_IMG0 + 10'd640;
    wire [9:0] hact   = hcnt - H_IMG0;
    wire       en_img = (hcnt >= H_IMG0) && (hcnt < H_IMG1);
    wire [3:0] dot    = col40 ? hact[3:0] : {1'b0, hact[2:0]};
    wire [3:0] dot_max = col40 ? 4'd15 : 4'd7;
    wire [6:0] idx    = col40 ? {1'b0, hact[9:4]} : hact[9:3];
    wire [9:0] pf0    = H_IMG0 - 10'd2;
    wire       prefetch = (hcnt == pf0) | (en_img & (dot == dot_max - 4'd1));
    wire [6:0] idx_pf = (hcnt == pf0) ? 7'd0 : idx + 7'd1;
    reg  [2:0] slot_l;
    always @(posedge clk) if (hcnt == 10'd0) slot_l <= slot;

    always @(posedge clk) if (prefetch) lb_addr <= {slot_l, idx_pf};

    // Con Screen 1 a 400 lineas el anillo trae {-, raster impar, raster par}
    wire [7:0] vid_b = (par & media) ? lb_q[15:8] : lb_q[7:0];
    wire [7:0] vid_r = lb_q[15:8];
    wire [7:0] vid_g = lb_q[23:16];

    //------------------------------------------------------------------
    // Registros de desplazamiento y color (como fp1100_display)
    //------------------------------------------------------------------
    reg [7:0] sh_b, sh_r, sh_g;
    reg       de, cursor_cell, pix2;
    wire      char_ok = ({3'd0, idx} < {2'd0, chars});
    wire      cursor_here = ((ma + {7'd0, idx}) == cursor) & cur_on;

    always @(posedge clk) begin
        if (en_img && dot == 4'd0) begin
            sh_b <= vid_b; sh_r <= vid_r; sh_g <= vid_g;
            de   <= visible & disp_on & char_ok;
            cursor_cell <= cursor_here & visible & char_ok;
            pix2 <= 1'b0;
        end else if (en_img) begin
            if (col40) pix2 <= ~pix2;
            if (~col40 | pix2) begin
                sh_b <= {1'b0, sh_b[7:1]};
                sh_r <= {1'b0, sh_r[7:1]};
                sh_g <= {1'b0, sh_g[7:1]};
            end
        end else begin
            de <= 1'b0; cursor_cell <= 1'b0;
        end
    end

    wire pb = screen1 ? (ra[3] ? sh_r[0] : sh_b[0]) : (pa[2] & sh_b[0]);
    wire pr = screen1 ? (ra[3] ? sh_r[0] : sh_b[0]) : (pa[1] & sh_r[0]);
    wire pg = screen1 ? (ra[3] ? sh_r[0] : sh_b[0]) : (pa[0] & sh_g[0]);
    wire verde = pa[4] & ~screen1;
    wire luma  = pb | pr | pg;

    wire [2:0] col_cursor = color_reg[7] ? 3'b111 : color_reg[6:4];   // {G,R,B}
    wire [2:0] col_borde  = color_reg[2:0];

    reg [2:0] col;
    always @* begin
        if (!de)              col = col_borde;
        else if (cursor_cell) col = col_cursor;
        else if (par)         col = {3{sh_b[0]}};           // monocromo, blanco
        else if (verde)       col = {luma, 1'b0, 1'b0};
        else                  col = {pg, pr, pb};
    end

    //------------------------------------------------------------------
    // Salida. El punto sale dos ciclos despues de su hcnt: la ventana de
    // imagen va con el mismo retraso. La vsync cambia al empezar la hsync.
    //------------------------------------------------------------------
    reg en_img_d;
    wire [7:0] nivel = (media & ~par & (scanlines != 2'd0)) ?
                       {~scanlines, 6'b000000} : 8'hFF;      // C0, 80, 40
    always @(posedge clk) begin
        R <= col[1] ? nivel : 8'h00;
        G <= col[2] ? nivel : 8'h00;
        B <= col[0] ? nivel : 8'h00;
        en_img_d <= en_img;
        hblank   <= ~en_img_d;
        vblank   <= (vcnt < V_ACT0) || (vcnt >= V_ACT1);
        hsync    <= (hcnt >= H_SYNC0);
        if (hcnt == H_SYNC0)
            vsync <= (vcnt == V_TOTAL - 1) || (vcnt < V_SYNC - 1);
    end

endmodule

`default_nettype wire
