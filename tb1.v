`timescale 1ps/1ps
module tb1;

reg clk1,clk2;
integer k;

processor mips(clk1,clk2);

initial begin
    clk1=0;clk2=0;
    repeat(20)begin
        #5 clk1=1;#5 clk1=0;
        #5 clk2=1;#5 clk2=0;
    end
end

initial begin
    for(k=0;k<32;k=k+1)
        mips.REG[k]=0;
    // ADDI rt, rs, imm
    mips.MEM[0]  = {6'd10, 5'd0, 5'd1, 16'd10};           // ADDI R1, R0, 10
    mips.MEM[1]  = {6'd10, 5'd0, 5'd2, 16'd20};           // ADDI R2, R0, 20
    mips.MEM[2]  = {6'd1,  5'd2, 5'd1, 5'd3, 5'd0, 6'd0}; // SUB  R3, R2, R1  -> R3 = 10  (non zero)
    mips.MEM[3]  = {6'd13, 5'd3, 5'd0, 16'd2};            // BNEQZ R3, +2     -> R3!=0 so branch to MEM[6]
    mips.MEM[4]  = {6'd10, 5'd0, 5'd4, 16'd99};           // ADDI R4, R0, 99  -> should be SKIPPED
    mips.MEM[5]  = {6'd10, 5'd0, 5'd5, 16'd99};           // ADDI R5, R0, 99  -> should be SKIPPED
    mips.MEM[6]  = {6'd1,  5'd2, 5'd2, 5'd6, 5'd0, 6'd0}; // SUB  R6, R2, R2  -> R6 = 0
    mips.MEM[7]  = {6'd14, 5'd6, 5'd0, 16'd2};            // BEQZ R6, +2      -> R6==0 so branch to MEM[10]
    mips.MEM[8]  = {6'd10, 5'd0, 5'd7, 16'd99};           // ADDI R7, R0, 99  -> should be SKIPPED
    mips.MEM[9]  = {6'd10, 5'd0, 5'd8, 16'd99};           // ADDI R8, R0, 99  -> should be SKIPPED
    mips.MEM[10] = {6'd10, 5'd0, 5'd9, 16'd55};           // ADDI R9, R0, 55  -> should EXECUTE
    mips.MEM[11] = {6'd63, 26'd0};                         // HLT

    mips.HALTED=0;
    mips.TAKEN_BRANCH=0;
    mips.PC=0;
    #600;
    for(k=0;k<11;k++)
        $display("R%1d - %2d",k,mips.REG[k]);   
end

initial begin
    $dumpfile("tb1.vcd");
    $dumpvars(0,tb1);
    #620 $finish;
end

endmodule
