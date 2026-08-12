# MITgcm Docker Tools

Docker-based workflow for compiling and running MITgcm verification experiments on multiple architectures.

## Overview

This repository provides Docker tools that enable fast, reproducible compilation and execution of MITgcm verification experiments. The key innovation is a **compile-once, run-many workflow** that eliminates unnecessary recompilation when only input parameters change.

### Key Benefits

✅ **Multi-architecture** - ARM64 (Apple Silicon) and x86_64 (Intel/AMD)  
✅ **Fast compilation** - Parallel builds with `-j` flag (2-3 min with `-j 8`)  
✅ **No recompilation** - Change input parameters without recompiling (~30 sec per run)  
✅ **Persistent storage** - Binaries and outputs saved outside Docker  
✅ **Easy setup** - Symlinks into your existing MITgcm installation

### Performance

| Workflow | Time | Speedup |
|----------|------|---------|
| **Traditional** (recompile every time) | ~10 min | Baseline |
| **This tool** (compile once, run many) | ~3 min + 30 sec per run | **8-20x faster** |

## Prerequisites

- **Docker Desktop** installed and running
- **MITgcm source code** (git clone from mitgcm.org)
- **8+ GB RAM** allocated to Docker
- **8+ CPUs** allocated to Docker (for parallel compilation)
- **Supported architecture:** ARM64 or x86_64
- **MPI support:** Built-in (OpenMPI included for MPI experiments)

### Configure Docker Resources

1. Open Docker Desktop → Settings → Resources
2. Set:
   - **CPUs:** 8-12 (for `-j 8`)
   - **Memory:** 8-12 GB
   - **Disk:** 64+ GB

## Quick Start

### 1. Clone This Repository

```bash
git clone https://github.com/ifenty/MITgcm_verification_docker.git
cd MITgcm_verification_docker
```

### 2. Link to Your MITgcm Installation

```bash
./scripts/setup_links.sh /path/to/your/MITgcm/verification
```

The script automatically:
- Detects your system architecture (ARM64 or x86_64)
- Suggests the appropriate build options file from MITgcm's `tools/build_options/`
- Creates symlinks in your verification directory

**Supported architectures:**
- **ARM64:** Apple Silicon (M1/M2/M3/M4), ARM servers → `linux_arm64_gfortran`
- **x86_64:** Intel/AMD PCs and workstations → `linux_amd64_gfortran`

### 3. Build Docker Image

```bash
cd /path/to/your/MITgcm/verification
docker build -t mitgcm:latest --build-arg OPTFILE=<your_optfile> -f Dockerfile ../
```

**Examples:**
```bash
# For ARM64 (Apple Silicon)
docker build -t mitgcm:latest --build-arg OPTFILE=linux_arm64_gfortran -f Dockerfile ../

# For x86_64 (Intel/AMD)
docker build -t mitgcm:latest --build-arg OPTFILE=linux_amd64_gfortran -f Dockerfile ../
```

**Build time:** ~5 minutes  
**Image size:** ~2.5 GB  
**Includes:** gfortran, NetCDF, OpenMPI

### 4. Compile and Run

**Non-MPI experiments:**
```bash
# Compile
./experiment_compile.sh 1D_ocean_ice_column -j 8

# Run
./experiment_run_no_compile.sh 1D_ocean_ice_column

# Compare against reference results
./compare_results.sh 1D_ocean_ice_column

# View results
less 1D_ocean_ice_column/output_docker/output.txt
```

**MPI experiments:**
```bash
# Compile with MPI
./experiment_compile.sh tutorial_global_oce_latlon -mpi -j 8

# Run with 4 MPI processes
./experiment_run_no_compile.sh tutorial_global_oce_latlon input -mpi 4

# Compare against reference results
./compare_results.sh tutorial_global_oce_latlon

# View results
less tutorial_global_oce_latlon/output_docker/output.txt
```

**Success indicators:**
- ✅ `mitgcmuv` binary in both `build_docker/` and `output_docker/`
- ✅ `output.txt` shows "PROGRAM MAIN: Execution ended Normally"
- ✅ `*.data` and `*.meta` output files created

