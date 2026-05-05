module ldpc_decoder #(
    parameter N        = 1024,
    parameter K        = 512,
    parameter Z        = 64,
    parameter MB       = 8,
    parameter NB       = 16,
    parameter MAX_ITER = 10,
    parameter Q        = 8
)(
    input  wire               clk,
    input  wire               rst_n,
    // LLR buffer read-port interface (replaces wide [N*Q-1:0] bus)
    output wire [9:0]          llr_rd_addr,  // byte address 0..N-1 driven during ST_INIT
    input  wire [Q-1:0]        llr_rd_data,  // async read from llr_buffer
    input  wire                valid_in,
    output reg  [K-1:0]       decoded,
    output reg                valid_out,
    output reg  [3:0]         iter_count
);

// ---------------------------------------------------------------------------
// Base matrix H_b[8][16]
// ---------------------------------------------------------------------------
localparam [767:0] HB = {
    // Row 7: parity col15=0, col14=0
    6'd0,  6'd0,  6'd63, 6'd63, 6'd63, 6'd63, 6'd63, 6'd63,
    6'd22, 6'd17, 6'd30, 6'd3,  6'd1,  6'd12, 6'd9,  6'd0,
    // Row 6: parity col14=0, col13=0
    6'd63, 6'd0,  6'd0,  6'd63, 6'd63, 6'd63, 6'd63, 6'd63,
    6'd5,  6'd28, 6'd15, 6'd11, 6'd20, 6'd6,  6'd25, 6'd7,
    // Row 5: parity col13=0, col12=0
    6'd63, 6'd63, 6'd0,  6'd0,  6'd63, 6'd63, 6'd63, 6'd63,
    6'd18, 6'd2,  6'd13, 6'd27, 6'd8,  6'd23, 6'd4,  6'd16,
    // Row 4: parity col12=0, col11=0
    6'd63, 6'd63, 6'd63, 6'd0,  6'd0,  6'd63, 6'd63, 6'd63,
    6'd10, 6'd31, 6'd21, 6'd14, 6'd29, 6'd0,  6'd19, 6'd24,
    // Row 3: parity col11=0, col10=0
    6'd63, 6'd63, 6'd63, 6'd63, 6'd0,  6'd0,  6'd63, 6'd63,
    6'd26, 6'd7,  6'd3,  6'd18, 6'd11, 6'd14, 6'd31, 6'd2,
    // Row 2: parity col10=0, col9=0
    6'd63, 6'd63, 6'd63, 6'd63, 6'd63, 6'd0,  6'd0,  6'd63,
    6'd13, 6'd24, 6'd9,  6'd5,  6'd29, 6'd16, 6'd8,  6'd21,
    // Row 1: parity col9=0, col8=0
    6'd63, 6'd63, 6'd63, 6'd63, 6'd63, 6'd63, 6'd0,  6'd0,
    6'd19, 6'd12, 6'd6,  6'd27, 6'd4,  6'd30, 6'd17, 6'd15,
    // Row 0: parity col8=0
    6'd63, 6'd63, 6'd63, 6'd63, 6'd63, 6'd63, 6'd63, 6'd0,
    6'd28, 6'd20, 6'd25, 6'd10, 6'd23, 6'd1,  6'd16, 6'd3
};

