# MITgcm Verification Docker Tools

Docker-based workflow for compiling and running MITgcm verification experiments
on multiple architectures, without installing a Fortran/MPI/NetCDF toolchain on
your host machine. The same framework can be adapted to compile and run custom
MITgcm configurations.

**MITgcm resources:**
- [Getting Started with MITgcm](https://mitgcm.readthedocs.io/en/latest/getting_started/getting_started.html)
- [Tutorial example experiments](https://mitgcm.readthedocs.io/en/latest/examples/examples.html)

## Overview

This repository provides Docker tools for fast, reproducible compilation and
execution of MITgcm verification experiments. The key idea is a
**compile-once, run-many workflow**: recompilation is only needed when Fortran
source changes, not when input parameters change.

- **Multi-architecture** — ARM64 (Apple Silicon) and x86_64 (Intel/AMD)
- **Fast compilation** — parallel builds via `-j`
- **No recompilation for input-only changes** — swap input directories freely
- **Persistent storage** — binaries and outputs are written to your host filesystem, not left inside the container
- **Easy setup** — one setup script symlinks these tools into your existing MITgcm checkout

## Prerequisites

- **Docker Desktop**, installed and running
- **MITgcm source code** (https://github.com/MITgcm/MITgcm)
- **8+ GB RAM** allocated to Docker
- **2+ CPUs** allocated to Docker (more CPUs → faster compilation via `-j`)
- **ARM64 or x86_64** host architecture

Docker Desktop → Settings → Resources: Memory 8-12 GB, CPUs 2+, Disk 64+ GB.
CPU allocation affects compilation speed, not model runtime — most experiments
only need 1-4 CPUs to run.

## Quick start

```bash
# 1. Clone this repository
git clone https://github.com/ifenty/MITgcm_verification_docker.git
cd MITgcm_verification_docker

# 2. Link the scripts into your MITgcm checkout
./scripts/setup_links.sh /path/to/your/MITgcm/verification

# 3. Build the Docker image (auto-detects ARM64/x86_64)
cd /path/to/your/MITgcm/verification
./docker_build.sh

# 4. Compile and run an experiment
./experiment_compile.sh 1D_ocean_ice_column -j 4
./experiment_run_no_compile.sh 1D_ocean_ice_column
./compare_results.sh 1D_ocean_ice_column
less 1D_ocean_ice_column/output_docker/output.txt
```

`setup_links.sh` detects your architecture, suggests the matching build-options
file from MITgcm's `tools/build_options/` (`linux_arm64_gfortran` or
`linux_amd64_gfortran`), and symlinks the scripts plus this README into your
verification directory.

**Verify the image built correctly:**
```bash
docker images | grep mitgcm
docker run --rm mitgcm:latest gfortran --version
```

The image contains only compilers, NetCDF and MPI libraries (roughly 1 GB) —
MITgcm source is **mounted** at runtime, not baked into the image, so editing
source code never requires a Docker rebuild.

## Core workflow: compile once, run many

```bash
# Compile once
./experiment_compile.sh 1D_ocean_ice_column -j 4

# Create an input variant and run it (no recompilation)
cp -r 1D_ocean_ice_column/input 1D_ocean_ice_column/input_custom
vim 1D_ocean_ice_column/input_custom/data
./experiment_run_no_compile.sh 1D_ocean_ice_column input_custom
less 1D_ocean_ice_column/output_docker/output.txt

# Edit and run again — still no recompilation
vim 1D_ocean_ice_column/input_custom/data
./experiment_run_no_compile.sh 1D_ocean_ice_column input_custom
```

Only Fortran source changes require recompiling; namelist/forcing-data changes
do not.

## Command reference

| Script | Purpose | Typical time |
|---|---|---|
| `docker_build.sh` | Build the Docker image | ~5 min |
| `experiment_compile.sh` | Compile an experiment (no run) | 2-4 min |
| `experiment_run_no_compile.sh` | Run using an already-compiled binary | ~30 sec |
| `compare_results.sh` | Compare output against the experiment's reference results | <1 sec |
| `docker_run_interactive.sh` | Open an interactive shell in the container | — |
| `setup_links.sh` | One-time setup: symlink these tools into a MITgcm checkout | — |

### `experiment_compile.sh`

```
./experiment_compile.sh <experiment> [-j N] [-mpi] [-mods <dir>] [-build <dir>] [-clean]
```

| Flag | Meaning |
|---|---|
| `-j N` | Parallel `make` jobs (default 4). Match to your Docker CPU allocation (`docker info \| grep CPUs`). |
| `-mpi` | Compile with MPI support. Requires `SIZE.h_mpi` in the experiment's `code/` directory; `nPx`/`nPy` are read from it automatically. |
| `-mods <dir>` | Build with a custom code directory instead of the experiment's own `code/`. **Must be an absolute path.** If the directory contains symlinks, they are automatically dereferenced (copied as real files) before mounting — no extra flag needed here. |
| `-build <dir>` | Build directory name (default `build_docker`). Use a non-default name to keep multiple builds of the same experiment side by side. |
| `-clean` | Force a full rebuild. Without it, builds are incremental — much faster for single-file changes. |

The compiled binary is written to both `<experiment>/<build-dir>/mitgcmuv` and
copied for you by `experiment_run_no_compile.sh` at run time.

### `experiment_run_no_compile.sh`

```
./experiment_run_no_compile.sh <experiment> [input_dir] [-mpi N] [-build <dir>] [-output <dir>]
```

| Flag | Meaning |
|---|---|
| `input_dir` | Input directory to use (default `input`). Any positional argument that isn't a recognized flag is treated as this. |
| `-mpi N` | Run with `N` MPI processes via `mpirun`. `N` must equal `nPx * nPy` from the experiment's `SIZE.h_mpi`. |
| `-build <dir>` | Build directory to take the binary from (default `build_docker`) — must match whatever `-build` you used at compile time. |
| `-output <dir>` | Output directory name (default `output_docker`). |

Requires a binary already produced by `experiment_compile.sh` in the matching
build directory.

### `compare_results.sh`

```
./compare_results.sh <experiment> [output_dir] [--match N]
```

Extracts `%MON` monitor lines from `<experiment>/results/output.txt`
(reference) and `<experiment>/<output_dir>/output.txt` (yours), and compares
them digit-by-digit using the same algorithm as MITgcm's own `testreport`.
Prints the number of matching digits and exits `0` (PASS) if it meets
`--match N` (default `13`), `1` (FAIL) otherwise.

### `docker_run_interactive.sh`

```
./docker_run_interactive.sh [-code <path>] [-taf_dir <path>] [-dereference] [-h]
```

Opens an interactive bash shell in the container for manual debugging,
inspecting build files, or running `genmake2`/`make` steps by hand. Run
`./docker_run_interactive.sh -h` for the full built-in help, including
worked examples.

| Flag | Meaning |
|---|---|
| `-code <path>` | Mount a custom code directory at `/custom_code` (absolute path required). |
| `-taf_dir <path>` | Mount a TAF installation at `/taf` and add it to `PATH`; see [TAF support](#taf-support-adjointtangent-linear) below. |
| `-dereference` | Dereference symlinks in `-code` before mounting. **Unlike `experiment_compile.sh -mods`, this script does not dereference automatically** — pass this flag explicitly if your code directory contains symlinks pointing outside it. |

## Repository structure

```
MITgcm_verification_docker/
├── README.md
├── LICENSE
├── Dockerfile
├── scripts/
│   ├── setup_links.sh
│   ├── docker_build.sh
│   ├── docker_run_interactive.sh
│   ├── experiment_compile.sh
│   ├── experiment_run_no_compile.sh
│   └── compare_results.sh
└── tests/
    └── test_script_integration.sh
```

`setup_links.sh` symlinks the six scripts and this README into your MITgcm
`verification/` directory (except `Dockerfile`, which is copied rather than
symlinked, since Docker requires a real file as its build context).

## How it works

1. **Symlink integration** — the scripts run from inside your MITgcm
   `verification/` directory via symlinks back to this repo, so `git pull`
   here updates every linked checkout at once.
2. **Mount-based Docker image** — the image contains only the compiler
   toolchain (gfortran, NetCDF, OpenMPI); MITgcm source is bind-mounted into
   the container at `/mitgcm` at build/run time, not copied into the image.
   Editing MITgcm source or your `-mods`/`-code` directory takes effect on the
   next compile with no Docker rebuild.
3. **Architecture detection** — every script inspects `uname -m` and picks the
   matching build-options file (`linux_arm64_gfortran` or
   `linux_amd64_gfortran`) and MPI architecture path automatically.
4. **Host-side persistence** — compiled binaries and run output live in
   `<experiment>/build_docker/` and `<experiment>/output_docker/` on your host,
   not inside the (ephemeral, `--rm`) container.

## MPI support

The image includes OpenMPI (`mpicc`, `mpif77`, `mpif90`, `mpirun`) and
NetCDF built with parallel I/O support. Docker runs on a single host, so
multi-node MPI is not supported — only multi-process, single-host runs.

```bash
# Check how many processes an experiment expects
grep -E "nPx|nPy" tutorial_global_oce_latlon/code/SIZE.h_mpi
# nPx = 2, nPy = 1  ->  2 processes total

# Compile with MPI support
./experiment_compile.sh tutorial_global_oce_latlon -mpi -j 4

# Run with that many processes
./experiment_run_no_compile.sh tutorial_global_oce_latlon -mpi 2
```

`-mpi N` at run time must equal `nPx * nPy` from `SIZE.h_mpi` or the model
will fail. There is no separate "MPI-enabled optfile" variant — `-mpi` at
compile time passes `-mpi` straight through to MITgcm's own `testreport` with
the same architecture-detected optfile used for non-MPI builds.

## Custom code modifications

Two different flags cover two different workflows — don't mix them up:

**`experiment_compile.sh -mods <dir>`** — build the experiment using files
from `<dir>` instead of its own `code/` directory (e.g. a modified
`kpp_calc.F`, or an overridden `SIZE.h`/`packages.conf`). The directory is
temporarily swapped in for `code/`, restored afterward, and also saved as
`<experiment>/code_validation/` for reference. **Symlinks inside `-mods` are
dereferenced automatically** — no extra flag needed.

```bash
mkdir -p /path/to/project/code_validation
cp custom_kpp_calc.F /path/to/project/code_validation/kpp_calc.F

./experiment_compile.sh lab_sea -mods /path/to/project/code_validation -j 8
./experiment_run_no_compile.sh lab_sea
```

**`docker_run_interactive.sh -code <dir> [-dereference]`** — mount `<dir>` at
`/custom_code` for a manual, interactive build (running `genmake2`/`make`
yourself inside the container). This script does **not** dereference symlinks
automatically; pass `-dereference` if `<dir>` contains symlinks pointing
outside it (a common pattern when referencing files directly from an MITgcm
checkout: `ln -s /MITgcm/pkg/kpp/kpp_calc.F kpp_calc.F`). Without
`-dereference`, Docker mounts the symlink itself and cannot follow it outside
the mounted directory, so the target file appears missing inside the
container.

```bash
./docker_run_interactive.sh -code /path/to/code_with_symlinks -dereference
```

Both flags require **absolute paths**; relative paths are rejected.

## TAF support (adjoint/tangent linear)

`docker_run_interactive.sh -taf_dir <path>` mounts a TAF (Tangent linear and
Adjoint Model Compiler) installation at `/taf`, adds it to `PATH`, and mounts
`~/.ssh` read-only for TAF license validation.

```bash
./docker_run_interactive.sh -code /path/to/custom/code -taf_dir /path/to/TAF

# Inside the container:
which staf                # /taf/staf
cd lab_sea/build
../../../tools/genmake2 -mods=/custom_code -optfile=$OPTFILE
make depend
make adall                 # adjoint
make ftlall                # tangent linear
```

`<path>/staf` must exist; `~/.ssh` is mounted read-only so the container can
read license keys but cannot alter your SSH configuration.

If your project has its own TAF setup notes (build flags, license quirks,
specific experiments), keep those alongside that project rather than in this
standalone repo — this section only covers what these Docker scripts do.

## Comparing results against reference

Every MITgcm verification experiment ships reference output in
`results/output.txt`.

```bash
./experiment_run_no_compile.sh 1D_ocean_ice_column
./compare_results.sh 1D_ocean_ice_column
#   Matching digits: 16
#   Required:        13
#   Status:          PASS
```

13+ matching digits is the default pass threshold (adjustable with
`--match N`); fewer usually indicates a compiler/platform difference or an
intentional code change rather than roundoff.

## Common workflows

**Sweep several input variants without recompiling:**
```bash
./experiment_compile.sh 1D_ocean_ice_column -j 8
for scenario in baseline warm cold; do
    cp -r 1D_ocean_ice_column/input "1D_ocean_ice_column/input_$scenario"
    # edit each input_$scenario/data as needed
done
for scenario in baseline warm cold; do
    ./experiment_run_no_compile.sh 1D_ocean_ice_column "input_$scenario"
    mv 1D_ocean_ice_column/output_docker/output.txt "results_$scenario.txt"
done
```

**Debug a compilation interactively:**
```bash
./docker_run_interactive.sh
# inside the container: run genmake2/make by hand, inspect build files
```

**Use with more than one MITgcm checkout:**
```bash
./scripts/setup_links.sh ~/MITgcm_v1/verification
./scripts/setup_links.sh ~/MITgcm_v2/verification
# both now share the same Docker tools; git pull here updates both
```

## Troubleshooting

| Problem | Fix |
|---|---|
| Docker build fails | Check Docker Desktop is running: `docker info` |
| Compilation is slow | Check CPU allocation: `docker info \| grep CPUs`; increase it in Docker Desktop → Settings → Resources |
| `Binary not found` when running | Compile first: `./experiment_compile.sh <experiment> -j 4` |
| Scripts stop working after moving the repo | Re-run `./scripts/setup_links.sh /path/to/MITgcm/verification` |
| `-mods`/`-code` rejected | Both require absolute paths — relative paths are rejected on purpose |
| "File not found" with custom code under `-code` | Directory likely has symlinks pointing outside it — add `-dereference` (compile's `-mods` does this automatically, no flag needed there) |
| Assembler/toolchain errors | Confirm architecture with `uname -m` and re-run `setup_links.sh` to pick the matching optfile |

## License

MIT License — see [LICENSE](LICENSE). This toolset is for use with MITgcm;
MITgcm itself is subject to its own license terms.
