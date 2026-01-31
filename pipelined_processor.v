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

    parameter RR_ALU= 3'd0, RM_ALU=3'd1, LOAD=3'd2, STORE= 3'd3, BRANCH=3'd4,HALT=3'd5; // instruction types

    reg HALTED;// whenever an halt instruction is encountered it is set to one stop the execution of the program

    reg TAKEN_BRANCH;// set to one when a branch is taken


    always @(posedge clk1) begin //IF STAGE
        if(HALTED==0)begin

            if((EX_MEM_IR[31:26] ==  BEQZ && EX_MEM_COND == 1)||
            (EX_MEM_IR[31:26] == BNEQZ && EX_MEM_COND == 0)) begin

                TAKEN_BRANCH <= #2 1;
                IF_ID_IR <= #2 MEM[EX_MEM_ALUOUT];
                IF_ID_NPC <= #2 EX_MEM_ALUOUT+1;
                PC <= #2 EX_MEM_ALUOUT+1;
            end 
            else begin
                IF_ID_IR <= #2 MEM[PC];
                IF_ID_NPC <= #2 PC+1 ;
                PC <=  #2 PC+1;

            end
        end
    end


    always @(posedge clk2) begin // ID STAGE
        if(HALTED==0) begin
            ID_EX_A <= #2 (IF_ID_IR[25:21]==5'd0)?0:  REG[IF_ID_IR[25:21]]; 
            ID_EX_B <= #2 (IF_ID_IR[20:16]==5'd0)?0:  REG[IF_ID_IR[20:16]];

            ID_EX_NPC <= #2 IF_ID_NPC;
            ID_EX_IR <= #2 IF_ID_IR;
            ID_EX_IMM <= #2 {{16{IF_ID_IR[15]}},IF_ID_IR[15:0]};

            // UPDATE THE TYPE
            case (IF_ID_IR[31:26])
                ADD,SUB,AND,OR,SLT,MUL: ID_EX_TYPE <= #2 RR_ALU;
                ADDI,SUBI,SLTI: ID_EX_TYPE <= #2 RM_ALU;
                LW: ID_EX_TYPE <= #2 LOAD;
                SW: ID_EX_TYPE <= #2 STORE;
                BEQZ,BNEQZ:ID_EX_TYPE <= #2 BRANCH;
                HLT: ID_EX_TYPE <= #2 HALT;

                default: ID_EX_TYPE <= #2 HALT;
            endcase
        end
    end



    always @(posedge clk1 ) begin // EX STAGE
        if(HALTED==0) begin
            EX_MEM_IR <= #2 ID_EX_IR;
            EX_MEM_TYPE <= #2 ID_EX_TYPE;
            TAKEN_BRANCH <= #2 0;
            case(ID_EX_TYPE)
                RR_ALU:begin
                    case (ID_EX_IR[31:26])
                        ADD: EX_MEM_ALUOUT <= #2 ID_EX_A + ID_EX_B;
                        SUB: EX_MEM_ALUOUT <= #2 ID_EX_A - ID_EX_B;
                        AND: EX_MEM_ALUOUT <= #2 ID_EX_A & ID_EX_B;
                        OR: EX_MEM_ALUOUT <= #2 ID_EX_A | ID_EX_B;
                        MUL: EX_MEM_ALUOUT <= #2 ID_EX_A * ID_EX_B;
                        SLT: EX_MEM_ALUOUT <= #2 ID_EX_A < ID_EX_B;
                        default: EX_MEM_ALUOUT <= #2 32'hxxxxxxxx;
                    endcase
                end
                RM_ALU: begin
                    case (ID_EX_IR[31:26])
                        ADDI: EX_MEM_ALUOUT <= #2 ID_EX_A + ID_EX_IMM;
                        SUBI: EX_MEM_ALUOUT <= #2 ID_EX_A - ID_EX_IMM;
                        SLTI: EX_MEM_ALUOUT <= #2 ID_EX_A < ID_EX_IMM;
                        default: EX_MEM_ALUOUT <= #2 32'hxxxxxxxx;
                    endcase
                end
                LOAD,STORE:begin
                    EX_MEM_ALUOUT <= #2 ID_EX_A + ID_EX_IMM;
                    EX_MEM_B <= #2 ID_EX_B;
                end
                BRANCH:begin
                    EX_MEM_COND <= #2 (ID_EX_A == 0);
                    EX_MEM_ALUOUT <= #2 ID_EX_NPC+ID_EX_IMM;
                end
            endcase
        end
    end


    always @(posedge clk2) begin // MEM STAGE
        if(HALTED==0) begin
            MEM_WB_IR <= #2 EX_MEM_IR;
            MEM_WB_TYPE <= #2 EX_MEM_TYPE;
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
