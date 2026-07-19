// ============================================================
// FULL B4G3 signed 8x8 multiplier  --  paper-complete, your names
// Langhammer, Pasca, Kucherenko, IEEE ARITH 2024.
//
// Pipeline of the paper, end to end:
//   1. B4G3 encode (Table II) + signed top dibit
//   2. carry / prefix network on the multiplier operand (Eq. 2/3)
//   3. partial products by ONE'S COMPLEMENT (invert, do not negate)
//   4. the negate "+1"s collected into a single SIGN VECTOR
//   5. carry-save COMPRESSION TREE (3:2 compressors)
//   6. final CPA
// ============================================================

// ---- MODULE 1: interior encoder (unchanged: B4G3 Table II) ----
//   sign_bit is now USED: it is the one's-complement "+1" correction.
module encoder(
  input  logic cin, b_curr, b_next,
  output logic s1, s2, s_negation, sign_bit
);
  always_comb begin
    case ({b_next, b_curr, cin})
      3'b000: begin s1=0; s2=0; s_negation=0; sign_bit=0; end
      3'b001: begin s1=1; s2=0; s_negation=0; sign_bit=0; end
      3'b010: begin s1=1; s2=0; s_negation=0; sign_bit=0; end
      3'b011: begin s1=0; s2=1; s_negation=0; sign_bit=0; end
      3'b100: begin s1=0; s2=1; s_negation=0; sign_bit=0; end
      3'b101: begin s1=1; s2=0; s_negation=1; sign_bit=1; end
      3'b110: begin s1=1; s2=0; s_negation=1; sign_bit=1; end
      3'b111: begin s1=0; s2=0; s_negation=1; sign_bit=1; end
    endcase
  end
endmodule

// ---- MODULE 1b: TOP encoder (signed: case 100 -> -2A) ----
module encoder_top(
  input  logic cin, b_curr, b_next,
  output logic s1, s2, s_negation, sign_bit
);
  always_comb begin
    case ({b_next, b_curr, cin})
      3'b000: begin s1=0; s2=0; s_negation=0; sign_bit=0; end  // M= 0
      3'b001: begin s1=1; s2=0; s_negation=0; sign_bit=0; end  // M=+1
      3'b010: begin s1=1; s2=0; s_negation=0; sign_bit=0; end  // M=+1
      3'b011: begin s1=0; s2=1; s_negation=0; sign_bit=0; end  // M=+2
      3'b100: begin s1=0; s2=1; s_negation=1; sign_bit=1; end  // M=-2
      3'b101: begin s1=1; s2=0; s_negation=1; sign_bit=1; end  // M=-1
      3'b110: begin s1=1; s2=0; s_negation=1; sign_bit=1; end  // M=-1
      3'b111: begin s1=0; s2=0; s_negation=1; sign_bit=1; end  // M= 0
    endcase
  end
endmodule

