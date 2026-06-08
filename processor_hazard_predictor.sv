`default_nettype none

module processor(
    input clk1,
    input reset,
    output [31:0] debug_pc,
    output debug_halted
);
parameter ADD =6'd0,SUB=6'd1,AND=6'd2,OR=6'd3,SLT=6'd4,MUL=6'd5,HLT=6'b111111, // r type instructions
          LW=6'd8,SW=6'd9,ADDI=6'd10,SUBI=6'd11,SLTI=6'd12,BNEQZ=6'd13,BEQZ=6'd14,// i type instructions
          NOPE=6'D42;//

    // just some dummy outputs for synthesis
    assign debug_pc     = PC;
    assign debug_halted = HALTED;
    //FIRST STAGE
    reg [31:0] IF_ID_IR,PC,IF_ID_NPC;
    reg IF_ID_PRED;
    //SECOND STAGE
    reg[31:0] ID_EX_IR, ID_EX_A, ID_EX_B, ID_EX_IMM, ID_EX_NPC ;
    reg ID_EX_PRED;

    reg[2:0] ID_EX_TYPE, EX_MEM_TYPE, MEM_WB_TYPE;

    //THIRD

    reg[31:0] EX_MEM_B, EX_MEM_IR, EX_MEM_ALUOUT,EX_MEM_PC;
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

    // ################# HAZARD DETECTION ###########################################################################
    wire LOAD_HAZARD;
    assign LOAD_HAZARD=(ID_EX_TYPE==LOAD) && ((IF_ID_IR[25:21]==ID_EX_IR[20:16])|| (IF_ID_IR[20:16]==ID_EX_IR[20:16]));

    // ######################## PIPELINE FLUSH####################

    wire BRANCH_TAKEN;
    assign BRANCH_TAKEN = ((EX_MEM_IR[31:26] ==  BEQZ && EX_MEM_COND == 1)||(EX_MEM_IR[31:26] == BNEQZ && EX_MEM_COND == 0)) && (EX_MEM_TYPE == BRANCH);
    wire BRANCH_FLUSH;
    assign BRANCH_FLUSH = (ID_EX_PRED^BRANCH_TAKEN) ;

    //########################THE STORY OF HALT AND THE 4 WASTED CYCLES(CORRUPTION OF MEMORY)
    logic HALT_DETECTED;

    /////########################################### BRANCH PREDICTOR#############################
    logic predict_taken;
    logic [31:0] predicted_address;

    bht  bht_module(.clk(clk1),.reset(reset),.update_en(EX_MEM_TYPE == BRANCH),.update_index(EX_MEM_PC[5:0]),.predict_taken(predict_taken),.actual_taken(BRANCH_TAKEN),.pc_index(IF_ID_NPC[5:0] -6'd1));
    btb btb_module(.clk(clk1),.reset(reset),.update_btb(BRANCH_TAKEN),.pc_index(IF_ID_NPC[5:0] -6'd1),.update_btb_pc_index(EX_MEM_PC[5:0]),.branch_address_in(EX_MEM_ALUOUT),.branch_address_out(predicted_address));


    always @(posedge clk1) begin //IF STAGE
        if(reset) begin
            IF_ID_IR  <= {NOPE,26'd0};
            IF_ID_NPC <= 32'd0;
            PC        <= 32'd0;
            TAKEN_BRANCH <= 0;
            HALT_DETECTED<=0;
            IF_ID_PRED <= 0;
        end
        else if(!HALTED)begin
            // this block basically handles the updation of pc 
            //two cases here if a branch instruction was found in and fulfilled the branch conditions then the pc would be updated accordingly 
            // this would happen when the branch instruction would have entered the MEM stage i.e once the execution stage is over

            if(HALT_DETECTED) begin
                PC <= PC;
                IF_ID_IR <= {NOPE,26'd0};
            end
            else if(LOAD_HAZARD) begin
                PC <= PC;
                IF_ID_IR <= IF_ID_IR;
                IF_ID_NPC <= IF_ID_NPC;
            end

            else if (predict_taken && (IF_ID_IR[31:26] == BEQZ ||IF_ID_IR[31:26]==BNEQZ) && !BRANCH_FLUSH) begin
                PC <= predicted_address+1;
                IF_ID_IR <=MEM[predicted_address];
                IF_ID_NPC <= predicted_address +1;
                IF_ID_PRED <= predict_taken;
                TAKEN_BRANCH <=1;
            end

            else if (BRANCH_FLUSH && EX_MEM_TYPE != NOP) begin
                if(ID_EX_PRED) begin
                    PC <=EX_MEM_PC + 2;
                    IF_ID_IR <= MEM[EX_MEM_PC + 1];
                    IF_ID_NPC <= EX_MEM_PC +2;
                    TAKEN_BRANCH <=0;
                end
                else begin
                    PC <= EX_MEM_ALUOUT+1;
                    IF_ID_IR <= MEM[EX_MEM_ALUOUT];
                    IF_ID_NPC <= EX_MEM_ALUOUT +1;
                    TAKEN_BRANCH <=1;
                end
            end
            // else if(EX_MEM_IR[31:26]==BEQZ && EX_MEM_COND==1 ||
            //         EX_MEM_IR[31:26]==BNEQZ && EX_MEM_COND==0) begin
            //     TAKEN_BRANCH <= 1;
            //     IF_ID_IR <= MEM[EX_MEM_ALUOUT];
            //     IF_ID_NPC <= EX_MEM_ALUOUT+1;
            //     PC <= EX_MEM_ALUOUT+1;
            // end
            else begin
                IF_ID_PRED <=0;
                TAKEN_BRANCH <= 0;
                IF_ID_IR <= MEM[PC];
                IF_ID_NPC <= PC+1;
                PC <= PC+1;
                HALT_DETECTED <= (ID_EX_TYPE == HALT);
            end
            
        end
    end

    //write first logic
    
    wire [31:0] REG_RS,REG_RT,WB_DATA;
    wire [4:0] WB_RD;
    assign WB_DATA = MEM_WB_TYPE == LOAD ? MEM_WB_LMD : MEM_WB_ALUOUT;
    assign WB_RD = (MEM_WB_TYPE == RR_ALU) ? MEM_WB_IR[15:11] :MEM_WB_IR[20:16];
    assign REG_RS = (IF_ID_IR[25:21] == 5'd0)?5'd0:( MEM_WB_RegWrite && IF_ID_IR[25:21] == WB_RD)? WB_DATA:REG[IF_ID_IR[25:21]];
    assign REG_RT = (IF_ID_IR[20:16] == 5'd0)?5'd0:(MEM_WB_RegWrite && IF_ID_IR[20:16] == WB_RD)?WB_DATA:REG[IF_ID_IR[20:16]];


    always @(posedge clk1) begin // ID STAGE
        if(reset) begin
            ID_EX_TYPE     <= NOP;
            ID_EX_IR       <= 32'd0;
            ID_EX_RegWrite <= 0;
            ID_EX_PRED <=0;
        end
        else if(!HALTED) begin
            // mips generally have a hardwired zero that is effectively the zeroth register here thats the design choice 
            // makes life easier in real life situations for nop operations or stalls

            // here what i intend to do is convert this two clock setup into a single clock setup
            // so my priority is to write first if the instruction asks me to


            ID_EX_A <=  REG_RS; 
            ID_EX_B <=  REG_RT;
            ID_EX_PRED <= IF_ID_PRED;
            ID_EX_NPC <=  IF_ID_NPC;
            ID_EX_IR <= HALT_DETECTED ? {NOPE,26'd0} : IF_ID_IR;
            ID_EX_IMM <=  {{16{IF_ID_IR[15]}},IF_ID_IR[15:0]};// this is just sign extension of 16 bit number

            // UPDATE THE TYPE
            case (IF_ID_IR[31:26])
            //categorising the type of instructions makes our lyf easier will writing the ex stage
            // adding the regwrite
                ADD,SUB,AND,OR,SLT,MUL:begin
                    ID_EX_TYPE <=  RR_ALU;
                    ID_EX_RegWrite <=  1;
                end 
                ADDI,SUBI,SLTI:begin 
                    ID_EX_TYPE <=  RM_ALU;
                    ID_EX_RegWrite <=  1;
                end
                LW: begin
                    ID_EX_TYPE <=  LOAD;
                    ID_EX_RegWrite <=  1;
                end
                SW: begin
                    ID_EX_TYPE <=  STORE;
                    ID_EX_RegWrite <=  0;
                end
                BEQZ,BNEQZ:begin 
                    ID_EX_TYPE <=  BRANCH;
                    ID_EX_RegWrite <=  0;
                end
                HLT: begin
                    ID_EX_TYPE <=  HALT;
                    ID_EX_RegWrite <=  0;
                end

                default:begin
                    ID_EX_TYPE <=  NOP;
                    ID_EX_RegWrite <=  0;
                end 
            endcase

            if(LOAD_HAZARD || BRANCH_FLUSH) begin
                ID_EX_TYPE<=  NOP;
                ID_EX_RegWrite<=  0;
                ID_EX_IR<=0;
                ID_EX_PRED <=0;
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
        if(EX_MEM_RegWrite && EX_MEM_RD==ID_EX_IR[25:21] && ID_EX_IR[25:21]!=0 )begin
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
        if(reset) begin
            EX_MEM_TYPE     <= NOP;
            EX_MEM_IR       <= 32'd0;
            EX_MEM_RegWrite <= 0;
            EX_MEM_PC <= '0;
        end 
        else if(!HALTED) begin
            EX_MEM_IR <= ID_EX_IR;
            EX_MEM_TYPE <= BRANCH_FLUSH? NOP : ID_EX_TYPE;//PIPELINE FLUSH
            EX_MEM_RegWrite <=  ID_EX_RegWrite;
            EX_MEM_PC <= ID_EX_NPC -1 ;
            
            
            case(ID_EX_TYPE)
                RR_ALU:begin
                    case (ID_EX_IR[31:26])
                        ADD: EX_MEM_ALUOUT <=  forwardA + forwardB;
                        SUB: EX_MEM_ALUOUT <=  forwardA - forwardB;
                        AND: EX_MEM_ALUOUT <=  forwardA & forwardB;
                        OR: EX_MEM_ALUOUT <=  forwardA | forwardB;
                        MUL: EX_MEM_ALUOUT <=  forwardA * forwardB;
                        SLT: EX_MEM_ALUOUT <=  forwardA < forwardB;//compare op
                        default: EX_MEM_ALUOUT <=  32'hxxxxxxxx;
                    endcase
                end
                RM_ALU: begin
                    case (ID_EX_IR[31:26])
                        ADDI: EX_MEM_ALUOUT <=  forwardA + ID_EX_IMM;
                        SUBI: EX_MEM_ALUOUT <=  forwardA - ID_EX_IMM;
                        SLTI: EX_MEM_ALUOUT <=  forwardA < ID_EX_IMM;
                        default: EX_MEM_ALUOUT <=  32'hxxxxxxxx;
                    endcase
                end
                LOAD,STORE:begin
                    EX_MEM_ALUOUT <=  forwardA + ID_EX_IMM;
                    EX_MEM_B <=  forwardB;// needed for store operation
                end
                BRANCH:begin
                    EX_MEM_COND <=  (forwardA == 0);
                    EX_MEM_ALUOUT <= BRANCH_FLUSH? EX_MEM_ALUOUT:ID_EX_NPC+ID_EX_IMM;
                end
            endcase
        end
    end


    always @(posedge clk1) begin // MEM STAGE
        if(reset) begin
            MEM_WB_TYPE     <= NOP;
            MEM_WB_IR       <= 32'd0;
            MEM_WB_RegWrite <= 0;
        end
        else if(!HALTED) begin
            MEM_WB_IR <=  EX_MEM_IR;
            MEM_WB_TYPE <=  EX_MEM_TYPE;
            MEM_WB_RegWrite <= BRANCH_FLUSH? 0: EX_MEM_RegWrite; 
            case (EX_MEM_TYPE)
                RR_ALU,RM_ALU:begin
                    MEM_WB_ALUOUT <=  EX_MEM_ALUOUT;
                end 
                LOAD:begin
                    MEM_WB_LMD <=  MEM[EX_MEM_ALUOUT];//LMD -> LOAD MEMORY DATA
                end
                STORE:begin
                    if(TAKEN_BRANCH == 0)
                        MEM[EX_MEM_ALUOUT] <=  EX_MEM_B;
                end
                default: ;
            endcase
        end
    end


    always @(posedge clk1) begin //WB STAGE
        if(reset) begin
            HALTED <= 0;
        end
        else if(!HALTED )begin
            case (MEM_WB_TYPE)
                RR_ALU: REG[MEM_WB_IR[15:11]] <= (MEM_WB_IR[15:11]==5'd0) ? 0: MEM_WB_ALUOUT;
                RM_ALU: REG[MEM_WB_IR[20:16]] <= (MEM_WB_IR[20:16]==5'd0) ? 0:MEM_WB_ALUOUT;
                LOAD: REG[MEM_WB_IR[20:16]]   <= (MEM_WB_IR[20:16]==5'd0) ? 0:MEM_WB_LMD;
                HALT: HALTED <=  1;
                default:; 
            endcase
        end
    end 
endmodule