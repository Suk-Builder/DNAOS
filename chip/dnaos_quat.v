// ============================================================================
// DNAOS Quaternary Processor - Tiny Tapeout Verification Chip
// ============================================================================
// Architecture: ATCG-native 4-level logic (quaternary)
// Technology: SkyWater 130nm CMOS (simulating 4-level with 2-bit pairs)
// Design: 4-valued register file + quaternary ALU + spiking neuron
// ============================================================================
// 
// Quaternary encoding:
//   A = 00 = 0.0V  (Adenine)
//   T = 01 = 1.0V  (Thymine)  
//   C = 10 = 2.0V  (Cytosine)
//   G = 11 = 3.0V  (Guanine)
//
// In CMOS we represent each quaternary digit as 2 binary bits.
// A real memristor implementation would use true multi-level storage.
// ============================================================================

module dnaos_quat (
    input  wire clk,
    input  wire rst_n,
    input  wire [7:0] sw,       // 8 switches for input
    output wire [6:0] seg,      // 7-segment display
    output wire [3:0] led,      // 4 LEDs (ATCG output)
    output wire [3:0] spike_out // Spike output for neuron
);

    // ========================================================================
    // Quaternary types (2-bit pairs)
    // ========================================================================
    // Each "base" is 2 bits: 00=A, 01=T, 10=C, 11=G
    // A quaternary byte = 4 bases = 8 bits
    
    wire [1:0] base_a = 2'b00;  // Adenine
    wire [1:0] base_t = 2'b01;  // Thymine
    wire [1:0] base_c = 2'b10;  // Cytosine
    wire [1:0] base_g = 2'b11;  // Guanine

    // ========================================================================
    // Quaternary Register File (4 registers x 4 bases = 4 bytes)
    // ========================================================================
    reg [7:0] qreg [0:3];  // 4 quaternary registers, each holds 4 bases
    
    // Register addresses
    localparam RA = 0;  // Register A (working)
    localparam RB = 1;  // Register B (operand)
    localparam RC = 2;  // Register C (result)
    localparam RD = 3;  // Register D (ATP counter)

    // ========================================================================
    // Quaternary ALU Operations
    // ========================================================================
    wire [1:0] op = sw[7:6];  // Operation select from switches
    
    localparam OP_AND  = 2'b00;  // Quaternary AND (min per base)
    localparam OP_OR   = 2'b01;  // Quaternary OR (max per base)
    localparam OP_NOT  = 2'b10;  // Quaternary NOT (complement per base)
    localparam OP_ADD  = 2'b11;  // Quaternary ADD (with carry)

    // Per-base quaternary AND (minimum)
    function [1:0] quat_min;
        input [1:0] a, b;
        begin
            if (a < b) quat_min = a;
            else       quat_min = b;
        end
    endfunction

    // Per-base quaternary OR (maximum)
    function [1:0] quat_max;
        input [1:0] a, b;
        begin
            if (a > b) quat_max = a;
            else       quat_max = b;
        end
    endfunction

    // Per-base quaternary NOT (complement: A<->G, T<->C)
    function [1:0] quat_not;
        input [1:0] a;
        begin
            case (a)
                2'b00: quat_not = 2'b11;  // A -> G
                2'b01: quat_not = 2'b10;  // T -> C
                2'b10: quat_not = 2'b01;  // C -> T
                2'b11: quat_not = 2'b00;  // G -> A
                default: quat_not = 2'b00;
            endcase
        end
    endfunction

    // Per-base quaternary ADD with carry
    // Sum = (a + b + carry_in) % 4
    // Carry_out = (a + b + carry_in) / 4
    function [2:0] quat_add;
        input [1:0] a, b;
        input cin;
        reg [2:0] sum;
        begin
            sum = {1'b0, a} + {1'b0, b} + {2'b0, cin};
            quat_add = sum;  // {carry, sum[1:0]}
        end
    endfunction

    // ========================================================================
    // ALU execution
    // ========================================================================
    reg [7:0] alu_result;
    reg [3:0] carry_out;
    
    always @(*) begin
        carry_out = 4'b0;
        case (op)
            OP_AND: begin
                alu_result[1:0] = quat_min(qreg[RA][1:0], qreg[RB][1:0]);
                alu_result[3:2] = quat_min(qreg[RA][3:2], qreg[RB][3:2]);
                alu_result[5:4] = quat_min(qreg[RA][5:4], qreg[RB][5:4]);
                alu_result[7:6] = quat_min(qreg[RA][7:6], qreg[RB][7:6]);
            end
            OP_OR: begin
                alu_result[1:0] = quat_max(qreg[RA][1:0], qreg[RB][1:0]);
                alu_result[3:2] = quat_max(qreg[RA][3:2], qreg[RB][3:2]);
                alu_result[5:4] = quat_max(qreg[RA][5:4], qreg[RB][5:4]);
                alu_result[7:6] = quat_max(qreg[RA][7:6], qreg[RB][7:6]);
            end
            OP_NOT: begin
                alu_result[1:0] = quat_not(qreg[RA][1:0]);
                alu_result[3:2] = quat_not(qreg[RA][3:2]);
                alu_result[5:4] = quat_not(qreg[RA][5:4]);
                alu_result[7:6] = quat_not(qreg[RA][7:6]);
            end
            OP_ADD: begin
                {carry_out[0], alu_result[1:0]} = quat_add(qreg[RA][1:0], qreg[RB][1:0], 1'b0);
                {carry_out[1], alu_result[3:2]} = quat_add(qreg[RA][3:2], qreg[RB][3:2], carry_out[0]);
                {carry_out[2], alu_result[5:4]} = quat_add(qreg[RA][5:4], qreg[RB][5:4], carry_out[1]);
                {carry_out[3], alu_result[7:6]} = quat_add(qreg[RA][7:6], qreg[RB][7:6], carry_out[2]);
            end
        endcase
    end

    // ========================================================================
    // Spiking Neuron (Leaky Integrate-and-Fire)
    // ========================================================================
    // Membrane potential: 8-bit accumulator
    // Threshold: configurable via register RD
    // Leak: decrement each cycle
    // Spike: when potential >= threshold, fire and reset
    
    reg [7:0] membrane_pot;
    reg [7:0] threshold;
    reg       spike;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            membrane_pot <= 8'h00;
            threshold    <= 8'h40;  // Default threshold = 64
            spike        <= 1'b0;
        end else begin
            spike <= 1'b0;
            
            // Integrate: add input (from ALU result lower bits)
            membrane_pot <= membrane_pot + alu_result[3:0];
            
            // Leak: subtract 1 each cycle
            if (membrane_pot > 8'h01)
                membrane_pot <= membrane_pot - 8'h01;
            
            // Fire: if potential >= threshold
            if (membrane_pot >= threshold) begin
                spike <= 1'b1;
                membrane_pot <= 8'h00;  // Reset
            end
        end
    end

    // ========================================================================
    // ATP Metabolism Counter
    // ========================================================================
    reg [15:0] atp_counter;
    reg       atp_exhausted;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            atp_counter   <= 16'hFFFF;  // Start with 65535 ATP
            atp_exhausted <= 1'b0;
        end else begin
            if (!atp_exhausted && spike) begin
                atp_counter <= atp_counter - 16'h0001;
                if (atp_counter == 16'h0001)
                    atp_exhausted <= 1'b1;
            end
        end
    end

    // ========================================================================
    // Register write logic
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            qreg[RA] <= 8'h00;  // AAAA
            qreg[RB] <= 8'hFF;  // GGGG
            qreg[RC] <= 8'h00;
            qreg[RD] <= 8'h00;
        end else begin
            // Write ALU result to RC
            qreg[RC] <= alu_result;
            
            // Switch input: load RA from switches [5:0] + 2 zeros
            if (sw[5]) begin
                qreg[RA] <= {sw[4:0], 3'b000};
            end
            // Switch input: load RB from switches [5:0] + 2 zeros
            if (sw[4]) begin
                qreg[RB] <= {sw[3:0], 4'b0000};
            end
        end
    end

    // ========================================================================
    // 7-Segment Display Driver
    // Shows the current ALU result as a hex value
    // ========================================================================
    reg [6:0] seg_reg;
    
    always @(*) begin
        case (alu_result[3:0])
            4'h0: seg_reg = 7'b1000000;
            4'h1: seg_reg = 7'b1111001;
            4'h2: seg_reg = 7'b0100100;
            4'h3: seg_reg = 7'b0110000;
            4'h4: seg_reg = 7'b0011001;
            4'h5: seg_reg = 7'b0010010;
            4'h6: seg_reg = 7'b0000010;
            4'h7: seg_reg = 7'b1111000;
            4'h8: seg_reg = 7'b0000000;
            4'h9: seg_reg = 7'b0010000;
            4'hA: seg_reg = 7'b0001000;
            4'hB: seg_reg = 7'b0000011;
            4'hC: seg_reg = 7'b1000110;
            4'hD: seg_reg = 7'b0100001;
            4'hE: seg_reg = 7'b0000110;
            4'hF: seg_reg = 7'b0001110;
        endcase
    end

    // ========================================================================
    // Output assignments
    // ========================================================================
    assign seg       = seg_reg;
    assign led       = alu_result[7:4];  // Upper 4 bits = 2 bases
    assign spike_out = {3'b0, spike};     // Spike on bit 0

endmodule
