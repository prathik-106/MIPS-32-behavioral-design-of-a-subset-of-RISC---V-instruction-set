module btb(
    input logic clk,
    input logic reset,
    input logic [5:0] pc_index,
    input logic [31:0] branch_address_in,
    input logic update_btb,
    input logic [5:0] update_btb_pc_index,
    output logic [31:0] branch_address_out
);

    reg [31:0] btb_mem[0:63];
    integer i;

    always @(posedge clk)begin
        if(reset)begin
            for(i=0;i<64;i=i+1) begin
                btb_mem[i] <= '0;
            end
        end
        else if(update_btb) begin
            btb_mem[update_btb_pc_index] <= branch_address_in;
        end
    end

    assign branch_address_out = btb_mem[pc_index];

endmodule