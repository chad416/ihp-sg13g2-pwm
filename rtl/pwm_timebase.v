// pwm_timebase -- centre-aligned up/down counter, shadow registers and the
// three per-phase PWM references (before dead time).
//
// Counter sequence for P >= 1: 0,1,..,P-1 (up), P,P-1,..,1 (down), 0, ...
// One period = 2*P cycles. Reference: up -> (cnt < C), down -> (cnt <= C),
// i.e. 2*C high cycles per period, centred on the valley (cnt = 0).
//
// Shadow transfer: the active registers take the pending values in the cycle
// where cnt = 0 (and continuously while disabled), unless hold_i is set. The
// values being loaded are already used in that cycle, so one PWM period
// (valley to valley) always runs on one consistent register set.

`default_nettype none

module pwm_timebase #(
    parameter integer CNT_W = 16,
    parameter integer DT_W  = 10
) (
    input  wire             clk_i,
    input  wire             rst_i,
    input  wire             en_i,
    input  wire             hold_i,
    input  wire [CNT_W-1:0] per_i,
    input  wire [CNT_W-1:0] cmpa_i,
    input  wire [CNT_W-1:0] cmpb_i,
    input  wire [CNT_W-1:0] cmpc_i,
    input  wire [ DT_W-1:0] dt_i,
    output reg  [CNT_W-1:0] cnt_o,
    output reg              dir_o,   // 0 = up, 1 = down
    output reg  [      2:0] ref_o,
    output reg              sync_o,  // registered, aligned with ref_o
    output reg  [ DT_W-1:0] dt_o     // active dead time, aligned with ref_o
);

  reg [CNT_W-1:0] per_q, cmpa_q, cmpb_q, cmpc_q;

  wire             at_zero = (cnt_o == {CNT_W{1'b0}});
  wire             load = ~hold_i & (~en_i | at_zero);

  // Effective values for this cycle: when loading, the new period starts now.
  wire [CNT_W-1:0] per_e = load ? per_i : per_q;
  wire [CNT_W-1:0] cmpa_e = load ? cmpa_i : cmpa_q;
  wire [CNT_W-1:0] cmpb_e = load ? cmpb_i : cmpb_q;
  wire [CNT_W-1:0] cmpc_e = load ? cmpc_i : cmpc_q;

  wire [CNT_W-1:0] per_m1 = per_e - {{(CNT_W - 1) {1'b0}}, 1'b1};

  function automatic cmp_ref(input [CNT_W-1:0] cnt, input down, input [CNT_W-1:0] c);
    cmp_ref = down ? (cnt <= c) : (cnt < c);
  endfunction

  always @(posedge clk_i) begin
    if (rst_i) begin
      per_q  <= {CNT_W{1'b0}};
      cmpa_q <= {CNT_W{1'b0}};
      cmpb_q <= {CNT_W{1'b0}};
      cmpc_q <= {CNT_W{1'b0}};
      dt_o   <= {DT_W{1'b1}};
      cnt_o  <= {CNT_W{1'b0}};
      dir_o  <= 1'b0;
      ref_o  <= 3'b000;
      sync_o <= 1'b0;
    end else begin
      if (load) begin
        per_q  <= per_i;
        cmpa_q <= cmpa_i;
        cmpb_q <= cmpb_i;
        cmpc_q <= cmpc_i;
        dt_o   <= dt_i;
      end

      if (!en_i || per_e == {CNT_W{1'b0}}) begin
        cnt_o <= {CNT_W{1'b0}};
        dir_o <= 1'b0;
      end else if (!dir_o) begin
        if (cnt_o >= per_m1) begin
          cnt_o <= per_e;
          dir_o <= 1'b1;
        end else begin
          cnt_o <= cnt_o + {{(CNT_W - 1) {1'b0}}, 1'b1};
        end
      end else begin
        if (cnt_o <= {{(CNT_W - 1) {1'b0}}, 1'b1}) begin
          cnt_o <= {CNT_W{1'b0}};
          dir_o <= 1'b0;
        end else begin
          cnt_o <= cnt_o - {{(CNT_W - 1) {1'b0}}, 1'b1};
        end
      end

      if (en_i) begin
        ref_o <= {cmp_ref(cnt_o, dir_o, cmpc_e), cmp_ref(cnt_o, dir_o, cmpb_e),
                  cmp_ref(cnt_o, dir_o, cmpa_e)};
      end else begin
        ref_o <= 3'b000;
      end
      sync_o <= en_i & at_zero;
    end
  end

endmodule

`default_nettype wire