// ---- MODULE 2: partial-product mux  (ONE'S COMPLEMENT form) ----
//   Selects the magnitude {0, A, 2A} (9-bit), then INVERTS it when
//   the digit is negative. The matching "+1" is the encoder sign_bit,
//   added later in the sign vector -- never here. One mux for all
//   dibits: the top dibit just also drives the s2 & s_negation combo.
module mux(
  input  logic s1, s2, s_negation,
  input  logic signed [7:0] A,
  output logic [8:0] p_product           // 1's-complement PP bits
);
  logic [8:0] mag;
  always_comb begin
    mag = '0;
    if (s1) mag = {A[7], A};              //  A   (sign-extend to 9)
    if (s2) mag = {A, 1'b0};              // 2A   (A << 1, 9 bits)
    p_product = s_negation ? ~mag : mag;  // invert only; no +1 here
  end
endmodule

// ---- MODULE 3 / 3b: Booth units (encoder/encoder_top + mux) ----
module booth_unit(
  input  logic signed [7:0] A,
  input  logic cin, b_curr, b_next,
  output logic [8:0] p_product,
  output logic sign_bit
);
  logic s1, s2, s_negation;
  encoder enc (.cin(cin), .b_curr(b_curr), .b_next(b_next),
               .s1(s1), .s2(s2), .s_negation(s_negation), .sign_bit(sign_bit));
  mux m (.s1(s1), .s2(s2), .s_negation(s_negation), .A(A), .p_product(p_product));
endmodule

module booth_unit_top(
  input  logic signed [7:0] A,
  input  logic cin, b_curr, b_next,
  output logic [8:0] p_product,
  output logic sign_bit
);
  logic s1, s2, s_negation;
  encoder_top enc (.cin(cin), .b_curr(b_curr), .b_next(b_next),
                   .s1(s1), .s2(s2), .s_negation(s_negation), .sign_bit(sign_bit));
  mux m (.s1(s1), .s2(s2), .s_negation(s_negation), .A(A), .p_product(p_product));
endmodule

// ---- MODULE 4: carry / prefix network (unchanged, yours) ----
module prefix_tree(
  input  logic [7:0] B,
  output logic cin0, cin1, cin2, cin3
);
  always_comb begin
    cin0 = 1'b0;
    cin1 = B[1] & B[0];
    cin2 = (B[3] & B[2]) | (B[3] & B[1] & B[0]);
    cin3 = (B[5] & B[4]) | (B[5] & (B[3] & B[2])) | (B[5] & B[3] & (B[1] & B[0]));
  end
endmodule

// ---- MODULE 5: 3:2 carry-save compressor (one tree node) ----
//   For inputs x,y,z:  x + y + z == s + (c << 1)  (mod 2^16).
module csa16(
  input  logic [15:0] x, y, z,
  output logic [15:0] s, c
);
  assign s = x ^ y ^ z;
  assign c = (x & y) | (y & z) | (x & z);
endmodule

// ---- MODULE 6: full multiplier ----
module booth_multiplier(
  input  logic signed [7:0]  A, B,
  output logic signed [15:0] product
);
  // 1) encode + carry network -> 2) one's-complement PPs + sign bits
  logic cin0, cin1, cin2, cin3;
  logic [8:0] b0, b1, b2, b3;            // 1's-complement PP magnitudes
  logic e0, e1, e2, e3;                  // sign-vector correction bits

  prefix_tree pt (.B(B), .cin0(cin0), .cin1(cin1), .cin2(cin2), .cin3(cin3));

  booth_unit     u0 (.A(A), .cin(cin0), .b_curr(B[0]), .b_next(B[1]), .p_product(b0), .sign_bit(e0));
  booth_unit     u1 (.A(A), .cin(cin1), .b_curr(B[2]), .b_next(B[3]), .p_product(b1), .sign_bit(e1));
  booth_unit     u2 (.A(A), .cin(cin2), .b_curr(B[4]), .b_next(B[5]), .p_product(b2), .sign_bit(e2));
  booth_unit_top u3 (.A(A), .cin(cin3), .b_curr(B[6]), .b_next(B[7]), .p_product(b3), .sign_bit(e3));

  // 3) sign-extend each PP to 16 bits and place at weight 4^i (shift 2i)
  logic [15:0] R0, R1, R2, R3;
  assign R0 =  {{7{b0[8]}}, b0};
  assign R1 = ({{7{b1[8]}}, b1}) << 2;
  assign R2 = ({{7{b2[8]}}, b2}) << 4;
  assign R3 = ({{7{b3[8]}}, b3}) << 6;

  // 4) sign vector: each "+1" correction sits at bit 2i (cols 0,2,4,6)
  logic [15:0] K;
  assign K = {9'b0, e3, 1'b0, e2, 1'b0, e1, 1'b0, e0};

  // 5) compression tree: reduce {R0,R1,R2,R3,K} (5 rows) to 2 rows
  logic [15:0] sa, ca, sb, cb, sc, cc;
  csa16 z1 (.x(R0), .y(R1),        .z(R2), .s(sa), .c(ca));
  csa16 z2 (.x(sa), .y(ca << 1),   .z(R3), .s(sb), .c(cb));
  csa16 z3 (.x(sb), .y(cb << 1),   .z(K),  .s(sc), .c(cc));

  // 6) final CPA
  assign product = $signed(sc + (cc << 1));
endmodule