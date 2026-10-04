//============================================================================
// FP-1100 - salida de video: puntos de 12,5 MHz, 800 por linea (VGA 640x480)
//
// La linea de la maquina son 1024 puntos de 16 MHz en 64 us, a 59,8 Hz y
// 261 lineas. Doblada, el monitor la ve como 31,25 kHz / 60 Hz y la toma por
// 640x480 VGA, que son 800 puntos por linea: muestrea la linea con SU reloj
// de 800 puntos. Si nosotros sacamos otro numero (1024 a 16 MHz, por
// ejemplo), cada punto nuestro cae entre dos suyos y las letras salen como
// ruido. Asi que aqui la linea son exactamente 800 puntos de 12,5 MHz (64
// us), que doblados son el 640x480 de 25 MHz que el monitor espera: 640 de
// imagen, 16 de porche, 96 de sincronismo y 48 de porche. Sin borde (no
// cabe). (Se probo con la imagen 8 puntos mas a la derecha, 56 y 8, y en
// otros monitores salia desplazada: se deja el VGA estandar.)
//
// Ojo, los 64 us por linea no son de PAL: la maquina hace 128 caracteres de
// 8 puntos a 16 MHz = 64 us, y con 261 lineas sale a 59,8 Hz.
//
// Reloj: clk_pix = 25 MHz, del mismo PLL que el sistema de 32 MHz (en
// Poseidon los dos salen de un VCO de 800 MHz). La relacion 25/32 es
// exacta, asi que 1024 puntos de 16 MHz duran lo mismo que 800 de 12,5 y el
// contador de puntos corre LIBRE: se alinea con la linea del CRTC al
// arrancar y ya no se mueve. Solo se realinea si el toggle del CRTC llega a
// mas de dos puntos de donde toca (el sub cambiando la longitud de linea).
// Reiniciarlo en cada linea mete el jitter del sincronizador en cada hsync
// y la imagen tiembla como agua.
//
// Lo que se toma del CRTC (fp1100_video, en clk_sys) al empezar cada linea:
// MA del primer caracter, raster, visible, vsync, caracteres por linea y
// cursor, con un toggle sincronizado por dos flip-flops.
//
// Los datos de VRAM no se leen aqui: los deja fp1100_vfetch en un buffer de
// linea mientras el CRTC recorre la linea, y se dibujan en la siguiente. Por
// eso todo lo que se toma del CRTC se retrasa una linea (p_*), vsync
// incluida: la imagen sale igual, una linea mas tarde.
//
// Centrado (como en el NewBrain): h_off mueve la imagen dentro de la linea
// (el sincronismo queda fijo); v_off mueve la vsync respecto a las lineas.
//
// Sincronismos segun la salida (tv15):
//   15 kHz  hsync de 59 puntos (4,7 us, el de la television) y la vsync del
//           CRTC (16 lineas) retrasada 0..16 lineas (8 por defecto).
//   31 kHz  (scandoubler o modo31) los de VGA 640x480: hsync de 96 puntos y
//           vsync de UNA linea de la maquina (2 de salida), colocada para que
//           las 400 lineas queden en medio de las 480 de VGA: 2 de vsync + 33
//           de porche + 40 de borde = la imagen 75 lineas despues del
//           principio de la vsync. Con la vsync de 16 lineas del CRTC (32 de
//           salida) los monitores y el OSSC, que cuentan el porche desde el
//           final de la vsync, se comian las lineas de arriba.
//
// El bit 0 de cada byte de VRAM es el pixel de la izquierda. Los planos son
// B, R y G, con sus habilitaciones en PA2, PA1 y PA0; con PA4 (pantalla
// verde) se hace el OR de los tres. SCREEN 1 (16 rasters por fila, R9 >= 8):
// los planos hacen de una sola pagina mono, RA 0-7 en B y 8-15 en R.
// Cursor: color b6-4 del registro de color si b7 = 0, si no blanco.
//
// hsync_cs: para el compuesto de 15 kHz que forma mist_video con ~(hs ^ vs):
// en las lineas de vsync el pulso va justo antes del sincronismo normal,
// para que el flanco de bajada del compuesto caiga en el mismo punto en
// todas las lineas.
//============================================================================
`default_nettype none

module fp1100_display (
    input  wire        clk_pix,         // 25 MHz
    input  wire        reset,
    output wire        ce_pix,          // 12,5 MHz (25 en modo31)
    input  wire        vga400,          // Screen 1 en 400 lineas a 31 kHz (OSD)
    output reg         modo31,          // sacando 31 kHz propios: sin scandoubler
    input  wire signed [5:0] h_off,     // puntos, + = a la derecha (-32..+12)
    input  wire signed [4:0] v_off,     // lineas, + = hacia abajo
    input  wire        tv15,            // salida a 15 kHz (sin scandoubler)

    // del CRTC (clk_sys)
    input  wire        linea_tgl,
    input  wire [13:0] lin_ma,
    input  wire [4:0]  lin_ra,
    input  wire        lin_visible,
    input  wire        lin_vsync,
    input  wire [7:0]  lin_chars,
    input  wire        lin_col40,
    input  wire        lin_display_on,
    input  wire        lin_screen1,
    input  wire [13:0] lin_cursor,
    input  wire        lin_cursor_on,
    input  wire        libre,           // 1: solo se alinea la primera vez (diagnostico)

    input  wire [7:0]  pa,
    input  wire [7:0]  color_reg,

    // buffer de linea (fp1100_vfetch, en clk_pix): {banco, caracter}
    output reg  [7:0]  lb_addr,
    input  wire [23:0] lb_q,            // {G, R, B}

    output reg  [7:0]  R,
    output reg  [7:0]  G,
    output reg  [7:0]  B,
    output reg         hsync,           // activo a nivel alto
    output reg         hsync_cs,        // idem para el sincronismo compuesto
    output reg         vsync,
    output reg         hblank,
    output reg         vblank
);
    localparam H_TOTAL  = 800;
    localparam H_IMG_STD = 48;          // porche trasero de VGA
    localparam H_SYNC0  = 704;          // 640 + 48 + 16 de porche delantero
    localparam H_SYNC1  = 800;          // 31 kHz: 96 puntos, VGA
    localparam H_SYNC1_TV = 763;        // 15 kHz: 59 puntos, 4,72 us
    localparam H_CS0    = 645;          // hsync_cs en las lineas de vsync (15 kHz)
    localparam H_CS1    = 704;

    // Comienzo de la imagen con el ajuste del menu (32..60 con el rango de
    // -16..+12): deja siempre 4 puntos o mas antes del sincronismo. El
    // sincronismo no se mueve: el monitor coloca la imagen contando desde
    // el, asi que llevarla a la derecha se come el porche delantero.
    wire [9:0] H_IMG0 = H_IMG_STD + {{4{h_off[5]}}, h_off};
    wire [9:0] H_IMG1 = H_IMG0 + 10'd640;

    // En modo31 todo va a 25 MHz: dos lineas de 800 puntos por cada linea
    // del CRTC (ver mas abajo).
    reg ce_mitad;
    always @(posedge clk_pix) ce_mitad <= reset ? 1'b0 : ~ce_mitad;
    assign ce_pix = ce_mitad | modo31;

    //------------------------------------------------------------------
    // Sincronizacion con el CRTC y captura de los datos de la linea
    //------------------------------------------------------------------
    reg [2:0] tgl_s;
    always @(posedge clk_pix) tgl_s <= {tgl_s[1:0], linea_tgl};
    wire nueva_linea = tgl_s[2] ^ tgl_s[1];

    reg [13:0] ma;
    reg [4:0]  ra;
    reg        visible, vs, col40, disp_on, screen1, cur_on;
    reg [7:0]  chars;
    reg [13:0] cursor;
    reg        banco;               // banco del buffer que se dibuja
    // lo tomado del CRTC en la linea anterior (la que el buffer ya tiene)
    reg [13:0] p_ma, p_cursor;
    reg [4:0]  p_ra;
    reg        p_visible, p_vs, p_col40, p_disp_on, p_screen1, p_cur_on;
    reg [7:0]  p_chars;
    reg [9:0]  hcnt;
    reg        arrancado;

    // El contador de puntos corre LIBRE: las dos lineas duran exactamente lo
    // mismo (1024 puntos a 16 MHz y 800 a 12,5, los dos relojes salen del
    // mismo PLL), asi que una vez alineado no se mueve. Solo se realinea
    // cuando el toggle del CRTC llega lejos de donde toca (al arrancar, o si
    // el sub cambiase la longitud de linea), y siempre en un flanco del ce
    // de pixel. Reiniciarlo en cada linea, como se hacia al principio, metia
    // el jitter de un ciclo del sincronizador en cada hsync y la imagen (y el
    // OSD) temblaban como agua.
    //
    // Modo31 (Screen 1 con "400 lines"): el Screen 1 es entrelazado, 400
    // lineas en dos tramas de 200. Con el scandoubler cada trama se pinta
    // doblada y las dos se alternan en las mismas lineas. En modo31 no se
    // usa el scandoubler: este modulo saca 31 kHz el mismo, con el contador
    // de puntos a 25 MHz, y en cada linea del CRTC pinta DOS lineas: la
    // raster par y la impar de esa fila (media = 0 y 1), que el lector de
    // linea trae juntas de la VRAM. Como las saca de la VRAM y no del barrido
    // del CRTC, las dos tramas dan la misma imagen de 400 lineas completa:
    // 640x400 progresivo a 31 kHz y 59,8 Hz, sin memoria de trama.
    reg realinear;
    reg media;                                       // modo31: segunda linea
    wire [9:0] desfase = hcnt;                       // donde deberia ser 0
    wire alineado = modo31 ? ((desfase <= 10'd2 & ~media) | (desfase >= H_TOTAL - 2 & media))
                           : ((desfase <= 10'd2) | (desfase >= H_TOTAL - 2));

    always @(posedge clk_pix) begin
        if (reset) begin
            hcnt <= 10'd0; arrancado <= 1'b0; realinear <= 1'b0;
            media <= 1'b0; modo31 <= 1'b0;
        end else begin
            if (nueva_linea) begin
                ma        <= p_ma;
                ra        <= p_ra;
                visible   <= p_visible;
                vs        <= p_vs;
                chars     <= p_chars;
                col40     <= p_col40;
                disp_on   <= p_disp_on;
                screen1   <= p_screen1;
                cursor    <= p_cursor;
                cur_on    <= p_cur_on;
                banco     <= tgl_s[2];          // el valor de antes del cambio
                modo31    <= vga400 & p_screen1;
                p_ma      <= lin_ma;
                p_ra      <= lin_ra;
                p_visible <= lin_visible;
                p_vs      <= lin_vsync;
                p_chars   <= lin_chars;
                p_col40   <= lin_col40;
                p_disp_on <= lin_display_on;
                p_screen1 <= lin_screen1;
                p_cursor  <= lin_cursor;
                p_cur_on  <= lin_cursor_on;
                if (!arrancado || (!alineado && !libre)) realinear <= 1'b1;
            end
            if (ce_pix) begin
                if (realinear) begin
                    hcnt      <= 10'd0;
                    media     <= 1'b0;
                    realinear <= 1'b0;
                    arrancado <= 1'b1;
                end else if (arrancado) begin
                    hcnt <= (hcnt == H_TOTAL - 1) ? 10'd0 : hcnt + 10'd1;
                    if (hcnt == H_TOTAL - 1) media <= modo31 & ~media;
                end
            end
        end
    end

    //------------------------------------------------------------------
    // Vsync retrasada 0..15 lineas (8 por defecto, v_off la mueve)
    //------------------------------------------------------------------
    reg  [16:0] vs_hist;
    always @(posedge clk_pix) if (nueva_linea) vs_hist <= {vs_hist[15:0], p_vs};
    wire [4:0] vs_idx = 5'd8 - v_off;       // v_off -8..+8 -> 16..0
    wire vs_ret = vs_hist[vs_idx];

    //------------------------------------------------------------------
    // 31 kHz: vsync de VGA, una linea de la maquina. Se cuentan las lineas
    // desde el principio de la vsync del CRTC (vs_hist[0], la referencia de
    // vs_idx = 0) y se mide el periodo de la trama, para poder ponerla
    // ANTES que la del CRTC: hace falta, porque la del CRTC empieza 35
    // lineas antes de la imagen y para centrar las 400 lineas en VGA tiene
    // que empezar 37,5 antes. vs_pos = lineas desde esa referencia (negativo:
    // antes); -2 por defecto, y v_off la adelanta (+ = imagen mas abajo).
    //------------------------------------------------------------------
    reg  [8:0] vlin, vperiodo;
    wire       vs_ini = p_vs & ~vs_hist[0];     // vs_hist[0] pasa a 1 en esta linea
    always @(posedge clk_pix) begin
        if (reset) begin
            vlin <= 9'd0; vperiodo <= 9'd0;
        end else if (nueva_linea) begin
            if (vs_ini) begin
                vperiodo <= vlin + 9'd1;
                vlin     <= 9'd0;
            end else if (vlin != 9'h1FF) vlin <= vlin + 9'd1;
        end
    end
    wire signed [5:0] vs_pos = -6'sd2 - {v_off[4], v_off};
    wire [8:0] vs_lin31 = vs_pos[5] ? (vperiodo + {{3{vs_pos[5]}}, vs_pos}) : {3'd0, vs_pos};
    wire vs_31 = (vlin == vs_lin31);
    wire vs_sel = tv15 ? vs_ret : vs_31;

    //------------------------------------------------------------------
    // Direccion del buffer de linea: se pone en el ultimo punto de cada
    // caracter para el siguiente; la block RAM la sirve un ciclo despues y
    // el ce de 12,5 MHz deja dos (en modo31, un punto antes).
    //------------------------------------------------------------------
    wire [9:0] hact = hcnt - H_IMG0;                    // punto dentro de la imagen
    wire       en_img = (hcnt >= H_IMG0) && (hcnt < H_IMG1);
    wire [3:0] dot    = col40 ? hact[3:0] : {1'b0, hact[2:0]};
    wire [3:0] dot_max = col40 ? 4'd15 : 4'd7;
    wire [6:0] idx    = col40 ? {1'b0, hact[9:4]} : hact[9:3];  // caracter actual
    wire [6:0] idx_sig = idx + 7'd1;
    // En modo31 hay un punto por ciclo: la direccion se pone un punto antes
    // para que el dato llegue a tiempo
    wire [9:0] pf0      = H_IMG0 - (modo31 ? 10'd2 : 10'd1);
    wire       prefetch = (hcnt == pf0) | (en_img & (dot == dot_max - {3'd0, modo31}));
    wire [6:0] idx_pf = (hcnt == pf0) ? 7'd0 : idx_sig;

    always @(posedge clk_pix) begin
        if (ce_pix & prefetch) lb_addr <= {banco, idx_pf};
    end

    // En modo31 el buffer trae {-, raster impar, raster par}, ya del plano
    // que toca (B para las rasters 0-7 de la fila, R para las 8-15)
    wire [7:0] vid_b = (modo31 & media) ? lb_q[15:8] : lb_q[7:0];
    wire [7:0] vid_r = lb_q[15:8];
    wire [7:0] vid_g = lb_q[23:16];

    //------------------------------------------------------------------
    // Registros de desplazamiento y color
    //------------------------------------------------------------------
    reg [7:0] sh_b, sh_r, sh_g;
    reg       de, cursor_cell, pix2;
    wire      char_ok = ({3'd0, idx} < {2'd0, chars});
    wire      cursor_here = ((ma + {7'd0, idx}) == cursor) & cur_on;

    always @(posedge clk_pix) begin
        if (ce_pix) begin
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
        else if (modo31)      col = {3{sh_b[0]}};           // monocromo, blanco
        else if (verde)       col = {luma, 1'b0, 1'b0};
        else                  col = {pg, pr, pb};
    end

    // La vsync cambia solo al empezar la hsync, como en VGA.
    // vs_ret y visible cambian con nueva_linea, que cae a +-2 puntos del
    // final de la hsync segun como haya quedado alineado el contador tras
    // un reset: si la vsync cambiaba ahi, el scandoubler (y el monitor) a
    // veces la veian en una linea y a veces en la siguiente, tramas alternas
    // desplazadas media linea, y el monitor lo tomaba por entrelazado
    // (960i) despues de cada reset o carga de la ROM.
    reg vs_linea;
    reg en_img_d;
    always @(posedge clk_pix) begin
        if (ce_pix) begin
            if (hcnt == H_SYNC0) vs_linea <= vs_sel;
            R <= {8{col[1]}};
            G <= {8{col[2]}};
            B <= {8{col[0]}};
            // el punto sale dos ce despues de su hcnt (registro de
            // desplazamiento y registro de salida): la ventana de la imagen
            // va con el mismo retraso. Antes iba uno antes y el ultimo punto
            // de la derecha (x = 639) caia en la zona borrada.
            en_img_d <= en_img;
            hblank   <= ~en_img_d;
            vblank   <= ~visible;
            hsync    <= (hcnt >= H_SYNC0) && (hcnt < (tv15 ? H_SYNC1_TV : H_SYNC1));
            hsync_cs <= vs_linea ? ((hcnt >= H_CS0) && (hcnt < H_CS1))
                                 : ((hcnt >= H_SYNC0) && (hcnt < (tv15 ? H_SYNC1_TV : H_SYNC1)));
            vsync    <= vs_linea;
        end
    end

endmodule

`default_nettype wire
