`timescale 1ns / 1ps

module system_top_dual_pico (
    input logic clk,
    input logic rst,
    // Debug Outputs
    output logic xtea_ready,
    output logic [63:0] xtea_result_out
);

    // =====================================================
    // SIGNALS
    // =====================================================

    // --- PICO 1 ---
    logic [7:0] p1_port_id;
    logic [7:0] p1_out_port;
    logic [7:0] p1_in_port;
    logic p1_write_strobe;
    logic p1_read_strobe;
    logic p1_done;

    // --- PICO 2 ---
    logic [7:0] p2_port_id;
    logic [7:0] p2_out_port;
    logic [7:0] p2_in_port;
    logic p2_write_strobe;
    logic p2_read_strobe;
    logic p2_interrupt; // Not used

    // --- FIFO ---
    logic fifo_wr_en;
    logic [7:0] fifo_din;
    logic fifo_rd_en;
    logic [7:0] fifo_dout;
    logic fifo_full;
    logic fifo_empty;

    // --- MEMORIES ---
    // Mem1 (Data Source)
    logic [7:0] mem1_addr;
    logic [7:0] mem1_data_out;
    
    // Mem2 (Key Source)
    logic [7:0] mem2_addr;
    logic [7:0] mem2_data_out;

    // Mem3 (Result Dest)
    logic [7:0] mem3_addr;
    logic [7:0] mem3_din;
    logic mem3_we;

    // --- XTEA ---
    logic [127:0] key_reg;
    logic [63:0] data_in_reg;
    logic [63:0] xtea_data_out;
    logic xtea_start;
    logic xtea_mode; // 0: Encrypt, 1: Decrypt
    
    // Registers for assembling XTEA inputs (same logic as before)
    logic [3:0] key_byte_ptr;
    logic [2:0] data_byte_ptr;
    logic [2:0] result_byte_ptr;


    // =====================================================
    // INSTANTIATION
    // =====================================================

    // 1. MEM1 (Ciphertext/Plaintext Source)
    // INIT_TYPE=3 for DECRYPTION TEST (Ciphertext)
    single_port_ram #(.INIT_TYPE(3)) ram_mem1 (
        .clk(clk), .we(1'b0), .addr(mem1_addr), .din(8'h00), .dout(mem1_data_out)
    );

    // 2. MEM2 (Key Source)
    single_port_ram #(.INIT_TYPE(2)) ram_mem2 (
        .clk(clk), .we(1'b0), .addr(mem2_addr), .din(8'h00), .dout(mem2_data_out)
    );

    // 3. MEM3 (Result Destination)
    single_port_ram #(.INIT_TYPE(0)) ram_mem3 (
        .clk(clk), .we(mem3_we), .addr(mem3_addr), .din(mem3_din), .dout()
    );

    // 4. FIFO BUFFER
    fifo_buffer #(.DEPTH(16), .DATA_WIDTH(8)) fifo_inst (
        .clk(clk), 
        .rst(rst), 
        .wr_en(fifo_wr_en), 
        .din(fifo_din), 
        .rd_en(fifo_rd_en), 
        .dout(fifo_dout), 
        .full(fifo_full), 
        .empty(fifo_empty)
    );

    // 5. PICO 1 (Data Reader)
    pico1_emulator p1_inst (
        .clk(clk), .rst(rst),
        .port_id(p1_port_id),
        .out_port(p1_out_port),
        .in_port(p1_in_port),
        .write_strobe(p1_write_strobe),
        .read_strobe(p1_read_strobe)
    );

    // 6. PICO 2 (Controller)
    pico2_emulator_v13 p2_inst (
        .clk(clk), .rst(rst),
        .address(12'b0), .instruction(18'b0), // Dummy
        .bram_enable(), .port_id(p2_port_id),
        .write_strobe(p2_write_strobe), .k_write_strobe(),
        .out_port(p2_out_port), .read_strobe(p2_read_strobe),
        .in_port(p2_in_port),
        .interrupt(1'b0), .interrupt_ack(), .sleep(1'b0)
    );

    // 7. XTEA CORE
    xtea_core xtea_inst (
        .clk(clk), .rst(rst),
        .start(xtea_start), 
        .decrypt(xtea_mode), 
        .key(key_reg), .data_in(data_in_reg),
        .data_out(xtea_data_out),
        .ready(xtea_ready)
    );
    
    assign xtea_result_out = xtea_data_out;


    // =====================================================
    // LOGIC & MAPPING
    // =====================================================

    // --- PICO 1 MAPPING ---
    // 0x30: Mem1 Addr Set
    // 0x31: Mem1 Data Read
    // 0x20: FIFO Write
    
    always_comb begin
        p1_in_port = 8'h00;
        
        // Mem1 Address Logic
        if (p1_write_strobe && p1_port_id == 8'h30)
             // Address is captured in register below
             ; 
             
        // FIFO Write Logic
        fifo_wr_en = (p1_write_strobe && p1_port_id == 8'h20);
        fifo_din = p1_out_port;

        // Reads
        if (p1_read_strobe && p1_port_id == 8'h31)
            p1_in_port = mem1_data_out;
        
        // Mem1 Addr Update (Register)
    end
    
    // Register for Mem1 Address (Controlled by Pico1)
    always_ff @(posedge clk or posedge rst) begin
        if (rst) mem1_addr <= 0;
        else if (p1_write_strobe && p1_port_id == 8'h30)
            mem1_addr <= p1_out_port;
    end


    // --- PICO 2 MAPPING ---
    // 0x20: Mem2 Key Addr
    // 0x21: Mem2 Key Data
    // 0x22: FIFO Read Data
    // 0x23: FIFO Status (Bit 0: Empty)
    // 0x3x: XTEA IO (Same as before)
    // 0x4x: Mem3 IO (Same as before)

    // FIFO Read Logic
    assign fifo_rd_en = (p2_read_strobe && p2_port_id == 8'h22);

    // Input Mux for Pico2
    always_comb begin
        p2_in_port = 8'h00;
        
        case (p2_port_id)
            // Mem2 Data
            8'h21: p2_in_port = mem2_data_out;
            
            // FIFO Data
            8'h22: p2_in_port = fifo_dout;
            
            // FIFO Status
            8'h23: p2_in_port = {7'b0, fifo_empty}; // Bit 0 = Empty

            // XTEA Status
            8'h34: p2_in_port = {7'b0, xtea_ready};
            
            // XTEA Result
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

    // Output/Register Logic for Pico2
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            mem2_addr <= 0;
            mem3_addr <= 0;
            mem3_din <= 0;
            mem3_we <= 0;
            
            key_reg <= 0;
            data_in_reg <= 0;
            xtea_start <= 0;
            xtea_mode <= 0; // Default Encrypt
            
            key_byte_ptr <= 0;
            data_byte_ptr <= 0;
            result_byte_ptr <= 0;
        end else begin
            // Default WE
            mem3_we <= 0;
            xtea_start <= 0;

            if (p2_write_strobe) begin
                case (p2_port_id)
                    // Mem2 Addr
                    8'h20: mem2_addr <= p2_out_port;
                    
                    // XTEA Key Loading (Port 0x30)
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
                    end
                    
                    // XTEA Data Loading (Port 0x31)
                    8'h31: begin
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
                    
                    // XTEA Control (Port 0x33)
                    8'h33: begin
                        xtea_start <= p2_out_port[0]; // Bit 0: Start
                        xtea_mode <= p2_out_port[1];  // Bit 1: Mode (0:Enc, 1:Dec)
                        
                        // Reset Pointers
                        key_byte_ptr <= 0;
                        data_byte_ptr <= 0;
                        result_byte_ptr <= 0; // Reset read pointer for result
                    end

                    // Mem3 Addr (Port 0x40)
                    8'h40: mem3_addr <= p2_out_port;

                    // Mem3 Data (Port 0x41)
                    8'h41: begin
                         mem3_din <= p2_out_port;
                         mem3_we <= 1; // Pulse WE
                    end
                endcase
            end
            
            // PICO2 READ OPERATIONS side-effects (pointer update)
            if (p2_read_strobe) begin
                if (p2_port_id == 8'h35) begin
                    result_byte_ptr <= result_byte_ptr + 1;
                end
            end
        end
    end

endmodule
