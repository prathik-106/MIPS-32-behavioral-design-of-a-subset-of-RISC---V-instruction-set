module bht(

    input logic clk,
    input logic reset,
    //read port
    input logic [5:0] pc_index,
    //write port
    input logic [5:0] update_index,
    input logic update_en,   
    input logic actual_taken,


    // output
    output logic predict_taken
);

    logic [1:0] bht_mem[0:63];
    integer i;

    always @(posedge clk) begin
        if(reset) begin
            for (i=0;i<64;i=i+1) begin
                bht_mem[i] <= 2'd1;
            end
        end
        else if (update_en) begin
            if(actual_taken) begin
                bht_mem[update_index]<= bht_mem[update_index] == 2'b11 ? 2'b11:bht_mem[update_index]+2'd1;
            end
            else begin
                bht_mem[update_index] <= bht_mem[update_index] == 2'd0?2'd0:bht_mem[update_index]-2'd1;
            end 
        end
    end

    assign predict_taken = bht_mem[pc_index][1];
endmodule