## Core Workflow: Compile Once, Run Many

The power of this tool is separating compilation from execution:

```bash
# Compile once (2-3 minutes)
./experiment_compile.sh 1D_ocean_ice_column -j 8

# Create custom input parameters
cp -r 1D_ocean_ice_column/input 1D_ocean_ice_column/input_custom
vim 1D_ocean_ice_column/input_custom/data

# Run with custom inputs (30 seconds, no recompilation!)
./experiment_run_no_compile.sh 1D_ocean_ice_column input_custom
less 1D_ocean_ice_column/output_docker/output.txt

# Edit parameters and run again
vim 1D_ocean_ice_column/input_custom/data
./experiment_run_no_compile.sh 1D_ocean_ice_column input_custom

# Run with different input variations
./experiment_run_no_compile.sh 1D_ocean_ice_column input_scenario1
./experiment_run_no_compile.sh 1D_ocean_ice_column input_scenario2
```

**Key insight:** Input parameter changes (namelist files, forcing data, etc.) don't require recompilation. Only recompile when you modify Fortran source code.

## Five Main Scripts

| Script | Purpose | Time | Usage |
|--------|---------|------|-------|
| `experiment_compile.sh` | Compile experiment | 2-4 min | `./experiment_compile.sh <exp> [-mpi] [-j N]` |
| `experiment_run_no_compile.sh` | Run with existing binary | ~30 sec | `./experiment_run_no_compile.sh <exp> [input_dir] [-mpi N]` |
| `compare_results.sh` | Compare against reference | ~1 sec | `./compare_results.sh <exp> [output_dir] [--match N]` |
| `docker_build.sh` | Build Docker image | ~5 min | `./docker_build.sh` |
| `docker_run_interactive.sh` | Interactive shell | N/A | `./docker_run_interactive.sh <exp>` |

**Key flags:**
- `-j N` - Parallel compilation with N jobs (e.g., `-j 8`)
- `-mpi` - Compile with MPI support (uses MPI-enabled optfile)
- `-mpi N` - Run with N MPI processes (uses mpirun)

## Compilation Speed Options

Control parallelization with the `-j` flag:

| Jobs | Time | Best For |
|------|------|----------|
| `-j 1` | 8-10 min | Serial compilation (debugging) |
| `-j 4` | 3-4 min | Default (4-core systems) |
| `-j 8` | 2-3 min | **Recommended** (8+ core systems) ⭐ |
| `-j 16` | ~2 min | Maximum (16+ core systems) |

**Check your Docker CPU allocation:**
```bash
docker info | grep CPUs
```

Should show at least 8 for `-j 8`.

## Binary Storage

After compilation, the binary exists in two locations:

```
<experiment>/
├── build_docker/
│   ├── mitgcmuv          ← Master copy (2.4 MB)
│   ├── Makefile          ← Build configuration
│   ├── *.o               ← Object files (1,486 files total)
│   └── *.f               ← Preprocessed Fortran
│
└── output_docker/
    ├── mitgcmuv          ← Runtime copy (used by run_no_compile.sh)
    ├── output.txt        ← Model log
    ├── *.data            ← Output data files
    └── *.meta            ← Metadata files
```

Both binaries are identical. The `output_docker/` copy is used by `run_no_compile.sh` for execution.

## Repository Structure

```
MITgcm_verification_docker/
├── README.md                      # This file
├── QUICK_REFERENCE.md             # Command cheat sheet
├── LICENSE                        # MIT License
├── Dockerfile                     # Docker image definition
│
├── scripts/                                # All executable scripts
│   ├── setup_links.sh                     # Setup and architecture detection
│   ├── experiment_compile.sh         # Compile script
│   ├── experiment_run_no_compile.sh  # Run script
│   ├── docker_build.sh            # Build Docker image
│   └── docker_run_interactive.sh          # Interactive shell
│
└── docs/                          # Additional documentation
    ├── CHANGELOG.md              # Version history
    ├── REPOSITORY_STRUCTURE.md   # How it works
    └── archive/                  # Detailed guides
```

