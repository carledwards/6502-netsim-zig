# 6502-netsim-zig

A Zig implementation of a 6502 processor simulator, derived from the Visual6502 project. This simulator provides a detailed emulation of the MOS Technology 6502 processor, including transistor-level simulation capabilities.

## Project Structure

```
.
├── src/          # Source code directory
│   ├── cpu.zig      # CPU implementation
│   ├── memory.zig   # Memory management
│   └── motherboard.zig # Motherboard simulation
├── data/         # Simulation data files
│   ├── segdefs.txt    # Segment definitions from Visual6502
│   └── transdefs.txt  # Transistor definitions from Visual6502
```

## Building and Running

### Prerequisites

- Zig 0.11.0 or later
- Git

### Getting Started

1. Clone the repository:
   ```bash
   git clone https://github.com/carledwards/6502-netsim-zig.git
   cd 6502-netsim-zig
   ```

2. Build the project:
   ```bash
   zig build
   ```

3. Run the simulator:
   ```bash
   zig build run
   ```

## Performance Analysis

The simulator can be built with different optimization levels to analyze and improve performance:

```bash
# Debug build (default)
zig build -Doptimize=Debug

# Release build with safety checks
zig build -Doptimize=ReleaseSafe

# Release build with minimal safety checks
zig build -Doptimize=ReleaseFast

# Release build with no safety checks
zig build -Doptimize=ReleaseSmall
```

You can also use Zig's built-in CPU profiling capabilities:

```bash
zig build run -Drelease-fast=true -Dtrace=cpu
```

## Attribution

This project is based on the work from [Visual6502](https://github.com/trebonian/visual6502) (www.visual6502.org), originally created by Greg James, Brian Silverman, and Barry Silverman. The original work was licensed under [Creative Commons Attribution-NonCommercial-ShareAlike 3.0](http://creativecommons.org/licenses/by-nc-sa/3.0/).

The segment and transistor definition files used in this project are derived from the Visual6502 project and are essential components for the transistor-level simulation of the 6502 processor. These files contain the detailed mapping of the processor's internal structure and connections.

## Data Files

- `data/segdefs.txt`: Contains segment definitions that describe the various components and pathways within the 6502 processor
- `data/transdefs.txt`: Contains transistor definitions that specify the switching elements and their connections within the processor

## Memory Management

The simulator uses Zig's memory allocation patterns for safe and efficient memory management:
- Arena allocators for long-lived allocations
- General Purpose Allocator for the main program
- Proper cleanup through Zig's defer statements and explicit deinit calls

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
