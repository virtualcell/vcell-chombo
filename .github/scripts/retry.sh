#!/usr/bin/env bash
# Run a command, retrying a bounded number of times:
#
#   .github/scripts/retry.sh <attempts> <delay-seconds> cmd [args...]
#
# This exists for `conan install` in the jobs that compile the dependency tree
# from source -- the Linux release builds, because Conan Center's binaries need
# a newer glibc than the manylinux_2_28 baseline, and the macOS GCC job,
# because Conan Center has no macOS binaries for a GCC profile. Building from
# source means fetching sources, and a fetch is an availability dependency
# sitting in the release path: a tagged release can fail because someone else's
# server is having a bad afternoon, which has nothing to do with the code being
# released.
#
# The failure that prompted this was gnu-config, which supplies config.guess
# and config.sub to the autotools-based dependencies and fetches them from GNU
# Savannah by commit SHA:
#
#   fatal: unable to access 'https://https.git.savannah.gnu.org/git/config.git/':
#          The requested URL returned error: 500
#   ConanException: Command 'git fetch --depth 1 origin 191bcb94...' failed
#          with errorcode '128'
#
# It happened nine times in one day, three of them consecutively. That specific
# case is no longer reachable: release.yml now excludes gnu-config from its
# forced source build, because the package is two shell scripts with nothing
# compiled in it, so there was never a glibc reason to rebuild it. Retrying was
# the wrong layer for that one -- see the comment there.
#
# What remains is cover for the other source fetches, which have not failed
# here but are the same kind of dependency. Nothing on Windows calls this: the
# Windows graph builds nothing from source, so it fetches no sources.
#
# Bounded on purpose. A reproducible failure still fails the job, just three
# times more slowly, and every attempt is announced so the log says plainly
# whether something was retried and why.
set -uo pipefail

attempts=${1:?attempts}
delay=${2:?delay seconds}
shift 2
[ "$#" -gt 0 ] || { echo "retry.sh: no command given" >&2; exit 2; }

for i in $(seq 1 "$attempts"); do
	if [ "$i" -gt 1 ]; then
		echo "::warning::retry.sh: attempt $i of $attempts for: $*"
	fi
	# status is captured in the else branch, not after the if. An if statement
	# that runs no branch leaves $? at 0, so reading it afterwards reported
	# every failure as status 0 -- and the final exit then succeeded, which is
	# the one thing a retry wrapper must never do.
	if "$@"; then
		[ "$i" -gt 1 ] && echo "retry.sh: succeeded on attempt $i"
		exit 0
	else
		status=$?
	fi
	echo "retry.sh: attempt $i of $attempts failed with status $status" >&2
	[ "$i" -lt "$attempts" ] && sleep "$delay"
done

echo "::error::retry.sh: all $attempts attempts failed for: $*" >&2
exit "${status:-1}"
