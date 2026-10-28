// pwm_spi_slave -- oversampled SPI slave, mode 0 (CPOL=0, CPHA=0).
//
// The SPI pins are synchronised into clk_i by the caller; this block only sees
// clean, synchronous versions and detects SCLK edges by comparing with the
// previous sample. There is therefore no SPI clock domain in the design.
// Requirement: f_SCLK <= f_clk/10, SCLK high and low >= 4 clk cycles.
//
// Frame (24 bits, MSB first): [23] 1=write/0=read, [22:16] address (only [19:16]
// decoded), [15:0] data. A write is issued when the 24th bit arrives. For a read,
// the address is known after 8 bits; the data is loaded on the following SCLK
// falling edge and shifted out on MISO, one bit per falling edge.

`default_nettype none

module pwm_spi_slave (
    input  wire        clk_i,
    input  wire        rst_i,      // synchronous, active high
    input  wire        sclk_i,     // synchronised
    input  wire        cs_ni,      // synchronised
    input  wire        mosi_i,     // synchronised (same latency as sclk_i)
    output wire        miso_o,
    output wire        miso_oe_o,
    output reg         wr_o,       // one-cycle write strobe
    output reg  [ 3:0] waddr_o,
    output reg  [15:0] wdata_o,
    output wire [ 3:0] raddr_o,
    input  wire [15:0] rdata_i
);

  reg        sclk_q;
  reg        cs_q;
  reg [ 4:0] bitcnt_q;  // bits received in this frame, 0..24
  reg [22:0] rx_q;
  reg [15:0] tx_q;

  wire active    = ~cs_ni;
  wire sclk_rise = sclk_i & ~sclk_q;
  wire sclk_fall = ~sclk_i & sclk_q;

  // After 8 bits the command byte sits in rx_q[7:0]; its low nibble is the address.
  assign raddr_o   = rx_q[3:0];
  assign miso_o    = tx_q[15];
  assign miso_oe_o = cs_q;

  always @(posedge clk_i) begin
    if (rst_i) begin
      sclk_q   <= 1'b0;
      cs_q     <= 1'b0;
      bitcnt_q <= 5'd0;
      rx_q     <= 23'd0;
      tx_q     <= 16'd0;
      wr_o     <= 1'b0;
      waddr_o  <= 4'd0;
      wdata_o  <= 16'd0;
    end else begin
      sclk_q <= sclk_i;
      cs_q   <= active;
      wr_o   <= 1'b0;

      if (!active) begin
        bitcnt_q <= 5'd0;
        tx_q     <= 16'd0;
      end else begin
        if (sclk_rise && bitcnt_q != 5'd24) begin
          rx_q     <= {rx_q[21:0], mosi_i};
          bitcnt_q <= bitcnt_q + 5'd1;
          if (bitcnt_q == 5'd23 && rx_q[22]) begin
            wr_o    <= 1'b1;
            waddr_o <= rx_q[18:15];
            wdata_o <= {rx_q[14:0], mosi_i};
          end
        end
        if (sclk_fall) begin
          if (bitcnt_q == 5'd8) tx_q <= rdata_i;
          else if (bitcnt_q > 5'd8 && bitcnt_q != 5'd24) tx_q <= {tx_q[14:0], 1'b0};
        end
      end
    end
  end

endmodule

`default_nettype wire
