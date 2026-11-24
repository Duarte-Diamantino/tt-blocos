`default_nettype none

// Formas das 7 peças, 4 rotações cada, alinhadas ao canto superior esquerdo
// de uma caixa 4x4.  shape[4*r + c] = célula da linha r, coluna c.
module pieces (
    input  wire [2:0]  t,
    input  wire [1:0]  rot,
    output reg  [15:0] shape
);
    always @* begin
        case ({t, rot})
            // 0: barra
            5'b000_00, 5'b000_10: shape = 16'h000F;
            5'b000_01, 5'b000_11: shape = 16'h1111;
            // 1: quadrado
            5'b001_00, 5'b001_01,
            5'b001_10, 5'b001_11: shape = 16'h0033;
            // 2: T
            5'b010_00: shape = 16'h0027;
            5'b010_01: shape = 16'h0232;
            5'b010_10: shape = 16'h0072;
            5'b010_11: shape = 16'h0131;
            // 3: S
            5'b011_00, 5'b011_10: shape = 16'h0036;
            5'b011_01, 5'b011_11: shape = 16'h0231;
            // 4: Z
            5'b100_00, 5'b100_10: shape = 16'h0063;
            5'b100_01, 5'b100_11: shape = 16'h0132;
            // 5: J
            5'b101_00: shape = 16'h0071;
            5'b101_01: shape = 16'h0113;
            5'b101_10: shape = 16'h0047;
            5'b101_11: shape = 16'h0322;
            // 6: L
            5'b110_00: shape = 16'h0074;
            5'b110_01: shape = 16'h0311;
            5'b110_10: shape = 16'h0017;
            5'b110_11: shape = 16'h0223;
            default:   shape = 16'h0000;
        endcase
    end
endmodule
