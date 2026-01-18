`timescale 1ns / 1ps

module top (
    input wire clk,
    input wire rst,
    output wire xtea_ready,
    output wire [63:0] xtea_result_out
);

    // =====================================================
    // WIRES & SIGNALS
    // =====================================================

    // --- PICO 1 SIGNALS ---
    wire [7:0] p1_port_id;
    wire [7:0] p1_out_port;
    wire [7:0] p1_in_port;
    wire p1_write_strobe;
    wire p1_read_strobe;
    wire p1_interrupt = 0;
    wire [11:0] p1_address;
    wire [17:0] p1_instruction;
    wire p1_bram_enable;
    
    // --- PICO 2 SIGNALS ---
    wire [7:0] p2_port_id;
    wire [7:0] p2_out_port;
    reg [7:0] p2_in_port; // Reg because of always block
    wire p2_write_strobe;
    wire p2_read_strobe;
    wire p2_interrupt = 0;
    wire [11:0] p2_address;
    wire [17:0] p2_instruction;
    wire p2_bram_enable;

    // --- FIFO ---
    reg fifo_wr_en;
    reg [7:0] fifo_din;
    wire fifo_rd_en;
    wire [7:0] fifo_dout;
    wire fifo_full;
    wire fifo_empty;

    // --- MEMORIES ---
    reg [7:0] mem1_addr;
    wire [7:0] mem1_data_out;
    
    reg [7:0] mem2_addr;
    wire [7:0] mem2_data_out;

    reg [7:0] mem3_addr;
    reg [7:0] mem3_din;
    reg mem3_we;

    // --- XTEA ---
    reg [127:0] key_reg;
    reg [63:0] data_in_reg;
    wire [63:0] xtea_data_out;
    reg xtea_start;
    reg xtea_mode; 
    
    // Internal pointers for XTEA loading
    reg [3:0] key_byte_ptr;
    reg [2:0] data_byte_ptr;
    reg [2:0] result_byte_ptr;

    // =====================================================
    // INSTANCES
    // =====================================================

    // 1. MEM1 (Ciphertext Source for Decryption Test - INIT_TYPE=3)
    single_port_ram #(.INIT_TYPE(3)) ram_mem1 (
        .clk(clk), .we(1'b0), .addr(mem1_addr), .din(8'h00), .dout(mem1_data_out)
    );

    // 2. MEM2 (Key Source - INIT_TYPE=2)
    single_port_ram #(.INIT_TYPE(2)) ram_mem2 (
        .clk(clk), .we(1'b0), .addr(mem2_addr), .din(8'h00), .dout(mem2_data_out)
    );

    // 3. MEM3 (Result Destination)
    single_port_ram #(.INIT_TYPE(0)) ram_mem3 (
        .clk(clk), .we(mem3_we), .addr(mem3_addr), .din(mem3_din), .dout()
    );

    // 4. FIFO
    fifo_buffer #(.DEPTH(16), .DATA_WIDTH(8)) fifo_inst (
        .clk(clk), .rst(rst), 
        .wr_en(fifo_wr_en), .din(fifo_din), 
        .rd_en(fifo_rd_en), .dout(fifo_dout), 
        .full(fifo_full), .empty(fifo_empty)
    );

    // 5. PICO 1 (Data Reader)
    kcpsm6 p1_cpu (
        .address(p1_address), .instruction(p1_instruction),
        .bram_enable(p1_bram_enable), .in_port(p1_in_port), .out_port(p1_out_port),
        .port_id(p1_port_id), .write_strobe(p1_write_strobe), .k_write_strobe(),
        .read_strobe(p1_read_strobe), .interrupt(p1_interrupt), .interrupt_ack(),
        .sleep(1'b0), .reset(rst), .clk(clk)
    );
    
    pico1_rom p1_rom_inst (
        .address(p1_address), .instruction(p1_instruction),
        .enable(p1_bram_enable), .clk(clk)
    );

    // 6. PICO 2 (Controller)
    kcpsm6 p2_cpu (
        .address(p2_address), .instruction(p2_instruction),
        .bram_enable(p2_bram_enable), .in_port(p2_in_port), .out_port(p2_out_port),
        .port_id(p2_port_id), .write_strobe(p2_write_strobe), .k_write_strobe(),
        .read_strobe(p2_read_strobe), .interrupt(p2_interrupt), .interrupt_ack(),
        .sleep(1'b0), .reset(rst), .clk(clk)
    );

    pico2_rom p2_rom_inst (
        .address(p2_address), .instruction(p2_instruction),
        .enable(p2_bram_enable), .clk(clk)
    );

    // 7. XTEA
    xtea_core xtea_inst (
        .clk(clk), .rst(rst),
        .start(xtea_start), .decrypt(xtea_mode), 
        .key(key_reg), .data_in(data_in_reg),
        .data_out(xtea_data_out), .ready(xtea_ready)
    );

    assign xtea_result_out = xtea_data_out;

    // =====================================================
    // LOGIC & MAPPING
    // =====================================================

    // --- PICO 1 LOGIC ---
    // Port 0x31: Mem1 Data Read
    assign p1_in_port = (p1_port_id == 8'h31) ? mem1_data_out : 8'h00;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            mem1_addr <= 0;
            fifo_wr_en <= 0;
            fifo_din <= 0;
        end else begin
            // FIFO Write (Port 0x20)
            fifo_wr_en <= (p1_write_strobe && p1_port_id == 8'h20);
            if (p1_write_strobe && p1_port_id == 8'h20) 
                fifo_din <= p1_out_port;
            
            // Mem1 Address (Port 0x30)
             if (p1_write_strobe && p1_port_id == 8'h30)
                mem1_addr <= p1_out_port;
        end
    end

    // --- PICO 2 LOGIC ---
    
    // FIFO Read Enable
    assign fifo_rd_en = (p2_read_strobe && p2_port_id == 8'h22);

    // INPUT MUX
    always @(*) begin
        case (p2_port_id)
            8'h21: p2_in_port = mem2_data_out;  // Mem2 Data
            8'h22: p2_in_port = fifo_dout;      // FIFO Data
            8'h23: p2_in_port = {7'b0, fifo_empty}; // FIFO Status
            8'h34: p2_in_port = {7'b0, xtea_ready}; // XTEA Status
            8'h35: begin // XTEA Result
                case (result_byte_ptr)
                    3'd0: p2_in_port = xtea_data_out[7:0];
                    3'd1: p2_in_port = xtea_data_out[15:8];
                    3'd2: p2_in_port = xtea_data_out[23:16];
                    3'd3: p2_in_port = xtea_data_out[31:24];
                    3'd4: p2_in_port = xtea_data_out[39:32];
                    3'd5: p2_in_port = xtea_data_out[47:40];
                    3'd6: p2_in_port = xtea_data_out[55:48];
                    3'd7: p2_in_port = xtea_data_out[63:56];
                    default: p2_in_port = 8'h00;
                endcase
            end
            default: p2_in_port = 8'h00;
        endcase
    end

    // OUTPUT & REGISTERS
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            mem2_addr <= 0;
            mem3_addr <= 0;
            mem3_din <= 0;
            mem3_we <= 0;
            
            key_reg <= 0;
            data_in_reg <= 0;
            xtea_start <= 0;
            xtea_mode <= 0;
            
            key_byte_ptr <= 0;
            data_byte_ptr <= 0;
            result_byte_ptr <= 0;
        end else begin
            mem3_we <= 0; // Default low
            xtea_start <= 0; // Default low

            // Writes
            if (p2_write_strobe) begin
                $display("Pico2 Write: Port=%h Data=%h Time=%t", p2_port_id, p2_out_port, $time);
                case (p2_port_id)
                    8'h20: mem2_addr <= p2_out_port; // Mem2 Addr
                    
                    // KEY LOAD (0x30)
                    8'h30: begin
                        $display("Loading Key Byte %d: %h", key_byte_ptr, p2_out_port);
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
                    end

                    // DATA LOAD (0x31)
                    8'h31: begin
                         $display("Loading Data Byte %d: %h", data_byte_ptr, p2_out_port);
                         case (data_byte_ptr)
                            3'd0: data_in_reg[7:0] <= p2_out_port;
                            3'd1: data_in_reg[15:8] <= p2_out_port;
                            3'd2: data_in_reg[23:16] <= p2_out_port;
                            3'd3: data_in_reg[31:24] <= p2_out_port;
                            3'd4: data_in_reg[39:32] <= p2_out_port;
                            3'd5: data_in_reg[47:40] <= p2_out_port;
                            3'd6: data_in_reg[55:48] <= p2_out_port;
                            3'd7: data_in_reg[63:56] <= p2_out_port;
                        endcase
                        data_byte_ptr <= data_byte_ptr + 1;
                    end

                    // CONTROL (0x33)
                    8'h33: begin
                        $display("XTEA Start Signal! Mode=%b Time=%t", p2_out_port, $time);
                        xtea_start <= p2_out_port[0];
                        xtea_mode <= p2_out_port[1];
                        // Reset loading pointers
                        key_byte_ptr <= 0;
                        data_byte_ptr <= 0;
                        result_byte_ptr <= 0;
                    end

                    // MEM3 ADDR (0x40)
                    8'h40: mem3_addr <= p2_out_port;

                    // MEM3 DATA (0x41)
                    8'h41: begin
                        $display("Writing Result to Mem3: Addr=%h Data=%h", mem3_addr, p2_out_port);
                        mem3_din <= p2_out_port;
                        mem3_we <= 1;
                    end
                endcase
            end

            // Reads (Side Effects)
            if (p2_read_strobe && p2_port_id == 8'h35) begin
                result_byte_ptr <= result_byte_ptr + 1;
            end
        end
    end

endmodule
