# B4G3 Multiplier: signed 8x8, SystemVerilog

A paper-complete implementation of the B4G3 multiplier from Langhammer, Pasca and Kucherenko, ["Multiplier Architecture with a Carry-Based Partial Product Encoding"](https://www.ac.uma.es/arith2024/papers/Multiplier%20Architecture%20with%20a%20Carry-Based%20Partial%20Product%20Encoding.pdf), IEEE 31st Symposium on Computer Arithmetic (ARITH 2024). Exhaustively verified over all 65,536 signed input pairs.

## The idea

A standard modified Booth radix-4 encoder selects each partial product from the full menu `{0, +A, +2A, -A, -2A}`. B4G3 trims `-2A` from the interior digit set, so the partial product mux only has to produce `{0, +A, +2A, -A}`. The missing cases are compensated by a small carry (prefix) network computed directly on the multiplier operand: cheaper selection logic, paid for with a carry network and a dedicated signed top dibit. The paper's claim is that this trade wins on FPGA and ASIC cost; this repo implements the architecture so that claim can be tested against a matched baseline.

## Pipeline

End to end, as in the paper:

1. B4G3 encode (Table II) plus a signed top-dibit encoder that keeps `-2A`
2. Carry/prefix network on the multiplier operand (Eq. 2/3)
3. Partial products in one's-complement form: invert, never negate
4. The "+1" negation corrections collected into a single sign vector row
5. 3:2 carry-save compression tree
6. Final carry-propagate adder

## Modules

| Module | Role |
|---|---|
| `encoder` | Interior B4G3 encoder (paper Table II), digit set `{0, +A, +2A, -A}` |
| `encoder_top` | Top dibit: signed, keeps the `-2A` case (`100 -> -2A`) |
| `mux` | Partial product select plus one's-complement inversion; one mux serves all dibits |
| `booth_unit` / `booth_unit_top` | Encoder + mux pairs |
| `prefix_tree` | Carry network that compensates the trimmed `-2A` digit |
| `csa16` | 3:2 carry-save compressor node |
| `booth_multiplier` | Top level: 8x8 signed in, 16-bit product out |

## Differences vs. standard Booth radix-4

The matched baseline lives in [booth-radix4-multiplier](https://github.com/kiankhooban/booth-radix4-multiplier). Both repos share an identical back end (one's-complement PPs, sign vector, compression tree, final CPA), so the designs differ in exactly three places:

- **Encoder input**: B4G3 units take a computed carry `cin` instead of the overlapping `b_prev` bit
- **Carry network**: B4G3 needs the `prefix_tree`; standard Booth overlaps windows and needs none
- **Top unit**: B4G3 needs a special signed top dibit; in standard Booth all four units are identical because the top window holds `B[7]`

Any synthesis comparison between the two repos isolates the encoding scheme.

## Verification

`tb_booth.sv` is self-checking. It first runs 15 named corner cases, chosen because they have actually broken revisions of these designs: `-128 * -128`, `A = -128` forcing the `-2A` overflow, `B = -128` exercising the top-dibit sign, and the `B = -86..-97` band where an earlier B4G3 revision failed. It then exhaustively sweeps all 65,536 signed pairs against golden `A * B`.

Status: **PASS**, 65,551 checks, 0 mismatches (Icarus Verilog 12).

## Running

```sh
# Icarus Verilog
iverilog -g2012 -o sim full_b4g3.sv tb_booth.sv && vvp sim

# Verilator
verilator --binary --top-module tb_booth full_b4g3.sv tb_booth.sv && obj_dir/Vtb_booth

# Vivado xsim: add both files, set tb_booth as top, Run All
```

Icarus prints `sorry: constant selects in always_* processes` notes. Those are sensitivity-list warnings, not errors; the exhaustive sweep confirms the logic is correct.

The testbench targets any design whose top module is `booth_multiplier(A, B, product)`, so the same file verifies both this repo and the baseline repo. Run it against one design at a time.

## Reference

M. Langhammer, B. Pasca, I. Kucherenko, "Multiplier Architecture with a Carry-Based Partial Product Encoding," IEEE 31st Symposium on Computer Arithmetic (ARITH), 2024. [PDF](https://www.ac.uma.es/arith2024/papers/Multiplier%20Architecture%20with%20a%20Carry-Based%20Partial%20Product%20Encoding.pdf)

## Related

- [booth-radix4-multiplier](https://github.com/kiankhooban/booth-radix4-multiplier): matched standard Booth radix-4 baseline
