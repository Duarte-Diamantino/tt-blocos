`default_nettype none

// Jogo de blocos 8x8 com saída VGA (PMOD TinyVGA no uo_out)
//   ui_in[0] esquerda   ui_in[1] direita   ui_in[2] rodar   ui_in[3] baixo
//   uo_out   VGA 640x480 @ 60 Hz (clock de 25,175 MHz)
//   uio_out  pontuação (linhas feitas) em binário, para 8 LEDs
module tt_um_duarte_diamantino_blocos (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);
    // ---- sincronismo VGA ----
    wire [9:0] h, v;
    wire       hsync, vsync, display_on, frame_tick;

    vga_sync sync (
        .clk(clk), .rst_n(rst_n), .h(h), .v(v),
        .hsync(hsync), .vsync(vsync), .display_on(display_on), .frame_tick(frame_tick)
    );

    // ---- botões: 2 flip-flops de sincronização ----
    reg [3:0] btn_s1, btn_s2;
    always @(posedge clk) begin
        btn_s1 <= ui_in[3:0];
        btn_s2 <= btn_s1;
    end

    // ---- posição no ecrã em células de 32x32 px ----
    wire [4:0] hc   = h[9:5];
    wire [4:0] vc   = v[9:5];
    wire [4:0] col5 = hc - 5'd6;        // o tabuleiro começa em x = 192
    wire [4:0] row5 = vc - 5'd3;        // e em y = 96
    wire [2:0] col  = col5[2:0];
    wire [2:0] row  = row5[2:0];
    wire       in_cols = (col5 < 5'd8);
    wire       in_rows = (row5 < 5'd8);

    // ---- jogo ----
    wire [7:0] vid_row_bits;
    wire [2:0] ptype, px, py;
    wire [1:0] prot;
    wire       piece_visible, game_over;
    wire [7:0] score;

    game g (
        .clk(clk), .rst_n(rst_n), .frame_tick(frame_tick), .btn(btn_s2),
        .vid_row(row), .vid_row_bits(vid_row_bits),
        .ptype(ptype), .prot(prot), .px(px), .py(py),
        .piece_visible(piece_visible), .game_over(game_over), .score(score)
    );

    // ---- desenho ----
    wire [15:0] vshape;
    pieces rom_video (.t(ptype), .rot(prot), .shape(vshape));

    wire [3:0] dr = {1'b0, row} - {1'b0, py};
    wire [3:0] dc = {1'b0, col} - {1'b0, px};
    wire piece_here = piece_visible && (dr[3:2] == 2'b00) && (dc[3:2] == 2'b00)
                      && vshape[{dr[1:0], dc[1:0]}];
    wire board_here = vid_row_bits[col];

    wire gap        = (h[4:0] == 5'd0) || (v[4:0] == 5'd0);     // linha de 1 px entre células
    wire wall       = ((hc == 5'd5 || hc == 5'd14) && vc >= 5'd3 && vc <= 5'd11)
                   || (vc == 5'd11 && hc >= 5'd5 && hc <= 5'd14);
    wire score_col  = (hc == 5'd16) && in_rows;
    wire score_here = score[3'd7 - row];                         // bit mais alto em cima

    // paleta própria, 2 bits por canal: {R1,R0,G1,G0,B1,B0}
    reg [5:0] piece_rgb;
    always @* begin
        case (ptype)
            3'd0:    piece_rgb = 6'b11_01_10;
            3'd1:    piece_rgb = 6'b01_11_10;
            3'd2:    piece_rgb = 6'b11_10_01;
            3'd3:    piece_rgb = 6'b10_01_11;
            3'd4:    piece_rgb = 6'b01_10_11;
            3'd5:    piece_rgb = 6'b11_11_01;
            default: piece_rgb = 6'b10_11_01;
        endcase
    end

    reg [5:0] rgb;
    always @* begin
        rgb = 6'b00_00_01;                                       // fundo
        if (wall) rgb = 6'b01_01_10;                             // paredes do poço
        if (in_cols && in_rows) begin
            rgb = 6'b00_00_00;                                   // célula vazia
            if (!gap) begin
                if (piece_here)      rgb = piece_rgb;
                else if (board_here) rgb = game_over ? 6'b10_00_00 : 6'b10_10_10;
            end
        end
        if (score_col && !gap) rgb = score_here ? 6'b11_10_00 : 6'b00_00_10;
        if (!display_on) rgb = 6'b00_00_00;
    end

    // saída registada, na ordem de pinos do PMOD TinyVGA:
    // {hsync, B0, G0, R0, vsync, B1, G1, R1}
    reg [7:0] vga_out;
    always @(posedge clk)
        vga_out <= {hsync, rgb[0], rgb[2], rgb[4], vsync, rgb[1], rgb[3], rgb[5]};

    assign uo_out  = vga_out;
    assign uio_out = score;
    assign uio_oe  = 8'hFF;

    wire _unused = &{ena, ui_in[7:4], uio_in, 1'b0};
endmodule
