// ============================================================
// Reusable self-checking testbench for any signed 8x8
// multiplier whose top module is `booth_multiplier(A, B, product)`.
//
// Run it against ONE design at a time (both B4G3 and Booth R4 use
// the same top name). It checks named corner cases first, then
// EXHAUSTIVELY sweeps all 65,536 signed pairs against golden A*B.
//
//   iverilog -g2012 -o sim <design>.sv tb_booth.sv && vvp sim
//   verilator --binary --top-module tb_booth <design>.sv tb_booth.sv && obj_dir/V*
//   (Vivado xsim: add both files, set tb_booth as top, Run All)
// ============================================================
`timescale 1ns/1ps
module tb_booth;

  logic signed [7:0]  A, B;
  logic signed [15:0] product;
  logic signed [15:0] golden;
  int unsigned errors = 0;
  int unsigned checks = 0;

  booth_multiplier dut (.A(A), .B(B), .product(product));

  task automatic chk(input signed [7:0] a, input signed [7:0] b, input string tag = "");
    A = a; B = b;
    #1;
    golden = a * b;
    checks++;
    if (product !== golden) begin
      errors++;
      if (errors <= 20)
        $display("  FAIL %-22s A=%5d B=%5d  got=%6d  exp=%6d",
                 tag, a, b, product, golden);
    end
  endtask

  initial begin
    // ---------- 1. Corner cases that have actually broken these designs ----------
    $display("--- corner cases ---");
    chk(-128, -128, "min*min  -> +16384");   // -2A overflow + sign-bug corner
    chk(-128,  127, "min*max  -> -16256");
    chk( 127, -128, "max*min");
    chk( 127,  127, "max*max  -> +16129");
    chk(-128,    3, "A=-128 forces -2A");     // the -2A-at-A=-128 overflow
    chk(-128,   -1, "min*-1   -> +128");
    chk(-128,    1, "min*+1");
    chk(  -1, -128, "B=-128 (top-dibit sign)");
    chk( -97,   50, "B=-97  (old B4G3 band)");
    chk( -86,    7, "B=-86  (band edge)");
    chk( -85,    7, "B=-85  (just outside)");
    chk(   0, -128, "zero*min");
    chk(-128,    0, "min*zero");
    chk(  -1,   -1, "-1*-1   -> +1");
    chk(  42,  -17, "arbitrary mix");

    // ---------- 2. Exhaustive sweep ----------
    $display("--- exhaustive sweep (65,536 pairs) ---");
    for (int i = -128; i <= 127; i++)
      for (int j = -128; j <= 127; j++)
        chk(i[7:0], j[7:0], "sweep");

    // ---------- 3. Verdict ----------
    $display("=====================================");
    $display("checks run : %0d", checks);
    $display("mismatches : %0d", errors);
    $display("RESULT     : %s", (errors == 0) ? "PASS" : "FAIL");
    $finish;
  end
endmodule
