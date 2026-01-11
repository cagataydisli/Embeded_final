`timescale 1ns / 1ps

module tb_system_dual_pico;

    // Inputs
    logic clk;
    logic rst;

    // Outputs
    logic xtea_ready;
    logic [63:0] xtea_result_out;

    // Instantiate the Unit Under Test (UUT)
    system_top_dual_pico uut (
        .clk(clk),
        .rst(rst),
        .xtea_ready(xtea_ready),
        .xtea_result_out(xtea_result_out)
    );

    // Clock generation
    always #5 clk = ~clk; // 100MHz clock

    integer i;

    initial begin
        // Initialize Inputs
        clk = 0;
        rst = 1;

        // Display Simulation Banner
        $display("==============================================");
        $display("DUAL PICOBLAZE SYSTEM TEST (Pico1 -> FIFO -> Pico2)");
        $display("==============================================");
        $display("Mode:      DECRYPTION");
        $display("Ciphertext: C3 B9 0E B5 22 56 FE 61");
        $display("Key:       00 01 02 03 04 05 06 07 08 09 0A 0B 0C 0D 0E 0F");
        $display("Expected:  11 22 33 44 55 66 77 88 (Plaintext)");
        $display("==============================================");

        // Reset Sequence
        #100;
        rst = 0;
        #100;
        
        $display("Reset released. System running...");
        
        // Wait for completion
        // Monitor Mem3 writes in the wave view or simply wait enough time
        wait(xtea_ready);
        $display("XTEA Core finished processing at time %t", $time);
        
        // Wait for Pico2 to read result and write to Mem3
        #5000;
        
        $display("--- FINAL RESULTS (Mem3) ---");
        // Access internal memory for verification (Hierarchical reference)
        for (i = 0; i < 8; i = i + 1) begin
            $display("Addr %0d: %h", i, uut.ram_mem3.ram[i]);
        end
        
        $display("==============================================");
        $finish;
    end
    
    // Optional: Monitor FIFO status
    // Monitor FIFO
    always @(posedge clk) begin
        if (uut.fifo_inst.wr_en && !uut.fifo_inst.full) begin
            $display("Time %t: FIFO WRITE -> %h", $time, uut.fifo_inst.din);
        end
        if (uut.fifo_inst.rd_en && !uut.fifo_inst.empty) begin
            $display("Time %t: FIFO READ  <- %h", $time, uut.fifo_inst.dout);
        end
    end

endmodule
