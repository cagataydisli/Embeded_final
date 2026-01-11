`timescale 1ns / 1ps

// ============================================================================
// pico2_emulator_v12 - FIXED KEY LOADING
// Key'i Mem2'den okuyarak doğru şekilde yükler
// ============================================================================

module pico2_emulator_v12 (
    input logic clk,
    input logic rst,
    input logic [11:0] address,
    input logic [17:0] instruction,
    output logic bram_enable,
    output logic [7:0] port_id,
    output logic write_strobe,
    output logic k_write_strobe,
    output logic [7:0] out_port,
    output logic read_strobe,
    input logic [7:0] in_port,
    input logic interrupt,
    output logic interrupt_ack,
    input logic sleep
);
    
    // v12: FIXED KEY LOADING FROM MEM2
    // Key artık Mem2'den okunuyor, counter değil!
    
    typedef enum logic [4:0] {
        S_INIT,
        // Key okuma (Mem2'den 16 byte)
        S_READ_KEY_ADDR,   
        S_READ_KEY_REQ,
        S_READ_KEY_WAIT,
        S_READ_KEY_CAPTURE,
        // Data okuma (Mem1'den 8 byte)
        S_READ_DATA_ADDR,   
        S_READ_DATA_REQ,
        S_READ_DATA_WAIT,
        S_READ_DATA_CAPTURE,
        // XTEA'ya gönderme
        S_SEND_KEY, 
        S_SEND_DATA, 
        S_START_ENC,
        S_WAIT_READY,
        S_READ_RESULT_SETUP,
        S_READ_RESULT,
        S_WRITE_ADDR, 
        S_WRITE_DATA, 
        S_STOP 
    } state_t;

    state_t state;
    
    // Counters
    logic [4:0] byte_counter; // 5-bit for up to 16 bytes (key)
    
    // Memory pointers
    logic [7:0] key_mem_ptr;   // Mem2 (Key) pointer
    logic [7:0] data_mem_ptr;  // Mem1 (Data) pointer
    logic [7:0] result_mem_ptr; // Mem3 (Result) pointer
    
    // Buffers
    logic [7:0] key_buffer [0:15];   // 16 bytes for 128-bit key
    logic [7:0] data_buffer [0:7];   // 8 bytes for 64-bit data

    // Dummy Outputs
    assign bram_enable = 1;
    assign k_write_strobe = 0;
    assign interrupt_ack = 0;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= S_INIT;
            port_id <= 0; 
            write_strobe <= 0; 
            read_strobe <= 0; 
            out_port <= 0;
            byte_counter <= 0; 
            key_mem_ptr <= 0;
            data_mem_ptr <= 0;
            result_mem_ptr <= 0;
        end else begin
            write_strobe <= 0;
            read_strobe <= 0;

            case (state)
                S_INIT: begin
                    state <= S_READ_KEY_ADDR;
                    key_mem_ptr <= 0;
                    data_mem_ptr <= 0;
                    result_mem_ptr <= 0;
                    byte_counter <= 0;
                end
                
                // =====================================================
                // KEY OKUMA (Mem2'den 16 byte) - Port 0x20/0x21
                // =====================================================
                S_READ_KEY_ADDR: begin
                    port_id <= 8'h20;          // KEY_ADDR_SET
                    out_port <= key_mem_ptr;
                    write_strobe <= 1;
                    state <= S_READ_KEY_REQ;
                end

                S_READ_KEY_REQ: begin
                    port_id <= 8'h21;          // KEY_DATA_READ
                    read_strobe <= 1; 
                    state <= S_READ_KEY_WAIT;
                end

                S_READ_KEY_WAIT: begin
                    port_id <= 8'h21;          // Hold port for data
                    state <= S_READ_KEY_CAPTURE;
                end

                S_READ_KEY_CAPTURE: begin
                    key_buffer[byte_counter] <= in_port; 
                    key_mem_ptr <= key_mem_ptr + 1;
                    byte_counter <= byte_counter + 1;
                    
                    if (byte_counter == 15) begin // 16 bytes done
                        state <= S_READ_DATA_ADDR;
                        byte_counter <= 0;
                        data_mem_ptr <= 0;
                    end else begin
                        state <= S_READ_KEY_ADDR; 
                    end
                end

                // =====================================================
                // DATA OKUMA (Mem1'den 8 byte) - Port 0x22/0x23
                // =====================================================
                S_READ_DATA_ADDR: begin
                    port_id <= 8'h22;          // DATA_ADDR_SET
                    out_port <= data_mem_ptr;
                    write_strobe <= 1;
                    state <= S_READ_DATA_REQ;
                end

                S_READ_DATA_REQ: begin
                    port_id <= 8'h23;          // DATA_DATA_READ
                    read_strobe <= 1; 
                    state <= S_READ_DATA_WAIT;
                end

                S_READ_DATA_WAIT: begin
                    port_id <= 8'h23;          // Hold port for data
                    state <= S_READ_DATA_CAPTURE;
                end

                S_READ_DATA_CAPTURE: begin
                    data_buffer[byte_counter] <= in_port; 
                    data_mem_ptr <= data_mem_ptr + 1;
                    byte_counter <= byte_counter + 1;
                    
                    if (byte_counter == 7) begin // 8 bytes done
                        state <= S_SEND_KEY;
                        byte_counter <= 0;
                    end else begin
                        state <= S_READ_DATA_ADDR; 
                    end
                end

                // =====================================================
                // XTEA KEY YÜKLEME (16 byte from buffer) - Port 0x30
                // =====================================================
                S_SEND_KEY: begin
                    port_id <= 8'h30;
                    out_port <= key_buffer[byte_counter]; // ✅ DOĞRU! Buffer'dan gönder
                    write_strobe <= 1;
                    
                    if (byte_counter == 15) begin
                        state <= S_SEND_DATA;
                        byte_counter <= 0;
                    end else begin
                        byte_counter <= byte_counter + 1;
                    end
                end

                // =====================================================
                // XTEA DATA YÜKLEME (8 byte from buffer) - Port 0x31
                // =====================================================
                S_SEND_DATA: begin
                    port_id <= 8'h31;
                    out_port <= data_buffer[byte_counter];
                    write_strobe <= 1;
                    
                    if (byte_counter == 7) begin
                        state <= S_START_ENC; 
                    end else begin
                        byte_counter <= byte_counter + 1;
                    end
                end

                // =====================================================
                // XTEA BAŞLAT - Port 0x33
                // =====================================================
                S_START_ENC: begin
                    port_id <= 8'h33; 
                    out_port <= 8'h03; // Bit 0=1 (Start), Bit 1=1 (Decrypt)
                    write_strobe <= 1;
                    state <= S_WAIT_READY;
                end

                // =====================================================
                // XTEA READY BEKLEMESİ - Port 0x34
                // =====================================================
                S_WAIT_READY: begin
                    port_id <= 8'h34;
                    if (in_port[0] == 1) begin
                        state <= S_READ_RESULT_SETUP;
                        byte_counter <= 0;
                    end
                end
                
                // =====================================================
                // SONUÇ OKUMA HAZIRLIK
                // =====================================================
                S_READ_RESULT_SETUP: begin
                    port_id <= 8'h35; 
                    read_strobe <= 1;  // Request first byte
                    state <= S_READ_RESULT;
                end

                // =====================================================
                // SONUÇ OKUMA - Port 0x35
                // Capture data AFTER read_strobe sent (pointer now updated)
                // =====================================================
                S_READ_RESULT: begin
                    port_id <= 8'h35;
                    // Capture the current byte (pointer was updated on previous cycle)
                    data_buffer[byte_counter] <= in_port; 
                    byte_counter <= byte_counter + 1;
                    
                    if (byte_counter == 7) begin
                        // All 8 bytes captured
                        state <= S_WRITE_ADDR;
                        byte_counter <= 0;
                        result_mem_ptr <= 0; 
                    end else begin
                        // Request next byte
                        read_strobe <= 1;
                    end
                end

                // =====================================================
                // MEM3'E YAZMA - Port 0x40/0x41
                // =====================================================
                S_WRITE_ADDR: begin
                    port_id <= 8'h40;
                    out_port <= result_mem_ptr;
                    write_strobe <= 1;
                    state <= S_WRITE_DATA; 
                end

                S_WRITE_DATA: begin
                    port_id <= 8'h41;
                    out_port <= data_buffer[byte_counter];
                    write_strobe <= 1;
                    
                    result_mem_ptr <= result_mem_ptr + 1;
                    byte_counter <= byte_counter + 1;
                    
                    if (byte_counter == 7) begin
                        state <= S_STOP; 
                    end else begin
                        state <= S_WRITE_ADDR; 
                    end
                end

                S_STOP: begin
                    // Stay here - simulation complete
                end

            endcase
        end
    end
endmodule
