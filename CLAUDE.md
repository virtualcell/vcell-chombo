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

## What is missing

- **MPI.** `OPTION_TARGET_PARALLEL` carries the old plumbing and warns at
  configure time. It is untested, and the release is serial only.
- **Windows.** No build yet; `conanfile.py` still rejects it. Two attempts are
  on record. Both were done on throwaway branches; the findings live here
  rather than on them.

  *MinGW-w64* (`windows-ci`, Aug 2026) built the entire Conan dependency tree
  and then hit **four** independent failures, not the single `AMRTools` one
  this file used to claim:

  - `j1()` is absent from mingw-w64's `<math.h>` (it is POSIX XSI). MSVC
    declares it as a deprecated alias for `_j1`, which is why
    `vcell-stochastic` builds the same `vcell-expressionparser` commit on
    Windows without a fix — the gap is MinGW's, not Windows'.
  - `sigaction` in `AMRTimeDependent/AMR.cpp` — a library `CHOMBO_LINK_ORDER`
    never links, but `make lib` builds anyway.
  - `fork`/`pipe` in `BaseTools/CH_Attach.cpp`, dead code whose only callers
    are commented out in Chombo's own tests.
    `BoxTools/VisItPythonConnection.cpp` and `BaseTools/memusage.cpp` are the
    same shape.
  - `std::integral` colliding with Chombo's `integral()` in
    `AMRTools/NodeIntegrals.cpp`, because `CH_Timer.H` and `Tuple.H` do
    `using namespace std;` at global scope and MSYS2's GCC 16 defaults to
    C++20 or later. Not a Windows problem at all — pin Chombo's own build to
    `-std=gnu++17` and it matches what GCC 13 already gives Linux and macOS.

  *clang-cl/flang* (`probe/clang-flang`, Oct 2026) follows `vcell-fvsolver`,
  which builds 167 fixed-form `.f` files plus a pybind11 wheel that way. A
  Linux probe holding `CXX=g++-13` constant and swapping only the Fortran half
  showed flang compiles ChomboFortran's generated output: 41 files, all nine
  linked libraries, zero Fortran errors. `clang -E -P -C` output is
  byte-identical to `g++ -E -P -C`'s apart from the 33-line `stdc-predef.h`
  comment block GCC implicitly includes and clang does not. Two things that
  route needs:

  - `-x c` on `CH_CPP`. There is one `.F` file, `AMRTools/CFLeastSquares.F`,
    and `Make.rules:443` pushes it through `$(CH_CPP)`. clang's driver
    recognises `.F` as Fortran, cannot compile it, and delegates to `gcc`,
    which dispatches to gfortran, which refuses `-E` without `-cpp` — so the
    error names gcc from a step that never mentions it. `-x c` says
    "preprocess this as text", which is all the pipeline ever meant.
  - ChomboFortran emitted its `subroutine` line with one leading space, putting
    the `s` in column 2 — inside fixed form's 1–5 label field. gfortran accepts
    that silently and flang 21 only warned, but **flang 22 rejects it outright**
    (`Character in fixed-form label field must be a digit`, with no warning
    group to suppress), and Windows flang starts at 22. `fort72` now pads such
    lines to column 7. It pads only a first non-blank in columns 1–5 that is
    not a digit: a numeric label belongs in that field, and **column 6 is the
    continuation marker** — Chombo's hand-written `.ChF` uses `$` there as well
    as the `     &` fort72 emits, and a rule reaching column 6 silently turns a
    continuation into a new statement. Measured before and after across 40
    generated files: exactly one line changes per file, and the regression
    baselines still match bit for bit.
  - flang cannot be paired with GCC as the ChomboFortran preprocessor, and this
    one is worth knowing before it happens. `g++` implicitly includes
    `stdc-predef.h`, the mandatory `-C` keeps its comments in the generated
    `.f`, and the apostrophe in `glibc's intent ...` reads to flang's
    fixed-form scanner as an unclosed character literal — a syntax error
    pointing at a copyright notice in a file nobody wrote. gfortran survives it
    only because its own `-cpp` pass strips C comments; flang's does not. clang
    never injects the header, so clang is the preprocessor to use; configuring
    the bad pairing is now a `FATAL_ERROR` rather than that scanner error.
- **VCell-generated inputs.** Every input in `tests/resources/` is
  hand-written. None has yet come out of VCell's `FiniteVolumeFileWriter`.
