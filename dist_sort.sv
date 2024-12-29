module dist_sort (
    input logic        clk, rst,
    input logic [63:0] query,
    input logic [63:0] search_0,
    input logic [63:0] search_1,
    input logic [63:0] search_2,
    input logic [63:0] search_3,
    input logic [63:0] search_4,
    input logic [63:0] search_5,
    input logic [63:0] search_6,
    input logic [63:0] search_7,
    input logic        in_valid,
    output logic [2:0] addr_1st,
    output logic [2:0] addr_2nd,
    output logic       out_valid
);

    // Parameters
    localparam N_PIPELINE_STAGES = 4;

    // Internal wires and registers
    logic [63:0] search_vectors_ff [7:0];
    logic [63:0] query_ff;
    logic [12:0] distances [7:0];
    logic [2:0]  indices [7:0];

    // Pipeline registers
    logic [12:0] min_distances_stage1 [3:0];
    logic [2:0]  min_indices_stage1 [3:0];
    logic [12:0] sec_distances_stage1 [3:0];
    logic [2:0]  sec_indices_stage1 [3:0];

    logic [12:0] min_distances_stage2 [1:0];
    logic [2:0]  min_indices_stage2 [1:0];
    logic [12:0] sec_distances_stage2 [1:0];
    logic [2:0]  sec_indices_stage2 [1:0];

    logic [12:0] overall_min_distance;
    logic [2:0]  overall_min_index;
    logic [12:0] overall_second_distance;
    logic [2:0]  overall_second_index;

    // Pipeline valid signals
    logic [N_PIPELINE_STAGES-1:0] pipeline_valid;
    logic in_valid_d1, in_valid_d2;

    // Flop the inputs and delay in_valid
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            for (int i = 0; i < 8; i++) begin
                search_vectors_ff[i] <= '0;
            end
            query_ff     <= '0;
            in_valid_d1  <= 1'b0;
            in_valid_d2  <= 1'b0;
        end else begin
            search_vectors_ff[0] <= search_0;
            search_vectors_ff[1] <= search_1;
            search_vectors_ff[2] <= search_2;
            search_vectors_ff[3] <= search_3;
            search_vectors_ff[4] <= search_4;
            search_vectors_ff[5] <= search_5;
            search_vectors_ff[6] <= search_6;
            search_vectors_ff[7] <= search_7;
            query_ff             <= query;
            in_valid_d1          <= in_valid;
            in_valid_d2          <= in_valid_d1;
        end
    end

    // Assign indices
    generate
        genvar idx;
        for (idx = 0; idx < 8; idx = idx + 1) begin : assign_indices
            assign indices[idx] = idx[2:0];
        end
    endgenerate

    // Instantiate calc_dist modules
    generate
        for (idx = 0; idx < 8; idx = idx + 1) begin : calc_dists
            calc_dist u_calc_dist (
                .clk(clk),
                .q(query_ff),
                .s(search_vectors_ff[idx]),
                .distance(distances[idx])
            );
        end
    endgenerate

    // Pipeline valid shift register
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            pipeline_valid <= '0;
        end else begin
            pipeline_valid[0] <= in_valid_d2;
            for (int i = 1; i < N_PIPELINE_STAGES; i = i + 1) begin
                pipeline_valid[i] <= pipeline_valid[i-1];
            end
        end
    end

    // Stage 1: Compare adjacent pairs
    generate
        for (genvar i = 0; i < 4; i = i + 1) begin : stage1_blocks
            always_ff @(posedge clk or posedge rst) begin
                if (rst) begin
                    min_distances_stage1[i] <= '0;
                    min_indices_stage1[i]   <= '0;
                    sec_distances_stage1[i] <= '0;
                    sec_indices_stage1[i]   <= '0;
                end else if (pipeline_valid[0]) begin
                    if (distances[2*i] < distances[2*i+1] ||
                        (distances[2*i] == distances[2*i+1] && indices[2*i] <= indices[2*i+1])) begin
                        min_distances_stage1[i] <= distances[2*i];
                        min_indices_stage1[i]   <= indices[2*i];
                        sec_distances_stage1[i] <= distances[2*i+1];
                        sec_indices_stage1[i]   <= indices[2*i+1];
                    end else begin
                        min_distances_stage1[i] <= distances[2*i+1];
                        min_indices_stage1[i]   <= indices[2*i+1];
                        sec_distances_stage1[i] <= distances[2*i];
                        sec_indices_stage1[i]   <= indices[2*i];
                    end
                end
            end
        end
    endgenerate

    // Stage 2: Compare results of Stage 1
    generate
        for (genvar i = 0; i < 2; i = i + 1) begin : stage2_blocks
            always_ff @(posedge clk or posedge rst) begin
                // Declarations must be at the top
                logic [12:0] dist0, dist1, dist2, dist3;
                logic [2:0]  idx0, idx1, idx2, idx3;
                logic [12:0] min_dist, sec_dist;
                logic [2:0]  min_idx, sec_idx;

                if (rst) begin
                    min_distances_stage2[i] <= '0;
                    min_indices_stage2[i]   <= '0;
                    sec_distances_stage2[i] <= '0;
                    sec_indices_stage2[i]   <= '0;
                end else if (pipeline_valid[1]) begin
                    // Collect distances and indices
                    dist0 = min_distances_stage1[2*i];
                    idx0  = min_indices_stage1[2*i];
                    dist1 = sec_distances_stage1[2*i];
                    idx1  = sec_indices_stage1[2*i];
                    dist2 = min_distances_stage1[2*i+1];
                    idx2  = min_indices_stage1[2*i+1];
                    dist3 = sec_distances_stage1[2*i+1];
                    idx3  = sec_indices_stage1[2*i+1];

                    // Initialize min and second min
                    // First, find the smallest distance
                    if (dist0 < dist2 || (dist0 == dist2 && idx0 <= idx2)) begin
                        min_dist = dist0;
                        min_idx  = idx0;
                        sec_dist = dist2;
                        sec_idx  = idx2;
                    end else begin
                        min_dist = dist2;
                        min_idx  = idx2;
                        sec_dist = dist0;
                        sec_idx  = idx0;
                    end

                    // Compare dist1
                    if (dist1 < min_dist || (dist1 == min_dist && idx1 < min_idx)) begin
                        sec_dist = min_dist;
                        sec_idx  = min_idx;
                        min_dist = dist1;
                        min_idx  = idx1;
                    end else if ((dist1 < sec_dist || (dist1 == sec_dist && idx1 < sec_idx)) && idx1 != min_idx) begin
                        sec_dist = dist1;
                        sec_idx  = idx1;
                    end

                    // Compare dist3
                    if (dist3 < min_dist || (dist3 == min_dist && idx3 < min_idx)) begin
                        sec_dist = min_dist;
                        sec_idx  = min_idx;
                        min_dist = dist3;
                        min_idx  = idx3;
                    end else if ((dist3 < sec_dist || (dist3 == sec_dist && idx3 < sec_idx)) && idx3 != min_idx) begin
                        sec_dist = dist3;
                        sec_idx  = idx3;
                    end

                    // If min and sec indices are the same, find next smallest unique index
                    if (min_idx == sec_idx) begin
                        // Initialize to maximum values
                        sec_dist = 13'h1FFF;
                        sec_idx  = 3'b111;

                        // Check all distances again to find next smallest unique index
                        if ((dist0 < sec_dist || (dist0 == sec_dist && idx0 < sec_idx)) && idx0 != min_idx) begin
                            sec_dist = dist0;
                            sec_idx  = idx0;
                        end
                        if ((dist1 < sec_dist || (dist1 == sec_dist && idx1 < sec_idx)) && idx1 != min_idx) begin
                            sec_dist = dist1;
                            sec_idx  = idx1;
                        end
                        if ((dist2 < sec_dist || (dist2 == sec_dist && idx2 < sec_idx)) && idx2 != min_idx) begin
                            sec_dist = dist2;
                            sec_idx  = idx2;
                        end
                        if ((dist3 < sec_dist || (dist3 == sec_dist && idx3 < sec_idx)) && idx3 != min_idx) begin
                            sec_dist = dist3;
                            sec_idx  = idx3;
                        end
                    end

                    min_distances_stage2[i] <= min_dist;
                    min_indices_stage2[i]   <= min_idx;
                    sec_distances_stage2[i] <= sec_dist;
                    sec_indices_stage2[i]   <= sec_idx;
                end
            end
        end
    endgenerate

    // Stage 3: Final comparison
    always_ff @(posedge clk or posedge rst) begin
        // Declarations must be at the top
        logic [12:0] dist0, dist1, dist2, dist3;
        logic [2:0]  idx0, idx1, idx2, idx3;
        logic [12:0] min_dist, sec_dist;
        logic [2:0]  min_idx, sec_idx;

        if (rst) begin
            overall_min_distance    <= '0;
            overall_min_index       <= '0;
            overall_second_distance <= '0;
            overall_second_index    <= '0;
        end else if (pipeline_valid[2]) begin
            // Collect distances and indices
            dist0 = min_distances_stage2[0];
            idx0  = min_indices_stage2[0];
            dist1 = sec_distances_stage2[0];
            idx1  = sec_indices_stage2[0];
            dist2 = min_distances_stage2[1];
            idx2  = min_indices_stage2[1];
            dist3 = sec_distances_stage2[1];
            idx3  = sec_indices_stage2[1];

            // Initialize min and second min
            // First, find the smallest distance
            if (dist0 < dist2 || (dist0 == dist2 && idx0 <= idx2)) begin
                min_dist = dist0;
                min_idx  = idx0;
                sec_dist = dist2;
                sec_idx  = idx2;
            end else begin
                min_dist = dist2;
                min_idx  = idx2;
                sec_dist = dist0;
                sec_idx  = idx0;
            end

            // Compare dist1
            if (dist1 < min_dist || (dist1 == min_dist && idx1 < min_idx)) begin
                sec_dist = min_dist;
                sec_idx  = min_idx;
                min_dist = dist1;
                min_idx  = idx1;
            end else if ((dist1 < sec_dist || (dist1 == sec_dist && idx1 < sec_idx)) && idx1 != min_idx) begin
                sec_dist = dist1;
                sec_idx  = idx1;
            end

            // Compare dist3
            if (dist3 < min_dist || (dist3 == min_dist && idx3 < min_idx)) begin
                sec_dist = min_dist;
                sec_idx  = min_idx;
                min_dist = dist3;
                min_idx  = idx3;
            end else if ((dist3 < sec_dist || (dist3 == sec_dist && idx3 < sec_idx)) && idx3 != min_idx) begin
                sec_dist = dist3;
                sec_idx  = idx3;
            end

            // If min and sec indices are the same, find next smallest unique index
            if (min_idx == sec_idx) begin
                // Initialize to maximum values
                sec_dist = 13'h1FFF;
                sec_idx  = 3'b111;

                // Check all distances again to find next smallest unique index
                if ((dist0 < sec_dist || (dist0 == sec_dist && idx0 < sec_idx)) && idx0 != min_idx) begin
                    sec_dist = dist0;
                    sec_idx  = idx0;
                end
                if ((dist1 < sec_dist || (dist1 == sec_dist && idx1 < sec_idx)) && idx1 != min_idx) begin
                    sec_dist = dist1;
                    sec_idx  = idx1;
                end
                if ((dist2 < sec_dist || (dist2 == sec_dist && idx2 < sec_idx)) && idx2 != min_idx) begin
                    sec_dist = dist2;
                    sec_idx  = idx2;
                end
                if ((dist3 < sec_dist || (dist3 == sec_dist && idx3 < sec_idx)) && idx3 != min_idx) begin
                    sec_dist = dist3;
                    sec_idx  = idx3;
                end
            end

            overall_min_distance    <= min_dist;
            overall_min_index       <= min_idx;
            overall_second_distance <= sec_dist;
            overall_second_index    <= sec_idx;
        end
    end

    // Output stage
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            addr_1st  <= 3'd0;
            addr_2nd  <= 3'd0;
            out_valid <= 1'b0;
        end else if (pipeline_valid[N_PIPELINE_STAGES-1]) begin
            addr_1st  <= overall_min_index;
            addr_2nd  <= overall_second_index;
            out_valid <= 1'b1;
        end else begin
            addr_1st  <= 3'd0;
            addr_2nd  <= 3'd0;
            out_valid <= 1'b0;
        end
    end

