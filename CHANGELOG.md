# Changelog

## v2.1.0 - 2026-08-08

### New Features

**MPI Support with Explicit Flags:**
- Added `-mpi` flag to `docker_compile_only.sh` for MPI compilation
- Added `-mpi N` flag to `run_no_compile.sh` for MPI execution
- Automatically selects MPI-enabled optfiles when `-mpi` is used
- Executes with `mpirun` when `-mpi N` is specified
- OpenMPI included in Docker image (mpicc, mpif77, mpif90, mpirun)

**User-Configurable Experiments:**
- Removed hardcoded default experiment from Dockerfile
- Users specify experiment when running scripts
- Docker CMD changed to interactive bash
- More flexible for different verification tests

**Docker Image Updates:**
- Installed libopenmpi-dev and openmpi-bin packages
- Installed libnetcdf-mpi-dev for parallel NetCDF I/O
- Added MPI_INC_DIR environment variable

**Documentation:**
- Clear MPI workflow with flag usage
- Examples showing MPI compilation and execution
- Updated QUICK_REFERENCE with MPI commands
- Documented MPI optfile fallback behavior

### Usage

```bash
# Non-MPI experiment
./docker_compile_only.sh 1D_ocean_ice_column -j 8
./run_no_compile.sh 1D_ocean_ice_column

# MPI experiment
./docker_compile_only.sh tutorial_global_oce_latlon -mpi -j 8
./run_no_compile.sh tutorial_global_oce_latlon input -mpi 4

# Try different MPI process counts (no recompilation!)
./run_no_compile.sh tutorial_global_oce_latlon input -mpi 2
./run_no_compile.sh tutorial_global_oce_latlon input -mpi 8
```

## v2.0.0 - 2026-08-08

### Major Changes

**Repository Reorganization:**
- Renamed from MITgcm_verification_mac to MITgcm_verification_docker
- Moved all scripts to `scripts/` directory
- Simplified documentation (README.md + QUICK_REFERENCE.md)
- Removed optfiles from repository (use MITgcm's `tools/build_options/`)

**Documentation Simplification:**
- Comprehensive README.md with all essential information
- QUICK_REFERENCE.md for advanced users
- Removed multiple overlapping documentation files

### New Structure

```
MITgcm_verification_docker/
├── README.md              # Comprehensive documentation
├── QUICK_REFERENCE.md     # Command reference
├── LICENSE
├── Dockerfile
├── scripts/               # All executable scripts
└── CHANGELOG.md           # This file
```

### Changes

- **setup_links.sh:** Now references MITgcm's optfiles instead of bundled copies
- **Dockerfile:** Uses optfiles from MITgcm source tree
- **Documentation:** Removed architecture-specific language, consistently refers to multiple architectures

## v1.1.0 - 2026-08-08

### Features

**Multi-Architecture Support:**
- Added automatic architecture detection in `setup_links.sh`
- Supported architectures: ARM64 (Apple Silicon) and x86_64 (Intel/AMD)
- Dockerfile supports `--build-arg OPTFILE=` for custom optfiles

## v1.0.0 - 2026-08-08

### Initial Release

**Features:**
- Docker-based compilation and execution for MITgcm
- Native ARM64 support (Apple Silicon)
- Parallel compilation with `-j` flag
- Compile-once, run-many workflow
- Persistent binary and output storage

**Scripts:**
- `docker_compile_only.sh` - Compile verification experiments
- `run_no_compile.sh` - Run without recompilation
- `build_and_run.sh` - Full verification tests
- `run_interactive.sh` - Interactive Docker shell
- `setup_links.sh` - Easy symlink setup

**Performance:**
- Compilation: 2-3 minutes (with `-j 8`)
- Run time: ~30 seconds (no compilation)
- **8x faster** than recompiling every time
