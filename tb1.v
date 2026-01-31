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
mips.MEM[0] = 32'h2821000a; // ADDI R1, R0, 10
mips.MEM[1] = 32'h0ce73800; // NOP
mips.MEM[2] = 32'h28420014; // ADDI R2, R0, 20
mips.MEM[3] = 32'h0ce73800; // NOP
mips.MEM[4] = 32'h28630019; // ADDI R3, R0, 25
mips.MEM[5] = 32'h0ce73800; // NOP
mips.MEM[6] = 32'h00222000; // ADD R4, R1, R2
mips.MEM[7] = 32'h0ce73800; // NOP
mips.MEM[8] = 32'h00832800; // ADD R5, R4, R3
mips.MEM[9] = 32'hfc000000; // HLT

    mips.HALTED=0;
    mips.TAKEN_BRANCH=0;
    mips.PC=0;
    #280;
    for(k=0;k<6;k++)
        $display("R%1d - %2d",k,mips.REG[k]);   
end

initial begin
    $dumpfile("tb1.vcd");
    $dumpvars(0,tb1);
    #300 $finish;
end

endmodule