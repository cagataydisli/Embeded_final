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
## System Architecture (Dual PicoBlaze - Project 5)

As per "Project 5 - Cryptology1.1" requirements, the system now uses two PicoBlaze emulator cores:

1.  **Pico1 (Data Reader):**
    *   Reads 8-byte data (Plaintext/Ciphertext) from `Mem1` (Address 0..7).
    *   Writes data into the `FIFO Buffer`.
    
2.  **FIFO Buffer:**
    *   Acts as a bridge between Pico1 and Pico2.
    *   Depth: 16, Width: 8-bit.

3.  **Pico2 (Controller & Key Manager):**
    *   Reads 128-bit Key from `Mem2` (Address 0..15).
    *   Reads 8-byte Data from `FIFO Buffer`.
    *   sends Key and Data to `xtea_core.sv`.
    *   Triggers Encryption/Decryption.
    *   Reads result from XTEA core.
    *   Writes result to `Mem3`.

### File Descriptions (New Architecture)
*   **`system_top_dual_pico.sv`**: Top-level module connecting all components.
*   **`pico1_emulator.sv`**: Implements Pico1 logic (Mem1 -> FIFO).
*   **`pico2_emulator_v13.sv`**: Implements Pico2 logic (Mem2/FIFO -> XTEA -> Mem3).
*   **`fifo_buffer.sv`**: Synchronization buffer.
*   **`tb_system_dual_pico.sv`**: Testbench for the dual-core system.

### Simulation (Dual Core)
1. Add `system_top_dual_pico.sv`, `pico1_emulator.sv`, `pico2_emulator_v13.sv`, `fifo_buffer.sv`, `xtea_core.sv`, `single_port_ram.sv` as Design Sources.
2. Add `tb_system_dual_pico.sv` as Simulation Source.
3. Run Simulation.

**Note:** The system is configured for **Decryption** by default in `pico2_emulator_v13.sv` and `tb_system_dual_pico.sv`.

## Switching Between Encryption and Decryption (Dual Core)

To switch modes in the Dual Core system:

1. **Set Mode (`pico2_emulator_v13.sv`)**:
   Inside `S_START_ENC` (approx line 200):
   - **Encrypt:** `out_port <= 8'h01;`
   - **Decrypt:** `out_port <= 8'h03;`

2. **Select Input Data (`system_top_dual_pico.sv`)**:
   Change `ram_mem1` initialization:
   - **Encrypt:** `.INIT_TYPE(1)`
   - **Decrypt:** `.INIT_TYPE(3)`

3. **Update Testbench (`tb_system_dual_pico.sv`)**:
   Update `$display` messages relative to the mode.

## Legacy Files
*   `pico2_emulator_v12.sv` & `system_top_debug_v2.sv`: Previous single-core debug versions.

## Key Features
- Standard 32-round XTEA algorithm
- Proper Big Endian byte ordering for XTEA compatibility
- Single-cycle round computation using combinational logic
- Memory-mapped I/O for data transfer
- Verified against Python reference implementation

## License
This project is created for educational purposes as part of an embedded systems course.
