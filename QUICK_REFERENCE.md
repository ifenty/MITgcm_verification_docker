# Quick Reference

Advanced user command reference for MITgcm Docker Tools.

## Setup (One Time)

```bash
git clone https://github.com/YOUR_USERNAME/MITgcm_verification_docker.git
cd MITgcm_verification_docker
./scripts/setup_links.sh /path/to/MITgcm/verification

cd /path/to/MITgcm/verification
docker build -t mitgcm:latest --build-arg OPTFILE=linux_amd64_gfortran -f Dockerfile ../
```

## Core Commands

```bash
# Compile with default parallelization
./docker_compile_only.sh <experiment>

# Compile with N parallel jobs
./docker_compile_only.sh <experiment> -j N

# Compile with MPI
./docker_compile_only.sh <experiment> -mpi -j N

# Run with default inputs
./run_no_compile.sh <experiment>

# Run with custom inputs
./run_no_compile.sh <experiment> <input_dir>

# Run with MPI (N processes)
./run_no_compile.sh <experiment> <input_dir> -mpi N

# Full verification test
./build_and_run.sh

# Interactive Docker shell
./run_interactive.sh <experiment>
```

## Examples

**Non-MPI:**
```bash
# Compile
./docker_compile_only.sh 1D_ocean_ice_column -j 8
./docker_compile_only.sh tutorial_barotropic_gyre -j 8

# Run multiple times with different inputs
./run_no_compile.sh 1D_ocean_ice_column
./run_no_compile.sh 1D_ocean_ice_column input_custom
./run_no_compile.sh 1D_ocean_ice_column input_scenario2
```

**MPI:**
```bash
# Compile with MPI
./docker_compile_only.sh tutorial_global_oce_latlon -mpi -j 8

# Run with MPI
./run_no_compile.sh tutorial_global_oce_latlon input -mpi 4
./run_no_compile.sh tutorial_global_oce_latlon input -mpi 8
```

## Parallelization

| Flag | Use Case |
|------|----------|
| `-j 1` | Serial (debugging) |
| `-j 4` | 4-core systems |
| `-j 8` | 8-core systems (recommended) |
| `-j 16` | 16+ core systems |

## Binary Locations

```
<experiment>/
├── build_docker/mitgcmuv     # Master copy with build artifacts
└── output_docker/mitgcmuv    # Runtime copy (used by run_no_compile.sh)
```

## Output Files

```
<experiment>/output_docker/
├── mitgcmuv           # Binary
├── output.txt         # Model log
├── *.data            # Output data
└── *.meta            # Metadata
```

## Architecture-Specific Setup

```bash
# ARM64 (Apple Silicon, ARM servers)
./scripts/setup_links.sh /path/to/verification linux_arm64_gfortran
docker build -t mitgcm:latest --build-arg OPTFILE=linux_arm64_gfortran -f Dockerfile ../

# x86_64 (Intel/AMD)
./scripts/setup_links.sh /path/to/verification linux_amd64_gfortran
docker build -t mitgcm:latest --build-arg OPTFILE=linux_amd64_gfortran -f Dockerfile ../
```

## Workflow Patterns

**Non-MPI:**
```bash
# Compile once
./docker_compile_only.sh 1D_ocean_ice_column -j 8

# Create input variants
cp -r 1D_ocean_ice_column/input 1D_ocean_ice_column/input_custom
vim 1D_ocean_ice_column/input_custom/data

# Run many times (no recompilation)
./run_no_compile.sh 1D_ocean_ice_column input_custom
vim 1D_ocean_ice_column/input_custom/data
./run_no_compile.sh 1D_ocean_ice_column input_custom
```

**MPI:**
```bash
# Compile once with MPI
./docker_compile_only.sh tutorial_global_oce_latlon -mpi -j 8

# Run with different MPI process counts (no recompilation)
./run_no_compile.sh tutorial_global_oce_latlon input -mpi 2
./run_no_compile.sh tutorial_global_oce_latlon input -mpi 4
./run_no_compile.sh tutorial_global_oce_latlon input -mpi 8
```

## Troubleshooting

```bash
# Check Docker CPUs
docker info | grep CPUs

# Rebuild Docker image
docker build -t mitgcm:latest --build-arg OPTFILE=<optfile> -f Dockerfile ../

# Re-run setup
./scripts/setup_links.sh /path/to/verification

# Check architecture
uname -m
```

## MPI Flags

| Flag | Script | Description |
|------|--------|-------------|
| `-mpi` | docker_compile_only.sh | Compile with MPI support (uses MPI-enabled optfile, e.g., linux_arm64_gfortran+mpi) |
| `-mpi N` | run_no_compile.sh | Run with N MPI processes (uses mpirun) |

## MPI Support

```bash
# Compile with MPI
./docker_compile_only.sh tutorial_global_oce_latlon -mpi -j 8

# Run with MPI (4 processes)
./run_no_compile.sh tutorial_global_oce_latlon input -mpi 4

# Run with different process counts (no recompilation!)
./run_no_compile.sh tutorial_global_oce_latlon input -mpi 2
./run_no_compile.sh tutorial_global_oce_latlon input -mpi 8

# Docker includes OpenMPI: mpicc, mpif77, mpif90, mpirun
```

## Key Insight

**Only recompile when Fortran source changes. Parameter changes don't require recompilation.**

Typical times:
- Compile: 2-3 min (with `-j 8`)
- Run: 30 sec
- Edit and run again: 30 sec

**8x faster** than recompiling every time.
