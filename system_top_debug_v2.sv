`timescale 1ns / 1ps

module system_top_debug_v2 (
    input logic clk,
    input logic rst
);

    // --- Signals ---

    // Pico1 (Not used in this version, but kept for compatibility)
    logic [11:0] p1_address;
    logic [17:0] p1_instruction;
    logic        p1_bram_enable;
    logic [7:0]  p1_port_id;
    logic        p1_write_strobe;
    logic        p1_k_write_strobe;
    logic [7:0]  p1_out_port;
    logic        p1_read_strobe;
    logic [7:0]  p1_in_port;
    logic        p1_interrupt;
    logic        p1_interrupt_ack;
    logic        p1_sleep;

    // Pico2
    logic [11:0] p2_address;
    logic [17:0] p2_instruction;
    logic        p2_bram_enable;
    logic [7:0]  p2_port_id;
    logic        p2_write_strobe;
    logic        p2_k_write_strobe;
    logic [7:0]  p2_out_port;
    logic        p2_read_strobe;
    logic [7:0]  p2_in_port;
    logic        p2_interrupt;
    logic        p2_interrupt_ack;
    logic        p2_sleep;

    // XTEA
    logic [127:0] xtea_key;
    logic [63:0]  xtea_data_in;
    logic [63:0]  xtea_data_out;
    logic         xtea_start;
    logic         xtea_mode; // 0: Enc, 1: Dec
    logic         xtea_ready;

    // Memory Signals
    // Mem1 (Plaintext Data)
    logic [7:0] mem1_addr;
    logic [7:0] mem1_data_out;
    
    // Mem2 (Key) - NEW!
    logic [7:0] mem2_addr;
    logic [7:0] mem2_data_out;
    
    // Mem3 (Result)
    logic [7:0] mem3_addr;
    logic [7:0] mem3_data_in;
    logic       mem3_we;
    logic [7:0] mem3_data_out;

    // Registers and Pointers
    logic [3:0] key_byte_ptr;
    logic [3:0] data_byte_ptr; 
    logic [2:0] result_byte_ptr; 

    logic [127:0] key_reg;
    logic [63:0]  data_in_reg;
    
    // --- Instantiations ---

    // Pico2 (XTEA Controller) - USING V12 MODULE (Fixed Key Loading)
    pico2_emulator_v12 p2_inst (
        .clk(clk), .rst(rst),
        .address(p2_address), .instruction(p2_instruction),
        .bram_enable(p2_bram_enable), .port_id(p2_port_id),
        .write_strobe(p2_write_strobe), .k_write_strobe(p2_k_write_strobe),
        .out_port(p2_out_port), .read_strobe(p2_read_strobe), .in_port(p2_in_port),
        .interrupt(p2_interrupt), .interrupt_ack(p2_interrupt_ack), .sleep(p2_sleep)
    );

    // XTEA Core - Now with correct 32 rounds
    xtea_core xtea_inst (
        .clk(clk), .rst(rst),
        .start(xtea_start), 
        .decrypt(xtea_mode), 
        .key(key_reg), .data_in(data_in_reg),
        .data_out(xtea_data_out),
        .ready(xtea_ready)
    );

    // Mem1: Initialized with Plaintext
    // Content: 11 22 33 44 55 66 77 88
    single_port_ram #(.INIT_TYPE(1)) ram_mem1 (
        .clk(clk), .we(1'b0), .addr(mem1_addr), .din(8'h00), .dout(mem1_data_out)
    );

    // Mem2: Initialized with Key - NEW!
    // Content: 00 01 02 03 04 05 06 07 08 09 0A 0B 0C 0D 0E 0F
    single_port_ram #(.INIT_TYPE(2)) ram_mem2 (
        .clk(clk), .we(1'b0), .addr(mem2_addr), .din(8'h00), .dout(mem2_data_out)
    );

    // Mem3: Result Memory (Empty)
    single_port_ram #(.INIT_TYPE(0)) ram_mem3 (
        .clk(clk), .we(mem3_we), .addr(mem3_addr), .din(mem3_data_in), .dout(mem3_data_out)
    );

    // --- Glue Logic ---

    // Pico2 Input Mux
    always_comb begin
        p2_in_port = 8'h00;
        case (p2_port_id)
            // Mem2 (Key) Read - Port 0x21
            8'h21: p2_in_port = mem2_data_out;
            
            // Mem1 (Data) Read - Port 0x23
            8'h23: p2_in_port = mem1_data_out;
            
            // XTEA Status - Port 0x34
            8'h34: p2_in_port = {7'b0, xtea_ready};
            
            // XTEA Result Read - Port 0x35
            8'h35: begin
                case (result_byte_ptr)
                    3'd0: p2_in_port = xtea_data_out[7:0];
                    3'd1: p2_in_port = xtea_data_out[15:8];
                    3'd2: p2_in_port = xtea_data_out[23:16];
                    3'd3: p2_in_port = xtea_data_out[31:24];
                    3'd4: p2_in_port = xtea_data_out[39:32];
                    3'd5: p2_in_port = xtea_data_out[47:40];
                    3'd6: p2_in_port = xtea_data_out[55:48];
                    3'd7: p2_in_port = xtea_data_out[63:56];
                    default: p2_in_port = 8'hAA;
                endcase
            end
            default: p2_in_port = 8'h00;
        endcase
    end

    // Register Updates
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            mem1_addr <= 0;
            mem2_addr <= 0;
            mem3_addr <= 0;
            mem3_data_in <= 0;
            mem3_we <= 0;
            
            key_reg <= 0;
            data_in_reg <= 0;
            
            xtea_start <= 0;
            xtea_mode <= 0;
            
            key_byte_ptr <= 0;
            data_byte_ptr <= 0;
            result_byte_ptr <= 0;
        end else begin
            // Default Values
            mem3_we <= 0;
            
            // PICO2 WRITE OPERATIONS
            if (p2_write_strobe) begin
                case (p2_port_id)
                    // Mem2 (Key) Address Set - Port 0x20
                    8'h20: mem2_addr <= p2_out_port;
                    
                    // Mem1 (Data) Address Set - Port 0x22
                    8'h22: mem1_addr <= p2_out_port;
                    
                    // XTEA Key Load (Auto Increment) - Port 0x30
                    8'h30: begin
                        case (key_byte_ptr)
                            4'd0: key_reg[7:0] <= p2_out_port;
                            4'd1: key_reg[15:8] <= p2_out_port;
                            4'd2: key_reg[23:16] <= p2_out_port;
                            4'd3: key_reg[31:24] <= p2_out_port;
                            4'd4: key_reg[39:32] <= p2_out_port;
                            4'd5: key_reg[47:40] <= p2_out_port;
                            4'd6: key_reg[55:48] <= p2_out_port;
                            4'd7: key_reg[63:56] <= p2_out_port;
                            4'd8: key_reg[71:64] <= p2_out_port;
                            4'd9: key_reg[79:72] <= p2_out_port;
                            4'd10: key_reg[87:80] <= p2_out_port;
                            4'd11: key_reg[95:88] <= p2_out_port;
                            4'd12: key_reg[103:96] <= p2_out_port;
                            4'd13: key_reg[111:104] <= p2_out_port;
                            4'd14: key_reg[119:112] <= p2_out_port;
                            4'd15: key_reg[127:120] <= p2_out_port;
                        endcase
                        key_byte_ptr <= key_byte_ptr + 1;
                        if (key_byte_ptr == 15) key_byte_ptr <= 0;
                    end

                    // XTEA Data Load (Auto Increment) - Port 0x31
                    8'h31: begin
                        case (data_byte_ptr)
                            4'd0: data_in_reg[7:0] <= p2_out_port;
                            4'd1: data_in_reg[15:8] <= p2_out_port;
                            4'd2: data_in_reg[23:16] <= p2_out_port;
                            4'd3: data_in_reg[31:24] <= p2_out_port;
                            4'd4: data_in_reg[39:32] <= p2_out_port;
                            4'd5: data_in_reg[47:40] <= p2_out_port;
                            4'd6: data_in_reg[55:48] <= p2_out_port;
                            4'd7: data_in_reg[63:56] <= p2_out_port;
                        endcase
                        data_byte_ptr <= data_byte_ptr + 1;
                        if (data_byte_ptr == 7) data_byte_ptr <= 0; 
                    end

                    // XTEA Control - Port 0x33
                    8'h33: begin
                        xtea_start <= p2_out_port[0]; // Bit 0: Start
                        xtea_mode <= p2_out_port[1];  // Bit 1: Mode (0= Encrypt)
                        
                        // Reset Read Pointer on Start
                        if (p2_out_port[0]) result_byte_ptr <= 0;
                    end

                    // Mem3 Address - Port 0x40
                    8'h40: mem3_addr <= p2_out_port;

                    // Mem3 Data + Write Enable - Port 0x41
                    8'h41: begin
                        mem3_data_in <= p2_out_port;
                        mem3_we <= 1; 
                    end
                endcase
            end

            // XTEA Start Signal Pulse Management
            if (xtea_start && !p2_write_strobe) begin
                xtea_start <= 0;
            end

            // PICO2 READ OPERATIONS
            if (p2_read_strobe) begin
                if (p2_port_id == 8'h35) begin
                    result_byte_ptr <= result_byte_ptr + 1;
                end
            end

        end
    end

endmodule
