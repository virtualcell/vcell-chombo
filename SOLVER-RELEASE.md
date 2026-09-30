# Solver release contract

vcell-chombo ships the way every VCell solver repository does, so that VCell can
consume it without per-solver special cases: desktop builds download a release
archive into `localsolvers/<platform>/`, and the cluster runs a SIF chosen by
vcell-fluxcd's submit configuration. The contract is section 1 of VCell's
[`docs/plan-solver-repos.md`](https://github.com/virtualcell/vcell/blob/master/docs/plan-solver-repos.md).
This file records how this repository meets it, and the choices made where the
contract left room.

Everything here is produced by [`.github/workflows/release.yml`](.github/workflows/release.yml).
Pull requests run all of it and publish nothing. A `vX.Y.Z` tag on `main`
publishes.

## Releases

Tag `main` with `vX.Y.Z`. The workflow attaches:

| asset | contents |
|---|---|
| `linux64.tgz` | x86_64, built on `manylinux_2_28` with gcc-toolset-13. Needs glibc 2.28 or newer, which the build checks. |
| `linux64arm.tgz` | aarch64, built the same way |
| `mac64.tgz` | universal binaries (arm64 + x86_64), built with Homebrew GCC 13 and merged with `lipo`, ad-hoc signed |
| `SHA256SUMS` | a checksum for each of the three archives |

There is **no `win64.zip`**. Chombo's build system needs GNU make, perl and a
Unix shell, so `conanfile.py` rejects Windows. The MinGW-w64 port on the
`windows-ci` branch gets as far as Chombo's `AMRTools` and then stops on an
overload ambiguity. VCell on Windows has never had a working Chombo, so
nothing is lost.

## Archive layout

Every archive is flat, with everything at its root:

```
VCellChombo2D_x64          the solvers, under the names VCell resolves
VCellChombo3D_x64            (SolverExecutable.VCellChombo + _x64)
libgfortran.so.5 ...       bundled GCC runtime (Linux: libgfortran, libquadmath, libz;
                             macOS: libgfortran, libquadmath, libstdc++, libgcc_s)
LICENSE                    this repository's licence (MIT)
THIRD-PARTY-LICENSES/      Chombo (BSD, notice required in binary redistributions),
                             vcell-messaging, vcell-expressionparser, and every
                             Conan package linked in (HDF5, libzip, zlib, libcurl, ...)
VERSION                    the release version, e.g. 1.0.0
```

There are no test binaries and no static libraries.

- **Linux.** The Conan dependencies are linked statically. `packaging/bundle-linux.sh`
  walks the executables' `ldd` closure and copies everything that is not glibc,
  `libstdc++` or `libgcc_s` next to them. It then sets `RUNPATH=$ORIGIN` on
  every ELF file, and fails the build if any file needs a `GLIBC_` symbol
  version newer than 2.28. `libstdc++` and `libgcc_s` count as system libraries
  here: gcc-toolset links the newer parts of libstdc++ statically, so the
  binaries need only the GCC 8 ABI that every glibc-2.28-era distribution
  ships.
- **macOS.** `packaging/bundle_macos.py` copies the non-system dylib closure
  (Homebrew's GCC runtime) into the archive and renames each copy
  `@rpath/<name>`. It leaves `@loader_path` as the only `LC_RPATH` and re-signs
  every file ad hoc. `packaging/make-universal.sh` then `lipo`s the arm64 and
  x86_64 stages together. No file refers to `/opt/homebrew` or `/usr/local`.
  The bundled GCC runtime comes from Homebrew's bottles for the build runner's
  macOS, 15 at present, so that is the effective minimum macOS version.

## Container image and SIF

- `ghcr.io/virtualcell/vcell-chombo:<X.Y.Z>` and `:latest`, for linux/amd64 and
  linux/arm64. `docker/Dockerfile` has no build stage: it is the Linux release
  archive, unpacked into `/opt/vcell-chombo` (on `PATH`), on
  `debian:bookworm-slim`. The image therefore carries exactly the release
  binaries, and it is small.
- `ghcr.io/virtualcell/vcell-chombo_singularity:<X.Y.Z>` and `:latest`, amd64,
  built from the image with `apptainer build` and pushed with ORAS.
- **Messaging is on** (`-DOPTION_TARGET_MESSAGING=ON`) in every build: the
  archives, the image and the SIF. The solver takes a trailing `-tid <n>` and
  reports status to the broker named in the input's `JMS_PARAM` block, over
  plain HTTP to its REST bridge. libcurl is therefore built without TLS
  (`conanfile.py`).
- `HDF5_USE_FILE_LOCKING=FALSE` is set in the image, because the solver writes
  HDF5 onto bind mounts.
- **Serial only.** Parallel (MPI) Chombo is a follow-up. It needs an MPI build
  (`OPTION_TARGET_PARALLEL`, untested since the split), an MPI-enabled image,
  and Slurm changes on VCell's side.

### Entry point

`/usr/local/bin/vcell-solver-entrypoint` (`docker/entrypoint.sh`) has
`ENTRYPOINT [...]` and `CMD ["--help"]`:

| arguments | behaviour |
|---|---|
| none, `--help`, `-h` | prints the version and the executables, and exits 0 |
| `VCellChombo2D_x64 ...` or `VCellChombo3D_x64 ...` | `exec`s the solver with those arguments unchanged, so its exit code and SIGTERM pass through |
| anything else | prints usage on stderr and exits 2 |

The entry point writes nothing, and it works as any uid. The solver writes its
results next to `BASE_FILE_NAME`, plus one scratch file (each timepoint's
`.sim.hdf5`, before zipping) in the current directory. If the current
directory is not writable, as can happen in a read-only SIF, the entry point
first makes any relative input path absolute and then starts the solver in
`$TMPDIR` (default `/tmp`). VCell always writes an absolute `BASE_FILE_NAME`,
so the results go to the same place in either case.

SlurmProxy's command line works as written:

```
singularity run --containall <binds> <env> vcell-chombo_singularity_<X.Y.Z>.sif \
    VCellChombo3D_x64 /simdata/<user>/SimID_<key>_0_.fvinput -tid <n>
```

## Checks

`tests/release/check_release.py` runs the shipped binaries with nothing from
the build tree. It needs only numpy and h5py on the host. It has four targets:

- an unpacked archive, run by an unprivileged user (Linux x86_64 and aarch64,
  and the universal mac archive on both arm64 and x86_64 runners);
- the image, run as the caller's uid;
- the SIF, run under `apptainer run --containall --bind <work>:/simdata` with a
  bare executable name, `/simdata` paths and `-tid 0`, as SlurmProxy runs it.

Every run passes `-tid 0` and points the input at a fake broker REST bridge. It
must report starting, progress and completed, and no failure. The cases, in 2D
and in 3D:

| case | what must hold |
|---|---|
| usage | no input: usage printed, non-zero exit |
| smoke | the `.log`, `.mesh.hdf5` and `.hdf5.zip` VCell reads are written. The run happens under a path longer than 256 characters, which overran the old 128-byte path buffers. |
| regression | the final timepoint matches `tests/resources/regress<N>d.baseline.txt` (rtol 1e-9, atol 1e-12) |
| analytic | the error against the closed-form solution is the one the scheme predicts, to within 15% (`tests/README.md`) |
| reference | two species exchange across the embedded-boundary membrane (`tests/resources/reference<N>d.fvinput`). The summed total stays constant while mass crosses. |

RESULTS_PLACEHOLDER
