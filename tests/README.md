# Tests

`ctest --test-dir build` runs three tests per solver.

| test | what it proves |
| --- | --- |
| `VCellChombo<N>D_x64_usage` | the binary starts and reports its usage |
| `VCellChombo<N>D_x64_smoke` | a simulation runs end to end and writes the `.log`, `.mesh.hdf5` and `.hdf5.zip` VCell expects |
| `VCellChombo<N>D_x64_regression` | the solver still computes what it used to |

All the inputs are hand-written — VCell normally generates `.fvinput` files — over
the same geometry: a disc (2D) or sphere (3D) of `cyt` inside a box of `ec`, one
volume PDE, zero flux across the membrane, no reaction.

The **smoke** cases start uniform at 1.0 and stay there. That exercises the whole
pipeline cheaply, so it is the first thing to fail when something is broken, but
it is not a numerical check: a uniform field satisfies almost any assertion.

The **regression** cases start as a Gaussian bump, so the field actually
diffuses, and the final timepoint is compared value by value against a stored
baseline. The final timepoint is the sensitive one — error accumulates into it.

## Regenerating a baseline

Only when the numbers are *supposed* to move. A failing regression test is a
question, not a chore.

```bash
ctest --test-dir build -R regression        # produces the run, then fails
./build/bin/compare_solution --write \
    build/tests/regress2d/extracted/SimID_regress2d_0_0004.sim.hdf5 \
    tests/resources/regress2d.baseline.txt
```

The failure message prints this command with the right paths filled in. Say in
the commit message *why* the numbers moved — a baseline updated without an
explanation is indistinguishable from a regression that was papered over.

## Tolerances

`compare_solution` uses a mixed test, `|got - want| <= atol + rtol * |want|`. The
absolute floor matters because these fields contain values at and near zero,
where a pure relative comparison is meaningless. Cells outside the solved region
carry VCell's `1.23456789e+300` sentinel and must match exactly — a change in
which cells are covered is a real regression, not rounding.

Defaults are `rtol=1e-9`, `atol=1e-12`, overridable at configure time:

```bash
cmake -B build -DVCELL_CHOMBO_REGRESSION_RTOL=1e-8 ...
```

What has actually been measured, rather than assumed:

- **Sensitivity.** Perturbing the diffusion coefficient by a relative `1e-6` is
  caught; `1e-10` is not. So these tests detect algorithmic changes without being
  hostage to last-bit noise.
- **Portability.** The baselines are generated on Linux with GCC 13. The same
  source compiled for a different architecture will not reproduce these fields
  bit for bit, and the tolerance that survives that is an empirical question. CI
  runs the same baselines on macOS arm64 and x86_64, so if `rtol` ever needs
  loosening, that is the evidence for it — record the observed worst-case
  relative difference here when it changes.

## What is still missing

These baselines are self-generated: they pin the solver against *itself*, which
catches regressions but says nothing about whether the answers were right in the
first place. Validating against VCell's own integration results, or against an
analytic solution for a case that has one, is the obvious next step.
