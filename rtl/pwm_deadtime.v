// pwm_deadtime -- complementary output pair with dead-time insertion.
//
// Rule: turning a switch off is immediate; turning a switch on is allowed only
// when the opposite switch is off and both have been off for at least
// DT_eff = max(dt_i, 1) consecutive cycles. Shoot-through is therefore
// impossible by construction, and reference pulses shorter than the dead time
// are swallowed rather than shortened. Outputs are registered.

`default_nettype none

module pwm_deadtime #(
    parameter integer DT_W = 10
) (
    input  wire            clk_i,
    input  wire            rst_i,
    input  wire            safe_i,  // force both off
    input  wire            ref_i,   // 1: high side wanted, 0: low side wanted
    input  wire [DT_W-1:0] dt_i,
    output reg             h_o,
    output reg             l_o
);

  localparam [DT_W-1:0] ONE = {{(DT_W - 1) {1'b0}}, 1'b1};
  localparam [DT_W-1:0] MAX = {DT_W{1'b1}};

  // Consecutive cycles (including the current one) in which h_o = l_o = 0,
  // saturating at MAX. Non-zero only while both outputs are off.
  reg  [DT_W-1:0] off_cnt_q;

  wire [DT_W-1:0] dt_eff = (dt_i == {DT_W{1'b0}}) ? ONE : dt_i;
  wire            gap_ok = ~h_o & ~l_o & (off_cnt_q >= dt_eff);

  reg h_d, l_d;
  always @(*) begin
    if (safe_i) begin
      h_d = 1'b0;
      l_d = 1'b0;
    end else if (ref_i) begin
      h_d = h_o | gap_ok;
      l_d = 1'b0;
    end else begin
      h_d = 1'b0;
      l_d = l_o | gap_ok;
    end
  end

  always @(posedge clk_i) begin
    if (rst_i) begin
      h_o       <= 1'b0;
      l_o       <= 1'b0;
      off_cnt_q <= {DT_W{1'b0}};
    end else begin
      h_o <= h_d;
      l_o <= l_d;
      if (h_d | l_d) off_cnt_q <= {DT_W{1'b0}};
      else if (off_cnt_q != MAX) off_cnt_q <= off_cnt_q + ONE;
    end
  end

`ifdef FORMAL
  // ---------------------------------------------------------------------------
  // Module-level proof with completely unconstrained ref_i, dt_i, safe_i, rst_i.
  // The checker counts both-off cycles from the *outputs only* and does not
  // look at off_cnt_q, so it is an independent observer of the pins.
  // f_off = length of the current run of both-off cycles (including this one,
  // not counting cycles spent in reset), saturating.
  // ---------------------------------------------------------------------------
  reg             f_past_valid = 1'b0;
  reg             f_rst_q = 1'b1;
  reg  [DT_W-1:0] f_off_prev = {DT_W{1'b0}};
  wire [DT_W-1:0] f_off = (f_rst_q || h_o || l_o) ? {DT_W{1'b0}} :
                          (f_off_prev == MAX) ? MAX : f_off_prev + ONE;

  always @(posedge clk_i) begin
    f_past_valid <= 1'b1;
    f_rst_q      <= rst_i;
    f_off_prev   <= f_off;
  end

  // Power-up: start in reset (the real block is reset before use).
  always @(*) if (!f_past_valid) assume (rst_i);

  always @(*) begin
    if (f_past_valid) begin
      // P1: never both switches of the phase on.
      assert (!(h_o && l_o));
      // Induction strengthening: the internal counter equals the observed one.
      assert (off_cnt_q == f_off);
    end
  end

  // Required dead time per SPEC 7, computed by the checker itself.
  wire [DT_W-1:0] f_dt_req = (dt_i == {DT_W{1'b0}}) ? ONE : dt_i;

  always @(posedge clk_i) begin
    if (f_past_valid && !$past(rst_i)) begin
      // P2: every turn-on is preceded by >= max(DT,1) both-off cycles, where
      // DT is the dead time in force when the turn-on was decided.
      if (h_o && !$past(h_o)) assert ($past(f_off) >= $past(f_dt_req) && !$past(l_o));
      if (l_o && !$past(l_o)) assert ($past(f_off) >= $past(f_dt_req) && !$past(h_o));
      // P3: safe request forces both off on the next edge.
      if ($past(safe_i)) assert (!h_o && !l_o);
    end
  end

  // Reachability: both hand-over directions with a non-trivial dead time.
  // (Module-level only; removed with chformal in the top-level cover task.)
  always @(posedge clk_i) begin
    if (f_past_valid && !$past(rst_i)) begin
      cover (h_o && !$past(h_o) && $past(dt_i) == 3);
      cover (l_o && !$past(l_o) && $past(dt_i) == 3);
    end
  end
`endif

endmodule

`default_nettype wire