## How It Works

1. **Symlink Integration:** Scripts are symlinked into your MITgcm `verification/` directory
2. **Docker Environment:** Provides consistent Linux environment with gfortran + NetCDF
3. **MITgcm Build Options:** Uses optfiles from MITgcm's `tools/build_options/`
4. **Volume Mounts:** Persistent storage for binaries and outputs on your host machine
5. **Architecture Detection:** Automatically selects correct compiler options

The repository is separate from MITgcm source, making it easy to update independently and use with multiple MITgcm installations.

## MPI Support

This Docker environment includes **OpenMPI** for experiments that require MPI parallelization.

### Compiling MPI Experiments

Use the `-mpi` flag to compile with MPI support:

```bash
# Compile with MPI (uses MPI-enabled optfile)
./experiment_compile.sh tutorial_global_oce_latlon -mpi -j 8

# Compile without MPI (default)
./experiment_compile.sh 1D_ocean_ice_column -j 8
```

The `-mpi` flag automatically tries to use an MPI-enabled optfile (e.g., `linux_arm64_gfortran+mpi`). If not available, it falls back to the standard optfile.

### Running MPI Experiments

Use the `-mpi N` flag to run with N MPI processes:

```bash
# Run with MPI (4 processes)
./experiment_run_no_compile.sh tutorial_global_oce_latlon input -mpi 4

# Run with MPI (8 processes)
./experiment_run_no_compile.sh tutorial_global_oce_latlon input -mpi 8

# Run without MPI (default)
./experiment_run_no_compile.sh 1D_ocean_ice_column
```

### Complete MPI Workflow

```bash
# 1. Compile with MPI
./experiment_compile.sh tutorial_global_oce_latlon -mpi -j 8

# 2. Run with 4 MPI processes
./experiment_run_no_compile.sh tutorial_global_oce_latlon input -mpi 4

# 3. Try different process counts (no recompilation needed!)
./experiment_run_no_compile.sh tutorial_global_oce_latlon input -mpi 2
./experiment_run_no_compile.sh tutorial_global_oce_latlon input -mpi 8
```

### MPI Environment

The Docker image includes:
- **OpenMPI:** Latest stable version from Debian
- **mpicc, mpif77, mpif90:** MPI compiler wrappers
- **mpirun:** MPI execution command (used automatically with `-mpi`)
- **NetCDF with MPI:** Parallel I/O support

### Notes

- MPI experiments require specific `SIZE.h` configuration (MPI domain decomposition)
- Use `-mpi N` where N matches your experiment's tile configuration
- Docker runs on a single host (multi-node MPI not supported)
- MPI optfiles (e.g., `linux_arm64_gfortran+mpi`) must exist in MITgcm's `tools/build_options/`

## Comparing Results Against Reference

Each verification experiment includes reference results in `results/output.txt`. Use `compare_results.sh` to verify your output matches the reference:

```bash
# Run and compare
./experiment_run_no_compile.sh 1D_ocean_ice_column
./compare_results.sh 1D_ocean_ice_column

# Output shows:
#   Matching digits: 16
#   Required:        13
#   Status:          ✓ PASS
```

