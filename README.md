# MITgcm Docker Tools

Docker-based workflow for compiling and running MITgcm verification experiments on multiple architectures.

**MITgcm Resources:**
- [Getting Started with MITgcm](https://mitgcm.readthedocs.io/en/latest/getting_started/getting_started.html)
- [Tutorial Example Experiments](https://mitgcm.readthedocs.io/en/latest/examples/examples.html)


## Overview

This repository provides Docker tools that enable fast, reproducible compilation and execution of MITgcm verification experiments. The key innovation is a **compile-once, run-many workflow** that eliminates unnecessary recompilation when only input parameters change.

### Key Benefits

✅ **Multi-architecture** - ARM64 (Apple Silicon) and x86_64 (Intel/AMD)  
✅ **Fast compilation** - Parallel builds with `-j` flag 
✅ **No recompilation** - Change input parameters without recompiling   
✅ **Persistent storage** - model executable binary and simulation outputs saved outside Docker  
✅ **Easy setup** - Symlinks into your existing MITgcm installation


## Prerequisites

- **Docker Desktop** installed and running
- **MITgcm source code** (available from https://github.com/MITgcm/MITgcm)
- **8+ GB RAM** allocated to Docker
- **1+ CPUs** allocated to Docker (for parallel compilation)
- **Supported architecture:** ARM64 or x86_64
- **MPI support:** Built-in (OpenMPI included for MPI experiments)

### Configure Docker Resources

Docker Desktop → Settings → Resources:
- **Memory:** 8-12 GB
- **CPUs:** 2+ (more CPUs = faster compilation via `-j` flag)
- **Disk:** 64+ GB

**Note:** Docker CPUs affect compilation speed, not model runtime. Most experiments need 1-4 CPUs to run.

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

**Recommended:** Use the build script (auto-detects your architecture):

```bash
cd /path/to/your/MITgcm/verification
./docker_build.sh
```

The script automatically detects your architecture and passes the correct build arguments.

**Verify the build succeeded:**
```bash
docker images | grep mitgcm
# Should show: mitgcm   latest   ...   ~2.5 GB

docker run --rm mitgcm:latest gfortran --version
# Should show: GNU Fortran (Debian ...) ...
```

**Manual build (if needed):**
```bash
# For ARM64 (Apple Silicon)
docker build -t mitgcm:latest --build-arg OPTFILE=linux_arm64_gfortran --build-arg MPI_ARCH=aarch64-linux-gnu -f Dockerfile ../

# For x86_64 (Intel/AMD)
docker build -t mitgcm:latest --build-arg OPTFILE=linux_amd64_gfortran --build-arg MPI_ARCH=x86_64-linux-gnu -f Dockerfile ../
```

**Build time:** ~5 minutes  
**Image size:** ~2.5 GB  
**Includes:** gfortran, NetCDF, OpenMPI

### 4. Compile and Run

**Non-MPI experiments:**
```bash
# Compile (adjust -j to match your CPU count)
./experiment_compile.sh 1D_ocean_ice_column -j 4

# Run
./experiment_run_no_compile.sh 1D_ocean_ice_column

# Compare against reference results
./compare_results.sh 1D_ocean_ice_column

# View results
less 1D_ocean_ice_column/output_docker/output.txt
```

**MPI experiments:**
```bash
# Compile with MPI (adjust -j to match your CPU count)
./experiment_compile.sh tutorial_global_oce_latlon -mpi -j 4

# Run with 2 MPI processes (nPx=2, nPy=1 from SIZE.h_mpi)
./experiment_run_no_compile.sh tutorial_global_oce_latlon -mpi 2

# Compare against reference results
./compare_results.sh tutorial_global_oce_latlon

# View results
less tutorial_global_oce_latlon/output_docker/output.txt
```

**Notes:**
- **`-j` flag:** Controls parallel compilation. Use `-j N` where N = your CPU count. Check with: `docker info | grep CPUs`
- **MPI processes:** Must match experiment's `SIZE.h_mpi` (nPx × nPy). Example: nPx=2, nPy=1 → use `-mpi 2`
- **Success:** Look for `mitgcmuv` binary in `output_docker/` and "Execution ended Normally" in `output.txt`

## Core Workflow: Compile Once, Run Many

The power of this tool is separating compilation from execution:

```bash
# Compile once (adjust -j to your CPU count: -j 2, -j 4, -j 8, etc.)
./experiment_compile.sh 1D_ocean_ice_column -j 4

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
| `experiment_compile.sh` | Compile experiment | 2-4 min | `./experiment_compile.sh <experiment> [-j N] [-mpi]` |
| `experiment_run_no_compile.sh` | Run with existing binary | ~30 sec | `./experiment_run_no_compile.sh <experiment> [input_dir] [-mpi N]` |
| `compare_results.sh` | Compare against reference | ~1 sec | `./compare_results.sh <experiment> [output_dir] [--match N]` |
| `docker_build.sh` | Build Docker image | ~5 min | `./docker_build.sh` |
| `docker_run_interactive.sh` | Interactive shell | N/A | `./docker_run_interactive.sh <experiment>` |

**Key flags:**
- `-j N` - Parallel compilation with N jobs (match to your CPU count: `-j 2`, `-j 4`, `-j 8`, etc.)
- `-mpi` (compile) - Compile with MPI support (auto-detects processes from SIZE.h_mpi)
- `-mpi N` (run) - Run with N MPI processes (uses mpirun)
- `input_dir` - Optional input directory (defaults to `input` if not specified)

## Compilation Speed

The `-j` flag controls parallel compilation jobs. **Match N to your CPU count** for best performance:

| Jobs | Time | When to Use |
|------|------|-------------|
| `-j 2` | 5-6 min | 2 CPUs available |
| `-j 4` | 3-4 min | 4 CPUs available (recommended) |
| `-j 8` | 2-3 min | 8+ CPUs available (fast) |

**Check your CPU allocation:** `docker info | grep CPUs`

Using more jobs than available CPUs provides no benefit.

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
    ├── mitgcmuv          ← Runtime copy (used by experiment_run_no_compile.sh)
    ├── output.txt        ← Model log
    ├── *.data            ← Output data files
    └── *.meta            ← Metadata files
```

Both binaries are identical. The `output_docker/` copy is used by `experiment_run_no_compile.sh` for execution.

## Repository Structure

```
MITgcm_verification_docker/
├── README.md                          # This file
├── QUICK_REFERENCE.md                 # Command cheat sheet
├── LICENSE                            # MIT License
├── Dockerfile                         # Docker image definition
│
├── scripts/                           # All executable scripts
│   ├── setup_links.sh                 # Setup and architecture detection
│   ├── docker_build.sh                # Build Docker image
│   ├── docker_run_interactive.sh      # Interactive shell
│   ├── experiment_compile.sh          # Compile experiment
│   ├── experiment_run_no_compile.sh   # Run without recompiling
│   └── compare_results.sh             # Compare against reference
│
└── docs/                              # Additional documentation
    ├── CHANGELOG.md                   # Version history
    ├── REPOSITORY_STRUCTURE.md        # How it works
    └── archive/                       # Detailed guides
```

## How It Works

1. **Symlink Integration:** Scripts are symlinked into your MITgcm `verification/` directory
2. **Docker Environment:** Provides consistent Linux environment with gfortran + NetCDF
3. **MITgcm Build Options:** Docker image includes full path to optfiles via `OPTFILE` environment variable
4. **Volume Mounts:** Persistent storage for binaries and outputs on your host machine
5. **Architecture Detection:** Automatically selects correct compiler options for ARM64 or x86_64

The repository is separate from MITgcm source, making it easy to update independently and use with multiple MITgcm installations.

## MPI Support

This Docker environment includes **OpenMPI** for experiments that require MPI parallelization.

### Compiling MPI Experiments

Use the `-mpi` flag to compile with MPI support:

```bash
# Compile with MPI (adjust -j to your CPU count)
./experiment_compile.sh tutorial_global_oce_latlon -mpi -j 4

# Compile without MPI (default)
./experiment_compile.sh 1D_ocean_ice_column -j 4
```

The `-mpi` flag automatically tries to use an MPI-enabled optfile (e.g., `linux_arm64_gfortran+mpi`). If not available, it falls back to the standard optfile.

### Running MPI Experiments

Use the `-mpi N` flag to run with N MPI processes. **N must match the experiment's `SIZE.h_mpi` configuration** (nPx × nPy):

```bash
# Check SIZE.h_mpi for required process count
cat tutorial_global_oce_latlon/code/SIZE.h_mpi | grep -E "nPx|nPy"
# Shows: nPx = 2, nPy = 1, so use -mpi 2

# Run with MPI (2 processes for tutorial_global_oce_latlon)
./experiment_run_no_compile.sh tutorial_global_oce_latlon -mpi 2

# Run with custom input directory and MPI
./experiment_run_no_compile.sh tutorial_global_oce_latlon input_custom -mpi 2

# Run without MPI (default)
./experiment_run_no_compile.sh 1D_ocean_ice_column
```

### MPI Environment

The Docker image includes:
- **OpenMPI:** Latest stable version from Debian
- **mpicc, mpif77, mpif90:** MPI compiler wrappers
- **mpirun:** MPI execution command (used automatically with `-mpi`)
- **NetCDF with MPI:** Parallel I/O support

**Limitations:**
- Docker runs on a single host (multi-node MPI not supported)
- The `-mpi N` value must exactly match nPx × nPy in `SIZE.h_mpi` or the model will fail

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
- **PASS (13+ digits):** Within acceptable roundoff error
- **FAIL (<13 digits):** May indicate compiler differences or code changes

**Custom threshold:**
```bash
./compare_results.sh 1D_ocean_ice_column --match 10  # More lenient
./compare_results.sh 1D_ocean_ice_column --match 16  # More strict
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

| Problem | Solution |
|---------|----------|
| **Docker build fails** | Check Docker is running: `docker info` |
| **Compilation slow (>5 min)** | Check CPU allocation: `docker info \| grep CPUs`<br>Increase CPUs in Docker Desktop → Settings → Resources |
| **Binary not found** | Compile first: `./experiment_compile.sh <experiment> -j 4` |
| **Scripts don't work after moving** | Re-run setup: `./scripts/setup_links.sh /path/to/MITgcm/verification` |
| **Assembler errors** | Check architecture: `uname -m`<br>Re-run setup with correct optfile (see Quick Start) |

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

## Additional Resources

- **[QUICK_REFERENCE.md](QUICK_REFERENCE.md)** - Command cheat sheet
- **`docs/`** - Detailed guides and changelog
- **[MITgcm](https://mitgcm.org/)** - MITgcm documentation
- **[Docker Desktop](https://docs.docker.com/desktop/)** - Docker documentation

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
