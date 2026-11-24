`default_nettype none

// Sincronismo VGA 640x480 @ 60 Hz (clock de pixel 25,175 MHz)
module vga_sync (
    input  wire       clk,
    input  wire       rst_n,
    output reg  [9:0] h,
    output reg  [9:0] v,
    output wire       hsync,       // ativo a 0
    output wire       vsync,       // ativo a 0
    output wire       display_on,
    output wire       frame_tick   // 1 ciclo no início do vblank
);
    always @(posedge clk) begin
        if (!rst_n) begin
            h <= 10'd0;
            v <= 10'd0;
        end else if (h == 10'd799) begin
            h <= 10'd0;
            v <= (v == 10'd524) ? 10'd0 : v + 10'd1;
        end else begin
            h <= h + 10'd1;
        end
    end

    assign hsync      = ~((h >= 10'd656) && (h < 10'd752));
    assign vsync      = ~((v >= 10'd490) && (v < 10'd492));
    assign display_on = (h < 10'd640) && (v < 10'd480);
    assign frame_tick = (h == 10'd0) && (v == 10'd480);
endmodule
