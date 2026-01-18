`timescale 1ns / 1ps

// ============================================================================
// XTEA Core - Verilog Implementation
// ============================================================================

module xtea_core (
    input wire clk,
    input wire rst,
    input wire start,
    input wire decrypt,
    input wire [127:0] key,
    input wire [63:0] data_in,
    output wire [63:0] data_out,
    output reg ready
);

    // Constants
    localparam [31:0] DELTA = 32'h9E3779B9;
    localparam NUM_ROUNDS = 32;
    
    // States
    localparam [1:0] IDLE = 2'b00;
    localparam [1:0] BUSY = 2'b01;
    localparam [1:0] DONE = 2'b10;
    
    reg [1:0] state;

    // Registers
    reg [31:0] v0, v1, sum;
    reg [5:0] round_ctr; 

    // Key Endianness Fixed Wires
    wire [31:0] k0, k1, k2, k3;
    
    assign k0 = {key[7:0], key[15:8], key[23:16], key[31:24]};
    assign k1 = {key[39:32], key[47:40], key[55:48], key[63:56]};
    assign k2 = {key[71:64], key[79:72], key[87:80], key[95:88]};
    assign k3 = {key[103:96], key[111:104], key[119:112], key[127:120]};

    // Data Endianness Fix
    wire [31:0] v0_init, v1_init;
    assign v0_init = {data_in[7:0], data_in[15:8], data_in[23:16], data_in[31:24]};
    assign v1_init = {data_in[39:32], data_in[47:40], data_in[55:48], data_in[63:56]};

    // Temporary signals for round calculation
    reg [31:0] sum_for_v0, sum_for_v1;
    reg [31:0] v0_new, v1_new;
    reg [31:0] sum_new;
    
    // Helper to select key part based on sum
    reg [31:0] key_sel_v0;
    reg [31:0] key_sel_v1;

    always @(*) begin
        if (!decrypt) begin
            // ENCRYPT
            sum_for_v0 = sum;
            sum_new = sum + DELTA;
            sum_for_v1 = sum_new; // v1 uses incremented sum
            
            // Key Selection for encrypt
            case (sum_for_v0 & 3)
                0: key_sel_v0 = k0;
                1: key_sel_v0 = k1;
                2: key_sel_v0 = k2;
                3: key_sel_v0 = k3;
            endcase
            
            case ((sum_for_v1 >> 11) & 3)
                0: key_sel_v1 = k0;
                1: key_sel_v1 = k1;
                2: key_sel_v1 = k2;
                3: key_sel_v1 = k3;
            endcase
            
            // v0 calculation
            v0_new = v0 + ((((v1 << 4) ^ (v1 >> 5)) + v1) ^ (sum_for_v0 + key_sel_v0));
            
            // v1 calculation uses v0_new
            v1_new = v1 + ((((v0_new << 4) ^ (v0_new >> 5)) + v0_new) ^ (sum_for_v1 + key_sel_v1));
        end else begin
            // DECRYPT - reverse order of encrypt
            // In decrypt: first undo v1, then undo v0
            // v1 was computed with sum_after_increment, v0 was computed with sum_before_increment
            sum_for_v1 = sum;               // v1 key uses current sum (before decrement)
            sum_new = sum - DELTA;
            sum_for_v0 = sum_new;           // v0 key uses decremented sum
            
            // Key Selection for decrypt
            case ((sum_for_v1 >> 11) & 3)
                0: key_sel_v1 = k0;
                1: key_sel_v1 = k1;
                2: key_sel_v1 = k2;
                3: key_sel_v1 = k3;
            endcase
            
            case (sum_for_v0 & 3)
                0: key_sel_v0 = k0;
                1: key_sel_v0 = k1;
                2: key_sel_v0 = k2;
                3: key_sel_v0 = k3;
            endcase
            
            // v1 calculation first (undo last step of encrypt)
            v1_new = v1 - ((((v0 << 4) ^ (v0 >> 5)) + v0) ^ (sum_for_v1 + key_sel_v1));
            
            // v0 calculation uses v1_new (undo first step of encrypt)
            v0_new = v0 - ((((v1_new << 4) ^ (v1_new >> 5)) + v1_new) ^ (sum_for_v0 + key_sel_v0));
        end
    end

    // FSM
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            v0 <= 0; v1 <= 0; sum <= 0; 
            round_ctr <= 0; 
            ready <= 0;
        end else begin
            case (state)
                IDLE: begin
                    // Ready stays high from previous DONE state until new start
                    if (start) begin
                        ready <= 0; // Clear ready on new start
                        state <= BUSY;
                        v0 <= v0_init;  
                        v1 <= v1_init; 
                        round_ctr <= 0;
                        if (!decrypt) begin
                            sum <= 0;
                        end else begin
                            // sum = DELTA * 32
                            sum <= 32'hC6EF3720; 
                        end
                    end
                end

                BUSY: begin
                    if (round_ctr == NUM_ROUNDS) begin
                        state <= DONE;
                    end else begin
                        v0 <= v0_new;
                        v1 <= v1_new;
                        sum <= sum_new;
                        round_ctr <= round_ctr + 1;
                    end
                end

                DONE: begin
                    ready <= 1; // Assert ready
                    state <= IDLE;
                end
            endcase
        end
    end

    // Output Data
    assign data_out = {v1[7:0], v1[15:8], v1[23:16], v1[31:24],
                       v0[7:0], v0[15:8], v0[23:16], v0[31:24]};

endmodule
