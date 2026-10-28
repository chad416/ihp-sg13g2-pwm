// pwm_regs -- software-visible register file (pending values) and read mux.
//
// PERIOD/CMPx/DEADTIME written here are the *pending* values; pwm_timebase
// copies them into the active (shadow) registers at the period valley.

`default_nettype none

module pwm_regs #(
    parameter integer CNT_W = 16,
    parameter integer DT_W  = 10
) (
    input  wire             clk_i,
    input  wire             rst_i,
    // bus
    input  wire             wr_i,
    input  wire [      3:0] waddr_i,
    input  wire [     15:0] wdata_i,
    input  wire [      3:0] raddr_i,
    output reg  [     15:0] rdata_o,
    // control
    output reg              en_o,
    output reg              outen_o,
    output reg              hold_o,
    output reg              fclr_o,    // one-cycle pulse
    output reg  [CNT_W-1:0] per_o,
    output reg  [CNT_W-1:0] cmpa_o,
    output reg  [CNT_W-1:0] cmpb_o,
    output reg  [CNT_W-1:0] cmpc_o,
    output reg  [ DT_W-1:0] dt_o,
    // status
    input  wire             fault_latched_i,
    input  wire             fault_in_i,
    input  wire             dir_i,
    input  wire             safe_i,
    input  wire [CNT_W-1:0] cnt_i
);

  localparam [3:0] A_CTRL = 4'h0, A_STATUS = 4'h1, A_PERIOD = 4'h2, A_CMPA = 4'h3,
                   A_CMPB = 4'h4, A_CMPC = 4'h5, A_DEADTIME = 4'h6, A_CNT = 4'h7,
                   A_ID = 4'hF;
  localparam [15:0] ID_VALUE = 16'h5033;

  always @(posedge clk_i) begin
    if (rst_i) begin
      en_o    <= 1'b0;
      outen_o <= 1'b0;
      hold_o  <= 1'b0;
      fclr_o  <= 1'b0;
      per_o   <= {CNT_W{1'b0}};
      cmpa_o  <= {CNT_W{1'b0}};
      cmpb_o  <= {CNT_W{1'b0}};
      cmpc_o  <= {CNT_W{1'b0}};
      dt_o    <= {DT_W{1'b1}};  // fail-safe: maximum dead time
    end else begin
      fclr_o <= 1'b0;
      if (wr_i) begin
        case (waddr_i)
          A_CTRL: begin
            en_o    <= wdata_i[0];
            outen_o <= wdata_i[1];
            hold_o  <= wdata_i[2];
            fclr_o  <= wdata_i[3];
          end
          A_PERIOD:   per_o <= wdata_i[CNT_W-1:0];
          A_CMPA:     cmpa_o <= wdata_i[CNT_W-1:0];
          A_CMPB:     cmpb_o <= wdata_i[CNT_W-1:0];
          A_CMPC:     cmpc_o <= wdata_i[CNT_W-1:0];
          A_DEADTIME: dt_o <= wdata_i[DT_W-1:0];
          default: ;
        endcase
      end
    end
  end

  always @(*) begin
    rdata_o = 16'h0000;
    case (raddr_i)
      A_CTRL:     rdata_o[2:0] = {hold_o, outen_o, en_o};
      A_STATUS:   rdata_o[3:0] = {safe_i, dir_i, fault_in_i, fault_latched_i};
      A_PERIOD:   rdata_o[CNT_W-1:0] = per_o;
      A_CMPA:     rdata_o[CNT_W-1:0] = cmpa_o;
      A_CMPB:     rdata_o[CNT_W-1:0] = cmpb_o;
      A_CMPC:     rdata_o[CNT_W-1:0] = cmpc_o;
      A_DEADTIME: rdata_o[DT_W-1:0] = dt_o;
      A_CNT:      rdata_o[CNT_W-1:0] = cnt_i;
      A_ID:       rdata_o = ID_VALUE;
      default:    ;
    endcase
  end

endmodule

`default_nettype wire
