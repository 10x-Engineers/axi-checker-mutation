// SVA evaluation smoke test. expected.txt lists every failure IEEE 1800 semantics require
// (cross-checked against a commercial simulator); check_env.sh diffs against it.
// A simulator that lets any of them pass would silently disarm correct checkers.
module sva_smoke;
  logic clk = 0, rstn = 0;
  always #5 clk = ~clk;
  logic v = 0, r = 0;
  logic [31:0] a = 32'h100;
  logic [7:0]  l = 0;

  p_one: assert property (@(posedge clk) disable iff (!rstn) (v && !r) |=> $stable(a));
  p_or:  assert property (@(posedge clk) disable iff (!rstn) (v && !r) |=> (!v || ($stable(a) && $stable(l))));
  p_or1: assert property (@(posedge clk) disable iff (!rstn) (v && !r) |=> (!v || $stable(a)));
  p_and: assert property (@(posedge clk) disable iff (!rstn) (v && !r) |=> ($stable(a) && $stable(l)));
  p_hold: assert property (@(posedge clk) disable iff (!rstn) (v && !r) |-> ##1 (v || $past(r)));

  initial begin
    repeat (2) @(posedge clk); rstn <= 1;
    repeat (2) @(posedge clk);
    v <= 1;                                  // valid, not ready
    @(posedge clk); a <= 32'h104;            // payload changes before the handshake
    @(posedge clk); a <= 32'h100; v <= 0;    // ...and VALID drops before it
    @(posedge clk); v <= 1;
    @(posedge clk); r <= 1;
    @(posedge clk); v <= 0; r <= 0;
    repeat (3) @(posedge clk);
    $display("SVA_SMOKE_DONE");
    $finish;
  end
endmodule
