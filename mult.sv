
module mult (
    input logic [15:0] inp_a,
    input logic [15:0] inp_b,
    output logic [31:0] prod,
    input logic clk,
    input logic rst
); //both inputs 16 bits, output 32 bits 
	
    logic [15:0] a_reg, b_reg;
    logic [31:0] prod_reg;
    // want to always flop all inputs and bits
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            a_reg <= 16'b0;
            b_reg <= 16'b0;
            prod_reg <= 32'b0;
        end else begin
            a_reg <= inp_a;
            b_reg <= inp_b;
            prod_reg <= a_reg * b_reg;
        end
    end

    assign prod = prod_reg;

endmodule
