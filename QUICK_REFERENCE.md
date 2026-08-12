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
./experiment_compile.sh <experiment>

# Compile with N parallel jobs
./experiment_compile.sh <experiment> -j N

# Compile with MPI
./experiment_compile.sh <experiment> -mpi -j N

# Run with default inputs
./experiment_run_no_compile.sh <experiment>

# Run with custom inputs
./experiment_run_no_compile.sh <experiment> <input_dir>

# Run with MPI (N processes)
./experiment_run_no_compile.sh <experiment> <input_dir> -mpi N

# Compare results against reference
./compare_results.sh <experiment>
./compare_results.sh <experiment> <output_dir> --match N

# Build Docker image
./docker_build.sh

# Interactive Docker shell
./docker_run_interactive.sh <experiment>
```

## Examples

**Non-MPI:**
```bash
# Compile
./experiment_compile.sh 1D_ocean_ice_column -j 8
./experiment_compile.sh tutorial_barotropic_gyre -j 8

# Run multiple times with different inputs
./experiment_run_no_compile.sh 1D_ocean_ice_column
./experiment_run_no_compile.sh 1D_ocean_ice_column input_custom
./experiment_run_no_compile.sh 1D_ocean_ice_column input_scenario2

# Compare results
./compare_results.sh 1D_ocean_ice_column
```

**MPI:**
```bash
# Compile with MPI
./experiment_compile.sh tutorial_global_oce_latlon -mpi -j 8

# Run with MPI
./experiment_run_no_compile.sh tutorial_global_oce_latlon input -mpi 4
./experiment_run_no_compile.sh tutorial_global_oce_latlon input -mpi 8

# Compare results
./compare_results.sh tutorial_global_oce_latlon
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
└── output_docker/mitgcmuv    # Runtime copy (used by experiment_run_no_compile.sh)
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
./experiment_compile.sh 1D_ocean_ice_column -j 8

# Create input variants
cp -r 1D_ocean_ice_column/input 1D_ocean_ice_column/input_custom
vim 1D_ocean_ice_column/input_custom/data

# Run many times (no recompilation)
./experiment_run_no_compile.sh 1D_ocean_ice_column input_custom
vim 1D_ocean_ice_column/input_custom/data
./experiment_run_no_compile.sh 1D_ocean_ice_column input_custom
```

**MPI:**
```bash
# Compile once with MPI
./experiment_compile.sh tutorial_global_oce_latlon -mpi -j 8

# Run with different MPI process counts (no recompilation)
./experiment_run_no_compile.sh tutorial_global_oce_latlon input -mpi 2
./experiment_run_no_compile.sh tutorial_global_oce_latlon input -mpi 4
./experiment_run_no_compile.sh tutorial_global_oce_latlon input -mpi 8
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
| `-mpi` | experiment_compile.sh | Compile with MPI support (uses MPI-enabled optfile, e.g., linux_arm64_gfortran+mpi) |
| `-mpi N` | experiment_run_no_compile.sh | Run with N MPI processes (uses mpirun) |

## MPI Support

```bash
# Compile with MPI
./experiment_compile.sh tutorial_global_oce_latlon -mpi -j 8

# Run with MPI (4 processes)
./experiment_run_no_compile.sh tutorial_global_oce_latlon input -mpi 4

# Run with different process counts (no recompilation!)
./experiment_run_no_compile.sh tutorial_global_oce_latlon input -mpi 2
./experiment_run_no_compile.sh tutorial_global_oce_latlon input -mpi 8

# Docker includes OpenMPI: mpicc, mpif77, mpif90, mpirun
```

## Result Comparison

```bash
# Compare output against reference results
./compare_results.sh 1D_ocean_ice_column

# Compare with custom output directory
./compare_results.sh 1D_ocean_ice_column output_custom

# Adjust matching threshold (default: 13 digits)
./compare_results.sh 1D_ocean_ice_column --match 10  # More lenient
./compare_results.sh 1D_ocean_ice_column --match 16  # More strict

# Exit codes:
#   0 = PASS (sufficient digit agreement)
#   1 = FAIL (insufficient agreement or missing files)
```

**How it works:**
- Extracts `%MON` lines from both reference and output files
- Compares numerical values digit-by-digit (same as `testreport`)
- Reports matching digits (typically 13-16 for exact match)
- PASS if matching digits ≥ threshold

## Key Insight

**Only recompile when Fortran source changes. Parameter changes don't require recompilation.**

Typical times:
- Compile: 2-3 min (with `-j 8`)
- Run: 30 sec
- Edit and run again: 30 sec

**8x faster** than recompiling every time.
