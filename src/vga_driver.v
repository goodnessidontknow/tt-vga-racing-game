/*
 * NOT the racing game for VGA: dodge the traffic.
 *
 * To play, open Inspect > VGA output and press Run. Use the switches under the
 * picture, or the keyboard:
 *   ui_in[0]  steer left     (Left arrow, A or 1)
 *   ui_in[1]  steer right    (Right arrow, D or 2)
 *   ui_in[2]  boost          (Up arrow, W, Space or 3)
 *
 * The score bar at the top grows while you survive, and the traffic spe0eds up
 * as it grows. A crash flashes the screen red and starts the run again.
 *
 * How this file is laid out:
 *   1. SETTINGS   Colours, sizes and speeds. Change anything here and press Run.
 *   2. WIRING     The pins and the sync generator. Leave this as it is.
 *   3. THE GAME   The rules: steering, traffic, crashes and the score.
 *   4. DRAWING    The colour of every pixel, from where things are.
 */

`default_nettype none

module tt_um_goodnessidontknow_vga_racing_game (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);

    // ========================================================================
    // 1. SETTINGS
    //    Change these freely. Nothing below needs editing when you do.
    // ========================================================================

    // Sizes, in pixels. The screen is 640 wide and 480 tall.
    localparam [9:0] GROUND_H  = 10'd2;
    localparam [9:0] GROUND_Y  = 10'd416;
    localparam [9:0] CAR_W     = 10'd24;
    localparam [9:0] CAR_H     = 10'd40;
    localparam [9:0] WARRIOR_X    = 10'd160;  // the part you can drive on
    localparam [9:0] TRAFFIC_W = 10'd32;   // keep to 48 or less, or it overhangs the kerb, ALSO KEEP AT A POWER OF 2
    localparam [9:0] TRAFFIC_H = 10'd32;

    localparam [9:0] TRAFFIC0_Y = GROUND_Y - TRAFFIC_H;
    localparam [9:0] LOWER_BUG = 10'd352;
    localparam [9:0] HIGHER_BUG = 10'd320;

    // Speeds, in pixels per frame. There are 60 frames every second.
    localparam [4:0] BASE_SPEED  = 5'd3;   // how fast the traffic comes at the start

    // How long the red flash lasts after a crash, in frames. 63 at most.
    localparam [5:0] CRASH_FRAMES = 6'd40;

    localparam [9:0] CAR_Y_START = GROUND_Y - CAR_H;  // how far down the screen the car sits

    // ========================================================================
    // 2. WIRING
    //    The pins and the monitor's timing. Leave this section as it is.
    // ========================================================================

    wire       hsync;
    wire       vsync;
    wire       video_active;
    wire [9:0] pix_x;          // the pixel being drawn now: 0 to 639 across
    wire [9:0] pix_y;          // and 0 to 479 down

    reg rst_n_q;
    always @(posedge clk) rst_n_q <= rst_n;

    hvsync_generator hvsync_gen (
        .clk(clk),
        .reset(~rst_n_q),
        .hsync(hsync),
        .vsync(vsync),
        .display_on(video_active),
        .hpos(pix_x),
        .vpos(pix_y)
    );

    wire jump        = ui_in[0];
    wire duck        = ui_in[1];
    // High for one clock as each frame ends. The game moves on once per frame.
    reg  vsync_q;
    wire new_frame = vsync & ~vsync_q;

    // ========================================================================
    // 3. THE GAME
    //    A few registers hold where everything is. They change once per frame.
    // ========================================================================

    reg [9:0] warrior_y;               // left edge of the car
    reg [9:0] traffic0_x;          // top left corner of each of the two vehicles
    reg [9:0] traffic1_x;
    reg [9:0] score;               // frames survived this run, up to 1023
    reg [5:0] crash_timer;         // frames of flash left after a crash, 0 when driving
    reg [7:0] random;             // shifts every clock, so its value looks random
    reg [3:0] run;

    localparam signed [5:0] VELOCITY = 6'sd20;
    reg signed [5:0] jump_speed;
    reg jumping;
    reg ducking;
    reg higher_bug;

    // The level goes up by one every 64 frames, and each level is one pixel faster.
    wire [3:0] level = score[9:6];
    wire [4:0] speed = BASE_SPEED + {1'b0, level};
    reg [4:0] scroll;

    // Where a vehicle joins the road: somewhere across the lane, 256 places.
    wire [9:0] random_x0 = {3'b101, random[6:0]};
    wire [9:0] random_x1 = {3'b101, random[7:1]};

    reg overlap;
    wire crash = overlap;

    // One subtraction per obstacle, bit 10 is 1 when the step is bigger when the obstacle passes x = 0
    wire [10:0] next0 = {1'b0, traffic0_x} - {6'd0, speed};
    wire [10:0] next1 = {1'b0, traffic1_x} - {6'd0, speed} - 11'b1;

    always @(posedge clk) begin
        vsync_q <= vsync;
        if (~rst_n_q) begin
            crash_timer <= 6'd1;
            random      <= 8'hA5;
        end else if (new_frame) begin
            random <= {random[6:0], random[7] ^ random[5] ^ random[4] ^ random[3]};
            if (crash_timer != 6'd0) begin
                // ---- after a crash: count the flash down, then start again
                crash_timer <= crash_timer - 6'd1;
                if (crash_timer == 6'd1) begin
                    warrior_y       <= CAR_Y_START;
                    traffic0_x <= random_x0;
                    traffic1_x <= random_x1;
                    higher_bug <= random[0];
                    score      <= 10'd0;
                    jumping <= 1'b0;
                end
            end else if (crash) begin
                crash_timer <= CRASH_FRAMES;
            end else begin
                if (jump & ~jumping) begin
                    jumping <= 1'b1;
                    jump_speed <= VELOCITY;
                end else if (jumping) begin
                    if (jump_speed == -VELOCITY) begin
                        warrior_y <= CAR_Y_START;
                        jumping <= 1'b0;
                    end else begin
                        warrior_y <= warrior_y - {{4{jump_speed[5]}}, jump_speed};
                        jump_speed <= jump_speed - 6'sd2;
                    end
                end


                // ---- traffic: move down, and rejoin at the top in a new place
                if (next0[10])  traffic0_x <= random_x0;
                else            traffic0_x <= next0[9:0];
                if (next1[10]) begin
                    traffic1_x <= random_x1;
                    higher_bug <= random[0];
                end else        traffic1_x <= next1[9:0];

                run <= run + 4'd1;
                scroll <= scroll + speed;
                ducking <= duck & ~jumping & ~jump;

                if (score != 10'h3ff) score <= score + 10'd1;
            end
        end
    end

    // ========================================================================
    // 4. DRAWING
    //    One question for each thing on screen: is this pixel inside it?
    // ========================================================================
    
    // the ground
    wire in_ground = (pix_y >= GROUND_Y) & (pix_y < GROUND_Y + GROUND_H);
    wire [4:0] ground_x = pix_x[4:0] + scroll;
    wire in_pebble = (pix_y >= GROUND_Y + 10'd14) & (pix_y < GROUND_Y +10'd16) & (ground_x[4:2] == 3'd0);

    // The car, with a window and four wheels.
    wire [9:0] wx = pix_x - WARRIOR_X;
    wire [9:0] wy = pix_y - warrior_y;
    
    wire stride = run[3] & ~jumping;
    wire flap = run[2];

    wire [4:0] row = wy[5:1];
    wire [4:0] head_row = ducking ? row - 5'd4 : row;

    reg [15:0] warrior_row;
    always @(*) begin
        case (head_row)
            5'd0: warrior_row =  {12'b001111110000, 4'b0};
            5'd1: warrior_row =  {12'b010000001000, 4'b0};
            5'd2: warrior_row =  {12'b100010000100, 4'b0};
            5'd3: warrior_row =  {12'b100010010011, 4'b0};
            5'd4: warrior_row =  {12'b100010110101, 4'b0};
            5'd5: warrior_row =  {12'b110010001001, 4'b0};
            5'd6: warrior_row =  {12'b001100010110, 4'b0};
            5'd7: warrior_row =  {12'b000111111000, 4'b0};
            5'd8: warrior_row =  {12'b001111110000, 4'b0};
            5'd9: warrior_row =  {12'b010001111000, 4'b0};
            5'd10: warrior_row = {12'b010001101000, 4'b0};
            5'd11: warrior_row = {12'b010011111000, 4'b0};
            5'd12: warrior_row = {12'b010011111000, 4'b0};
            5'd13: warrior_row = {12'b010100111000, 4'b0};
            5'd14: warrior_row = {12'b011000110000, 4'b0};
            5'd15: warrior_row = stride ? {12'b010111111110, 4'b0} : {12'b010111111000, 4'b0};
            5'd16: warrior_row = stride ? {12'b011111111110, 4'b0} : {12'b010111111000, 4'b0};
            5'd17: warrior_row = stride ? {12'b111110001110, 4'b0} : {12'b100111110000, 4'b0};
            5'd18: warrior_row = stride ? {12'b111000001111, 4'b0} : {12'b011111111000, 4'b0};
            5'd19: warrior_row = stride ? {12'b011100000000, 4'b0} : {12'b000111100000, 4'b0};
            default: warrior_row = 16'b0;
        endcase
    end

    reg [15:0] duck_row;
    always @(*) begin
        case (row)
            5'd12: duck_row = {12'b001111111110, 4'b0};
            5'd13: duck_row = {12'b001100111001, 4'b0};
            5'd14: duck_row = {12'b101100000101, 4'b0};
            5'd15: duck_row = {12'b011110000010, 4'b0};
            5'd16: duck_row = {12'b001111111100, 4'b0};
            5'd17: duck_row = {12'b101111111100, 4'b0};
            5'd18: duck_row = {12'b010111111100, 4'b0};
            5'd19: duck_row = {12'b000111111000, 4'b0};
            default: duck_row = 16'b0;
        endcase
    end

    wire [15:0] pose_row = (ducking & row >= 5'd12) ? duck_row : warrior_row;
    wire in_warrior = (wx < CAR_W) & (wy < CAR_H) & pose_row[~wx[4:1]];

    // The two vehicles, each with a darker strip six pixels deep along the top.
    wire [9:0] x0 = pix_x - traffic0_x; // TRAFFIC_W is a power of two, the same test can be done with a subtraction
    wire [9:0] x1 = pix_x - traffic1_x;

    wire [9:0] y0 = pix_y - TRAFFIC0_Y;
    wire [9:0] y1 = pix_y - (higher_bug ? HIGHER_BUG : LOWER_BUG);

    reg [15:0] cactus_row;
    always @(*) begin
        case (y0[4:1])
            4'd0:  cactus_row = 16'b0000000110000000;
            4'd1:  cactus_row = 16'b0000001111000000;
            4'd2:  cactus_row = 16'b0000001111000000;
            4'd3:  cactus_row = 16'b0000001111001100;
            4'd4:  cactus_row = 16'b0000001111001100;
            4'd5:  cactus_row = 16'b0110001111001100;
            4'd6:  cactus_row = 16'b0110001111001100;
            4'd7:  cactus_row = 16'b0110001111001100;
            4'd8:  cactus_row = 16'b0110001111111100;
            4'd9:  cactus_row = 16'b0111111111000000;
            4'd10: cactus_row = 16'b0000001111000000;
            4'd11: cactus_row = 16'b0000001111000000;
            4'd12: cactus_row = 16'b0000001111000000;
            4'd13: cactus_row = 16'b0000001111000000;
            4'd14: cactus_row = 16'b0000001111000000;
            4'd15: cactus_row = 16'b0000011111100000;
            default: cactus_row = 16'b0;
        endcase
    end

    reg [15:0] bug_row;
    always @(*) begin
        case (y1[4:1])
            4'd2:  bug_row = flap ? 16'b0000000000000000 : 16'b0000000001110000;
            4'd3:  bug_row = flap ? 16'b0000000000000000 : 16'b0000000110001000;
            4'd4:  bug_row = flap ? 16'b0000000000000000 : 16'b0000001000001000;
            4'd5:  bug_row = flap ? 16'b0100000011110000 : 16'b0100001000010000;
            4'd6:  bug_row = flap ? 16'b0010000100001000 : 16'b0010000100100000;
            4'd7:  bug_row = 16'b0001111111111000;
            4'd8:  bug_row = 16'b0001111111111100;
            4'd9:  bug_row = 16'b0011011111111110;
            4'd10: bug_row = 16'b0011111111111110;
            4'd11: bug_row = 16'b0001111111111100;
            4'd12: bug_row = 16'b0000111111111000;
            4'd13: bug_row = 16'b0000010010010000;
            4'd14: bug_row = 16'b0000100100100000;
            4'd15: bug_row = 16'b0000100100100000;
            default: bug_row = 16'b0;
        endcase
    end

    wire in_cactus = (x0 < TRAFFIC_W) & (y0 < TRAFFIC_H) & cactus_row[~x0[4:1]];
    wire in_bug = (x1 < TRAFFIC_W) & (y1 < TRAFFIC_H) & bug_row[~x1[4:1]];
    wire in_traffic  = in_cactus | in_bug;

    always @(posedge clk) begin
        if (new_frame)                      overlap <= 1'b0;
        else if (in_warrior & in_traffic)   overlap <= 1'b1;
    end

    // The score bar: one pixel longer for every two frames survived.
    wire in_score = (pix_y >= 10'd8) & (pix_y < 10'd18) &
                    (pix_x >= 10'd8) & (pix_x < 10'd8 + {1'b0, score[9:1]});

    // The first line that matches wins, so anything higher up is drawn on top
    // of anything lower down. Move a line to change what covers what.

    wire night = score[9];
    wire draw = in_score | in_warrior | in_traffic | in_ground | in_pebble;
    wire colour = video_active & (draw ~^ night);
    reg colour_q;
    always @(posedge clk) colour_q <= colour;

    assign uo_out  = {hsync, colour_q, colour_q, colour_q, vsync, colour_q, colour_q, colour_q};
    assign uio_out = 8'h00;
    assign uio_oe  = 8'h00;

    wire _unused_ok = &{ena, uio_in, ui_in[7:2], ground_x[1:0]};

endmodule
