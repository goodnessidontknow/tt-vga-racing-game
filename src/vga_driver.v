/*
 * NOT the racing game for VGA: dodge the traffic.
 *
 * To play, open Inspect > VGA output and press Run. Use the switches under the
 * picture, or the keyboard:
 *   ui_in[0]  steer left     (Left arrow, A or 1)
 *   ui_in[1]  steer right    (Right arrow, D or 2)
 *   ui_in[2]  boost          (Up arrow, W, Space or 3)
 *
 * The score bar at the top grows while you survive, and the traffic speeds up
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
    localparam [9:0] GROUND_H  = 10'd10;
    localparam [9:0] GROUND_Y  = 10'd400;
    localparam [9:0] CAR_W     = 10'd24;
    localparam [9:0] CAR_H     = 10'd40;
    localparam [9:0] CAR_X    = 10'd160;  // the part you can drive on
    localparam [9:0] TRAFFIC_W = 10'd32;   // keep to 48 or less, or it overhangs the kerb, ALSO KEEP AT A POWER OF 2
    localparam [9:0] TRAFFIC_H = 10'd32;

    localparam [9:0] TRAFFIC0_Y = GROUND_Y - TRAFFIC_H;
    localparam [9:0] TRAFFIC1_Y = 10'd270;

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

    reg [9:0] car_y;               // left edge of the car
    reg [9:0] traffic0_x;          // top left corner of each of the two vehicles
    reg [9:0] traffic1_x;
    reg [9:0] score;               // frames survived this run, up to 1023
    reg [5:0] crash_timer;         // frames of flash left after a crash, 0 when driving
    reg [7:0] random;             // shifts every clock, so its value looks random
    reg [3:0] run;

    localparam signed [5:0] VELOCITY = 6'sd20;
    reg signed [5:0] jump_speed;
    reg jumping;

    // The level goes up by one every 64 frames, and each level is one pixel faster.
    wire [3:0] level = score[9:6];
    wire [4:0] speed = BASE_SPEED + {1'b0, level};

    // Where a vehicle joins the road: somewhere across the lane, 256 places.
    wire [9:0] random_x0 = {3'b101, random[6:0]};
    wire [9:0] random_x1 = {3'b101, random[7:1]};

    // A crash is the car's rectangle overlapping a vehicle's rectangle.
    wire hit0 = (traffic0_x > CAR_X - TRAFFIC_W) & (traffic0_x < CAR_X + CAR_W) & (car_y > TRAFFIC0_Y - CAR_H);// & (car_y < TRAFFIC0_Y + TRAFFIC_H);
    wire hit1 = (traffic1_x > CAR_X - TRAFFIC_W) & (traffic1_x < CAR_X + CAR_W) & (car_y < TRAFFIC1_Y + TRAFFIC_H);// & (car_y > TRAFFIC1_Y - CAR_H);
    wire crash = hit0 | hit1;

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
                    car_y       <= CAR_Y_START;
                    traffic0_x <= random_x0;
                    traffic1_x <= random_x1;
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
                        car_y <= CAR_Y_START;
                        jumping <= 1'b0;
                    end else begin
                        car_y <= car_y - {{4{jump_speed[5]}}, jump_speed};
                        jump_speed <= jump_speed - 6'sd2;
                    end
                end


                // ---- traffic: move down, and rejoin at the top in a new place
                if (next0[10])  traffic0_x <= random_x0;
                else            traffic0_x <= next0[9:0];
                if (next1[10])  traffic1_x <= random_x1;
                else            traffic1_x <= next1[9:0];

                run <= run + 4'd1;

                if (score != 10'h3ff) score <= score + 10'd1;
            end
        end
    end

    // ========================================================================
    // 4. DRAWING
    //    One question for each thing on screen: is this pixel inside it?
    // ========================================================================
    
    // the ground
    wire in_ground    = (pix_y >= GROUND_Y) & (pix_y < GROUND_Y + GROUND_H);

    // The car, with a window and four wheels.
    wire [9:0] cy = pix_y - car_y;
    wire in_car    = (pix_x >= CAR_X) & (pix_x < (CAR_X + CAR_W)) & (cy < CAR_H);
    
    wire stride = run[3] + ~jumping;

    reg [15:0] warrior_row;
    always @(*) begin
        case (cy[5:1])
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
    wire in_warrior = in_car & warrior_row[~pix_x[4:1]];

    // The two vehicles, each with a darker strip six pixels deep along the top.
    wire [9:0] x0 = pix_x - traffic0_x; // TRAFFIC_W is a power of two, the same test can be done with a subtraction
    wire [9:0] x1 = pix_x - traffic1_x;
    wire in_traffic0 = (x0 < TRAFFIC_W) & (pix_y >= TRAFFIC0_Y) & (pix_y < TRAFFIC0_Y + TRAFFIC_H);
    wire in_traffic1 = (x1 < TRAFFIC_W) & (pix_y >= TRAFFIC1_Y) & (pix_y < TRAFFIC1_Y + TRAFFIC_H);
    wire in_traffic  = in_traffic0 | in_traffic1;

    // The score bar: one pixel longer for every two frames survived.
    wire in_score = (pix_y >= 10'd8) & (pix_y < 10'd18) &
                    (pix_x >= 10'd8) & (pix_x < 10'd8 + {1'b0, score[9:1]});

    // The first line that matches wins, so anything higher up is drawn on top
    // of anything lower down. Move a line to change what covers what.
    reg colour;//[5:0] colour;
    always @(*) begin
        if      (~video_active | in_score | in_warrior | in_traffic | in_ground) colour = 1'b0;
        else    colour = 1'b1;
    end

    assign uo_out  = {hsync, colour, colour, colour, vsync, colour, colour, colour};
    assign uio_out = 8'h00;
    assign uio_oe  = 8'h00;

    wire _unused_ok = &{ena, uio_in, ui_in[7:3]};

endmodule
