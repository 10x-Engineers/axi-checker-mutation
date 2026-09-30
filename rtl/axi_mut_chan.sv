// One AXI channel (VALID/READY + payload) through the mutation interposer.
//
// The real path (src -> dst) is never corrupted: the only thing this stage ever
// does to it is withhold VALID from dst while holding READY low to src, which is
// legal back-pressure. Mutations are applied to the obs_* copy, which shows the
// channel as seen at the source's port and is what the checkers observe.
//
// IHI 0022 L SSA2.1.1 (p.27, MUST): no combinatorial path between an interface's
// inputs and outputs, so the stall is decided from registers only: while armed,
// READY is held low before the next beat arrives, and a beat that turns out not to
// be the target is released one cycle later.

module axi_mut_chan #(
  parameter int W = 8
) (
  input  logic         clk,
  input  logic         rst_n,

  input  logic         src_valid,
  output logic         src_ready,
  input  logic [W-1:0] src_payload,

  output logic         dst_valid,
  input  logic         dst_ready,
  output logic [W-1:0] dst_payload,

  output logic         obs_valid,
  output logic         obs_ready,
  output logic [W-1:0] obs_payload,

  // Static configuration, set once by the interposer at time 0.
  input  axi_mut_pkg::mut_op_e op,
  input  int unsigned  nth,       // 1-based index of the matching beat to hit
  input  logic [W-1:0] tmask,     // beat matches when (payload & tmask) == tval
  input  logic [W-1:0] tval,
  input  logic [W-1:0] xmask,     // bits to flip (GLITCH) or override (OVERRIDE)
  input  logic [W-1:0] xval,
  input  int unsigned  stall,     // back-pressure cycles on the hit beat (>= 2)

  output logic         inject     // high on the cycle the violation is on obs
);
  import axi_mut_pkg::*;

  logic        pending;   // VALID seen on src, handshake not yet taken
  logic        passing;   // current beat was seen while armed and is not the target
  logic        active;    // the hit beat is in progress (after its first cycle)
  logic        fired;
  int unsigned matched;   // matching beats already handshaken
  int unsigned scnt;      // cycle index within the hit beat

  logic stalls_op, armed, beat_start, match, hit_start, tgt, stalling, hs;
  int unsigned cyc;

  assign stalls_op  = (op == MUT_VALID_DROP) || (op == MUT_GLITCH);
  assign armed      = (op != MUT_NONE) && !fired && (matched == nth - 1);
  assign beat_start = src_valid && !pending;
  assign match      = ((src_payload & tmask) == (tval & tmask));
  assign hit_start  = armed && beat_start && match;
  assign tgt        = hit_start || active;
  assign cyc        = hit_start ? 0 : scnt;

  // Registers only: armed/passing/active/scnt/fired/matched.
  assign stalling   = stalls_op && ((armed && !passing) || (active && scnt < stall));

  assign dst_valid   = src_valid && !stalling;
  assign src_ready   = dst_ready && !stalling;
  assign dst_payload = src_payload;
  assign hs          = src_valid && src_ready;

  always_comb begin
    obs_valid   = src_valid;
    obs_ready   = src_ready;
    obs_payload = src_payload;
    inject      = 1'b0;
    if (tgt) begin
      unique case (op)
        MUT_VALID_DROP: if (cyc == 1) begin obs_valid = 1'b0; inject = 1'b1; end
        MUT_GLITCH:     if (cyc == 1) begin obs_payload = src_payload ^ xmask; inject = 1'b1; end
        MUT_OVERRIDE:   begin
                          obs_payload = (src_payload & ~xmask) | (xval & xmask);
                          inject      = (cyc == 0);
                        end
        default: ;
      endcase
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      pending <= 1'b0;
      passing <= 1'b0;
      active  <= 1'b0;
      fired   <= 1'b0;
      matched <= 0;
      scnt    <= 0;
    end else begin
      pending <= src_valid && !hs;
      if (hs)                                        passing <= 1'b0;
      else if (armed && beat_start && !match)        passing <= 1'b1;
      if (hit_start) begin
        fired  <= 1'b1;
        active <= !hs;
        scnt   <= 1;
      end else if (active) begin
        scnt <= scnt + 1;
        if (hs) active <= 1'b0;
      end
      if (hs && match && !tgt && !fired) matched <= matched + 1;
    end
  end
endmodule
