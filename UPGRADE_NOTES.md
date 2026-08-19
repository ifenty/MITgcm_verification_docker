# MITgcm Verification Docker - Architecture Upgrade

## What Changed

The Docker tool has been upgraded from a **copy-based** to a **mount-based** architecture, enabling users to modify MITgcm source code and input files without rebuilding the Docker image.

### Before (Copy-based)
- MITgcm source copied into Docker image at build time
- Source modifications required rebuilding Docker image (~5 min)
- Users couldn't easily modify code/input files

### After (Mount-based)
- Docker image contains only compilers + libraries
- MITgcm source mounted from host at runtime
- Modify code/inputs freely, recompile instantly
- No Docker rebuild needed

## Key Benefits

✅ **Instant code changes** - Edit MITgcm source, recompile immediately  
✅ **Custom experiments** - Add instrumentation, modify physics  
✅ **Faster iteration** - No 5-minute Docker rebuild penalty  
✅ **Smaller image** - Image is ~400MB instead of ~2.5GB  
✅ **Multiple MITgcm versions** - Easy to switch between different MITgcm checkouts

## What You Need to Do

### First Time Setup

1. **Rebuild Docker image** (one time, ~2-3 min):
   ```bash
   # Run from your MITgcm verification directory (scripts are symlinked there)
   cd /path/to/MITgcm/verification
   ./docker_build.sh
   
   # Or from the repository root
   cd /path/to/MITgcm_verification_docker
   ./scripts/docker_build.sh
   ```

2. **Done!** The new image is ready to use with any MITgcm installation.

**Note:** The `docker_build.sh` script now properly resolves symlinks, so it works correctly whether run from the verification directory (via symlink) or from the repository root.

### Using the Tool

**No changes to your workflow!** Commands remain the same:

```bash
cd /path/to/MITgcm/verification

# Compile (uses your local MITgcm source)
./experiment_compile.sh lab_sea -j 12

# Run (uses your local MITgcm source)
./experiment_run_no_compile.sh lab_sea
```

### Key Difference

- **Old**: Docker used a frozen copy of MITgcm from image build time
- **New**: Docker uses your current MITgcm source from the host filesystem

This means:
- ✅ Modify `pkg/kpp/kpp_calc.F` → recompile → changes take effect
- ✅ Edit `verification/lab_sea/input/data` → rerun → changes take effect
- ✅ Add new experiments to verification/ → immediately available

## Technical Details

### Docker Image Changes

**Dockerfile**:
- Removed: `COPY . /home/mitgcm/MITgcm`
- Changed: `WORKDIR /mitgcm/verification` (points to mount)
- Changed: `ENV PATH=/mitgcm/tools:$PATH`

### Script Changes

**experiment_compile.sh**:
```bash
# Old: Used MITgcm inside container
cd /home/mitgcm/MITgcm/verification

# New: Mounts host MITgcm
docker run -v "$MITGCM_ROOT:/mitgcm" mitgcm:latest
cd /mitgcm/verification
```

**experiment_run_no_compile.sh**:
```bash
# New: Mounts host MITgcm for input files
docker run -v "$MITGCM_ROOT:/mitgcm" -v "$OUTPUT_DIR:/output" mitgcm:latest
```

### Mount Points

| Host Path | Container Path | Purpose |
|-----------|----------------|---------|
| `$MITGCM_ROOT` | `/mitgcm` | Full MITgcm source (read-write, mounted not copied) |
| `$EXPERIMENT/build_docker` | `/build_output` | Build artifacts |
| `$EXPERIMENT/output_docker` | `/output` | Model output |

**Key Insight:** MITgcm source is mounted as a volume, not copied. This means:
- Files on host = files in container (same inode)
- Edit on host → immediately visible in container
- No need to rebuild Docker image when modifying MITgcm code
- Custom code directories (via `-mods`) are also mounted automatically

## Example: Adding Custom Instrumentation

Before this upgrade, you couldn't easily add instrumentation. Now:

```bash
# 1. Modify MITgcm source
cd /Users/me/MITgcm/pkg/kpp
vim kpp_calc.F  # Add WRITE statements for debugging

# 2. Add custom files
cp my_validation.F /Users/me/MITgcm/verification/lab_sea/code/

# 3. Compile with your changes
cd /Users/me/MITgcm/verification
./experiment_compile.sh lab_sea -j 12

# 4. Run
./experiment_run_no_compile.sh lab_sea > output_with_debug.txt

# Changes are immediate - no Docker rebuild!
```

## Troubleshooting

### "Cannot find MITgcm root directory"
- Ensure you're running scripts from `MITgcm/verification/`
- Or that symlinks are properly set up via `setup_links.sh`

### "Binary not found"
- Run `experiment_compile.sh` first
- Check that `$EXPERIMENT/output_docker/mitgcmuv` exists

### Compilation errors after upgrade
- Clean build directory: `rm -rf $EXPERIMENT/build_docker`
- Recompile: `./experiment_compile.sh $EXPERIMENT -j 12`

### Old binaries not updating
- The new architecture always uses current source
- Old cached binaries are overwritten on recompile

## Backward Compatibility

**Scripts are backward compatible** - if you have the old Docker image, scripts will still work (but won't get the new benefits).

**To get the benefits**: Rebuild the Docker image with `docker_build.sh`.

## Migration Checklist

- [ ] Rebuild Docker image: `./scripts/docker_build.sh`
- [ ] Test compilation: `./experiment_compile.sh lab_sea -j 4`
- [ ] Test run: `./experiment_run_no_compile.sh lab_sea`
- [ ] Verify output: `less lab_sea/output_docker/output.txt`
- [ ] Try modifying source and recompiling

## Questions?

This upgrade enables the workflow needed for:
- KPP Python port validation (add instrumentation to kpp_calc.F)
- Custom physics development
- Debugging with added WRITE statements
- Multiple MITgcm versions/branches

The tool is now much more flexible while maintaining the same simple interface!
