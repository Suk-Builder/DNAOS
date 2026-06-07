// ============================================================================
// DNAOS Quaternary Processor - Testbench
// ============================================================================
`timescale 1ns/1ps

module dnaos_quat_tb;

    reg  clk;
    reg  rst_n;
    reg  [7:0] sw;
    wire [6:0] seg;
    wire [3:0] led;
    wire [3:0] spike_out;

    dnaos_quat dut (
        .clk(clk),
        .rst_n(rst_n),
        .sw(sw),
        .seg(seg),
        .led(led),
        .spike_out(spike_out)
    );

    // Clock: 10ns period
    always #5 clk = ~clk;

    // Base names for display
    task print_base;
        input [1:0] b;
        begin
            case (b)
                2'b00: $write("A");
                2'b01: $write("T");
                2'b10: $write("C");
                2'b11: $write("G");
            endcase
        end
    endtask

    task print_quat_byte;
        input [7:0] val;
        begin
            print_base(val[7:6]);
            print_base(val[5:4]);
            print_base(val[3:2]);
            print_base(val[1:0]);
        end
    endtask

    integer i;

    initial begin
        $dumpfile("dnaos_quat.vcd");
        $dumpvars(0, dnaos_quat_tb);

        $display("============================================================");
        $display(" DNAOS Quaternary Processor - Testbench");
        $display("============================================================");

        // Initialize
        clk   = 0;
        rst_n = 0;
        sw    = 8'h00;

        // Reset
        #20 rst_n = 1;
        #10;

        // ============================================================
        // Test 1: Quaternary AND
        // ============================================================
        $display("\n--- Test 1: Quaternary AND ---");
        sw = 8'b00_000100;  // OP_AND, load RA
        #10;
        sw = 8'b00_001000;  // OP_AND, load RB
        #10;
        sw = 8'b00_000000;  // OP_AND, execute
        #10;
        $write("  RA = "); print_quat_byte(dut.qreg[0]); $display("");
        $write("  RB = "); print_quat_byte(dut.qreg[1]); $display("");
        $write("  RC = "); print_quat_byte(dut.qreg[2]); $display(" (AND result)");

        // ============================================================
        // Test 2: Quaternary OR
        // ============================================================
        $display("\n--- Test 2: Quaternary OR ---");
        sw = 8'b01_000000;  // OP_OR
        #10;
        $write("  RA = "); print_quat_byte(dut.qreg[0]); $display("");
        $write("  RB = "); print_quat_byte(dut.qreg[1]); $display("");
        $write("  RC = "); print_quat_byte(dut.qreg[2]); $display(" (OR result)");

        // ============================================================
        // Test 3: Quaternary NOT
        // ============================================================
        $display("\n--- Test 3: Quaternary NOT ---");
        sw = 8'b10_000000;  // OP_NOT
        #10;
        $write("  RA = "); print_quat_byte(dut.qreg[0]); $display("");
        $write("  RC = "); print_quat_byte(dut.qreg[2]); $display(" (NOT result)");
        $display("  Expected: A<->G, T<->C");

        // ============================================================
        // Test 4: Quaternary ADD
        // ============================================================
        $display("\n--- Test 4: Quaternary ADD ---");
        // Set RA = ATCG (00 01 10 11 = 0x1B)
        dut.qreg[0] = 8'h1B;  // ATCG
        // Set RB = GCTA (11 10 01 00 = 0xE4)
        dut.qreg[1] = 8'hE4;  // GCTA
        sw = 8'b11_000000;  // OP_ADD
        #10;
        $write("  RA = "); print_quat_byte(dut.qreg[0]); $display(" (ATCG)");
        $write("  RB = "); print_quat_byte(dut.qreg[1]); $display(" (GCTA)");
        $write("  RC = "); print_quat_byte(dut.qreg[2]); $display(" (ADD result)");
        $display("  Carry = %b", dut.carry_out);

        // ============================================================
        // Test 5: Spiking Neuron
        // ============================================================
        $display("\n--- Test 5: Spiking Neuron ---");
        $display("  Running 200 cycles to observe spiking behavior...");
        sw = 8'b11_000000;  // Keep adding
        for (i = 0; i < 200; i = i + 1) begin
            #10;
            if (dut.spike) begin
                $display("  SPIKE at cycle %0d! membrane=%0d ATP=%0d", 
                         i, dut.membrane_pot, dut.atp_counter);
            end
        end

        // ============================================================
        // Test 6: ATP Exhaustion
        // ============================================================
        $display("\n--- Test 6: ATP Exhaustion ---");
        $display("  ATP remaining: %0d", dut.atp_counter);
        $display("  ATP exhausted: %0d", dut.atp_exhausted);

        $display("\n============================================================");
        $display(" All tests complete");
        $display("============================================================");

        #100;
        $finish;
    end

endmodule
