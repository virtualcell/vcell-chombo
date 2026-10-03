# CLAUDE.md

Guidance for Claude Code (claude.ai/code) working in this repository. Read
`README.md` first — it covers what the project is, how to build it, and the
provenance of the split. This file records the things that are easy to get wrong.

## Orientation

Two executables, one source tree: `VCellChombo2D_x64` and `VCellChombo3D_x64`,
identical sources compiled with `CH_SPACEDIM=2` or `3` against that dimension's
Chombo libraries. VCell launches them as subprocesses against a `.fvinput` file.

`VCellChombo/src/` splits roughly into:

- `FiniteVolume.cpp` — `main`, argument handling, `vcellExit`.
- `FVSolver.cpp` — the `.fvinput` parser. One `load*` method per block
  (`SIMULATION_PARAM_BEGIN`, `MODEL_BEGIN`, `CHOMBO_SPEC_BEGIN`,
  `VARIABLE_BEGIN`, `COMPARTMENT_BEGIN`, `MEMBRANE_BEGIN`, …). The block-comment
  above each method is the format documentation; there is no schema elsewhere.
- `ChomboScheduler.cpp` / `ChomboSemiImplicitScheduler.cpp` — geometry, EB mesh
  generation and the time loop. This is where most of the volume is.
- `ChomboGeometry.cpp` / `ChomboIF.cpp` — the implicit-function geometry.
  `ChomboIF` is a Chombo `BaseIF` backed by two `vcell-expressionparser`
  expressions per subdomain.
- `SimTool.cpp` — the run driver: output files, the `.log`, `.hdf5.zip`
  archiving, progress messaging, the `.tid` lock.
- `DataSet.cpp` / `PostProcessingHdf5Writer.cpp` — HDF5 output (C API only; the
  C++ API is not used anywhere, and `hdf5_cpp` is deliberately not linked).
- `ZipUtils.cpp` — libzip wrapper, added during the split.

## Things that will bite you

**Chombo compile definitions must match the libraries.** `CH_USE_64`,
`CH_USE_COMPLEX`, `CH_USE_DOUBLE`, `CH_USE_HDF5`, `CH_USE_SETVAL`,
`CH_USE_MEMORY_TRACKING` and friends change struct layouts and inline function
bodies in Chombo's headers. `VCellChombo/CMakeLists.txt` sets them to match what
`cmake/BuildChomboLibs.cmake` passes to Chombo's make. Changing one side without
the other is an ODR violation that links cleanly and then misbehaves at runtime.

**The Fortran compiler must preprocess.** ChomboFortran generates `.f` via
`g++ -E -P -C`, and `-C` is deliberate: without it the preprocessor would treat
Fortran's `//` string-concatenation operator as a comment. The cost is that C
comment blocks survive into the `.f` — starting with gcc's implicitly included
`stdc-predef.h` — and only the Fortran compiler's own `-cpp` pass removes them.
`BuildChomboLibs.cmake` appends `-cpp` to `FC` for exactly this reason. Drop it
and every ChomboFortran file fails with "Non-numeric character in statement
label".

**2D and 3D share `chombo/lib`.** Generated `*_F.H` headers and `lib/include` are
dimension-dependent and get overwritten. The builds are serialized
(`add_chombo_dimension(3 DEPENDS chombo_2d)`) and each snapshots its headers into
`build/chombo/<dim>d/include/`. Never point a solver target at
`chombo/lib/include` directly.

**Chombo's config string carries the full compiler names.** The archives and
the `o/`, `f/`, `p/` and `d/` directories are named for `$(CXX)` and `$(FC)`
exactly as passed — `2d.Linux.64.g++-13.gfortran-13.OPT` if that is what you
gave it. The CMake path looks different only because
`_chombo_compiler_name()` in `BuildChomboLibs.cmake` deliberately strips them
to `g++`/`gfortran`, since Chombo matches basenames to pick its flag sets.
Anything that matches those directory names has to cope with both forms.

**Chombo's HDF5 guards are inconsistent.** `EBAMRIO.H` declares
`writeEBLevelname` and `writeEBAMRname` inside `#ifdef CH_USE_HDF5`, but
`EBConductivityOp::dumpAMR`/`dumpLevel` and `EBAMRPoissonOp::dumpAMR`/
`dumpLevel` call them unguarded, while `EBViscousTensorOp.H` guards its
equivalents. Every real build is `USE_HDF=TRUE`, so this never shows — but a
`USE_HDF=FALSE` build fails in `EBAMRElliptic` for a reason unrelated to
whatever you were changing.

**Chombo's build leaks into the source tree.** `chombo/lib/*.a`,
`chombo/lib/include/`, `chombo/lib/src/*/{o,d,f,p}/` and generated `*_F.H` are
all gitignored build products. If `CollectChomboLibs.cmake` reports finding two
candidate archives for one library, that is stale output from a different
configuration — clean the tree.

**GCC, not Clang — on Linux and macOS.** gfortran's runtime links against
libstdc++, so those builds have to be a libstdc++ world. Do not copy
vcell-ode's Clang/libc++/mold profile here. Windows is the exception and is
heading the other way, to clang-cl and flang: MSVC has no Fortran at all, and
CPython's Windows ABI rules out MinGW for the eventual pybind11 wheel. See
*What is missing*.

## Modifying Chombo

`chombo/` is vendored and locally patched. Prefer surgical, well-commented edits
over an upstream re-sync — upstream Chombo has moved on and VCell's copy carries
its own fixes going back years ("Terry's fix for our version of chombo"). Every
change made during the split is commented in place explaining why.

