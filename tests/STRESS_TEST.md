# New-install stress test

`tests/new_install_stress_test.sh` checks that this repository works as the
README describes, starting from nothing: it clones MITgcm into a fresh
directory, installs the tools the way a new user would, builds the Docker
image, and then compiles, runs and compares real verification experiments.
Every comparison result is cross-checked against MITgcm's own `testreport`,
run in the same container.

This document is written so that an automated agent can run the test,
decide whether it passed, and triage failures without reading the script.

## Quick reference

| Item | Value |
|---|---|
| Command | `tests/new_install_stress_test.sh` (run from anywhere) |
| Success | exit status `0` **and** `"overall": "PASS"` in `summary.json` |
| Failure | exit status `1`; failing checks have `"status": "FAIL"` |
| Could not start | exit status `2` (bad option, `--workdir` already has `MITgcm/`) |
| Machine-readable results | `<workdir>/summary.json`, `<workdir>/summary.tsv` |
| Per-check logs | `<workdir>/logs/<CHECK-ID>.log` |
| testreport oracle logs | `<workdir>/logs/oracle_<experiment>.log` |
| Typical run time | 2–3 min with a cached image and 16 cores; add ~5 min for a first image build and ~30 s for the GitHub clone |
| Disk space | ~1 GB in the work directory (MITgcm clone + builds) |
| Network | Needed only to clone from GitHub (default) and for a first image build |

The work directory is printed at the start of the run. Unless `--workdir` is
given it is a new directory under `$TMPDIR` (or `/tmp`).

## Prerequisites

- Docker daemon running and usable by the current user (`docker info` works)
- `git`, `bash`, standard Unix tools (awk, sed, grep, find)
- ARM64 or x86_64 host
- Network access to GitHub, or a local MITgcm repository passed with
  `--mitgcm-src`

## Running it

```bash
# Full test against the latest MITgcm on GitHub
tests/new_install_stress_test.sh

# Offline / faster: clone from a local MITgcm repository
tests/new_install_stress_test.sh --mitgcm-src /path/to/MITgcm

# Keep results in a known place and remove the clone if everything passed
tests/new_install_stress_test.sh --workdir /tmp/stress --cleanup

# Only some groups (PRE, INS and FIN always run)
tests/new_install_stress_test.sh --groups SER,MPI --skip-build
```

