`timescale 1ns/1ps
`default_nettype none

// Testbench: testa a lógica do jogo em "modo rápido" (frame_tick forçado a cada
// 64 ciclos em vez de 420000) e grava uma imagem VGA real (640x480) em frame.ppm.
module tb;
    reg clk = 1'b0;
    always #20 clk = ~clk;                       // ~25 MHz

    reg        rst_n = 1'b0;
    reg  [7:0] ui_in = 8'd0;
    wire [7:0] uo_out, uio_out, uio_oe;

    tt_um_duarte_diamantino_blocos dut (
        .ui_in(ui_in), .uo_out(uo_out), .uio_in(8'd0), .uio_out(uio_out),
        .uio_oe(uio_oe), .ena(1'b1), .clk(clk), .rst_n(rst_n)
    );

    localparam LEFT = 0, RIGHT = 1, ROT = 2, DOWN = 3;
    localparam S_SPAWN = 3'd4;

    // frame_tick rápido
    reg  [5:0] fcnt = 6'd0;
    always @(posedge clk) fcnt <= fcnt + 6'd1;
    wire fast_tick = (fcnt == 6'd0);

    integer spawns = 0;
    always @(posedge clk) if (dut.g.state == S_SPAWN) spawns <= spawns + 1;

    // posição do pixel que está em uo_out (a saída é registada: 1 ciclo de atraso)
    reg [9:0] hq, vq;
    always @(posedge clk) begin
        hq <= dut.h;
        vq <= dut.v;
    end

    integer errors = 0;
    integer seed   = 7;

    task wait_ticks(input integer n);
        integer i;
        begin
            for (i = 0; i < n; i = i + 1) begin
                @(negedge clk);
                while (dut.frame_tick !== 1'b1) @(negedge clk);
            end
        end
    endtask

    task press(input integer b);
        begin
            ui_in[b] = 1'b1; wait_ticks(2);
            ui_in[b] = 1'b0; wait_ticks(2);
        end
    endtask

    task presses(input integer b, input integer n);
        integer i;
        begin
            for (i = 0; i < n; i = i + 1) press(b);
        end
    endtask

    // carrega em "baixo" até a peça assentar e aparecer a seguinte
    task drop;
        integer s0, guard;
        begin
            s0 = spawns;
            guard = 0;
            ui_in[DOWN] = 1'b1;
            while (spawns == s0 && guard < 200000) begin
                @(negedge clk);
                guard = guard + 1;
            end
            ui_in[DOWN] = 1'b0;
            if (guard >= 200000) begin
                $display("  FALHA a peca nao assentou");
                errors = errors + 1;
            end
            wait_ticks(1);
        end
    endtask

    task show_board;
        integer rr, cc;
        reg [7:0] row;
        begin
            for (rr = 0; rr < 8; rr = rr + 1) begin
                row = dut.g.board >> (8 * rr);
                $write("        |");
                for (cc = 0; cc < 8; cc = cc + 1) $write("%s", row[cc] ? "#" : ".");
                $write("|\n");
            end
            $display("        pontos=%0d  game_over=%0d", dut.g.score, dut.g.game_over);
        end
    endtask

    task check(input cond, input [8*64-1:0] msg);
        begin
            if (cond) $display("  OK    %0s", msg);
            else begin
                $display("  FALHA %0s", msg);
                errors = errors + 1;
            end
        end
    endtask

    // grava uma imagem completa a partir dos pinos VGA
    task capture_frame;
        integer fd, n, hs_low, vs_low;
        reg [1:0] R, G, B;
        begin
            release dut.frame_tick;
            @(negedge clk);
            while (!(hq == 10'd0 && vq == 10'd0)) @(negedge clk);
            fd = $fopen("frame.ppm", "w");
            $fwrite(fd, "P3\n640 480\n3\n");
            hs_low = 0;
            vs_low = 0;
            for (n = 0; n < 800 * 525; n = n + 1) begin
                if (hq < 10'd640 && vq < 10'd480) begin
                    R = {uo_out[0], uo_out[4]};
                    G = {uo_out[1], uo_out[5]};
                    B = {uo_out[2], uo_out[6]};
                    $fwrite(fd, "%0d %0d %0d\n", R, G, B);
                end
                if (!uo_out[7]) hs_low = hs_low + 1;
                if (!uo_out[3]) vs_low = vs_low + 1;
                @(negedge clk);
            end
            $fclose(fd);
            check(hs_low == 525 * 96, "HSync: 96 ciclos a 0 por linha");
            check(vs_low == 2 * 800,  "VSync: 2 linhas a 0 por imagem");
            force dut.frame_tick = fast_tick;
        end
    endtask

    integer n, m, rots, lines;

    initial begin
        force dut.frame_tick = fast_tick;
        force dut.g.new_type = 3'd0;                       // só barras
        repeat (10) @(negedge clk);
        rst_n = 1'b1;
        wait_ticks(2);

        $display("Teste A: duas barras completam uma linha");
        presses(LEFT, 3);
        check(dut.g.px == 0, "a parede esquerda trava a peca (px = 0)");
        drop;
        check(dut.g.board[63:56] == 8'h0F, "barra assentou na linha 7, colunas 0-3");
        force dut.g.new_type = 3'd1;                       // a seguir: quadrados
        presses(RIGHT, 2);
        drop;
        check(dut.g.score == 1,      "linha completa conta 1 ponto");
        check(dut.g.board == 64'd0,  "linha completa foi apagada");

        $display("Teste B: quatro quadrados completam duas linhas");
        presses(LEFT, 2);  drop;
        drop;
        presses(RIGHT, 2); drop;
        force dut.g.new_type = 3'd0;                       // a seguir: barra
        presses(RIGHT, 4); drop;
        check(dut.g.score == 3,      "duas linhas de uma vez: 3 pontos no total");
        check(dut.g.board == 64'd0,  "tabuleiro ficou vazio");

        $display("Teste C: rotacao e paredes");
        press(ROT);
        check(dut.g.prot == 1, "barra rodou para a vertical");
        presses(RIGHT, 6);
        check(dut.g.px == 7,   "a parede direita trava a peca (px = 7)");
        press(ROT);
        check(dut.g.prot == 1, "rotacao contra a parede foi recusada");
        release dut.g.new_type;                            // a partir daqui, peças aleatórias
        drop;
        check(dut.g.board == 64'h80808080_00000000, "barra vertical assentou na coluna 7");
        show_board;

        $display("Teste D: jogo aleatorio ate ao game over, imagem VGA e recomeco");
        n = 0;
        while (!dut.g.game_over && n < 200) begin
            rots = {$random(seed)} % 4;
            m    = ({$random(seed)} % 9) - 4;
            presses(ROT, rots);
            if (m < 0) presses(LEFT, -m); else presses(RIGHT, m);
            if (n == 2) begin
                ui_in[DOWN] = 1'b1; wait_ticks(5); ui_in[DOWN] = 1'b0; wait_ticks(1);
                $display("  a gravar uma imagem VGA a meio do jogo...");
                show_board;
                capture_frame;
            end
            drop;
            n = n + 1;
        end
        lines = dut.g.score;
        check(dut.g.game_over == 1, "o jogo acaba quando a peca nova ja nao cabe");
        show_board;
        $display("  pecas jogadas ao calhas: %0d, pontos no fim: %0d", n, lines);
        press(ROT);
        check(dut.g.game_over == 0 && dut.g.score == 0 && dut.g.board == 64'd0,
              "um botao recomeca o jogo com tudo limpo");

        if (errors == 0) $display("\nTODOS OS TESTES PASSARAM");
        else             $display("\n%0d FALHAS", errors);
        $finish;
    end
endmodule
