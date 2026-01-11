`timescale 1ns / 1ps

module single_port_ram #(
    parameter INIT_TYPE = 0 // 0: Empty, 1: Plaintext, 2: Ciphertext
)(
    input logic clk,
    input logic we,
    input logic [7:0] addr,
    input logic [7:0] din,
    output logic [7:0] dout
);

    logic [7:0] ram [0:255];

    initial begin
        integer i;
        for (i = 0; i < 256; i = i + 1) begin
            ram[i] = 0;
        end
        
        if (INIT_TYPE == 1) begin
            // Plaintext: 11 22 33 44 55 66 77 88
            ram[0] = 8'h11;
            ram[1] = 8'h22;
            ram[2] = 8'h33;
            ram[3] = 8'h44;
            ram[4] = 8'h55;
            ram[5] = 8'h66;
            ram[6] = 8'h77;
            ram[7] = 8'h88;
        end else if (INIT_TYPE == 2) begin
            // Key: 00 01 02 03 04 05 06 07 08 09 0A 0B 0C 0D 0E 0F
            ram[0] = 8'h00;
            ram[1] = 8'h01;
            ram[2] = 8'h02;
            ram[3] = 8'h03;
            ram[4] = 8'h04;
            ram[5] = 8'h05;
            ram[6] = 8'h06;
            ram[7] = 8'h07;
            ram[8] = 8'h08;
            ram[9] = 8'h09;
            ram[10] = 8'h0A;
            ram[11] = 8'h0B;
            ram[12] = 8'h0C;
            ram[13] = 8'h0D;
            ram[14] = 8'h0E;
            ram[15] = 8'h0F;
        end
    end

    always_ff @(posedge clk) begin
        if (we) begin
            ram[addr] <= din;
        end
        dout <= ram[addr];
    end

endmodule
