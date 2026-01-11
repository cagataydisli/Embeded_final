`timescale 1ns / 1ps

// ============================================================================
// pico2_emulator_v13 - DUAL CORE SUPPORT
// Reads Key from Mem2
// Reads Data from FIFO (sent by Pico1)
// Controls XTEA
// Writes Result to Mem3
// ============================================================================

module pico2_emulator_v13 (
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
    input logic [7:0] in_port,  // Data from System (Mem2 / FIFO / XTEA / Mem3)
    input logic interrupt,
    output logic interrupt_ack,
    input logic sleep
);
    
    typedef enum logic [4:0] {
        S_INIT,
        // Key Reading (Mem2)
        S_READ_KEY_ADDR,   
        S_READ_KEY_REQ,
        S_READ_KEY_WAIT,
        S_READ_KEY_CAPTURE,
        
        // Data Reading (FIFO) - CHANGED
        S_CHECK_FIFO_STATUS,
        S_READ_FIFO_REQ,
        S_READ_FIFO_WAIT, 
        S_READ_FIFO_WAIT_RAM, // Added for FIFO Latency
        S_READ_FIFO_CAPTURE,

        // XTEA Control
        S_SEND_KEY, 
        S_SEND_DATA, 
        S_START_ENC,
        S_WAIT_READY,
        
        // Result Reading (XTEA Output)
        S_READ_RESULT_SETUP,
        S_READ_RESULT,
        
        // Result Writing (Mem3)
        S_WRITE_ADDR, 
        S_WRITE_DATA, 
        S_STOP 
    } state_t;

    state_t state;
    
    // Counters & Registers
    logic [4:0] byte_counter; 
    logic [7:0] key_mem_ptr;
    logic [7:0] result_mem_ptr;
    
    logic [7:0] key_buffer [0:15];
    logic [7:0] data_buffer [0:7];

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
            result_mem_ptr <= 0;
        end else begin
            write_strobe <= 0;
            read_strobe <= 0;

            case (state)
                S_INIT: begin
                    state <= S_READ_KEY_ADDR;
                    key_mem_ptr <= 0;
                    result_mem_ptr <= 0;
                    byte_counter <= 0;
                end
                
                // =====================================================
                // 1. KEY READ (Mem2) - unchanged
                // =====================================================
                S_READ_KEY_ADDR: begin
                    port_id <= 8'h20; // KEY ADDR
                    out_port <= key_mem_ptr;
                    write_strobe <= 1;
                    state <= S_READ_KEY_REQ;
                end

                S_READ_KEY_REQ: begin
                    port_id <= 8'h21; // KEY DATA
                    read_strobe <= 1; 
                    state <= S_READ_KEY_WAIT;
                end

                S_READ_KEY_WAIT: begin
                    port_id <= 8'h21;
                    state <= S_READ_KEY_CAPTURE;
                end

                S_READ_KEY_CAPTURE: begin
                    key_buffer[byte_counter] <= in_port; 
                    key_mem_ptr <= key_mem_ptr + 1;
                    byte_counter <= byte_counter + 1;
                    
                    if (byte_counter == 15) begin 
                        state <= S_CHECK_FIFO_STATUS; // Done Key, go to FIFO
                        byte_counter <= 0;
                    end else begin
                        state <= S_READ_KEY_ADDR; 
                    end
                end

                // =====================================================
                // 2. DATA READ (FIFO) - NEW
                // Port 0x22: FIFO Data Read
                // Port 0x23: FIFO Status (Bit 0: Empty)
                // =====================================================
                S_CHECK_FIFO_STATUS: begin
                    port_id <= 8'h23; // Read FIFO Status
                    read_strobe <= 1;
                    // Need a wait state to capture status?
                    // Assuming combinational/fast enough or adding a wait state if needed.
                    // For emulator safety, let's add a wait.
                    state <= S_READ_FIFO_WAIT; // Use this as status wait
                end
                
                // Using S_READ_FIFO_WAIT as a generic wait state here is messy.
                // Let's make it simpler: Just try to read 0x22. 
                // If System Top ensures we wait for 'not empty', we can simplify.
                // But let's check status properly.
                
                // Actually, let's just assume we polling Status until NOT EMPTY.
                
                S_READ_FIFO_WAIT: begin // Status is ready to be captured
                     port_id <= 8'h23;
                     if (in_port[0] == 0) begin // Bit 0 = Empty. 0 means Not Empty? No usually 1 is Empty.
                         // Let's assume Bit 0 = 1 is EMPTY.
                         // Convert logic: if Empty (1), keep waiting. If Not Empty (0), Read Data.
                         if (in_port[0] == 0) begin
                             state <= S_READ_FIFO_REQ;
                         end else begin
                            // FIFO Empty, retry status check
                            state <= S_CHECK_FIFO_STATUS; // Retry
                         end
                     end else begin
                         // Still empty
                         state <= S_CHECK_FIFO_STATUS;
                     end
                end

                S_READ_FIFO_REQ: begin
                    port_id <= 8'h22; // FIFO Data
                    read_strobe <= 1; // Perform Read (Pops from FIFO)
                    state <= S_READ_FIFO_WAIT_RAM; // Go to wait state
                end

                S_READ_FIFO_WAIT_RAM: begin
                    // Wait for FIFO RAM output to stabilize (1 cycle latency)
                    state <= S_READ_FIFO_CAPTURE;
                end

                S_READ_FIFO_CAPTURE: begin
                    // Data is now valid on in_port
                    data_buffer[byte_counter] <= in_port; 
                    byte_counter <= byte_counter + 1;
                    
                    if (byte_counter == 7) begin // 8 bytes done
                        state <= S_SEND_KEY;
                        byte_counter <= 0;
                    end else begin
                        state <= S_CHECK_FIFO_STATUS; // Go back to check for next byte
                    end
                end

                // =====================================================
                // 3. XTEA OPERATIONS - Same as v12
                // =====================================================
                S_SEND_KEY: begin
                    port_id <= 8'h30;
                    out_port <= key_buffer[byte_counter]; 
                    write_strobe <= 1;
                    if (byte_counter == 15) begin
                        state <= S_SEND_DATA;
                        byte_counter <= 0;
                    end else begin
                        byte_counter <= byte_counter + 1;
                    end
                end

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

                S_START_ENC: begin
                    port_id <= 8'h33; 
                    out_port <= 8'h03; // DECRYPT MODE (default for verification)
                    write_strobe <= 1;
                    state <= S_WAIT_READY;
                end

                S_WAIT_READY: begin
                    port_id <= 8'h34;
                    if (in_port[0] == 1) begin
                        state <= S_READ_RESULT_SETUP;
                        byte_counter <= 0;
                    end
                end
                
                S_READ_RESULT_SETUP: begin
                    port_id <= 8'h35; 
                    read_strobe <= 1; 
                    state <= S_READ_RESULT;
                end

                S_READ_RESULT: begin
                    port_id <= 8'h35;
                    data_buffer[byte_counter] <= in_port; 
                    byte_counter <= byte_counter + 1;
                    if (byte_counter == 7) begin
                        state <= S_WRITE_ADDR;
                        byte_counter <= 0;
                        result_mem_ptr <= 0; 
                    end else begin
                        read_strobe <= 1;
                    end
                end

                // =====================================================
                // 4. MEM3 WRITING
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
                     // Stay here
                end

            endcase
        end
    end
endmodule
