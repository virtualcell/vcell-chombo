/*
 *  <sys/time.h> compatibility shim for Windows.
 *
 *  Reached only through the include path this repository adds on Windows; see
 *  the WIN32 branch in the top-level CMakeLists.txt.
 *
 *  It exists for one line in a submodule. vcell-messaging's
 *  include/VCELL/SimulationMessaging.h includes <sys/time.h>, which the MSVC
 *  runtime does not have, and the only thing it needs from it is time_t -- for
 *  SimulationMessaging::lastSentEventTime -- which <time.h> provides. The
 *  include is simply unnecessary there.
 *
 *  Done this way rather than by patching vcell-messaging because that submodule
 *  is shared with vcell-ode, vcell-stochastic and vcell-mbsolver, and per
 *  CLAUDE.md a fix has to land upstream before this repository can bump the
 *  gitlink. Trading a cross-repository round trip for ten lines here is not a
 *  close call -- but it IS worth fixing upstream eventually, at which point
 *  this file and its include path can go.
 *
 *  Deliberately not an emulation layer. There is no gettimeofday here: nothing
 *  that reaches this shim calls it. If something starts to, add the guard at
 *  the call site rather than growing this file.
 */

#ifndef VCELL_COMPAT_WINDOWS_SYS_TIME_H
#define VCELL_COMPAT_WINDOWS_SYS_TIME_H

#include <time.h>   /* time_t */

#endif