**How it works:**
- Extracts monitor output statistics (`%MON` lines) from both files
- Compares numerical values digit-by-digit (same algorithm as MITgcm's `testreport`)
- Reports number of matching digits
- Default requirement: 13 digits (adjustable with `--match N`)

**Pass/Fail criteria:**
- **PASS (13+ digits):** Numerical differences within acceptable roundoff error
- **FAIL (<13 digits):** May indicate compiler differences, parameter changes, or code modifications

**Custom matching threshold:**
```bash
./compare_results.sh 1D_ocean_ice_column --match 10  # More lenient (10 digits)
./compare_results.sh 1D_ocean_ice_column --match 16  # More strict (16 digits)
```

## Common Workflows

### Testing Different Parameter Sets

```bash
# Compile once
./experiment_compile.sh 1D_ocean_ice_column -j 8

# Create multiple input variants
for scenario in baseline warm cold; do
    cp -r 1D_ocean_ice_column/input 1D_ocean_ice_column/input_$scenario
    # Edit parameters in each input_$scenario/data file
done

# Run all scenarios (no recompilation)
for scenario in baseline warm cold; do
    ./experiment_run_no_compile.sh 1D_ocean_ice_column input_$scenario
    mv 1D_ocean_ice_column/output_docker/output.txt results_$scenario.txt
done
```

### Debugging Compilation Issues

```bash
# Open interactive shell in Docker
./docker_run_interactive.sh 1D_ocean_ice_column

# Inside Docker, you can:
# - Run genmake2 manually
# - Check compiler flags
# - Test compilation steps
# - Inspect build files
```

### Using Different Experiments

```bash
# List available experiments
ls -d */

# Compile different experiment
./experiment_compile.sh tutorial_barotropic_gyre -j 8

# Run it
./experiment_run_no_compile.sh tutorial_barotropic_gyre
```

## Troubleshooting

### Docker Build Fails

**Problem:** Docker image build fails

**Check:** Docker is running
```bash
docker info
```

**Check:** Building from correct directory
```bash
cd /path/to/MITgcm/verification
docker build -t mitgcm:latest --build-arg OPTFILE=linux_amd64_gfortran -f Dockerfile ../
```

### Compilation is Slow

**Problem:** Compilation takes >5 minutes with `-j 8`

**Check:** Docker CPU allocation
```bash
docker info | grep CPUs
```

**Solution:** Increase CPUs in Docker Desktop → Settings → Resources

### Binary Not Found

**Problem:** `run_no_compile.sh` reports binary not found

**Solution:** Compile first
```bash
./experiment_compile.sh 1D_ocean_ice_column -j 8
```

### Symlinks Broken

**Problem:** Scripts don't work after moving repository

**Solution:** Re-run setup
```bash
cd /path/to/MITgcm_verification_docker
./scripts/setup_links.sh /path/to/MITgcm/verification
```

### Wrong Architecture

**Problem:** Compilation fails with assembler errors

**Solution:** Specify correct optfile
```bash
# Check your architecture
uname -m

# For ARM64
./scripts/setup_links.sh /path/to/MITgcm/verification linux_arm64_gfortran

# For x86_64
./scripts/setup_links.sh /path/to/MITgcm/verification linux_amd64_gfortran
```

Then rebuild Docker image with matching optfile.

## Multiple MITgcm Installations

You can use this repository with multiple MITgcm installations:

```bash
# Link to installation 1
./scripts/setup_links.sh ~/MITgcm_v1/verification

# Link to installation 2
./scripts/setup_links.sh ~/MITgcm_v2/verification

# Both installations now use the same Docker tools
# Updates via git pull apply to both
```

## Updating the Tools

```bash
cd /path/to/MITgcm_verification_docker
git pull

# Symlinks automatically point to updated scripts
# No need to re-run setup unless structure changes
```

## Advanced Usage

See [QUICK_REFERENCE.md](QUICK_REFERENCE.md) for advanced command reference.

## Support

- **Quick Reference:** See [QUICK_REFERENCE.md](QUICK_REFERENCE.md) for command cheat sheet
- **Additional Docs:** See `docs/` directory for detailed guides (optional)
- **Issues:** Report on GitHub (after publication)
- **MITgcm:** https://mitgcm.org/
- **Docker:** https://docs.docker.com/desktop/

## License

MIT License. See [LICENSE](LICENSE) file.

This toolset is designed for use with MITgcm. MITgcm itself is subject to its own license terms.

## Contributing

Contributions welcome! Please test on your system before submitting PRs.

## Acknowledgments

- Built for MITgcm verification experiments
- Supports ARM64 (Apple Silicon) and x86_64 (Intel/AMD)
- Uses official MITgcm build system (`testreport`)
- Enables rapid iteration for scientific computing workflows
