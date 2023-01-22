# The PUCRS-RV Processor Core

### Description 

PUCRS-RV is a simple processor core that implements the RISC-V 32-bit integer instruction set architecture (ISA), i.e., the RV32I ISA defined by the RISC-V specifications, available at the [RISC-V Organization](https://riscv.org/). PUCRS-RV was written in the SystemVerilog Hardware Description Language (HDL).

The processor core was designed at the Hardware Development Support Group (GAPH) of the School of Technology, PUCRS, Brazil.

The design takes the form of a synchronous, 5-stage pipeline, operating at the rising edge of clock. The processor core pipeline stages are summarized as:

- Fetch: Contains the Program Counter (PC) register and logic and has access to an external Instruction Memory.
- Decoder: Decodes the instruction, retrieving its type, binary format, function, and operands information from the binary code.
- Operand Fetch: Retrieves operands from the Register Bank (if any) and performs data conflict detection (hazards). When data conflict(s) is(are) detected, this stage inserts bubbles until the hazard is eliminated.
- Execute: Performs the operation dictated by the instruction code on retrieved operands. It comprises six (6) execution units. Each unit is responsible for a given operation, e.g., shifts are executed in the Shift Unit, and memory operations are conducted by the Memory Unit.
- Retire: Ends the execution of instructions (an action called here "instruction retirement"). This can imply a write-back in the Register Bank, performing a write operation in the data memory, or branching to another part of the program code, among other possible actions.

<img src="RISCV_block.png" alt="block diagram">
> PUCRS-RV BLOCK DIAGRAM.


## RTL code and Pipeline Organization Details

This processor organization was based on the Asynchronous RISC-V (ARV) high level functional model. This model was developed as a specification for an asynchronous version of RISC-V, originally written in the Google GO language. ARV is available in the [ARV Go High-level Functional Model](https://github.com/marlls1989/arv) repository.

The PUCRS-RV  defines three main loops that control the processor flow.

- First Stage: 
This stage is implemented by the [Fetch Unit](https://github.com/Willian-Nunes/pucrs-rv/blob/master/rtl/fetch.sv). It contains the Program Counter (PC) logic. The value contained in the PC is used to address the instruction memory; at each clock cycle it is updated, either to the following instruction address (PC+4, since the memory is byte addressed but instructions take 4 bytes), or to a branch address. The PC can also keep its value unchanged in case there is a need for inserting one or more bubbles, due to the detection of data hazard(s). The adopted jump/branch prediction policy is "never taken".
Each instruction that leaves the first stage is associated to a Tag created in this stage and that will track the instruction along the pipeline. The instruction Tag controls the flow of each instruction. Every time a jump/branch occurs the tag will be increased meaning that newly fetched instructions now belong to a new flow, and that the instructions possibly fetched before taking the branch are to be discarded, and the effects of their execution are to be eliminated.

- Second Stage:
It is materialized as the [Decoder Unit](https://github.com/Willian-Nunes/pucrs-rv/blob/master/rtl/decoder.sv). This stage is responsible for the generation and scheduling of instruction control signals, based in the instruction binary code fetched in the previous stage. A first information decoded by this unit is the instruction definition (e.g., ADDI, BNE). Based on this information the stage generates a signal to select the Execute Unit responsible for the specific operation. This stage also decodes the instruction type (e.g., register, immediate, or branch).

- Third Stage: 
This is the Operand Fetch Stage and is implemented by the [Operand Fetch Unit](https://github.com/Willian-Nunes/pucrs-rv/blob/master/rtl/operandFetch.sv). This Unit is responsible for sending read address(es) to the Register Bank, which are extracted from the instruction binary code. The binary code is also used for immediate operand processing, based on the detected instruction type. This instruction type also determines the operands that will be sent to the Fourth Stage. This Unit implements data hazard detection, by tracking registers with pending writes, which are part of the Register Locking Queue (RLQ). A new entry is added to the RLQ whenever an instruction that is expected to write a register in the Register Bank leaves the Third stage. The inserted value is the identifier of the destination register (regD) of the instruction at hand. Identifier are encoded in 32-bit one-hot format (each bit of the signal represents a specific register of the Register Bank). This queue has the length of the remaining stages in the pipeline (2 in the case of this organization). The queue uses a bitwise OR operation that generates a mask to indicate the locked registers. A data hazard is detected when the instruction in the Fetch Stage has a register operand that must be read from one of the locked registers, what causes the processor control to issue a signal called "bubble", indicating the need to stall the pipeline, until the data conflict is solved. This stage also looks for memory data hazards, caused by situations where a read is performed right after a write to memory. For this purpose, the bit zero of the regD one-hot signal is employed, since this bit is never used to signal a data conflict, since The zeroth register in the Register Bank is the 0 constant and is thus a read only register. The RLQ is accordingly used to generate the register bank write-enable signal. The head position of the RLQ holds the index of the register that must receive the write-back enable signal. This signal is processed with a bitwise AND operation with the write enable received from the Fifth Stage (The Retire Unit).

- Fourth Stage:
This stage is the Execute Stage, implemented by the [Execute Unit](https://github.com/Willian-Nunes/pucrs-rv/blob/master/rtl/execute.sv). The stage instantiates the six execution units (adder, bypass, branch, logic, memory and shift). Each of these units receives data to process only when the instruction arriving at the state requires its associated operation. For example, the Adder Unit only receives the operands when the instruction is one of ADD(I), SUB(I) and SLT(U). For every other instruction this unit inputs are assigned to the high impedance state ('Z). This behavior is implemented by a module (the dispatcher) that only dispatches the instruction to the designed Execution Unit and keeps all other units with inputs at the ''Z' state. Execution Units, after receiving its operands, perform the computation and output its result. At the end of the stage there is a demultiplexer that forwards the appropriate result to the next stage.

- Fifth Stage:
This is the last pipeline stage, which is responsible for the retirement of instructions. This stage is implemented by the [Retire Unit](https://github.com/Willian-Nunes/pucrs-rv/blob/master/rtl/retire.sv). Instructions entering this stage first pass by a flow validation, by comparing the instruction Tag and the current Retire Tag. If these are equal it means that the instruction is valid (belongs to the valid execution flow). Otherwise, it means that after the instruction was fetched a jump/branch occurred and the execution flow was changed, meaning this instruction must be discarded. Every time a jump/branch finishes execution the internal Tag of the pipeline is incremented and in the next cycle the Tag of the First Stage will also be increased to match the newly defined execution flow.
The Retire Unit is responsible for committing results of each instruction, by producing actions that depend on the signals issued by it. There are 3 possible sets of actions: 
1) Write-back operation - performed by sending a "write enable" signal and the "data" to be written to the Register Bank.
2) Jump/Branch operation - performed by sending a "jump" signal and a jump/branch address to the First Stage.
3) Memory Write operation - performed by sending the "data", "write enable" and "write address" signals to the external Data Memory.

### The three PUCRS-RV control loops

The PUCRS-RV organization implements three main control loops that organizae the processor execution flow.

1) The first loop is the outermost loop that comprises the entire processor. It starts in the first stage and goes through until the Fifth Stage where it is closed by the control signals sent back to the First Stage. This loop is implemented by the Tag system that manages the retirement of instructions. It is updated every time a jump/branch occurs. It is closed at the Retire Unit.

2) The second loop includes the Third, Fourth and Fifth Stages. This is called the Datapath Loop and implements the data write-back in the Register Bank. This loop is also closed at the Retire Unit.

3) The third loop comprises the data hazard conflict mechanism that is implemented by the RLQ.


## Requirements

To perform code compilation the RISC-V toolchain is required. The toolchain includes a compiler that performs the compilation of the applications source code written in the C language. This compiler generates a binary file, and this file is the entry of the processor simulation. Applications are in the [app/](https://github.com/Willian-Nunes/pucrs-rv/tree/master/app) folder.

The installation of the toolchain is only needed if you want to compile new applications or change parameters in the furnished examples. Applications are already compiled, and their binary codes are in the [bin/](https://github.com/Willian-Nunes/pucrs-rv/tree/master/bin) folder.

To install the RISC-V toolchain, a guide and a script are provided inside the [tools/riscv-toolchain](https://github.com/Willian-Nunes/pucrs-rv/tree/master/tools/riscv-toolchain) folder.

To perform simulation, it is necessary to have access to a SystemVerilog simulator (e.g. ISE, MODELSIM). To perform the simulation of a specific application, it is required to edit the binary input file in the [ram.sv](https://github.com/Willian-Nunes/pucrs-rv/blob/master/sim/ram.sv) file. The line to be edited is in the "initial" block, in line 54. The testbench and the memory (RAM) behavioral implementation are in the [/sim](https://github.com/Willian-Nunes/pucrs-rv/blob/master/sim/) folder. Once the desired application is selected and the testbench is correctly pointing to it, is is possible to simulate application using the chosen simulator. 

## Applications
This repository provides some applications that were used to validate the processor organization functionality. Source codes of the applications are located the [app/](https://github.com/Willian-Nunes/pucrs-rv/tree/master/app) folder. All of these can be built using their specific Makefile, which will generate its associated binary output file. It is recommended that binary files be moved to the [bin/](https://github.com/Willian-Nunes/pucrs-rv/tree/master/bin) folder using a copy command (cp in Linux OS). Inside the [bin/](https://github.com/Willian-Nunes/pucrs-rv/tree/master/bin) folder all given applications are already compiled and ready to be simulated.

### Coremark
The [Coremark](https://github.com/Willian-Nunes/pucrs-rv/tree/master/app/coremark) is a standard benchmark set of applications developed by The EDN Embedded Microprocessor Benchmark Consortium ([EEMBC](https://www.eembc.org/)). It was ported to run in PUCRS-RV and can be compiled by simply running the command "make" inside the Coremark folder mentioned above. This generates a binary called "coremark.bin". In the PUCRS-RV, since there is only one thread, Coremark runs for just one iteration.

### RISCV Tests
The [riscv-tests](https://github.com/marlls1989/riscv-tests/tree/159079a82ecc332ce32e5db84aff9f814dc7ec12) are the "Berkeley Suite" developed to validate RISC-V implementations. It tests all the instructions by running comparisons between the expected results and those generated by the design under verification (DUV).

### Sample Codes
The [samplecode](https://github.com/Willian-Nunes/pucrs-rv/tree/master/app/samplecode) folder contains some simple applications that were used to test selected functionalities of the PUCRS-RV processor core. These applications use the BareOS, a simple Operating System. All applications are compiled simply running the "make" command. To add more applications, it is only necessary to add the C source code of one or more applications in the folder and then edit the [Makefile](https://github.com/Willian-Nunes/pucrs-rv/blob/master/app/samplecode/Makefile) so that it also compiles the new application. To achieve that, just edit line 13 of the Makefile, by adding the name of the new application(s) on the "PROGNAME" variable, that defines the list of applications that will be "made".

The currently provided applications are:
1. Dummy - Tests the processor core halt function.
2. Hello World - Tests the "stdout" of the processor, by printing "Hello World".
3. Hanoi Tower - Implements a Hanoi Tower solving algorithm.
