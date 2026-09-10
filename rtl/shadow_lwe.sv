/*
 * shadow_lwe.sv -- seed-compressed LWE encryptor with on-chip mask expansion.
 * --------------------------------------------------------------------------
 * Standard LWE encryption transmits (a[0..N-1], b), where the mask vector a[]
 * dominates the ciphertext: 630 x 32 b = 2520 B of the 2524 B total. Here a[] is
 * instead expanded on chip from a public 128-bit seed with Ascon-XOF128, so only
 * (seed, b) leaves the device: 20 B, a 126x reduction.
 *
 *   seed --[ascon_xof]--> 64-b keystream --[gather]--> LANES x 32-b beats
 *                                                          |
 *                                    [lwe_encrypt_par] ----+--> b
 *
 * The MAC is the verified LATTICE core (lwe_encrypt_par.sv) reused unmodified;
 * its forwarded a[] stream is intentionally discarded, since the receiver
 * regenerates a[] from the seed. Only the tlast beat, carrying b, is captured.
 *
 * Two knobs set the rate balance:
 *   ROUNDS_PER_CYCLE : how fast the mask is produced (Ascon permutation rounds/cycle)
 *   LANES            : how fast the mask is consumed (mask words MAC'd per cycle)
 * Mask expansion hides inside an inference shadow only when production keeps up
 * with consumption; sweeping these two is the paper's feasibility frontier.
 *
 * Verified bit-exact against model/ascon.py (which reproduces the official NIST
 * Ascon KATs and the LWE reference).
 */
`timescale 1ns/1ps
module shadow_lwe #(
    parameter int N                = 630,
    parameter int W                = 32,
    parameter int LANES            = 8,     // must be even (two 32-b words per Ascon beat)
    parameter int ROUNDS_PER_CYCLE = 1
) (
    input  logic                clk,
    input  logic                rst,
    // key load (one bit per cycle, N cycles, before the first encryption)
    input  logic                i_sk_load,
    input  logic                i_sk_bit,
    // per-record inputs
    input  logic [127:0]        i_seed,
    input  logic                i_m,        // message bit
    input  logic signed [W-1:0] i_e,        // error sample
    input  logic                i_start,
    output logic                o_busy,
    // ciphertext: (seed, b). a[] never leaves the device.
    output logic signed [W-1:0] o_b,
    output logic                o_valid
);
    localparam int GW = LANES * W;          // gathered beat width
    localparam int WPB = LANES / 2;         // 64-b Ascon words per beat

    // ---------------- mask generator ----------------
    logic         xof_start, xof_ready;
    wire  [63:0]  xof_word;
    wire          xof_valid, xof_busy;

    ascon_xof #(.ROUNDS_PER_CYCLE(ROUNDS_PER_CYCLE)) u_xof (
        .clk(clk), .rst(rst), .i_seed(i_seed), .i_start(xof_start),
        .o_busy(xof_busy), .o_word(xof_word), .o_valid(xof_valid), .i_ready(xof_ready));

    // ---------------- gather 64-b keystream into LANES*W beats ----------------
    // First keystream word supplies the lowest lanes, matching the little-endian
    // word extraction in the reference model.
    logic [GW-1:0]          gbuf;
    logic [$clog2(WPB+1)-1:0] gcnt;
    logic                   beat_valid;
    wire                    beat_ready;

    assign xof_ready = !beat_valid;         // stall the sponge while a beat waits

    always_ff @(posedge clk) begin
        if (rst) begin
            gbuf <= '0; gcnt <= '0; beat_valid <= 1'b0;
        end else begin
            if (beat_valid && beat_ready) beat_valid <= 1'b0;
            if (xof_valid && xof_ready) begin
                gbuf <= GW'(({xof_word, gbuf}) >> 64);  // shift in from the top (GW==64 safe)
                if (gcnt == WPB[$bits(gcnt)-1:0] - 1) begin
                    gcnt <= '0; beat_valid <= 1'b1;
                end else gcnt <= gcnt + 1'b1;
            end
            if (i_start) begin gcnt <= '0; beat_valid <= 1'b0; end
        end
    end

    // ---------------- verified LWE MAC (LATTICE core, reused) ----------------
    wire         mac_busy, mac_done;
    wire         m_tvalid, m_tlast;
    wire [GW-1:0] m_tdata;
    wire         s_tready;
    assign beat_ready = s_tready;

    lwe_encrypt_par #(.N(N), .W(W), .LANES(LANES)) u_mac (
        .clk(clk), .rst_n(~rst),
        .sk_load_en(i_sk_load), .sk_bit(i_sk_bit),
        .start(i_start), .m_in(i_m), .e_in(i_e),
        .busy(mac_busy), .done(mac_done),
        .s_axis_tvalid(beat_valid), .s_axis_tready(s_tready), .s_axis_tdata(gbuf),
        .m_axis_tvalid(m_tvalid), .m_axis_tready(1'b1),
        .m_axis_tdata(m_tdata), .m_axis_tlast(m_tlast));

    // launch the sponge with the record's seed at start
    assign xof_start = i_start;
    assign o_busy    = mac_busy;

    // capture b: the only ciphertext word that is transmitted
    always_ff @(posedge clk) begin
        if (rst) begin
            o_b <= '0; o_valid <= 1'b0;
        end else begin
            o_valid <= 1'b0;
            if (m_tvalid && m_tlast) begin
                o_b     <= $signed(m_tdata[W-1:0]);
                o_valid <= 1'b1;
            end
        end
    end
endmodule
