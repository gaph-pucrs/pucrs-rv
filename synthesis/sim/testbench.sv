/*!\file testbench.sv
 * PUCRS-RV VERSION - 1.0 - Public Release
 *
 * Distribution:  December 2021
 *
 * Willian Nunes   <willian.nunes@edu.pucrs.br>
 * Marcos Sartori  <marcos.sartori@acad.pucrs.br>
 * Ney calazans    <ney.calazans@pucrs.br>
 *
 * Research group: GAPH-PUCRS  <>
 *
 * \brief
 * Testbench for pucrs-rv simulation.
 *
 * \detailed
 * Testbench for pucrs-rv simulation.
 */

`timescale 1ns/1ps

`include "/home/williannunes/pucrs-rv/rtl/pkg.sv"
`include "/home/williannunes/pucrs-rv/sim/ram.sv"
`include "../logical/logical.v"
`include "/soft64/design-kits/stm/65nm-cmos065_536/CORE65GPSVT_5.1/behaviour/verilog/CORE65GPSVT.v"
`include "/soft64/design-kits/stm/65nm-cmos065_536/CLOCK65GPSVT_3.1/behaviour/verilog/CLOCK65GPSVT.v"
import my_pkg::*;

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////// CPU TESTBENCH IMPLEMENTATION //////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
module PUCRS_RV_tb ();

logic         clk, rstCPU;
logic [31:0]  i_address, instruction;
logic         read;
logic [31:0]  read_address, data_read, write_address, data_write;
logic [3:0]   write;
byte          char;
logic [31:0]  Rd_data, Wr_address, Wr_data;


////////////////////////////////////////////////////// Clock generator //////////////////////////////////////////////////////////////////////////////
  always begin
    #2.5 clk = 1;
    #2.5 clk = 0;
  end

////////////////////////////////////////////////////// RAM INSTANTIATION ///////////////////////////////////////////////////////////////////////
	RAM_mem #('0) RAM_MEM(.clock(clk), .rst(rstCPU), .write_enable(write), .read_enable(read), .i_address(i_address), 
            .read_address(read_address), .write_address(Wr_address), .Wr_data(Wr_data), .data_read(Rd_data), .instruction(instruction));

// data memory signals --------------------------------------------------------
  always_comb
    if(write!=0) begin
        Wr_address <= write_address;                            // Wr_address - write_address
        Wr_data <= data_write;                                  // Wr_data - data_write
    end else begin 
        Wr_data <= '0;
        Wr_address <= '0;
    end
/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
  always_comb
    if(read==1) begin
        if(read_address==32'h80006000)
            data_read <= $time/1000;
        else 
            data_read <= Rd_data; 
    end else
        data_read <= 'Z; 		                                // data_cpu

/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////// Memory Mapped regs ///////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
  always @(posedge clk) begin
    if((write_address == 32'h80004000 | write_address == 32'h80001000) & write!=0) begin
        char <= data_write[7:0];
        $write("%c",char);
    end

    if(write_address==32'h80000000) begin
        $display("# %t END OF SIMULATION",$time);
        $finish;
    end
  end

/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////// CPU INSTANTIATION ////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    PUCRS_RV dut (.clk(clk), .reset(rstCPU), .instruction(instruction), .i_address(i_address), .read(read), .read_address(read_address),
             .DATA_in(data_read), .DATA_out(data_write), .write_address(write_address), .write(write));

/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////// RESET CPU ////////////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //always #1000000000
    //    $display("%d elapsed", $time);

    initial begin
        $sdf_annotate("../logical/logical.sdf", dut, , , "maximum");
        
        rstCPU = 0;                                         // RESET for CPU initialization
        #1000 rstCPU = 1;                                     // Hold state for 30 ns
    end
endmodule