module fifo_buffer #(
    parameter DEPTH = 16,       // Tampon derinliği
    parameter DATA_WIDTH = 8    // Veri genişliği (PicoBlaze 8-bit olduğu için)
)(
    input  logic clk,
    input  logic rst,
    input  logic wr_en,                 // Yazma yetkisi
    input  logic [DATA_WIDTH-1:0] din,  // Yazılacak veri
    input  logic rd_en,                 // Okuma yetkisi
    output logic [DATA_WIDTH-1:0] dout, // Okunan veri
    output logic full,                  // Tampon dolu mu?
    output logic empty                  // Tampon boş mu?
);

    // Bellek Dizisi
    logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];
    
    // İşaretçiler (Pointers)
    logic [$clog2(DEPTH)-1:0] wr_ptr;
    logic [$clog2(DEPTH)-1:0] rd_ptr;
    logic [$clog2(DEPTH):0] count;      // Eleman sayısı sayacı

    // Yazma İşlemi
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            wr_ptr <= 0;
        end else if (wr_en && !full) begin
            mem[wr_ptr] <= din;
            wr_ptr <= (wr_ptr == DEPTH-1) ? 0 : wr_ptr + 1;
        end
    end

    // Okuma İşlemi
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            rd_ptr <= 0;
            dout <= 0; // Reset anında çıkışı temizle
        end else if (rd_en && !empty) begin
            dout <= mem[rd_ptr];
            rd_ptr <= (rd_ptr == DEPTH-1) ? 0 : rd_ptr + 1;
        end
    end

    // Sayaç (Counter) Logic
    always_ff @(posedge clk or posedge rst) begin
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

    // Full ve Empty Bayrakları (Kombinasyonel olarak üretilir, sonra registerlanır)
    // Vivado uyumluluğu için daha basit bir yapı:
    // Bayrakları doğrudan count değerine bakarak sürekli güncellemek yerine,
    // count register'ının bir sonraki değerini tahmin eden ayrı bir mantık kuralım.
    
    // next_count sinyali
    logic [$clog2(DEPTH):0] next_count;
    
    always_comb begin
        if (wr_en && !full && rd_en && !empty)
            next_count = count;
        else if (wr_en && !full)
            next_count = count + 1;
        else if (rd_en && !empty)
            next_count = count - 1;
        else
            next_count = count;
    end

    // Bayrakları Clock ile güncelle (Glichten kaçınmak için registered output)
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            full <= 0;
            empty <= 1;
        end else begin
            full <= (next_count == DEPTH);
            empty <= (next_count == 0);
        end
    end

endmodule
