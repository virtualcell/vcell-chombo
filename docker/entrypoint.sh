#!/bin/sh
# vcell-solver-entrypoint -- the standard VCell solver-image entry point
# (SOLVER-RELEASE.md; VCell's docs/plan-solver-repos.md section 1.5).
#
#   <image>                      print the version and the executables, exit 0
#   <image> --help               the same
#   <image> VCellChombo2D_x64 /simdata/<user>/SimID_<k>_0_.fvinput -tid <n>
#                                exec that solver with exactly those arguments
#   <image> anything-else        usage on stderr, exit 2
#
# SlurmProxy runs the SIF as
#   singularity run --containall <binds> <env> <sif> <executable> <args> -tid <n>
# so the first argument is a bare executable name and the paths are container
# paths under /simdata. `exec` keeps the solver as the container's main process:
# its exit code and SIGTERM (a Slurm cancel) pass straight through.
#
# Nothing here writes anywhere. The solver itself writes its results next to
# BASE_FILE_NAME, and one scratch file, the per-timepoint .sim.hdf5 it zips
# into the results, in the current directory. Under a read-only SIF the
# current directory may not be writable, so when it is not, the solver is
# started in $TMPDIR instead, with a relative input-file argument made
# absolute first. VCell always writes an absolute BASE_FILE_NAME, so the
# results land in the same place either way.
set -eu

root=/opt/vcell-chombo
exes="VCellChombo2D_x64 VCellChombo3D_x64"

describe() {
	echo "vcell-chombo $(cat "$root/VERSION" 2>/dev/null || echo unknown)"
	echo "Chombo embedded-boundary finite-volume solver for the Virtual Cell (serial; messaging on)"
	echo
	echo "executables:"
	for e in $exes; do echo "  $e"; done
	echo
	echo "usage: <image> <executable> [-tid <taskID>] <input.fvinput>"
	echo "       <image> <executable> -ccd <input.fvinput>   (convert Chombo output to VCell output)"
}

case "${1-}" in
	"" | --help | -h)
		describe
		exit 0
		;;
esac

for e in $exes; do
	if [ "$1" = "$e" ]; then
		if ! { [ -w . ] && [ -x . ]; } 2>/dev/null; then
			here=$(pwd)
			exe=$1
			shift
			for a in "$@"; do
				shift
				case "$a" in
					-* | /*) set -- "$@" "$a" ;;
					*) if [ -e "$here/$a" ]; then set -- "$@" "$here/$a"; else set -- "$@" "$a"; fi ;;
				esac
			done
			set -- "$exe" "$@"
			cd "${TMPDIR:-/tmp}"
		fi
		exec "$@"
	fi
done

{
	echo "vcell-solver-entrypoint: unknown executable '$1'"
	echo
	describe
} >&2
exit 2
