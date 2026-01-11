`timescale 1ns / 1ps

module tb_system_debug_v2;

    logic clk;
    logic rst;

    // Instantiate Updated System Top
    system_top_debug_v2 uut (
        .clk(clk),
        .rst(rst)
    );

    // Clock Generation (100 MHz - 10ns Period)
    always #5 clk = ~clk;

    // Simulation Control
    initial begin
        clk = 0;
        rst = 1;
        #100;
        rst = 0;
        
        $display("==============================================");
        $display("XTEA Decryption Test - v12 (Fixed Key Loading)");
        $display("==============================================");
        $display("Ciphertext: C3 B9 0E B5 22 56 FE 61");
        $display("Key:       00 01 02 03 04 05 06 07 08 09 0A 0B 0C 0D 0E 0F");
        $display("Expected:  11 22 33 44 55 66 77 88 (Plaintext)");
        $display("==============================================");

        // Run until completion or timeout
        #50000; 

        // Check Memory 3 
        $display("");
        $display("--- FINAL RESULTS (Mem3) ---");
        $display("Addr 0: %h", uut.ram_mem3.ram[0]);
        $display("Addr 1: %h", uut.ram_mem3.ram[1]);
        $display("Addr 2: %h", uut.ram_mem3.ram[2]);
        $display("Addr 3: %h", uut.ram_mem3.ram[3]);
        $display("Addr 4: %h", uut.ram_mem3.ram[4]);
        $display("Addr 5: %h", uut.ram_mem3.ram[5]);
        $display("Addr 6: %h", uut.ram_mem3.ram[6]);
        $display("Addr 7: %h", uut.ram_mem3.ram[7]);
        $display("");
        $display("==============================================");

        $finish;
    end
    
    // Monitor Pico2 Operations
    always @(posedge clk) begin
        if (uut.p2_write_strobe) begin
            $display("Time %t PICO2 WRITE Port:%h Data:%h", $time, uut.p2_port_id, uut.p2_out_port);
        end
    end

endmodule
