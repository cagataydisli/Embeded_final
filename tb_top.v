`timescale 1ns / 1ps

module tb_top;

    // Inputs
    reg clk;
    reg rst;

    // Outputs
    wire xtea_ready;
    wire [63:0] xtea_result_out;

    // Instantiate the Unit Under Test (UUT)
    top uut (
        .clk(clk), 
        .rst(rst), 
        .xtea_ready(xtea_ready), 
        .xtea_result_out(xtea_result_out)
    );

    // Clock generation
    always #5 clk = ~clk; // 100MHz clock

    // Timeout counter
    integer timeout_cnt;
    
    initial begin
        // Initialize Inputs
        clk = 0;
        rst = 1;
        timeout_cnt = 0;

        // Wait for global reset
        #100;
        rst = 0;
        
        $display("Simulation Started at %t", $time);

        // Poll for xtea_ready with timeout
        while (xtea_ready == 0 && timeout_cnt < 5000) begin
            #10;
            timeout_cnt = timeout_cnt + 1;
            
            // Print debug every 1000 cycles
            if (timeout_cnt % 1000 == 0) begin
                $display("[%t] Still waiting... FIFO empty=%b, xtea_ready=%b", 
                    $time, uut.fifo_empty, xtea_ready);
            end
        end

        if (xtea_ready == 1) begin
            $display("XTEA Ready Detected!");
            $display("Time: %t, Result: %h", $time, xtea_result_out);
            // Wait for Pico2 to write results to Mem3
            #5000;
        end else begin
            $display("TIMEOUT at %t! xtea_ready never went high.", $time);
        end
        
        // Always dump status at end
        $display("=== Final Status ===");
        $display("xtea_start=%b, xtea_mode=%b, xtea_ready=%b", 
            uut.xtea_start, uut.xtea_mode, xtea_ready);
        $display("key_reg=%h", uut.key_reg);
        $display("data_in_reg=%h", uut.data_in_reg);
        $display("xtea_data_out=%h", uut.xtea_data_out);
        $display("FIFO empty=%b, full=%b", uut.fifo_empty, uut.fifo_full);
        
        $display("=== MEM3 Contents (first 8 bytes) ===");
        $display("Mem3[0]=%h Mem3[1]=%h Mem3[2]=%h Mem3[3]=%h",
            uut.ram_mem3.ram[0], uut.ram_mem3.ram[1], 
            uut.ram_mem3.ram[2], uut.ram_mem3.ram[3]);
        $display("Mem3[4]=%h Mem3[5]=%h Mem3[6]=%h Mem3[7]=%h",
            uut.ram_mem3.ram[4], uut.ram_mem3.ram[5], 
            uut.ram_mem3.ram[6], uut.ram_mem3.ram[7]);
        
        #100;
        $finish;
    end
      
endmodule