## Submodules

`vcell-expressionparser` and `vcell-messaging` are shared with `vcell-ode`. A fix
made here has to go upstream to `virtualcell/<name>` before this repo can be
cloned by anyone else — bumping the gitlink to a commit that only exists locally
produces a checkout nobody else can resolve.

Both require C++20 (`std::format`), which is why the whole project is C++20 even
though Chombo itself is much older code.

## Input files

`tests/resources/smoke{2,3}d.fvinput` are hand-written and were built by reading
`FVSolver.cpp`; VCell normally generates these. Two non-obvious points if you
write another one:

- Each subdomain carries **two** expressions. `IF` is a level set — negative
  inside — and `USER` is a boolean predicate, non-zero inside. `ChomboIF::value`
  cross-checks them and aborts the run on disagreement, so they have to describe
  the same region in their two different conventions.
- `TIME_STEP` is not a recognized token in this solver (unlike the FV solver's
  input format). Use `TIME_INTERVALS`.

## Releases

`SOLVER-RELEASE.md` is the source of truth for what a release contains and how
it is checked. `.github/workflows/release.yml` builds it. Things that bite:

- The Linux release builds in `manylinux_2_28` with gcc-toolset-13, and
  compiles the whole Conan tree from source (`--build="*"`), because Conan
  Center's Linux binaries need a newer glibc. `packaging/bundle-linux.sh`
  fails the build if any file needs a glibc newer than 2.28.
- The macOS dylibs are bundled, not static. After changing link flags, check
  that `packaging/bundle_macos.py` still finds everything; it fails on any
  reference outside the archive.
- `tests/release/check_release.py` is the release-level test. ctest is the
  build-level one. Keep the two in step when you add an input.

## The Windows build

clang-cl and flang, not MSVC and not MinGW: MSVC has no Fortran compiler, and
MinGW is ruled out by CPython's MSVC/UCRT ABI for the eventual pybind11 wheel.
`conan-profiles/CI-CD/Windows-AMD64_profile.txt` and `SOLVER-RELEASE.md` carry
the rest. Messaging is off; the archive needs no bundler, because everything is
statically linked and `packaging/check-windows.ps1` fails the build if that
stops being true.

MSYS2 is part of the build and is not a leftover of the abandoned MinGW
attempt. ChomboFortran is perl and `chombo/lib/mk` needs GNU make and a shell
with `pipefail` whoever compiles, so MSYS2 supplies those as build tools while
nothing it ships compiles anything. Its `usr/bin` goes on `PATH` for the build
step only, because Chombo's recipes call `find`, `chmod`, `cp`, `sort` and
`uniq` bare and expect GNU semantics — and because that same directory holds a
coreutils `link.exe` which would shadow MSVC's linker, so `windows.yml` renames
it first.

Things specific to this toolchain that cost a round each to find:

- **`CH_CPP` needs `-x c` under clang.** There is one `.F` file,
  `AMRTools/CFLeastSquares.F`, and `Make.rules:443` pushes it through
  `$(CH_CPP)`. clang's driver recognises `.F` as Fortran, cannot compile it, and
  delegates to `gcc`, which dispatches to gfortran, which refuses `-E` without
  `-cpp` — so the error names two compilers the failing step never invoked.
- **flang cannot be paired with GCC as that preprocessor.** `g++` implicitly
  includes `stdc-predef.h`, the mandatory `-C` keeps its comments in the
  generated `.f`, and the apostrophe in `glibc's intent ...` reads to flang's
  scanner as an unclosed character literal. gfortran survives only because its
  own `-cpp` pass strips C comments; flang's does not. Configuring that pairing
  is a `FATAL_ERROR` naming the cause.
- **clang-cl ignores GNU-style flags rather than rejecting them.**
  `-std=gnu++17` and `-funroll-loops` produced "unknown argument ignored" and
  did nothing, so the standard pin was silently inert.
  `BuildChomboLibs.cmake` picks the spelling from
  `CMAKE_CXX_COMPILER_FRONTEND_VARIANT`.
- **MSVC's STL honours removals libstdc++ does not.** `std::ptr_fun` and
  `std::bind2nd` in `BaseTools/IndexTMI.H` were removed in C++17; libstdc++
  keeps them, MSVC gates them behind `_HAS_AUTO_PTR_ETC`. That is a reprieve,
  not a fix.
- **`CH_USE_MEMORY_TRACKING` has to follow Chombo per platform.** `USE_MT?=TRUE`
  is the default and Chombo's own `Darwin` block overrides it to `FALSE`, so the
  libraries carry tracking everywhere except macOS. Windows resolves `$(system)`
  to `CYGWIN`, which gets no override. Getting this wrong is an ODR violation
  that links cleanly: the macro takes `class Arena` from 8 bytes to 144, and
  `BaseFab<T>::define` is a header template, so `new BArena(...)` is sized in
  whichever translation unit instantiates it.

`.github/workflows/windows-asan.yml` is a dispatch-only AddressSanitizer build.
It is what found that ODR violation, and its header records the five
non-obvious things about clang-cl's ASan on Windows that getting it to run cost.

## What is missing

- **MPI.** `OPTION_TARGET_PARALLEL` carries the old plumbing and warns at
  configure time. It is untested, and the release is serial only.
- **Windows is built now**, so it is no longer on this list; see *The Windows
  build* below for what it took and what stays true.
- **VCell-generated inputs.** Every input in `tests/resources/` is
  hand-written. None has yet come out of VCell's `FiniteVolumeFileWriter`.
