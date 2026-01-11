# XTEA Encryption/Decryption System - FPGA Implementation

## Overview
This project implements a complete XTEA (eXtended Tiny Encryption Algorithm) encryption/decryption system on FPGA. The system uses a PicoBlaze-based controller to manage data flow between memory and the XTEA core.

## Architecture

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   Memory 1  │     │   Memory 2  │     │   Memory 3  │
│ (Plaintext) │     │    (Key)    │     │  (Result)   │
└──────┬──────┘     └──────┬──────┘     └──────┬──────┘
       │                   │                   │
       └───────────┬───────┴───────────────────┘
                   │
           ┌───────▼───────┐
           │  Pico2        │
           │  Emulator     │
           │  (Controller) │
           └───────┬───────┘
                   │
           ┌───────▼───────┐
           │   XTEA Core   │
           │  (32 rounds)  │
           └───────────────┘
```

## Files

### Core Modules
- **`xtea_core.sv`** - XTEA encryption/decryption core with fixed algorithm and endianness handling
- **`pico2_emulator_v12.sv`** - PicoBlaze-compatible controller for memory and XTEA management
- **`system_top_debug_v2.sv`** - Top-level system integration module
- **`single_port_ram.sv`** - Parameterized RAM module with initialization options

### Testbenches
- **`tb_system_debug_v2.sv`** - Main system testbench

### PicoBlaze Components
- **`kcpsm6.vhd`** - PicoBlaze 6 processor core
- **`pico1_rom.vhd`** / **`pico2_rom.vhd`** - Program ROM for PicoBlaze
- **`pico1_code.psm`** / **`pico2_code.psm`** - PicoBlaze assembly source

### Supporting Modules
- **`fifo_buffer.sv`** - FIFO buffer implementation
- **`MUX.sv`** - Multiplexer module
- **`pico1_emulator.sv`** - Alternative PicoBlaze emulator

## Test Vector

| Parameter | Value |
|-----------|-------|
| Plaintext | `11 22 33 44 55 66 77 88` |
| Key | `00 01 02 03 04 05 06 07 08 09 0A 0B 0C 0D 0E 0F` |
| Ciphertext | `C3 B9 0E B5 22 56 FE 61` |
| Rounds | 32 (standard XTEA) |

## Running Simulation

### Using Vivado (Command Line)
```tcl
xvlog -sv system_top_debug_v2.sv pico2_emulator_v12.sv xtea_core.sv single_port_ram.sv tb_system_debug_v2.sv
xelab -debug typical tb_system_debug_v2 -s sim_test
xsim sim_test -runall
```

### Expected Output (Encryption)
```
--- FINAL RESULTS (Mem3) ---
Addr 0: c3
Addr 1: b9
Addr 2: 0e
Addr 3: b5
Addr 4: 22
Addr 5: 56
Addr 6: fe
Addr 7: 61
```

### Expected Output (Decryption)
```
--- FINAL RESULTS (Mem3) ---
Addr 0: 11
Addr 1: 22
Addr 2: 33
Addr 3: 44
Addr 4: 55
Addr 5: 66
Addr 6: 77
Addr 7: 88
```

## Switching Between Encryption and Decryption

To switch between modes, you need to modify 3 files:

1. **Set Mode (`pico2_emulator_v12.sv`)**:
   Inside the `S_START_ENC` state (approx. line 200), change the `out_port` value:
   - **Encrypt:** `out_port <= 8'h01;` // Bit 1=0
   - **Decrypt:** `out_port <= 8'h03;` // Bit 1=1

2. **Select Input Data (`system_top_debug_v2.sv`)**:
   Change the `INIT_TYPE` parameter for `ram_mem1` (approx. line 95):
   - **Encrypt (Load Plaintext):** `.INIT_TYPE(1)`
   - **Decrypt (Load Ciphertext):** `.INIT_TYPE(3)`

3. **Update Testbench (`tb_system_debug_v2.sv`)**:
   Update the `$display` messages to reflect the current test mode (Encryption vs Decryption).

## Key Features
- Standard 32-round XTEA algorithm
- Proper Big Endian byte ordering for XTEA compatibility
- Single-cycle round computation using combinational logic
- Memory-mapped I/O for data transfer
- Verified against Python reference implementation

## License
This project is created for educational purposes as part of an embedded systems course.
