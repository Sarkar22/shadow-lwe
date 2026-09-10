// Parameter-fixed wrapper for ASIC sign-off at the paper's recommended point.
`timescale 1ns/1ps
module shadow_lwe_top (
    input  logic clk, input logic rst,
    input  logic i_sk_load, input logic i_sk_bit,
    input  logic [127:0] i_seed, input logic i_m,
    input  logic signed [31:0] i_e, input logic i_start,
    output logic o_busy, output logic signed [31:0] o_b, output logic o_valid);
  shadow_lwe #(.N(630), .W(32), .LANES(2), .ROUNDS_PER_CYCLE(2)) u_dut (
    .clk(clk), .rst(rst), .i_sk_load(i_sk_load), .i_sk_bit(i_sk_bit),
    .i_seed(i_seed), .i_m(i_m), .i_e(i_e), .i_start(i_start),
    .o_busy(o_busy), .o_b(o_b), .o_valid(o_valid));
endmodule
