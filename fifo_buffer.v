`timescale 1ns / 1ps

module fifo_buffer #(
    parameter DEPTH = 16,       
    parameter DATA_WIDTH = 8
)(
    input  wire clk,
    input  wire rst,
    input  wire wr_en,                 
    input  wire [DATA_WIDTH-1:0] din,  
    input  wire rd_en,                 
    output reg  [DATA_WIDTH-1:0] dout, 
    output reg  full,                  
    output reg  empty                  
);

    // Calculate Log2 of DEPTH for pointer widths
    function integer clog2;
        input integer value;
        begin
            value = value - 1;
            for (clog2 = 0; value > 0; clog2 = clog2 + 1)
                value = value >> 1;
        end
    endfunction

    localparam ADDR_WIDTH = clog2(DEPTH);

    // Memory Array
    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];
    
    // Pointers
    reg [ADDR_WIDTH-1:0] wr_ptr;
    reg [ADDR_WIDTH-1:0] rd_ptr;
    reg [ADDR_WIDTH:0] count;
    reg [ADDR_WIDTH:0] next_count;

    // Write Logic
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            wr_ptr <= 0;
        end else if (wr_en && !full) begin
            mem[wr_ptr] <= din;
            if (wr_ptr == DEPTH-1)
                wr_ptr <= 0;
            else
                wr_ptr <= wr_ptr + 1;
        end
    end

    // Read Logic
    // MODIFICATION: Combinational Read (FWFT) for PicoBlaze compatibility
    // PicoBlaze expects ready data when RDPRT is executed.
    always @(*) begin
        dout = mem[rd_ptr];
    end

    // Pointer Update
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            rd_ptr <= 0;
        end else if (rd_en && !empty) begin
            // dout <= mem[rd_ptr]; // REMOVED registered output
            if (rd_ptr == DEPTH-1)
                rd_ptr <= 0;
            else
                rd_ptr <= rd_ptr + 1;
        end
    end

    // Counter Logic
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            count <= 0;
        end else begin
            if (wr_en && !full && rd_en && !empty)
                count <= count;
            else if (wr_en && !full)
                count <= count + 1;
            else if (rd_en && !empty)
                count <= count - 1;
        end
    end

    // Combinational Next Count Logic
    always @(*) begin
        if (wr_en && !full && rd_en && !empty)
            next_count = count;
        else if (wr_en && !full)
            next_count = count + 1;
        else if (rd_en && !empty)
            next_count = count - 1;
        else
            next_count = count;
    end

    // Full/Empty Flags
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            full <= 0;
            empty <= 1;
        end else begin
            full <= (next_count == DEPTH);
            empty <= (next_count == 0);
        end
    end

endmodule
