// AD9361 SPI Slave Model — Minimal Responder
//
// SPI Mode 1 (CPOL=0, CPHA=1): data changes on rising edge, sampled on falling.
// AD9361 protocol: 16-bit command {R_nW, CNT[2:0], 2'b00, ADDR[9:0]}, then data bytes.
// Multi-byte reads auto-decrement the address.

module ad9361_spi_slave (
    input  wire spi_clk,
    input  wire spi_csn,
    input  wire spi_mosi,
    output reg  spi_miso
);

    reg [7:0] regs [0:1023];

    reg [15:0] cmd_shift;
    reg [7:0]  data_shift;
    reg [4:0]  bit_cnt;
    reg        cmd_done;
    reg        r_nw;
    reg [2:0]  byte_cnt;
    reg [2:0]  bytes_remaining;
    reg [9:0]  addr;

    integer i;

    initial begin
        for (i = 0; i < 1024; i = i + 1)
            regs[i] = 8'h00;
        regs[10'h037] = 8'h0A;  // AD9361 product ID
        spi_miso = 1'b0;
        cmd_shift = 16'h0000;
        data_shift = 8'h00;
        bit_cnt = 5'd0;
        cmd_done = 1'b0;
        r_nw = 1'b0;
        byte_cnt = 3'd0;
        bytes_remaining = 3'd0;
        addr = 10'd0;
    end

    // CSN rising edge = end of transaction
    always @(posedge spi_csn) begin
        if (cmd_done && !r_nw && byte_cnt > 0) begin
            // Write transaction completed — data already stored
        end
        bit_cnt <= 5'd0;
        cmd_done <= 1'b0;
        byte_cnt <= 3'd0;
        bytes_remaining <= 3'd0;
        spi_miso <= 1'b0;
    end

    // Sample MOSI on falling edge (SPI Mode 1, CPHA=1)
    always @(negedge spi_clk) begin
        if (!spi_csn) begin
            if (!cmd_done) begin
                cmd_shift <= {cmd_shift[14:0], spi_mosi};
                bit_cnt <= bit_cnt + 1;
                if (bit_cnt == 5'd15) begin
                    cmd_done <= 1'b1;
                    // AD9361: bit 15 = 0 (read) / 1 (write). Invert so r_nw=1 means read.
                    r_nw <= ~cmd_shift[14];
                    bytes_remaining <= cmd_shift[13:11] + 1; // CNT field
                    addr <= {cmd_shift[8:0], spi_mosi}; // ADDR field (last bit is current mosi)
                    byte_cnt <= 3'd0;
                    bit_cnt <= 5'd0;
                    // For reads, pre-load first data byte
                    data_shift <= regs[{cmd_shift[8:0], spi_mosi}];
                end
            end else begin
                // Data phase
                bit_cnt <= bit_cnt + 1;
                if (r_nw) begin
                    // Read: ignore MOSI during data phase
                end else begin
                    // Write: capture MOSI bits
                    data_shift <= {data_shift[6:0], spi_mosi};
                end
                if (bit_cnt == 5'd7) begin
                    bit_cnt <= 5'd0;
                    if (!r_nw) begin
                        // Write: store received byte
                        regs[addr] <= {data_shift[6:0], spi_mosi};
                        $display("[SPI] %0t: WRITE  addr=0x%03h data=0x%02h", $time, addr, {data_shift[6:0], spi_mosi});
                    end else begin
                        $display("[SPI] %0t: READ   addr=0x%03h data=0x%02h", $time, addr, regs[addr]);
                    end
                    byte_cnt <= byte_cnt + 1;
                    addr <= addr - 1; // auto-decrement
                    if (r_nw)
                        data_shift <= regs[addr - 1]; // pre-load next byte for read
                end
            end
        end
    end

    // Drive MISO on rising edge (SPI Mode 1, CPHA=1)
    always @(posedge spi_clk) begin
        if (!spi_csn && cmd_done && r_nw) begin
            spi_miso <= data_shift[7];
            data_shift <= {data_shift[6:0], 1'b0};
        end else begin
            spi_miso <= 1'b0;
        end
    end

endmodule
