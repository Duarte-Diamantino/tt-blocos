`default_nettype none

// Lógica do jogo: tabuleiro 8x8 (1 bit por célula), peça ativa e FSM.
// O tabuleiro é uma pequena RAM de 8 linhas x 8 bits feita de flip-flops D.
module game (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        frame_tick,     // 1 ciclo por imagem, no início do vblank
    input  wire [3:0]  btn,            // {baixo, rodar, direita, esquerda}, já sincronizados
    input  wire [2:0]  vid_row,        // porta de leitura do vídeo
    output wire [7:0]  vid_row_bits,
    output reg  [2:0]  ptype,
    output reg  [1:0]  prot,
    output reg  [2:0]  px,
    output reg  [2:0]  py,
    output wire        piece_visible,
    output wire        game_over,
    output reg  [7:0]  score
);
    localparam S_IDLE  = 3'd0,
               S_CHECK = 3'd1,
               S_LOCK  = 3'd2,
               S_CLEAR = 3'd3,
               S_SPAWN = 3'd4,
               S_OVER  = 3'd5;

    localparam A_MOVE  = 2'd0,
               A_DOWN  = 2'd1,
               A_SPAWN = 2'd2;

    reg [2:0]  state;
    reg [63:0] board;          // linha k = board[8*k +: 8]; bit c = coluna c

    // candidato a nova posição (só é aceite se não colidir)
    reg [2:0]  c_type;
    reg [1:0]  c_rot;
    reg [3:0]  c_px;           // 0..8
    reg [3:0]  c_py;           // 0..8
    reg [1:0]  act;
    reg [1:0]  r;              // linha da peça a verificar/escrever (uma por ciclo)
    reg        coll;
    reg [2:0]  clr_row;

    // ROM das peças (porta do jogo)
    wire [15:0] gshape;
    pieces rom_game (.t(c_type), .rot(c_rot), .shape(gshape));

    wire [3:0]  srow   = gshape[4*r +: 4];
    wire [3:0]  rowidx = c_py + {2'b00, r};
    wire [11:0] mask   = {8'd0, srow} << c_px;

    // porta de leitura do jogo, partilhada pela verificação e pela limpeza de linhas
    wire [2:0]  gidx   = (state == S_CLEAR) ? clr_row : rowidx[2:0];
    wire [7:0]  grow   = board[8*gidx +: 8];

    wire        oob    = (srow != 4'd0) && (rowidx[3] || (mask[11:8] != 4'd0));
    wire        hit    = |(grow & mask[7:0]);
    wire        full   = &grow;

    // botões: só contam no frame_tick (isto já elimina os ressaltos)
    reg  [3:0]  btn_prev;
    wire [3:0]  press = btn & ~btn_prev;

    // queda automática, mais rápida à medida que a pontuação sobe
    reg  [4:0]  fall_cnt;
    wire [3:0]  level      = (score[7:4] != 4'd0) ? 4'd15 : score[3:0];
    wire [4:0]  fall_limit = btn[3] ? 5'd2 : (5'd30 - {1'b0, level});
    wire        fall_due   = (fall_cnt >= fall_limit);

    // gerador pseudo-aleatório de 11 bits (período 2047, primo com 420000 ciclos/imagem)
    reg  [10:0] lfsr;
    wire [2:0]  new_type = (lfsr[2:0] == 3'd7) ? {1'b0, lfsr[4:3]} : lfsr[2:0];

    wire restart   = (state == S_OVER) && frame_tick && (|press);
    wire clear_all = !rst_n || restart;
    wire do_lock   = (state == S_LOCK) && !rowidx[3];
    wire do_shift  = (state == S_CLEAR) && full;

    // tabuleiro: escrever a peça (OR) e fazer descer as linhas acima de uma linha cheia
    wire [71:0] board_up = {board, 8'd0};   // board_up[8*k +: 8] = linha k-1 (0 para k = 0)

    genvar k;
    generate
        for (k = 0; k < 8; k = k + 1) begin : rows
            always @(posedge clk) begin
                if (clear_all)
                    board[8*k +: 8] <= 8'd0;
                else if (do_lock && rowidx[2:0] == k)
                    board[8*k +: 8] <= board[8*k +: 8] | mask[7:0];
                else if (do_shift && clr_row >= k)
                    board[8*k +: 8] <= board_up[8*k +: 8];
            end
        end
    endgenerate

    always @(posedge clk) begin
        if (!rst_n)
            lfsr <= 11'h001;
        else
            lfsr <= {lfsr[9:0], lfsr[10] ^ lfsr[8]};
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            state    <= S_SPAWN;
            score    <= 8'd0;
            btn_prev <= 4'd0;
            fall_cnt <= 5'd0;
            ptype    <= 3'd0;
            prot     <= 2'd0;
            px       <= 3'd0;
            py       <= 3'd0;
            c_type   <= 3'd0;
            c_rot    <= 2'd0;
            c_px     <= 4'd0;
            c_py     <= 4'd0;
            act      <= A_MOVE;
            r        <= 2'd0;
            coll     <= 1'b0;
            clr_row  <= 3'd0;
        end else begin
            case (state)
            // espera pela próxima imagem e escolhe uma ação
            S_IDLE: if (frame_tick) begin
                btn_prev <= btn;
                if (fall_cnt != 5'd31) fall_cnt <= fall_cnt + 5'd1;
                c_type <= ptype;
                c_rot  <= prot;
                c_px   <= {1'b0, px};
                c_py   <= {1'b0, py};
                act    <= A_MOVE;
                r      <= 2'd0;
                coll   <= 1'b0;
                if (press[2]) begin
                    c_rot <= prot + 2'd1;
                    state <= S_CHECK;
                end else if (press[0] && px != 3'd0) begin
                    c_px  <= {1'b0, px} - 4'd1;
                    state <= S_CHECK;
                end else if (press[1]) begin
                    c_px  <= {1'b0, px} + 4'd1;
                    state <= S_CHECK;
                end else if (fall_due) begin
                    c_py     <= {1'b0, py} + 4'd1;
                    act      <= A_DOWN;
                    fall_cnt <= 5'd0;
                    state    <= S_CHECK;
                end
            end

            // verifica as 4 linhas da peça candidata, uma por ciclo
            S_CHECK: begin
                r <= r + 2'd1;
                if (r == 2'd3) begin
                    coll <= 1'b0;
                    if (!(coll || oob || hit)) begin
                        ptype <= c_type;
                        prot  <= c_rot;
                        px    <= c_px[2:0];
                        py    <= c_py[2:0];
                        state <= S_IDLE;
                    end else if (act == A_DOWN) begin
                        c_py  <= {1'b0, py};      // volta à posição atual para a fixar
                        state <= S_LOCK;
                    end else if (act == A_SPAWN) begin
                        state <= S_OVER;
                    end else begin
                        state <= S_IDLE;          // movimento recusado
                    end
                end else begin
                    coll <= coll || oob || hit;
                end
            end

            // escreve a peça no tabuleiro, uma linha por ciclo
            S_LOCK: begin
                r <= r + 2'd1;
                if (r == 2'd3) begin
                    clr_row <= 3'd7;
                    state   <= S_CLEAR;
                end
            end

            // procura linhas cheias de baixo para cima
            S_CLEAR: begin
                if (full)
                    score <= score + 8'd1;      // as linhas descem; volta a testar a mesma
                else if (clr_row == 3'd0)
                    state <= S_SPAWN;
                else
                    clr_row <= clr_row - 3'd1;
            end

            // nova peça no topo
            S_SPAWN: begin
                c_type <= new_type;
                c_rot  <= 2'd0;
                c_px   <= 4'd2;
                c_py   <= 4'd0;
                act    <= A_SPAWN;
                r      <= 2'd0;
                coll   <= 1'b0;
                state  <= S_CHECK;
            end

            // fim de jogo: qualquer botão recomeça
            S_OVER: if (frame_tick) begin
                btn_prev <= btn;
                if (|press) begin
                    score <= 8'd0;
                    state <= S_SPAWN;
                end
            end

            default: state <= S_SPAWN;
            endcase
        end
    end

    assign vid_row_bits  = board[8*vid_row +: 8];
    assign piece_visible = (state != S_OVER);
    assign game_over     = (state == S_OVER);
endmodule
