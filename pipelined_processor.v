`default_nettype none

module processor(input clk1,input clk2);
parameter ADD =6'd0,SUB=6'd1,AND=6'd2,OR=6'd3,SLT=6'd4,MUL=6'd5,HLT=6'b111111, // r type instructions
          LW=6'd8,SW=6'd9,ADDI=6'd10,SUBI=6'd11,SLTI=6'd12,BNEQZ=6'd13,BEQZ=6'd14;// i type instructions

    //FIRST STAGE
    reg [31:0] IF_ID_IR,PC,IF_ID_NPC;
    //SECOND STAGE
    reg[31:0] ID_EX_IR, ID_EX_A, ID_EX_B, ID_EX_IMM, ID_EX_NPC;

    reg[2:0] ID_EX_TYPE, EX_MEM_TYPE, MEM_WB_TYPE;

    //THIRD

    reg[31:0] EX_MEM_B, EX_MEM_IR, EX_MEM_ALUOUT;
    reg  EX_MEM_COND;

    // FOURTH

    reg[31:0] MEM_WB_ALUOUT, MEM_WB_LMD, MEM_WB_IR;

    reg [31:0] REG[0:31];// regbank
    reg [31:0] MEM[0:1023];// instruction memory

    parameter RR_ALU= 3'd0, RM_ALU=3'd1, LOAD=3'd2, STORE= 3'd3, BRANCH=3'd4,HALT=3'd5,NOP=3'd6; // instruction types

    reg HALTED;// whenever an halt instruction is encountered it is set to one stop the execution of the program

    reg TAKEN_BRANCH;// set to one when a branch is taken

    //#################   HAZARD #1  IMPLEMENTATION FORWARDING UNIT-REMOVES STALLS
    reg ID_EX_RegWrite, EX_MEM_RegWrite, MEM_WB_RegWrite;

    // ################# HAZARD DETECTION
    wire LOAD_HAZARD;
    assign LOAD_HAZARD=(ID_EX_TYPE==LOAD) && ((IF_ID_IR[25:21]==ID_EX_IR[20:16])|| (IF_ID_IR[20:16]==ID_EX_IR[20:16]));

    always @(posedge clk1) begin //IF STAGE
        if(HALTED==0)begin
            // this block basically handles the updation of pc 
            //two cases here if a branch instruction was found in and fulfilled the branch conditions then the pc would be updated accordingly 
            // this would happen when the branch instruction would have entered the MEM stage i.e once the execution stage is over
            if(LOAD_HAZARD) begin
                PC<= #2 PC;
                IF_ID_IR<= #2 IF_ID_IR;
                IF_ID_NPC<= #2 IF_ID_NPC;
            end

            else if((EX_MEM_IR[31:26] ==  BEQZ && EX_MEM_COND == 1)||
            (EX_MEM_IR[31:26] == BNEQZ && EX_MEM_COND == 0)) begin

                TAKEN_BRANCH <= #2 1;
                IF_ID_IR <= #2 MEM[EX_MEM_ALUOUT];
                IF_ID_NPC <= #2 EX_MEM_ALUOUT+1;
                PC <= #2 EX_MEM_ALUOUT+1;
            end 
            else begin
                TAKEN_BRANCH<=#2 0;
                IF_ID_IR <= #2 MEM[PC];
                IF_ID_NPC <= #2 PC+1 ;
                PC <=  #2 PC+1;
            end
            
        end
    end


    always @(posedge clk2) begin // ID STAGE
        if(HALTED==0) begin
            // mips generally have a hardwired zero that is effectively the zeroth register here thats the design choice 
            // makes life easier in real life situations for nop operations or stalls
            
            ID_EX_A <= #2 (IF_ID_IR[25:21]==5'd0)?0:  REG[IF_ID_IR[25:21]]; // IVE WRITEN THIS DIFFERENTLY 
            ID_EX_B <= #2 (IF_ID_IR[20:16]==5'd0)?0:  REG[IF_ID_IR[20:16]];

            ID_EX_NPC <= #2 IF_ID_NPC;
            ID_EX_IR <= #2 IF_ID_IR;
            ID_EX_IMM <= #2 {{16{IF_ID_IR[15]}},IF_ID_IR[15:0]};// this is just sign extension of 16 bit number

            // UPDATE THE TYPE
            case (IF_ID_IR[31:26])
            //categorising the type of instructions makes our lyf easier will writing the ex stage
            // adding the regwrite
                ADD,SUB,AND,OR,SLT,MUL:begin
                    ID_EX_TYPE <= #2 RR_ALU;
                    ID_EX_RegWrite <= #2 1;
                end 
                ADDI,SUBI,SLTI:begin 
                    ID_EX_TYPE <= #2 RM_ALU;
                    ID_EX_RegWrite <= #2 1;
                end
                LW: begin
                    ID_EX_TYPE <= #2 LOAD;
                    ID_EX_RegWrite <= #2 1;
                end
                SW: begin
                    ID_EX_TYPE <= #2 STORE;
                    ID_EX_RegWrite <= #2 0;
                end
                BEQZ,BNEQZ:begin 
                    ID_EX_TYPE <= #2 BRANCH;
                    ID_EX_RegWrite <= #2 0;
                end
                HLT: begin
                    ID_EX_TYPE <= #2 HALT;
                    ID_EX_RegWrite <= #2 0;
                end

                default:begin
                    ID_EX_TYPE <= #2 HALT;
                    ID_EX_RegWrite <= #2 0;
                end 
            endcase

            if(LOAD_HAZARD) begin
                ID_EX_TYPE<= #2 NOP;
                ID_EX_RegWrite<= #2 0;
                ID_EX_IR<=0;
            end
        end
    end


    // EX STAGE
    // Helper signals
    wire [4:0] EX_MEM_RD = (EX_MEM_TYPE == RR_ALU) ? EX_MEM_IR[15:11] : (EX_MEM_TYPE == RM_ALU || EX_MEM_TYPE == LOAD) ? EX_MEM_IR[20:16] : 0;

    wire [4:0] MEM_WB_RD = (MEM_WB_TYPE == RR_ALU) ? MEM_WB_IR[15:11] : (MEM_WB_TYPE == RM_ALU || MEM_WB_TYPE == LOAD) ? MEM_WB_IR[20:16] : 0;
    reg [31:0] forwardA,forwardB;
    always@(*) begin
        forwardA=ID_EX_A;
        forwardB=ID_EX_B;
        if(EX_MEM_RegWrite && EX_MEM_RD==ID_EX_IR[25:21] && ID_EX_IR[25:21]!=0)begin
            //rr or rm operations
            forwardA=EX_MEM_ALUOUT;
        end
        else if(MEM_WB_RegWrite && MEM_WB_RD==ID_EX_IR[25:21] && ID_EX_IR[25:21]!=0) begin
            //load
            forwardA=(MEM_WB_TYPE==LOAD)?MEM_WB_LMD:MEM_WB_ALUOUT;
        end
        
        if(EX_MEM_RegWrite && EX_MEM_RD==ID_EX_IR[20:16] && ID_EX_IR[20:16]!=0)begin
            //rr or rm operations

            forwardB=EX_MEM_ALUOUT;
        end
        else if(MEM_WB_RegWrite && MEM_WB_RD==ID_EX_IR[20:16] && ID_EX_IR[20:16]!=0) begin
            //load
            forwardB=(MEM_WB_TYPE==LOAD)?MEM_WB_LMD:MEM_WB_ALUOUT;
        end
        
    end

    always @(posedge clk1 ) begin 
        if(HALTED==0) begin
            EX_MEM_IR <= #2 ID_EX_IR;
            EX_MEM_TYPE <= #2 ID_EX_TYPE;
            EX_MEM_RegWrite <= #2 ID_EX_RegWrite;
            
            
            case(ID_EX_TYPE)
                RR_ALU:begin
                    case (ID_EX_IR[31:26])
                        ADD: EX_MEM_ALUOUT <= #2 forwardA + forwardB;
                        SUB: EX_MEM_ALUOUT <= #2 forwardA - forwardB;
                        AND: EX_MEM_ALUOUT <= #2 forwardA & forwardB;
                        OR: EX_MEM_ALUOUT <= #2 forwardA | forwardB;
                        MUL: EX_MEM_ALUOUT <= #2 forwardA * forwardB;
                        SLT: EX_MEM_ALUOUT <= #2 forwardA < forwardB;//compare op
                        default: EX_MEM_ALUOUT <= #2 32'hxxxxxxxx;
                    endcase
                end
                RM_ALU: begin
                    case (ID_EX_IR[31:26])
                        ADDI: EX_MEM_ALUOUT <= #2 forwardA + ID_EX_IMM;
                        SUBI: EX_MEM_ALUOUT <= #2 forwardA - ID_EX_IMM;
                        SLTI: EX_MEM_ALUOUT <= #2 forwardA < ID_EX_IMM;
                        default: EX_MEM_ALUOUT <= #2 32'hxxxxxxxx;
                    endcase
                end
                LOAD,STORE:begin
                    EX_MEM_ALUOUT <= #2 forwardA + ID_EX_IMM;
                    EX_MEM_B <= #2 forwardB;// needed for store operation
                end
                BRANCH:begin
                    EX_MEM_COND <= #2 (forwardA == 0);
                    EX_MEM_ALUOUT <= #2 ID_EX_NPC+ID_EX_IMM;
                end
            endcase
        end
    end


    always @(posedge clk2) begin // MEM STAGE
        if(HALTED==0) begin
            MEM_WB_IR <= #2 EX_MEM_IR;
            MEM_WB_TYPE <= #2 EX_MEM_TYPE;
            MEM_WB_RegWrite <= #2 EX_MEM_RegWrite; 
            case (EX_MEM_TYPE)
                RR_ALU,RM_ALU:begin
                    MEM_WB_ALUOUT <= #2 EX_MEM_ALUOUT;
                end 
                LOAD:begin
                    MEM_WB_LMD <= #2 MEM[EX_MEM_ALUOUT];
                end
                STORE:begin
                    if(TAKEN_BRANCH == 0)
                        MEM[EX_MEM_ALUOUT] <= #2 EX_MEM_B;
                end
                default: ;
            endcase
        end
    end


    always @(posedge clk1) begin //WB STAGE
        if(TAKEN_BRANCH == 0)begin
            case (MEM_WB_TYPE)
                RR_ALU: REG[MEM_WB_IR[15:11]] <= #2 MEM_WB_ALUOUT;
                RM_ALU: REG[MEM_WB_IR[20:16]] <= #2 MEM_WB_ALUOUT;
                LOAD: REG[MEM_WB_IR[20:16]] <= #2 MEM_WB_LMD;
                HALT: HALTED <= #2 1;
                default:; 
            endcase
        end
    end 
endmodule