function [5:0] hb_entry;
    input [3:0] row;
    input [3:0] col;
    reg [9:0] idx;
    begin
        idx = ({6'b0, row} * 10'd16) + {6'b0, col};
        hb_entry = HB[idx*6 +: 6];
    end
endfunction

// Drive LLR buffer read address combinatorially from init_cnt
assign llr_rd_addr = init_cnt[9:0];

// ---------------------------------------------------------------------------
// Distributed RAM arrays — exactly ONE read port each (asynchronous).
// Each array is driven ONLY by its own write-only always @(posedge clk) block.
// NO async-reset sensitivity → Vivado infers DRAM correctly.
// ---------------------------------------------------------------------------
(* ram_style = "distributed" *) reg signed [Q-1:0] v_llr  [0:N-1];
(* ram_style = "distributed" *) reg signed [Q-1:0] ch_llr [0:N-1];
(* ram_style = "distributed" *) reg signed [Q-1:0] msg_cv [0:MB*NB*Z-1];

// Write-port registers (driven by main FSM; these are normal FFs with async reset)
reg        ch_llr_we;
reg [9:0]  ch_llr_wa;
reg [Q-1:0] ch_llr_wd;

reg        v_llr_we;
reg [9:0]  v_llr_wa;
reg [Q-1:0] v_llr_wd;

reg        msg_cv_we;
reg [12:0] msg_cv_wa;
reg [Q-1:0] msg_cv_wd;

// ---------------------------------------------------------------------------
// LUTRAM write blocks — posedge-only, no reset.
// Vivado: single synchronous write + asynchronous read → distributed RAM.
// ---------------------------------------------------------------------------
always @(posedge clk) begin
    if (ch_llr_we) ch_llr[ch_llr_wa] <= ch_llr_wd;
end

always @(posedge clk) begin
    if (v_llr_we) v_llr[v_llr_wa] <= v_llr_wd;
end

always @(posedge clk) begin
    if (msg_cv_we) msg_cv[msg_cv_wa] <= msg_cv_wd;
end

// ---------------------------------------------------------------------------
// FSM
// ---------------------------------------------------------------------------
localparam ST_IDLE       = 3'd0;
localparam ST_INIT       = 3'd1;
localparam ST_CNU_GATHER = 3'd2;
localparam ST_CNU_WR     = 3'd3;
localparam ST_VNU_ROW    = 3'd4;
localparam ST_OUTPUT     = 3'd5;

reg [2:0]  state;
reg [12:0] init_cnt;    // 0..MB*NB*Z-1 = 8191
reg [2:0]  cur_row;     // CNU check-node row  0..MB-1
reg [5:0]  cur_z;       // CNU check-node pos  0..Z-1
reg [3:0]  col_cnt;     // CNU gather/scatter col 0..NB-1
reg [9:0]  vn_cnt;      // VNU variable index  0..N-1
reg [2:0]  row_cnt;     // VNU check-row index 0..MB-1
reg [3:0]  iter;

// CNU accumulators
reg [Q-2:0] cnu_min1;
reg [Q-2:0] cnu_min2;
reg [3:0]   cnu_min1_idx;
reg         cnu_total_sign;
reg         cnu_sign [0:NB-1];   // 16 × 1-bit FFs, fine as registers

// VNU accumulator
reg signed [Q+3:0] s_acc;        // 12-bit

// ---------------------------------------------------------------------------
// Saturate 12-bit signed → 8-bit signed
// ---------------------------------------------------------------------------
function signed [7:0] sat;
    input signed [11:0] x;
    begin
        if      (x > 12'sd127)  sat =  8'sd127;
        else if (x < -12'sd127) sat = -8'sd127;
        else                    sat = x[7:0];
    end
endfunction

// ---------------------------------------------------------------------------
// Main FSM — async reset for non-RAM registers only.
// Array writes go through write-port registers; actual LUTRAM writes happen
// in the separate posedge-only blocks above (1-cycle pipeline).
// ---------------------------------------------------------------------------
always @(posedge clk or negedge rst_n) begin : main_fsm

    // Combinatorial locals
    reg [5:0]         sh;
    reg [5:0]         shifted_z, msg_z_v;
    reg [9:0]         vaddr;
    reg [12:0]        midx;
    reg signed [8:0]  sum_ext;
    reg signed [7:0]  extval;
    reg [6:0]         absval;
    reg               sgnval;
    reg [3:0]         cc_v;
    reg [5:0]         sz_v;
    reg signed [11:0] s;
    reg signed [7:0]  vllr_new;

    if (!rst_n) begin
        state          <= ST_IDLE;
        valid_out      <= 1'b0;
        iter_count     <= 4'd0;
        iter           <= 4'd0;
        cur_row        <= 3'd0;
        cur_z          <= 6'd0;
        col_cnt        <= 4'd0;
        vn_cnt         <= 10'd0;
        row_cnt        <= 3'd0;
        init_cnt       <= 13'd0;
        cnu_min1       <= 7'h7F;
        cnu_min2       <= 7'h7F;
        cnu_min1_idx   <= 4'd0;
        cnu_total_sign <= 1'b0;
        s_acc          <= {(Q+4){1'b0}};
        // Clear write ports (prevents spurious writes on reset release)
        ch_llr_we      <= 1'b0;
        v_llr_we       <= 1'b0;
        msg_cv_we      <= 1'b0;
        ch_llr_wa      <= 10'd0;
        v_llr_wa       <= 10'd0;
        msg_cv_wa      <= 13'd0;
        ch_llr_wd      <= {Q{1'b0}};
        v_llr_wd       <= {Q{1'b0}};
        msg_cv_wd      <= {Q{1'b0}};
    end else begin
        valid_out <= 1'b0;

        // Default: disable all writes each cycle
        ch_llr_we <= 1'b0;
        v_llr_we  <= 1'b0;
        msg_cv_we <= 1'b0;

        case (state)

            // ----------------------------------------------------------
            ST_IDLE: begin
                if (valid_in) begin
                    init_cnt <= 13'd0;
                    iter     <= 4'd0;
                    state    <= ST_INIT;
                end
            end

            // ----------------------------------------------------------
            // Initialise: clear all 8192 msg_cv entries; load ch_llr and
            // v_llr for the first N=1024 entries.
            // Write port is registered → actual LUTRAM write 1 cycle later.
            // Last write (init_cnt=8191) commits on the first cycle of
            // ST_CNU_GATHER, which reads address 0 — no conflict.
            ST_INIT: begin
                msg_cv_we <= 1'b1;
                msg_cv_wa <= init_cnt;
                msg_cv_wd <= {Q{1'b0}};
                if (init_cnt < N) begin
                    ch_llr_we <= 1'b1;
                    ch_llr_wa <= init_cnt[9:0];
                    ch_llr_wd <= llr_rd_data;
                    v_llr_we  <= 1'b1;
                    v_llr_wa  <= init_cnt[9:0];
                    v_llr_wd  <= llr_rd_data;
                end
                if (init_cnt == MB*NB*Z - 1) begin
                    cur_row        <= 3'd0;
                    cur_z          <= 6'd0;
                    col_cnt        <= 4'd0;
                    cnu_min1       <= 7'h7F;
                    cnu_min2       <= 7'h7F;
                    cnu_min1_idx   <= 4'd0;
                    cnu_total_sign <= 1'b0;
                    state          <= ST_CNU_GATHER;
                end else begin
                    init_cnt <= init_cnt + 1'b1;
                end
            end

            // ----------------------------------------------------------
            // CNU gather: one column per cycle.
            // Reads v_llr and msg_cv asynchronously (1 read port each).
            ST_CNU_GATHER: begin
                sh = hb_entry({1'b0, cur_row}, col_cnt);
                if (sh != 6'h3F) begin
                    shifted_z = cur_z - sh;
                    vaddr     = {col_cnt, shifted_z};
                    midx      = {cur_row, col_cnt, cur_z};
                    sum_ext = {v_llr[vaddr][Q-1], v_llr[vaddr]}
                            - {msg_cv[midx][Q-1],  msg_cv[midx]};
                    extval  = sat({{3{sum_ext[Q]}}, sum_ext});
                    sgnval  = extval[Q-1];
                    absval  = sgnval ? (~extval[Q-2:0] + 7'd1)
                                    : {1'b0, extval[Q-2:0]};
                    cnu_sign[col_cnt]  <= sgnval;
                    cnu_total_sign     <= cnu_total_sign ^ sgnval;
                    if (absval <= cnu_min1) begin
                        cnu_min2     <= cnu_min1;
                        cnu_min1     <= absval;
                        cnu_min1_idx <= col_cnt;
                    end else if (absval < cnu_min2) begin
                        cnu_min2     <= absval;
                    end
                end else begin
                    cnu_sign[col_cnt] <= 1'b0;
                end
                if (col_cnt == NB-1) begin
                    col_cnt <= 4'd0;
                    state   <= ST_CNU_WR;
                end else begin
                    col_cnt <= col_cnt + 1'b1;
                end
            end

            // ----------------------------------------------------------
            // CNU scatter: write ONE msg_cv entry per cycle via write port.
            ST_CNU_WR: begin
                sh = hb_entry({1'b0, cur_row}, col_cnt);
                if (sh != 6'h3F) begin
                    midx      = {cur_row, col_cnt, cur_z};
                    msg_cv_we <= 1'b1;
                    msg_cv_wa <= midx;
                    msg_cv_wd <= (cnu_total_sign ^ cnu_sign[col_cnt]) ?
                        -$signed({1'b0, (col_cnt == cnu_min1_idx) ? cnu_min2 : cnu_min1}) :
                         $signed({1'b0, (col_cnt == cnu_min1_idx) ? cnu_min2 : cnu_min1});
                end
                if (col_cnt == NB-1) begin
                    col_cnt <= 4'd0;
                    if (cur_z == Z-1) begin
                        cur_z <= 6'd0;
                        if (cur_row == MB-1) begin
                            cur_row <= 3'd0;
                            vn_cnt  <= 10'd0;
                            row_cnt <= 3'd0;
                            state   <= ST_VNU_ROW;
                        end else begin
                            cur_row        <= cur_row + 1'b1;
                            cnu_min1       <= 7'h7F;
                            cnu_min2       <= 7'h7F;
                            cnu_min1_idx   <= 4'd0;
                            cnu_total_sign <= 1'b0;
                            state          <= ST_CNU_GATHER;
                        end
                    end else begin
                        cur_z          <= cur_z + 1'b1;
                        cnu_min1       <= 7'h7F;
                        cnu_min2       <= 7'h7F;
                        cnu_min1_idx   <= 4'd0;
                        cnu_total_sign <= 1'b0;
                        state          <= ST_CNU_GATHER;
                    end
                end else begin
                    col_cnt <= col_cnt + 1'b1;
                end
            end

            // ----------------------------------------------------------
            // VNU row: one check-row per variable per cycle.
            // Reads ch_llr (row_cnt==0) and msg_cv asynchronously.
            // Writes v_llr via write port (1-cycle pipeline).
            ST_VNU_ROW: begin
                cc_v = vn_cnt[9:6];
                sz_v = vn_cnt[5:0];

                if (row_cnt == 3'd0)
                    s = {{4{ch_llr[vn_cnt][Q-1]}}, ch_llr[vn_cnt]};
                else
                    s = s_acc;

                sh = hb_entry({1'b0, row_cnt}, cc_v);
                if (sh != 6'h3F) begin
                    msg_z_v = sz_v + sh;
                    midx    = {row_cnt, cc_v, msg_z_v};
                    s = s + {{4{msg_cv[midx][Q-1]}}, msg_cv[midx]};
                end

                if (row_cnt == MB-1) begin
                    vllr_new  = sat(s);
                    v_llr_we  <= 1'b1;
                    v_llr_wa  <= vn_cnt;
                    v_llr_wd  <= vllr_new;
                    if (iter == MAX_ITER-1 && vn_cnt < K)
                        decoded[vn_cnt[8:0]] <= vllr_new[Q-1];
                    row_cnt <= 3'd0;
                    if (vn_cnt == N-1) begin
                        if (iter == MAX_ITER-1) begin
                            state <= ST_OUTPUT;
                        end else begin
                            iter           <= iter + 1'b1;
                            cur_row        <= 3'd0;
                            cur_z          <= 6'd0;
                            col_cnt        <= 4'd0;
                            cnu_min1       <= 7'h7F;
                            cnu_min2       <= 7'h7F;
                            cnu_min1_idx   <= 4'd0;
                            cnu_total_sign <= 1'b0;
                            state          <= ST_CNU_GATHER;
                        end
                    end else begin
                        vn_cnt <= vn_cnt + 1'b1;
                    end
                end else begin
                    s_acc   <= s;
                    row_cnt <= row_cnt + 1'b1;
                end
            end

            // ----------------------------------------------------------
            ST_OUTPUT: begin
                iter_count <= iter;
                valid_out  <= 1'b1;
                state      <= ST_IDLE;
            end

            default: state <= ST_IDLE;

        endcase
    end
end

endmodule
