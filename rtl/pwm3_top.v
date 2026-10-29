// pwm3_top -- 3-phase centre-aligned PWM generator with dead-time insertion,
// fault shutdown and an SPI register interface. See SPEC.md for the contract.
//
//   pins --> pwm_sync2 --> pwm_spi_slave --> pwm_regs --> pwm_timebase --> 3x pwm_deadtime --> pins
//                  \--> fault latch ----------------------------------------/ (safe)
//
// Single clock (clk_i), synchronous active-high reset derived from rst_ni through
// a 2-flop synchroniser. Every asynchronous input is synchronised; every output
// is driven straight from a flip-flop.

`default_nettype none

module pwm3_top #(
    parameter integer CNT_W = 16,  // <= 16 (register width)
    parameter integer DT_W  = 10   // <= 16
) (
    input  wire       clk_i,
    input  wire       rst_ni,
    // SPI slave, mode 0
    input  wire       spi_sclk_i,
    input  wire       spi_cs_ni,
    input  wire       spi_mosi_i,
    output wire       spi_miso_o,
    output wire       spi_miso_oe_o,
    // protection
    input  wire       fault_i,
    // gate drive commands, [0]=A [1]=B [2]=C
    output wire [2:0] pwm_h_o,
    output wire [2:0] pwm_l_o,
    output wire       sync_o
);

  // ---------------------------------------------------------------------------
  // Synchronisers
  // ---------------------------------------------------------------------------
  wire rst_n_s;
  pwm_sync2 #(.W(1)) u_rst_sync (
      .clk_i(clk_i),
      .d_i  (rst_ni),
      .q_o  (rst_n_s)
  );
  wire rst = ~rst_n_s;

  wire sclk_s, cs_n_s, mosi_s, fault_s;
  pwm_sync2 #(.W(4)) u_in_sync (
      .clk_i(clk_i),
      .d_i  ({fault_i, spi_mosi_i, spi_cs_ni, spi_sclk_i}),
      .q_o  ({fault_s, mosi_s, cs_n_s, sclk_s})
  );

  // ---------------------------------------------------------------------------
  // Register interface
  // ---------------------------------------------------------------------------
  wire        wr;
  wire [ 3:0] waddr, raddr;
  wire [15:0] wdata, rdata;

  pwm_spi_slave u_spi (
      .clk_i    (clk_i),
      .rst_i    (rst),
      .sclk_i   (sclk_s),
      .cs_ni    (cs_n_s),
      .mosi_i   (mosi_s),
      .miso_o   (spi_miso_o),
      .miso_oe_o(spi_miso_oe_o),
      .wr_o     (wr),
      .waddr_o  (waddr),
      .wdata_o  (wdata),
      .raddr_o  (raddr),
      .rdata_i  (rdata)
  );

  wire en, outen, hold, fclr;
  wire [CNT_W-1:0] per, cmpa, cmpb, cmpc, cnt;
  wire [DT_W-1:0] dt_pend, dt_act;
  wire dir;
  reg fault_latched_q;
  wire safe = fault_s | fault_latched_q | ~outen;

  pwm_regs #(
      .CNT_W(CNT_W),
      .DT_W (DT_W)
  ) u_regs (
      .clk_i          (clk_i),
      .rst_i          (rst),
      .wr_i           (wr),
      .waddr_i        (waddr),
      .wdata_i        (wdata),
      .raddr_i        (raddr),
      .rdata_o        (rdata),
      .en_o           (en),
      .outen_o        (outen),
      .hold_o         (hold),
      .fclr_o         (fclr),
      .per_o          (per),
      .cmpa_o         (cmpa),
      .cmpb_o         (cmpb),
      .cmpc_o         (cmpc),
      .dt_o           (dt_pend),
      .fault_latched_i(fault_latched_q),
      .fault_in_i     (fault_s),
      .dir_i          (dir),
      .safe_i         (safe),
      .cnt_i          (cnt)
  );

  // ---------------------------------------------------------------------------
  // Fault latch: set by the synchronised fault, cleared by software only when
  // the fault input has gone away.
  // ---------------------------------------------------------------------------
  always @(posedge clk_i) begin
    if (rst) fault_latched_q <= 1'b0;
    else if (fault_s) fault_latched_q <= 1'b1;
    else if (fclr) fault_latched_q <= 1'b0;
  end

  // ---------------------------------------------------------------------------
  // Time base and dead-time units
  // ---------------------------------------------------------------------------
  wire [2:0] pwm_ref;

  pwm_timebase #(
      .CNT_W(CNT_W),
      .DT_W (DT_W)
  ) u_tb (
      .clk_i (clk_i),
      .rst_i (rst),
      .en_i  (en),
      .hold_i(hold),
      .per_i (per),
      .cmpa_i(cmpa),
      .cmpb_i(cmpb),
      .cmpc_i(cmpc),
      .dt_i  (dt_pend),
      .cnt_o (cnt),
      .dir_o (dir),
      .ref_o (pwm_ref),
      .sync_o(sync_o),
      .dt_o  (dt_act)
  );

  genvar i;
  generate
    for (i = 0; i < 3; i = i + 1) begin : g_phase
      pwm_deadtime #(
          .DT_W(DT_W)
      ) u_dt (
          .clk_i (clk_i),
          .rst_i (rst),
          .safe_i(safe),
          .ref_i (pwm_ref[i]),
          .dt_i  (dt_act),
          .h_o   (pwm_h_o[i]),
          .l_o   (pwm_l_o[i])
      );
    end
  endgenerate

`ifdef FORMAL
  // ---------------------------------------------------------------------------
  // Top-level properties. All inputs (SPI pins, fault_i, rst_ni) are free, so
  // the proofs hold for *any* register programming and any SPI traffic.
  // The per-phase no-overlap and dead-time proofs live in pwm_deadtime and are
  // checked here as well, in context.
  // ---------------------------------------------------------------------------
  reg [2:0] f_cyc = 3'd0;
  always @(posedge clk_i) if (f_cyc != 3'd7) f_cyc <= f_cyc + 3'd1;

  // Power-up: rst_ni held low long enough to propagate through the synchroniser.
  always @(*) if (f_cyc < 3'd3) assume (!rst_ni);
  wire f_ok = (f_cyc >= 3'd4);

  wire f_any_on = |{pwm_h_o, pwm_l_o};

  // Independent "tripped" observer: set when the synchronised fault is seen,
  // cleared only by reset or by a CTRL write with FCLR=1 while no fault is
  // present (SPEC 8). It does not look at fault_latched_q.
  reg f_trip = 1'b0;
  always @(posedge clk_i) begin
    if (rst) f_trip <= 1'b0;
    else if (fault_s) f_trip <= 1'b1;
    else if ($past(wr && waddr == 4'h0 && wdata[3])) f_trip <= 1'b0;
  end

  always @(posedge clk_i) begin
    if (f_ok) begin
      // FAULT LATENCY (N = 3): fault_i high when sampled -> all outputs off
      // three clock edges later, independent of any other input.
      if ($past(fault_i, 3)) assert (!f_any_on);
      // After a fault, outputs stay off until software clears it.
      if ($past(f_trip) && !$past(rst)) assert (!f_any_on);
      // Outputs disabled by software -> off.
      if ($past(!outen) && !$past(rst)) assert (!f_any_on);
    end
  end

  // Lemmas for induction.
  always @(*) begin
    if (f_ok) begin
      assert (f_trip == fault_latched_q);
      if (fault_latched_q) assert (safe);
    end
  end

  // Reachability (cover mode): the register path and the fault-clear path work
  // through real SPI frames (the hand-over itself is covered in pwm_deadtime).
  always @(posedge clk_i) begin
    if (f_ok) begin
      cover (wr && waddr == 4'h3);  // SPI write to CMPA
      cover ($past(fault_latched_q) && !fault_latched_q && !$past(rst));  // fault cleared by SW
    end
  end

`ifdef FORMAL_COVER_OUTPUTS
  // The outputs really switch after SPI programming. Only reachable within a
  // short bound when the reset dead time is small, so these are enabled only in
  // the cover_dt2 task (DT_W = 2, reset dead time 3 cycles).
  always @(posedge clk_i) begin
    if (f_ok) begin
      cover (pwm_l_o[0] && !$past(pwm_l_o[0]));  // low side A turns on
      cover (pwm_h_o[0] && !$past(pwm_h_o[0]));  // high side A turns on
    end
  end
`endif
`endif

endmodule

`default_nettype wire
