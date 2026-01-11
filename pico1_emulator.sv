`timescale 1ns / 1ps

module pico1_emulator (
    input  logic clk,
    input  logic rst,
    // PicoBlaze-like Interface
    input  logic [7:0] in_port,     // Data from System (Mem1)
    output logic [7:0] out_port,    // Data to System (FIFO / Mem1 Addr)
    output logic [7:0] port_id,     // Port Address
    output logic write_strobe,      // Write Enable
    output logic read_strobe        // Read Enable
);

    // States
    typedef enum logic [2:0] {
        IDLE,
        SET_ADDR,
        READ_WAIT,
        READ_WAIT_2,
        READ_DATA,
        WRITE_FIFO,
        NEXT_BYTE,
        DONE
    } state_t;

    state_t state;
    logic [2:0] byte_ctr; // 0 to 7
    logic [7:0] data_reg;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            byte_ctr <= 0;
            write_strobe <= 0;
            read_strobe <= 0;
            port_id <= 0;
            out_port <= 0;
        end else begin
            // Default strobes
            write_strobe <= 0;
            read_strobe <= 0;

            case (state)
                IDLE: begin
                    byte_ctr <= 0;
                    state <= SET_ADDR;
                end

                // 1. Set Memory Address (Port 0x30)
                SET_ADDR: begin
                    port_id <= 8'h30;
                    out_port <= {5'b0, byte_ctr}; // Address 0..7
                    write_strobe <= 1;
                    state <= READ_WAIT;
                end

                // 2. Wait for Memory Access (Two cycle delay for Addr Latch + RAM Access)
                READ_WAIT: begin
                    // Prepare to read from Port 0x31
                    port_id <= 8'h31;
                    read_strobe <= 1; 
                    state <= READ_WAIT_2; // Added Wait State
                end

                READ_WAIT_2: begin
                    port_id <= 8'h31;
                    read_strobe <= 1; 
                    state <= READ_DATA;
                end

                // 3. Capture Data from Memory
                READ_DATA: begin
                    // Data is available on in_port now (if system logic serves it combinatorially or registered)
                    // Assuming we captured it or it's holding. Capturing now.
                    port_id <= 8'h31; 
                    data_reg <= in_port; // Capture from Mem1
                    state <= WRITE_FIFO;
                end

                // 4. Write to FIFO (Port 0x20)
                WRITE_FIFO: begin
                    port_id <= 8'h20;
                    out_port <= data_reg;
                    write_strobe <= 1; // Trigger FIFO write
                    state <= NEXT_BYTE;
                end

                // 5. Check loop
                NEXT_BYTE: begin
                    if (byte_ctr == 7) begin
                        state <= DONE; // Transfer Complete
                    end else begin
                        byte_ctr <= byte_ctr + 1;
                        state <= SET_ADDR;
                    end
                end

                DONE: begin
                    // Stay here
                    state <= DONE;
                end
            endcase
        end
    end

endmodule
