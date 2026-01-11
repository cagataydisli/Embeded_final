module pico1_emulator (
    input  logic clk,
    input  logic rst,
    // System Arayüzü - KCPSM6 Uyumlu
    output logic [11:0] address,      // Dummy
    input  logic [17:0] instruction,  // Dummy
    output logic        bram_enable,  // Dummy
    output logic [7:0]  port_id,
    output logic [7:0]  out_port,
    input  logic [7:0]  in_port,
    output logic        write_strobe,
    output logic        k_write_strobe, // Dummy
    output logic        read_strobe,
    input  logic        interrupt,      // Dummy
    output logic        interrupt_ack,  // Dummy
    input  logic        sleep           // Dummy
);
    // Dummy outputs
    assign address = 0;
    assign bram_enable = 1;
    assign k_write_strobe = 0;
    assign interrupt_ack = 0;

    // Logic
    typedef enum logic [2:0] {
        S_SET_ADDR, S_READ_MEM, S_CHECK_FIFO, S_WRITE_FIFO, S_NEXT_ADDR
    } state_t;

    state_t state = S_SET_ADDR;
    logic [7:0] mem_ptr = 0;
    logic [7:0] data_reg = 0;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= S_SET_ADDR; mem_ptr <= 0; port_id <= 0; out_port <= 0; write_strobe <= 0; read_strobe <= 0;
        end else begin
            write_strobe <= 0; read_strobe <= 0; // Default Low
            case (state)
                S_SET_ADDR: begin
                    port_id <= 8'h01; out_port <= mem_ptr; write_strobe <= 1; state <= S_READ_MEM;
                end
                S_READ_MEM: begin
                    port_id <= 8'h02; read_strobe <= 1; // MEM Read
                    state <= S_CHECK_FIFO;
                end
                S_CHECK_FIFO: begin
                    data_reg <= in_port; // Capture Mem Data
                    port_id <= 8'h04; read_strobe <= 1; // Read FIFO Status
                    state <= S_WRITE_FIFO;
                end
                S_WRITE_FIFO: begin
                    if (in_port[0] == 0) begin // Not Full
                        port_id <= 8'h03; out_port <= data_reg; write_strobe <= 1; state <= S_NEXT_ADDR;
                    end else state <= S_CHECK_FIFO; // Full, retry
                end
                S_NEXT_ADDR: begin
                    mem_ptr <= mem_ptr + 1;
                    if (mem_ptr == 16) state <= S_SET_ADDR; // Loop or Stop
                    else state <= S_SET_ADDR;
                end
            endcase
        end
    end
endmodule
