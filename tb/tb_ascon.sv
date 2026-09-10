/*
 * tb_ascon.sv -- self-checking testbench for ascon_xof.
 * Replays the known-answer vectors emitted by model/ascon.py (which itself
 * reproduces the official NIST Ascon-XOF128 KATs) and checks every squeezed word.
 * Run at several ROUNDS_PER_CYCLE values to prove the knob does not change results.
 */
`timescale 1ns/1ps
`ifndef RPC
 `define RPC 1
`endif
module tb_ascon;
    localparam int NW = 8;                 // words per vector line

    logic clk = 0, rst = 1;
    logic [127:0] seed;
    logic start, ready;
    wire  [63:0]  word;
    wire          valid, busy;

    ascon_xof #(.ROUNDS_PER_CYCLE(`RPC)) dut (
        .clk(clk), .rst(rst), .i_seed(seed), .i_start(start),
        .o_busy(busy), .o_word(word), .o_valid(valid), .i_ready(ready));

    always #5 clk = ~clk;

    integer fd, n, pass = 0, fail = 0, total = 0, i;
    reg [127:0] vseed;
    reg [63:0]  exp [0:NW-1];
    reg [1023:0] hdr;

    task run_vector;
        begin
            @(negedge clk); seed = vseed; start = 1'b1;
            @(negedge clk); start = 1'b0;
            for (i = 0; i < NW; i = i + 1) begin
                while (valid !== 1'b1) @(negedge clk);
                total = total + 1;
                if (word === exp[i]) pass = pass + 1;
                else begin
                    fail = fail + 1;
                    $display("  MISMATCH seed=%032h word[%0d]: exp %016h got %016h",
                             vseed, i, exp[i], word);
                end
                ready = 1'b1; @(negedge clk); ready = 1'b0;
            end
        end
    endtask

    initial begin
        start = 0; ready = 0; seed = 0;
        repeat (4) @(negedge clk); rst = 0;
        fd = $fopen("../tb/ascon_vectors.hex", "r");
        if (fd == 0) begin $display("ERROR: cannot open ascon_vectors.hex"); $finish; end
        n = $fgets(hdr, fd);                        // skip comment header
        while (!$feof(fd)) begin
            n = $fscanf(fd, " %h", vseed);
            if (n == 1) begin
                for (i = 0; i < NW; i = i + 1) n = $fscanf(fd, " %h", exp[i]);
                run_vector;
            end
        end
        $fclose(fd);
        $display("------------------------------------------------------------");
        $display("ASCON-XOF128 TB (ROUNDS_PER_CYCLE=%0d): %0d/%0d words exact, %0d mismatch",
                 `RPC, pass, total, fail);
        if (fail == 0 && total > 0) $display("RESULT: PASS");
        else                        $display("RESULT: FAIL");
        $finish;
    end
endmodule
