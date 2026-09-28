# MITgcm Verification Docker Tools

Docker-based workflow for compiling and running MITgcm verification experiments
on multiple architectures, without installing a Fortran/MPI/NetCDF toolchain on
your host machine. The same framework can be adapted to compile and run custom
MITgcm configurations.

**MITgcm resources:**
- [Getting Started with MITgcm](https://mitgcm.readthedocs.io/en/latest/getting_started/getting_started.html)
- [Tutorial example experiments](https://mitgcm.readthedocs.io/en/latest/examples/examples.html)

## Overview

This repository provides Docker tools for reproducible compilation and
execution of MITgcm verification experiments. The key idea is a
**compile-once, run-many workflow**: recompilation is only needed when Fortran
source changes, not when input parameters change.

- **Multi-architecture** — ARM64 (Apple Silicon) and x86_64 (Intel/AMD)
- **Parallel builds** — `make -j N`
- **No recompilation for input-only changes** — swap input directories freely
- **testreport-compatible** — builds, input staging and result comparison follow MITgcm's own `testreport`
- **Persistent storage** — binaries and outputs are written to your host filesystem, not left inside the container
- **Easy setup** — one setup script symlinks these tools into your existing MITgcm checkout

## Prerequisites

- **Docker** (Docker Desktop on macOS/Windows, Docker Engine on Linux), installed and running
- **MITgcm source code** (https://github.com/MITgcm/MITgcm)
- **bash** and standard Unix tools on the host (no compilers needed on the host)
- **8+ GB RAM** allocated to Docker
- **2+ CPUs** allocated to Docker (more CPUs → faster compilation via `-j`)
- **ARM64 or x86_64** host architecture

Docker Desktop → Settings → Resources: Memory 8-12 GB, CPUs 2+, Disk 64+ GB.
CPU allocation affects compilation speed and how many MPI processes can run
efficiently.

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

# 4. Compile, run, and check an experiment
./experiment_compile.sh 1D_ocean_ice_column -j 4
./experiment_run_no_compile.sh 1D_ocean_ice_column
./compare_results.sh 1D_ocean_ice_column
less 1D_ocean_ice_column/output_docker/output.txt
```

`setup_links.sh` detects your architecture, checks that the matching
build-options file exists in MITgcm's `tools/build_options/`
(`linux_arm64_gfortran` or `linux_amd64_gfortran`), and symlinks the scripts
plus this README into your verification directory.

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
./experiment_run_no_compile.sh 1D_ocean_ice_column input_custom -output output_custom
less 1D_ocean_ice_column/output_custom/output.txt

# Edit and run again — still no recompilation
vim 1D_ocean_ice_column/input_custom/data
./experiment_run_no_compile.sh 1D_ocean_ice_column input_custom -output output_custom
```

Only Fortran source changes require recompiling; namelist/forcing-data changes
do not.

## Command reference

| Script | Purpose | Typical time |
|---|---|---|
| `docker_build.sh` | Build the Docker image | ~5 min (first time) |
| `experiment_compile.sh` | Compile an experiment (no run) | 15 s – a few min |
| `experiment_run_no_compile.sh` | Run using an already-compiled binary | seconds – minutes |
| `compare_results.sh` | Compare output against the experiment's reference results | <1 sec |
| `docker_run_interactive.sh` | Open a shell in the container (or run piped commands) | — |
| `setup_links.sh` | One-time setup: symlink these tools into a MITgcm checkout | — |

Every script accepts `-h`/`--help`.

### `experiment_compile.sh`

```
./experiment_compile.sh <experiment> [-j N] [-mpi] [-mods <dir>] [-build <dir>] [-clean]
```

| Flag | Meaning |
|---|---|
| `-j N` | Parallel `make` jobs (default 4). Match to your Docker CPU allocation (`docker info \| grep CPUs`). |
| `-mpi` | Compile with MPI for `nPx * nPy` processes, read from the experiment's `code/SIZE.h_mpi` (or from `SIZE.h_mpi` in the `-mods` directory). `code/SIZE.h` is never modified. |
| `-mods <dir>` | Build with `<dir>` **instead of** the experiment's own `code/` directory. `<dir>` must be an **absolute path to an existing directory** and must contain everything `code/` would (`SIZE.h`, `packages.conf`, option files, …) plus your modified files. Symlinks inside it (at any depth) are dereferenced automatically. |
| `-build <dir>` | Build directory name inside the experiment (default `build_docker`). Use a non-default name to keep multiple builds of the same experiment side by side. |
| `-clean` | Delete the host-side build directory before compiling. |

Compilation runs MITgcm's `testreport -norun` inside the container. testreport
always runs `make Clean` first, so **every compile is a full rebuild** (about
15 s for small experiments with `-j 16`). The build happens in
`<experiment>/build/` of your MITgcm checkout; afterwards the build files and
binary are copied to `<experiment>/<build-dir>/`, together with
`compile.log` and `build_info.txt` (records whether the build is MPI and for
how many processes). testreport's `tr_*` output directories are removed after
each compile.

### `experiment_run_no_compile.sh`

```
./experiment_run_no_compile.sh <experiment> [input_dir] [-mpi N] [-build <dir>] [-output <dir>]
```

| Flag | Meaning |
|---|---|
| `input_dir` | Input directory to use (default `input`). Any positional argument that isn't a recognized flag is treated as this. |
| `-mpi N` | Run with `N` MPI processes via `mpirun`. `N` must equal the process count the binary was compiled for (`nPx * nPy` from `SIZE.h_mpi`); a mismatch, or running an MPI build without `-mpi`, is rejected with the correct command. |
| `-build <dir>` | Build directory to take the binary from (default `build_docker`) — must match whatever `-build` you used at compile time. |
| `-output <dir>` | Output (run) directory name inside the experiment (default `output_docker`). |

Input files are staged the way testreport does it:

- Files in `input_dir` are symlinked into the output directory (relative
  links, valid on the host too). For `input.<X>` directories (e.g.
  `input.nlfs`), files missing from `input.<X>` are taken from `input/`.
- For MPI runs, `<file>.mpi` variants (e.g. `data.exch2.mpi`) replace `<file>`.
- If the input directory contains a `prepare_run` script, it is run in the
  output directory before the model starts.

Before each run, symlinks and `STDOUT.*`/`STDERR.*`/`output.txt` files left in
the output directory by an earlier run are removed, so a run never silently
picks up inputs from a different input directory. Other files from earlier runs
(e.g. `.data` output) are overwritten by the model but not deleted — use a
separate `-output` directory per scenario to keep results apart.

The model log is `<output-dir>/output.txt` (for MPI runs it is a copy of
`STDOUT.0000`; `mpirun`'s own messages go to `mpirun.log`). MITgcm exits with
status 0 even when it stops on an error, so the script checks the log instead:
it **exits non-zero unless the model reports `Execution ended Normally`**.
`run_info.txt` records the input directory used, for `compare_results.sh`.

### `compare_results.sh`

```
./compare_results.sh <experiment> [output_dir] [--match N] [--ref <file>]
```

Compares `<experiment>/<output_dir>/output.txt` (default `output_docker`)
against the experiment's reference output using the same algorithm as
MITgcm's `testreport`:

- The variables come from the experiment's `tr_checklist` file (or
  testreport's default list: `cg2d_init_res` plus theta/salt/u/v min, max,
  mean and std-dev, plus passive tracers). The **first** checklist entry
  decides PASS/FAIL; the others are reported for information.
- Each variable is compared as its own time series; the result is the number
  of matching decimal digits (16 = identical, 22 = identically zero).
- A variable reported as `N/O` could not be compared (missing, different
  number of records, or NaN/Inf in the output); `N/O` on the deciding
  variable is a FAIL.
- The reference is `results/output.txt`, or `results/output.<X>.txt` when the
  run used `input.<X>` (override with `--ref <file>`). MPI outputs are handled
  automatically.

Exits `0` (PASS) if the deciding variable matches at least `--match N`
digits (default `10`, the same as testreport), `1` (FAIL) otherwise. The
script can be run from any directory.

### `docker_run_interactive.sh`

```
./docker_run_interactive.sh [-code <path>] [-taf_dir <path>] [-dereference] [-h]
```

Opens an interactive bash shell in the container for manual debugging,
inspecting build files, or running `genmake2`/`make` steps by hand. MITgcm is
mounted at `/mitgcm` and `$OPTFILE` points to the build-options file for your
architecture. If stdin is not a terminal, the commands piped to it run
non-interactively instead:

```bash
echo 'cd 1D_ocean_ice_column && ls' | ./docker_run_interactive.sh
```

If the `mitgcm:latest` image does not exist yet, it is built with
`docker_build.sh` first. Run `./docker_run_interactive.sh -h` for the full
built-in help, including worked examples.

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
    ├── test_script_integration.sh   # argument handling (no Docker needed)
    ├── test_regressions.sh          # regression tests with a mock docker (no Docker needed)
    ├── new_install_stress_test.sh   # end-to-end test on a fresh MITgcm clone (real Docker)
    └── STRESS_TEST.md               # how to run and read the stress test
```

`setup_links.sh` symlinks the five user-facing scripts and this README into
your MITgcm `verification/` directory (except `Dockerfile`, which is copied
rather than symlinked, since Docker requires a real file as its build context).

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
   `linux_amd64_gfortran`); the image locates the matching OpenMPI headers
   itself.
4. **testreport underneath** — compilation uses `testreport -norun`, runs stage
   inputs the way testreport does, and `compare_results.sh` ports testreport's
   comparison, so results agree with what MITgcm's own test suite reports.
5. **Host-side persistence** — compiled binaries and run output live in
   `<experiment>/build_docker/` and `<experiment>/output_docker/` on your host,
   not inside the (ephemeral, `--rm`) container.

## MPI support

The image includes OpenMPI (`mpicc`, `mpif77`, `mpif90`, `mpirun`) and
NetCDF built with parallel I/O support. Docker runs on a single host, so
multi-node MPI is not supported — only multi-process, single-host runs.

```bash
# Check how many processes an experiment's MPI layout uses
grep -E "nPx|nPy" tutorial_barotropic_gyre/code/SIZE.h_mpi
# nPx = 2, nPy = 2  ->  4 processes total

# Compile with MPI support (prints the process count and the run command)
./experiment_compile.sh tutorial_barotropic_gyre -mpi -j 4

# Run with that many processes
./experiment_run_no_compile.sh tutorial_barotropic_gyre -mpi 4
./compare_results.sh tutorial_barotropic_gyre
```

`-mpi` at compile time passes `-MPI=<nPx*nPy>` to testreport, which builds
from `SIZE.h_mpi` (and any other `*_mpi` files in `code/`) without modifying
the files in `code/`. (testreport's own bare `-mpi` would shrink the layout to
2 processes; the scripts avoid that.) The same architecture-detected optfile is
used for MPI and non-MPI builds.

## Custom code modifications

Two different flags cover two different workflows — don't mix them up:

**`experiment_compile.sh -mods <dir>`** — build the experiment using `<dir>`
instead of its own `code/` directory. `<dir>` replaces `code/` completely, so
start from a copy of `code/` and add or change files in it (e.g. a modified
`kpp_calc.F`). During the build `code/` is temporarily swapped out, and it is
restored afterwards (also when the build fails); on success `<dir>` is saved
as `<experiment>/code_validation/` for reference. **Symlinks inside `-mods` are
dereferenced automatically** — no extra flag needed.

```bash
cp -r lab_sea/code /path/to/project/code_validation
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
`~/.ssh` **read-only** at `/home/mitgcm/.ssh` for TAF license validation.

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

`<path>` should contain the `staf` executable (a warning is printed if it does
not). Because `~/.ssh` is mounted read-only, the container can read license
keys but cannot alter your SSH configuration.

If your project has its own TAF setup notes (build flags, license quirks,
specific experiments), keep those alongside that project rather than in this
standalone repo — this section only covers what these Docker scripts do.

## Comparing results against reference

Every MITgcm verification experiment ships reference output in
`results/output.txt`.

```bash
./experiment_run_no_compile.sh 1D_ocean_ice_column
./compare_results.sh 1D_ocean_ice_column
#   Var      Monitor field            Digits
#   PS       cg2d_init_res            10
#   ...
# > hSIav    seaice_heff_mean         11
#   ...
#   Matching digits: 11
#   Required:        10
#   Status:          ✓ PASS
```

10+ matching digits on the deciding variable is the default pass threshold
(adjustable with `--match N`); fewer usually indicates a compiler/platform
difference or an intentional code change rather than roundoff. Results
depend on the compiler and platform, so a given experiment may match the
reference to a different number of digits on different machines.

## Common workflows

**Sweep several input variants without recompiling:**
```bash
./experiment_compile.sh 1D_ocean_ice_column -j 8
for scenario in baseline warm cold; do
    cp -r 1D_ocean_ice_column/input "1D_ocean_ice_column/input_$scenario"
    # edit each input_$scenario/data as needed
done
for scenario in baseline warm cold; do
    ./experiment_run_no_compile.sh 1D_ocean_ice_column "input_$scenario" -output "output_$scenario"
done
```

**Run a secondary input configuration (as testreport does):**
```bash
./experiment_compile.sh adjustment.cs-32x32x1 -j 8
./experiment_run_no_compile.sh adjustment.cs-32x32x1 input.nlfs -output output_nlfs
./compare_results.sh adjustment.cs-32x32x1 output_nlfs    # uses results/output.nlfs.txt
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

## Testing

```bash
tests/test_script_integration.sh     # argument handling, seconds, no Docker
tests/test_regressions.sh            # regression tests with a mock docker, seconds, no Docker
tests/new_install_stress_test.sh     # full end-to-end check on a fresh MITgcm clone (real Docker)
```

The stress test clones MITgcm, installs these tools the way a new user would,
and checks every documented behaviour against real builds and runs, including
cross-checking `compare_results.sh` against testreport itself. See
[tests/STRESS_TEST.md](tests/STRESS_TEST.md) for options, the list of checks
and how to read the results.

## Troubleshooting

| Problem | Fix |
|---|---|
| Docker build fails | Check Docker is running: `docker info` |
| Compilation is slow | Check CPU allocation: `docker info \| grep CPUs`; increase it in Docker Desktop → Settings → Resources |
| `Binary not found` when running | Compile first: `./experiment_compile.sh <experiment> -j 4` |
| `Compilation FAILED` | Read `<experiment>/<build-dir>/compile.log` |
| `Model did not end normally` | Read the end of `<experiment>/<output-dir>/output.txt` (and `mpirun.log` for MPI runs); usually a missing or wrong input file |
| `-mpi N does not match the build` | Use the process count printed by `experiment_compile.sh -mpi` (`nPx * nPy` from `SIZE.h_mpi`) |
| `Found leftover code_orig/` | A `-mods` compile was interrupted; restore with `cd <experiment> && rm -rf code && mv code_orig code` |
| Scripts stop working after moving the repo | Re-run `./scripts/setup_links.sh /path/to/MITgcm/verification` |
| `-mods`/`-code` rejected | Both require absolute paths to existing directories — relative paths are rejected on purpose |
| "File not found" with custom code under `-code` | Directory likely has symlinks pointing outside it — add `-dereference` (compile's `-mods` does this automatically, no flag needed there) |
| Assembler/toolchain errors | Confirm architecture with `uname -m` and rebuild the image with `./docker_build.sh` |

## License

MIT License — see [LICENSE](LICENSE). This toolset is for use with MITgcm;
MITgcm itself is subject to its own license terms.