| Option | Meaning |
|---|---|
| `--mitgcm-src <url\|path>` | Repository to clone (default `https://github.com/MITgcm/MITgcm.git`). A local path is cloned with `--depth 1` via `file://`. |
| `--mitgcm-ref <ref>` | Branch or tag to check out (default: the repository's default branch). |
| `--workdir <dir>` | Work directory. Created if missing; must not already contain `MITgcm/`. |
| `--jobs <N>` | `make -j` value (default: number of CPUs, capped at 16). |
| `--groups <G,...>` | Run only these groups: `SER MPI INP CMP MOD INT`. `CMP` automatically adds `SER`. Checks in unselected groups are reported as `SKIP`. |
| `--skip-build` | Do not run `docker_build.sh`; reuse the existing `mitgcm:latest` image. Use only when the image was built from the current Dockerfile. |
| `--cleanup` | If every check passed, delete the MITgcm clone and fixtures at the end (logs and summaries are kept). |
| `--list` | Print the check catalogue and exit. |

### Side effects outside the work directory

- Without `--skip-build`, `docker_build.sh` rebuilds and **re-tags
  `mitgcm:latest`** from this repository's Dockerfile. This is the same image
  the scripts use for normal work.
- Nothing else outside the work directory is modified. The test never touches
  the user's own MITgcm checkout (it clones), and the `~/.ssh` check uses a
  fake `HOME` inside the work directory.
- `$TMPDIR` is set to `<workdir>/tmp` for all scripts, so leftover temp files
  are detectable and contained.

## Experiments used

| Experiment | Why |
|---|---|
| `1D_ocean_ice_column` | Serial build; has a `tr_checklist` whose deciding variable (`hSIav`) is not the first monitor field; source for the negative controls and `-mods` tests. |
| `tutorial_barotropic_gyre` | `SIZE.h_mpi` with nPx=2, nPy=2 → 4 MPI processes. |
| `adjustment.cs-32x32x1` | `input/prepare_run` (links grid files from another experiment), a secondary `input.nlfs` directory layered on `input/`, and `data.exch2.mpi`. |

## Check catalogue

Checks run in the order below. A check whose prerequisite did not `PASS` is
reported as `SKIP` with `detail = "requires <ID> (<status>)"`; the root cause
is always the first `FAIL` above it.

| ID | Requires | What it verifies (README claim) | Pass criteria |
|---|---|---|---|
| PRE-01 | — | Prerequisites | `docker info` and `git --version` succeed |
| INS-01 | PRE-01 | Fresh MITgcm clone | `git clone` succeeds and `verification/1D_ocean_ice_column` exists |
| INS-02 | INS-01 | `setup_links.sh` installs the tools | The 5 scripts are symlinks to this repo's `scripts/`, executable; `Dockerfile` is a real file identical to the repo's |
| INS-03 | INS-02 | `setup_links.sh` can be re-run | Second run exits 0 and reports `already linked` |
| INS-04 | INS-02 | "Every script accepts `-h`/`--help`" | Both flags exit 0 and print usage, for all scripts including `setup_links.sh` |
| INS-05 | INS-02 | `docker_build.sh` builds a working image | Build succeeds; image has gfortran, `mpirun`, and `mpi.h` in `$MPI_INC_DIR` |
| SER-01 | INS-05 | Serial compile | Exit 0; `build_docker/mitgcmuv`, `compile.log`, `build_info.txt` with `MPI=false`; no `tr_*` directories left in `verification/` |
| SER-02 | SER-01 | Serial run | Exit 0; `output.txt` contains `Execution ended Normally`; `run_info.txt` records `INPUT_DIR=input` |
| SER-03 | SER-02 | "`compare_results.sh` uses the same algorithm as testreport" | `compare_results.sh` exits 0 **and** its matching digits equal testreport's for the deciding variable |
| MPI-01 | INS-05 | `-mpi` builds for nPx·nPy from `SIZE.h_mpi` without modifying `code/` | Exit 0; `build_info.txt` has `MPI=true`, `NPROCS=nPx*nPy`; hint shows `-mpi N`; no tracked file in `code/` changed |
| MPI-02 | MPI-01 | `-mpi N` run | Exit 0; exactly N `STDOUT.*` files; `output.txt` identical to `STDOUT.0000`; normal end |
| MPI-03 | MPI-02 | MPI comparison | `compare_results.sh` PASS and digits equal `testreport -MPI=N` |
| MPI-04 | MPI-01 | Process-count mismatch is rejected | `-mpi <wrong N>` and a missing `-mpi` both exit non-zero with the correct hint |
| INP-01 | INS-05 | `prepare_run` is executed; comparison for `input/` | Run exit 0; `tile001.mitgrid` linked by `prepare_run`; compare PASS with digits equal testreport's |
| INP-02 | INP-01 | `input.<X>` layered over `input/`; reference `output.<X>.txt` | `data` links to `../input.nlfs/data`, `bathy_f2.bin` to `../input/bathy_f2.bin`; compare uses `results/output.nlfs.txt`, PASS, digits equal testreport's `adjustment.cs-32x32x1.nlfs` |
| INP-03 | SER-01 | No stale inputs across runs; model errors are reported | After a run with `input/`, a run in the same output dir with an input copy lacking `data.kpp` has no `data.kpp` link, exits non-zero with `did not end normally`, and the model log mentions `data.kpp` |
| CMP-01 | SER-02 | `compare_results.sh` detects bad output | An identical copy PASSes; 1 %-perturbed, truncated, all-NaN and empty outputs each FAIL |
| CMP-02 | SER-02 | `compare_results.sh` works from any directory | Running it via its full path from the work directory exits 0 |
| MOD-01 | INS-05 | `-mods` (symlinks dereferenced), `-build`, `-output`, `code_validation/` | A mods dir of symlinks plus an instrumented `packages_boot.F` compiles; `code/` unchanged, no `code_orig/`, `code_validation/` has real files, `$TMPDIR` empty; the marker appears only in the mods run; that run still matches the reference |
| MOD-02 | INS-05 | Failed `-mods` compile cleans up | A mods dir with invalid Fortran exits non-zero; `code/` restored, no `code_orig/`, `$TMPDIR` empty, `compile.log` present |
| MOD-03 | INS-02 | Nonexistent `-mods` is rejected | Exit non-zero with `does not exist`; the path is not created |
| INT-01 | INS-05 | `docker_run_interactive.sh` (piped stdin) | Starts in `/mitgcm/verification`, `$OPTFILE` set, MITgcm mounted, a manual `genmake2`/`make depend`/`make` build produces `mitgcmuv` |
| INT-02 | INS-05 | `-code` / `-dereference` | Without `-dereference` the external symlinks dangle in the container; with it they are real files; temp dir removed |
| INT-03 | INS-05 | `-taf_dir` and read-only `~/.ssh` | `staf` resolves to `/taf/staf` and runs (mock `staf`); `~/.ssh` readable but not writable in the container |
| FIN-01 | INS-01 | The scripts leave the MITgcm checkout clean | No tracked-file changes (`git status --untracked-files=no`), no `code_orig/`, no `tr_*` directories |

A real TAF installation is not needed: INT-03 uses a mock `staf` script and
verifies only what the scripts do (mount, `PATH`, read-only `~/.ssh`).

## Output formats

### `summary.json`

Example (comments added for explanation; the real file is plain JSON):

```jsonc
{
  "overall": "PASS",               // "PASS" if no check FAILed, else "FAIL"
  "passed": 25, "failed": 0, "skipped": 0,
  "seconds": 138,
  "workdir": "/tmp/mitgcm_stress.AbC123",
  "repository_commit": "<commit of this repo>",
  "repository_dirty": false,        // true = run with uncommitted changes
  "mitgcm_source": "https://github.com/MITgcm/MITgcm.git",
  "mitgcm_commit": "<commit of the clone>",
  "arch": "x86_64",
  "checks": [
    {"id": "SER-03", "group": "SER", "status": "PASS", "seconds": 16,
     "description": "Serial compare == testreport",
     "detail": "11 digits (testreport: 11)", "log": "logs/SER-03.log"}
  ]
}
```

`status` is one of `PASS`, `FAIL`, `SKIP`. `detail` is empty or a one-line
reason: for `FAIL` the failed condition, for `SKIP` the missing prerequisite
or unselected group, for some `PASS` checks extra facts (digits, process
count, commit).

### `summary.tsv`

Header `id  status  seconds  description  detail`, one tab-separated line per
check in execution order.

### Logs

`logs/<ID>.log` holds everything the check ran (commands are prefixed with
`+ `), the script output, and a final line `### result: <STATUS> <detail>`.
The line starting `CHECK FAILED:` names the condition that failed. The
testreport oracle runs are in `logs/oracle_<experiment>.log`; their summary
line looks like `Y Y Y Y>13<16 16 ... pass  tutorial_barotropic_gyre`,
where the number between `>` and `<` is the deciding variable's digits.

## Interpreting results

- **PASS** means the tools behave as documented on this machine, with this
  MITgcm version and this image.
- **Digits differ from testreport** (SER-03, MPI-03, INP-01/02 detail
  `compare_results.sh says X digits, testreport says Y`): a bug in
  `compare_results.sh` or in how inputs are staged by
  `experiment_run_no_compile.sh`; the model output itself is shared.
- **Both give low digits** (compare FAIL but digits equal testreport's): the
  platform/compiler differs from the one that produced the reference output.
  This is a property of MITgcm on this platform, not of these scripts; check
  whether `testreport` alone reports `FAIL` in `logs/oracle_<experiment>.log`.
- **`repository_dirty: true`**: the result describes uncommitted local
  changes, not a released commit.
- **Everything after INS-05 is SKIP**: the image could not be built or
  verified; see `logs/INS-05.log` (usually Docker not running, no network for
  `apt-get`, or too little disk space).

## Triage guide

| Failing check | First look at | Common causes |
|---|---|---|
| PRE-01 | `logs/PRE-01.log` | Docker not running; user not in `docker` group |
| INS-01 | `logs/INS-01.log` | No network; wrong `--mitgcm-src`/`--mitgcm-ref` |
| INS-05 | `logs/INS-05.log` | apt mirrors unreachable during build; Docker disk full |
| SER-01, MPI-01, INP-01 compile | `<workdir>/MITgcm/verification/<exp>/build_docker/compile.log` | Optfile/compiler incompatibility with this MITgcm version |
| SER-02, MPI-02, INP-01 run | `<workdir>/MITgcm/verification/<exp>/output_docker/output.txt` (and `mpirun.log`) | Missing input files; too few CPUs for MPI (runs use `--oversubscribe`) |
| MPI-01 "modified tracked files" | `git -C <workdir>/MITgcm status` | Compile script writing into `code/` |
| MOD-01/02 temp files | `ls <workdir>/tmp` | Temp dereference directory not cleaned up |
| INT-* | `logs/INT-*.log` | Docker cannot mount the path (Docker Desktop file-sharing settings on macOS) |
| FIN-01 | `git -C <workdir>/MITgcm status`, `find <workdir>/MITgcm/verification -name code_orig` | A script modified or left files in the checkout |

The MITgcm clone is left in place after a failure (even with `--cleanup`), so
builds and outputs can be inspected under `<workdir>/MITgcm/verification/`.
Test-created directories use the prefix `*_stress_*` (e.g.
`output_stress_mods`, `build_stress_broken`).

## Related tests

| Script | Docker | Time | Purpose |
|---|---|---|---|
| `tests/test_script_integration.sh` | no | seconds | Argument handling of the run and compare scripts |
| `tests/test_regressions.sh` | no (mock `docker`) | seconds | One or more tests per fixed bug; asserts exact docker arguments (e.g. `:ro`, `-MPI=4`) |
| `tests/new_install_stress_test.sh` | yes | minutes | End-to-end behaviour on a fresh install, verified against testreport |

Run the two fast suites after every change; run the stress test before a
release or after changing the Dockerfile or any script's container commands.

## Adding a check

1. Write a function `check_<GROUP>_<NN>()` in the script. Use
   `cond || fail "reason" || return 1` for each assertion and `note "..."`
   for extra detail on success. Output goes to the check's log.
2. Register it in the main section with
   `run_check <ID> <GROUP> "<description>" check_<GROUP>_<NN> [required IDs...]`.
3. Add it to `list_checks` and to the catalogue table above.
