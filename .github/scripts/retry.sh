#!/usr/bin/env bash
# Run a command, retrying a bounded number of times:
#
#   .github/scripts/retry.sh <attempts> <delay-seconds> cmd [args...]
#
# This exists for `conan install`. The Linux release build compiles the whole
# Conan tree from source -- Conan Center's binaries need a newer glibc than the
# manylinux_2_28 baseline -- and gnu-config, which supplies config.guess and
# config.sub to the autotools-based dependencies, fetches its sources from GNU
# Savannah by commit SHA:
#
#   fatal: unable to access 'https://https.git.savannah.gnu.org/git/config.git/':
#          The requested URL returned error: 500
#   ConanException: Command 'git fetch --depth 1 origin 191bcb94...' failed
#          with errorcode '128'
#
# That is an availability dependency sitting in the release path: a tagged
# release can fail because savannah.gnu.org is having a bad afternoon, which has
# nothing to do with the code being released. It happened nine times in one day,
# three of them consecutively.
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
