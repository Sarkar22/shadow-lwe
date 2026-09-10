/*
 * tb_shadow.sv -- end-to-end check of the seed-compressed LWE encryptor.
 * Loads the secret key, drives (seed, m, e), and compares b against the golden
 * model, which chains the official-KAT Ascon-XOF128 with the LWE reference.
 */
`timescale 1ns/1ps
`ifndef RPC
 `define RPC 1
`endif
`ifndef LANES
 `define LANES 8
`endif
module tb_shadow;
    localparam int N = 630, W = 32;

    logic clk = 0, rst = 1;
    logic sk_load = 0, sk_bit = 0, start = 0, m = 0;
    logic [127:0] seed;
    logic signed [W-1:0] e;
    wire  signed [W-1:0] b;
    wire  busy, valid;

    shadow_lwe #(.N(N), .W(W), .LANES(`LANES), .ROUNDS_PER_CYCLE(`RPC)) dut (
        .clk(clk), .rst(rst), .i_sk_load(sk_load), .i_sk_bit(sk_bit),
        .i_seed(seed), .i_m(m), .i_e(e), .i_start(start),
        .o_busy(busy), .o_b(b), .o_valid(valid));

    always #5 clk = ~clk;

    integer fd, n, i, pass = 0, fail = 0, total = 0, cyc, t0;
    reg [127:0] vseed;
    reg [N-1:0] vsk;
    reg [3:0]   vm;
    reg [31:0]  ve, vb;
    reg [1023:0] hdr;

    always @(posedge clk) if (!rst) cyc = cyc + 1;

    task run_vector;
        begin
            // load the secret key, LSB first
            @(negedge clk);
            for (i = 0; i < N; i = i + 1) begin
                sk_load = 1'b1; sk_bit = vsk[i]; @(negedge clk);
            end
            sk_load = 1'b0;
            seed = vseed; m = vm[0]; e = $signed(ve);
            @(negedge clk); start = 1'b1; t0 = cyc;
            @(negedge clk); start = 1'b0;
            while (valid !== 1'b1) @(negedge clk);
            total = total + 1;
            if (b === $signed(vb)) pass = pass + 1;
            else begin
                fail = fail + 1;
                $display("  MISMATCH seed=%032h: exp b=%08h got %08h", vseed, vb, b);
            end
            @(negedge clk);
        end
    endtask

    initial begin
        cyc = 0;
        repeat (4) @(negedge clk); rst = 0;
        fd = $fopen("../tb/shadow_vectors.hex", "r");
        if (fd == 0) begin $display("ERROR: cannot open shadow_vectors.hex"); $finish; end
        n = $fgets(hdr, fd);
        while (!$feof(fd)) begin
            n = $fscanf(fd, " %h %h %h %h %h", vseed, vsk, vm, ve, vb);
            if (n == 5) run_vector;
        end
        $fclose(fd);
        $display("------------------------------------------------------------");
        $display("SHADOW-LWE TB (RPC=%0d, LANES=%0d): %0d/%0d exact, %0d mismatch",
                 `RPC, `LANES, pass, total, fail);
        $display("  encryption latency: %0d cycles/record", cyc - t0);
        if (fail == 0 && total > 0) $display("RESULT: PASS");
        else                        $display("RESULT: FAIL");
        $finish;
    end
endmodule
