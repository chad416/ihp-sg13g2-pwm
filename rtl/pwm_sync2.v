// pwm_sync2 -- 2-flop synchroniser for asynchronous single-bit inputs.
//
// Each bit is synchronised independently. Only use this for signals where an
// individual bit may be sampled one cycle early or late (levels, slow strobes);
// never for multi-bit buses. The flops have no reset on purpose: a reset would
// itself need synchronising, and the chain flushes within two cycles anyway.

`default_nettype none

module pwm_sync2 #(
    parameter integer W = 1
) (
    input  wire         clk_i,
    input  wire [W-1:0] d_i,
    output wire [W-1:0] q_o
);

  (* async_reg = "true" *) reg [W-1:0] meta_q;
  (* async_reg = "true" *) reg [W-1:0] sync_q;

  always @(posedge clk_i) begin
    meta_q <= d_i;
    sync_q <= meta_q;
  end

  assign q_o = sync_q;

endmodule

`default_nettype wire
