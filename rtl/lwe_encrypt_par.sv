// =============================================================================
// lwe_encrypt_par.sv  —  LWE encryption core, PARALLEL MAC (LANES-wide)
//
//   Same math as lwe_encrypt.sv:  b = Δm + e + Σ sk[i]·a[i]
//   but processes LANES words of a[] per cycle instead of one.
//
//   Throughput  : ceil(N/LANES) cycles per encryption (vs N for the serial core)
//   Bottleneck  : the AXI-Stream input width (LANES·W) — NOT the adders.
//   Output width = input width (a[] is part of the ciphertext, streamed through).
//
//   LANES=1 reduces to the serial behaviour. N need not be a multiple of LANES;
//   the final beat masks the unused high lanes (they contribute 0 to b).
// =============================================================================

`default_nettype none

module lwe_encrypt_par #(
    parameter int N     = 630,
    parameter int W     = 32,
    parameter int LANES = 8
)(
    input  wire                     clk,
    input  wire                     rst_n,

    // ── control plane ───────────────────────────────────────────────────────
    input  wire                     sk_load_en,
    input  wire                     sk_bit,
    input  wire                     start,
    input  wire                     m_in,
    input  wire signed [W-1:0]      e_in,
    output reg                      busy,
    output reg                      done,

    // ── data plane: a[] in (AXI-Stream slave, LANES·W wide) ─────────────────
    input  wire                     s_axis_tvalid,
    output reg                      s_axis_tready,
    input  wire [LANES*W-1:0]       s_axis_tdata,

    // ── data plane: ciphertext out (AXI-Stream master, LANES·W wide) ────────
    output reg                      m_axis_tvalid,
    input  wire                     m_axis_tready,
    output reg  [LANES*W-1:0]       m_axis_tdata,
    output reg                      m_axis_tlast
);

    localparam signed [W-1:0] DELTA  = (1 <<< (W-3));
    localparam int            NBEATS = (N + LANES - 1) / LANES;   // beats for a[]
    localparam int            BCW    = $clog2(NBEATS + 1);

    localparam [1:0] S_IDLE = 2'd0, S_PASS = 2'd1, S_EMITB = 2'd2;

    // ── secret-key register file (master copy, loaded once per session) ──────
    reg [N-1:0]               sk_reg;
    reg [$clog2(N)-1:0]       sk_wr;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sk_reg <= '0;
            sk_wr  <= '0;
        end else if (sk_load_en && !busy) begin
            sk_reg[sk_wr] <= sk_bit;
            sk_wr <= (sk_wr == N-1) ? '0 : sk_wr + 1'b1;
        end
    end

    // ── datapath state ────────────────────────────────────────────────────────
    reg  [1:0]          state;
    reg  [BCW-1:0]      beat;
    reg  signed [W-1:0] acc;

    // Key is consumed IN ORDER: copy sk_reg into a working shift register at
    // start, expose the low LANES bits each beat, shift right by LANES. No
    // dynamic indexing → no wide muxes. Bits past N shift in as 0 (tail mask).
    reg  [N-1:0]        sk_work;

    // adder tree: sum of the LANES conditional partials this cycle
    reg  signed [W-1:0] partial_sum;
    integer l;
    always @(*) begin
        partial_sum = '0;
        for (l = 0; l < LANES; l = l + 1)
            if (sk_work[l])
                partial_sum = partial_sum + $signed(s_axis_tdata[l*W +: W]);
    end

    // ── AXI-Stream handshake (combinational) ─────────────────────────────────
    always @(*) begin
        s_axis_tready = 1'b0;
        m_axis_tvalid = 1'b0;
        m_axis_tdata  = '0;
        m_axis_tlast  = 1'b0;
        case (state)
            S_PASS: begin
                m_axis_tvalid = s_axis_tvalid;
                m_axis_tdata  = s_axis_tdata;     // forward a[] words
                m_axis_tlast  = 1'b0;
                s_axis_tready = m_axis_tready;
            end
            S_EMITB: begin
                m_axis_tvalid = 1'b1;
                m_axis_tdata  = {{(LANES*W-W){1'b0}}, acc};  // b in lane 0
                m_axis_tlast  = 1'b1;
                s_axis_tready = 1'b0;
            end
            default: ;
        endcase
    end

    // ── control FSM ───────────────────────────────────────────────────────────
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state   <= S_IDLE;
            busy    <= 1'b0;
            done    <= 1'b0;
            beat    <= '0;
            acc     <= '0;
            sk_work <= '0;
        end else begin
            done <= 1'b0;
            case (state)
                S_IDLE: begin
                    if (start) begin
                        acc     <= (m_in ? DELTA : -DELTA) + e_in;
                        sk_work <= sk_reg;          // load key into shift reg
                        beat    <= '0;
                        busy    <= 1'b1;
                        state   <= S_PASS;
                    end
                end
                S_PASS: begin
                    if (s_axis_tvalid && m_axis_tready) begin
                        acc     <= acc + partial_sum;
                        sk_work <= sk_work >> LANES; // next LANES key bits
                        if (beat == NBEATS-1) state <= S_EMITB;
                        else                  beat  <= beat + 1'b1;
                    end
                end
                S_EMITB: begin
                    if (m_axis_tready) begin
                        done  <= 1'b1;
                        busy  <= 1'b0;
                        state <= S_IDLE;
                    end
                end
                default: state <= S_IDLE;
            endcase
        end
    end

endmodule

`default_nettype wire