endmodule

module calc_dist (
    input              clk, rst,
    input      [63:0]  q, // Query vector (16 x 4-bit)
    input      [63:0]  s, // Search vector (16 x 4-bit)
    output reg [12:0]  distance // Sum of squared differences
);
    // Declare qi and si as arrays of 4-bit unsigned values
    wire [3:0] qi [15:0];
    wire [3:0] si [15:0];
    // Zero-extended qi and si to 5 bits for arithmetic
    wire [4:0] qi_ext [15:0];
    wire [4:0] si_ext [15:0];
    // Difference and squared difference
    wire signed [5:0] diff [15:0];
    wire [9:0] dist_squared [15:0];
    // Temporary variable for summation
    reg [12:0] temp_distance;

    // Combined generate loop
    generate
        genvar idx;
        for (idx = 0; idx < 16; idx = idx + 1) begin : compute_elements
            // Extract 4-bit slices from q and s in reverse order
            assign qi[idx] = q[63 - idx*4 -: 4];
            assign si[idx] = s[63 - idx*4 -: 4];
            // Zero-extend to 5 bits
            assign qi_ext[idx] = {1'b0, qi[idx]};
            assign si_ext[idx] = {1'b0, si[idx]};
            // Compute difference
            assign diff[idx] = $signed(qi_ext[idx]) - $signed(si_ext[idx]);
            // Compute squared difference
            assign dist_squared[idx] = diff[idx] * diff[idx];
        end
    endgenerate

    // Sum the squared differences
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            distance <= '0;
        end else begin
            temp_distance = 0;
            for (int i = 0; i < 16; i = i + 1) begin
                temp_distance = temp_distance + dist_squared[i];
            end
            distance <= temp_distance;
        end
    end
endmodule
