`timescale 1ns / 1ps

// ============================================================================
// XTEA Core - Fixed Algorithm Implementation
// Single phase per clock: updates v0, sum, AND v1 in proper sequence
// Uses combinational logic to chain v0 -> v1 within same clock cycle
// ============================================================================

module xtea_core (
    input logic clk,
    input logic rst,
    input logic start,
    input logic decrypt,
    input logic [127:0] key,
    input logic [63:0] data_in,
    output logic [63:0] data_out,
    output logic ready
);

    // XTEA Constants (Delta)
    localparam logic [31:0] DELTA = 32'h9E3779B9;
    localparam NUM_ROUNDS = 32;
    
    // States
    typedef enum logic [1:0] {IDLE, BUSY, DONE} state_t;
    state_t state;

    // Registers
    logic [31:0] v0, v1, sum;
    logic [5:0] round_ctr; // 6 bits for 32 rounds

    // --- KEY Endianness Fix ---
    // Memory layout (byte 0..15): 00 01 02 03 | 04 05 06 07 | 08 09 0A 0B | 0C 0D 0E 0F
    // key_reg layout: [7:0]=00, [15:8]=01, ... [127:120]=0F
    // For k[0], we need bytes 0,1,2,3 as 0x00010203 (Big Endian)
    
    logic [31:0] k[0:3];
    
    // Byte swap to convert LE register to BE value
    assign k[0] = {key[7:0], key[15:8], key[23:16], key[31:24]};
    assign k[1] = {key[39:32], key[47:40], key[55:48], key[63:56]};
    assign k[2] = {key[71:64], key[79:72], key[87:80], key[95:88]};
    assign k[3] = {key[103:96], key[111:104], key[119:112], key[127:120]};

    // --- DATA Endianness Fix ---
    logic [31:0] v0_init, v1_init;
    assign v0_init = {data_in[7:0], data_in[15:8], data_in[23:16], data_in[31:24]};
    assign v1_init = {data_in[39:32], data_in[47:40], data_in[55:48], data_in[63:56]};

    // ===========================================================================
    // COMBINATIONAL ROUND LOGIC - Calculate one complete round in one cycle
    // This ensures proper data dependency: v0_new feeds into v1 calculation
    // ===========================================================================
    
    // ENCRYPT: sum is used first with current value, then incremented for v1
    // DECRYPT: sum is used first (decremented version), then used for v0
    
    logic [31:0] sum_for_v0, sum_for_v1;
    logic [31:0] v0_new, v1_new;
    logic [31:0] sum_new;
    
    // Encryption:
    // v0 += (((v1 << 4) ^ (v1 >> 5)) + v1) ^ (sum + key[sum & 3]);
    // sum += delta;
    // v1 += (((v0 << 4) ^ (v0 >> 5)) + v0) ^ (sum + key[(sum>>11) & 3]); // uses NEW v0 and NEW sum
    
    // Decryption:
    // v1 -= (((v0 << 4) ^ (v0 >> 5)) + v0) ^ (sum + key[(sum>>11) & 3]);
    // sum -= delta;
    // v0 -= (((v1 << 4) ^ (v1 >> 5)) + v1) ^ (sum + key[sum & 3]); // uses NEW v1 and NEW sum
    
    always_comb begin
        if (!decrypt) begin
            // ENCRYPT
            sum_for_v0 = sum;
            sum_new = sum + DELTA;
            sum_for_v1 = sum_new; // v1 uses sum AFTER increment
            
            // v0 calculation uses current v1 and current sum
            v0_new = v0 + ((((v1 << 4) ^ (v1 >> 5)) + v1) ^ (sum_for_v0 + k[sum_for_v0 & 3]));
            
            // v1 calculation uses NEW v0 and NEW sum
            v1_new = v1 + ((((v0_new << 4) ^ (v0_new >> 5)) + v0_new) ^ (sum_for_v1 + k[(sum_for_v1 >> 11) & 3]));
        end else begin
            // DECRYPT
            sum_for_v1 = sum;
            sum_new = sum - DELTA;
            sum_for_v0 = sum_new; // v0 uses sum AFTER decrement
            
            // v1 calculation uses current v0 and current sum
            v1_new = v1 - ((((v0 << 4) ^ (v0 >> 5)) + v0) ^ (sum_for_v1 + k[(sum_for_v1 >> 11) & 3]));
            
            // v0 calculation uses NEW v1 and NEW sum
            v0_new = v0 - ((((v1_new << 4) ^ (v1_new >> 5)) + v1_new) ^ (sum_for_v0 + k[sum_for_v0 & 3]));
        end
    end

    // Main FSM
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            v0 <= 0; v1 <= 0; sum <= 0; 
            round_ctr <= 0; 
            ready <= 0;
        end else begin
            case (state)
                IDLE: begin
                    ready <= 0;
                    if (start) begin
                        state <= BUSY;
                        
                        // Use correctly byte-swapped values
                        v0 <= v0_init;  
                        v1 <= v1_init; 
                        round_ctr <= 0;
                        
                        if (!decrypt) begin
                            sum <= 0;
                        end else begin
                            // Initialize sum for 32 Rounds
                            // sum = DELTA * 32 = 0xC6EF3720
                            sum <= DELTA * NUM_ROUNDS; 
                        end
                    end
                end

                BUSY: begin
                    if (round_ctr == NUM_ROUNDS) begin
                        state <= DONE;
                    end else begin
                        // One complete round per cycle
                        v0 <= v0_new;
                        v1 <= v1_new;
                        sum <= sum_new;
                        round_ctr <= round_ctr + 1;
                    end
                end

                DONE: begin
                    ready <= 1;
                    state <= IDLE;
                end
            endcase
        end
    end

    // Output Data - Swap back to byte order for memory storage
    assign data_out = {v1[7:0], v1[15:8], v1[23:16], v1[31:24],
                       v0[7:0], v0[15:8], v0[23:16], v0[31:24]};

endmodule