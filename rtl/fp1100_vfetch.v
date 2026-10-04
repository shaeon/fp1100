//============================================================================
// FP-1100 - lector de linea de VRAM y buffer de linea
//
// El video ya no lee la VRAM punto a punto: al empezar cada linea del CRTC
// este modulo lee de la VRAM los bytes de los tres planos de esa linea (80
// caracteres como mucho) y los deja en un buffer de linea; fp1100_display los
// dibuja durante la linea SIGUIENTE. Asi la VRAM puede estar en SDRAM: en vez
// de un acceso con plazo de 640 ns por caracter, hay 80 accesos a repartir
// en 64 us. Toda la imagen (y la vsync con ella) sale una linea mas tarde.
//
// El buffer tiene dos bancos: mientras se llena uno, el video lee el otro.
// Banco = valor de linea_tgl tras el cambio que abre la linea.
//
// Puerto de lectura generico (vale para SDRAM y para block RAM):
//   rd   pulso con addr (direccion de VRAM, 14 bits, la misma para los tres
//        planos); una peticion cada vez
//   ack  pulso con q = {-, G, R, B}
//   Con par = 1 (modo31, Screen 1 en 400 lineas: ver fp1100_display) addr
//   es par y se piden addr y addr+1, las rasters par e impar de la fila, de
//   los planos B y R: q = {R(addr+1), B(addr+1), R(addr), B(addr)}. Aqui se
//   elige el plano (B para las rasters 0-7, R para las 8-15) y el buffer
//   guarda {-, impar, par}. Una sola peticion por caracter, como siempre.
//
// Para la salida de 31 kHz propia (fp1100_vga, macro VGA_525 del top) cada
// linea se escribe ademas en un anillo de 8 lineas, {lin_n[2:0], caracter},
// que se lee con el reloj de VGA: aquel saca 525 lineas por cada 261 de la
// maquina y va adelantandose poco a poco, asi que no le basta con la linea
// anterior. Si no se usa, Quartus lo quita.
//============================================================================
`default_nettype none

module fp1100_vfetch (
    input  wire        clk,
    input  wire        reset,

    // del CRTC (fp1100_video, mismo reloj)
    input  wire        linea_tgl,
    input  wire [13:0] lin_ma,
    input  wire [8:0]  lin_n,
    input  wire [4:0]  lin_ra,
    input  wire        lin_visible,
    input  wire        lin_display_on,
    input  wire [7:0]  lin_chars,
    input  wire        lin_screen1,
    input  wire        vga400,          // Screen 1 en 400 lineas (modo31)

    // lectura de VRAM
    output reg         rd,
    output reg         par,             // pedir dos rasters (ver abajo)
    output reg  [13:0] addr,
    input  wire        ack,
    input  wire [31:0] q,

    // lado del video
    input  wire        clk_pix,
    input  wire [7:0]  lb_addr,         // {banco, caracter}
    output reg  [23:0] lb_q,

    // lado de fp1100_vga
    input  wire        clk_vga,
    input  wire [9:0]  lb31_addr,       // {linea[2:0], caracter}
    output reg  [23:0] lb31_q
);
    reg        tgl_d;
    reg        banco;
    reg [13:0] ma;
    reg [3:0]  ra;
    reg        modo_par;
    reg [6:0]  i, n;
    reg        activo, esperando;
    reg        rq_banco;
    reg [6:0]  rq_i;
    reg [2:0]  linea, rq_linea;

    reg [23:0] lb [0:255];
    reg        lb_we;
    reg [7:0]  lb_wa;
    reg [23:0] lb_wd;
    reg [23:0] lb31 [0:1023];
    reg [9:0]  lb31_wa;

    wire       nueva = (linea_tgl != tgl_d);
    wire [13:0] ma_i = ma + {7'd0, i};

    always @(posedge clk) begin
        rd    <= 1'b0;
        lb_we <= 1'b0;
        tgl_d <= linea_tgl;

        if (reset) begin
            activo    <= 1'b0;
            esperando <= 1'b0;
        end else begin
            if (nueva) begin
                banco  <= linea_tgl;
                linea  <= lin_n[2:0];
                ma     <= lin_ma;
                ra     <= lin_ra[3:0];
                modo_par <= vga400 & lin_screen1;
                i      <= 7'd0;
                n      <= (lin_chars > 8'd80) ? 7'd80 : lin_chars[6:0];
                activo <= lin_visible & lin_display_on & (lin_chars != 8'd0);
            end

            // Cada dato va a donde se pidio (banco e indice guardados con la
            // peticion), aunque la linea haya cambiado entretanto
            if (esperando && ack) begin
                lb_we     <= 1'b1;
                lb_wa     <= {rq_banco, rq_i};
                lb31_wa   <= {rq_linea, rq_i};
                lb_wd     <= !modo_par ? q[23:0] :
                             ra[3] ? {8'h00, q[31:24], q[15:8]} : {8'h00, q[23:16], q[7:0]};
                esperando <= 1'b0;
            end else if (activo && !esperando && !nueva) begin
                rd        <= 1'b1;
                addr      <= {ma_i[10:0], ra[2:1], ra[0] & ~modo_par};
                par       <= modo_par;
                rq_banco  <= banco;
                rq_linea  <= linea;
                rq_i      <= i;
                esperando <= 1'b1;
                i         <= i + 7'd1;
                if (i + 7'd1 == n) activo <= 1'b0;
            end
        end
    end

    // Buffer: escribe clk (sistema), lee clk_pix. Una M9K.
    always @(posedge clk) if (lb_we) lb[lb_wa] <= lb_wd;
    always @(posedge clk_pix) lb_q <= lb[lb_addr];

    // Anillo de 8 lineas para fp1100_vga: escribe clk, lee clk_vga
    always @(posedge clk) if (lb_we) lb31[lb31_wa] <= lb_wd;
    always @(posedge clk_vga) lb31_q <= lb31[lb31_addr];

endmodule

`default_nettype wire
