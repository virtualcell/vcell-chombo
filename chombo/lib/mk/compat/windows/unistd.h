/*
 *  <unistd.h> compatibility shim for Windows.  Added by VCell, not part of
 *  upstream Chombo.
 *
 *  Twenty-five files under lib/src include <unistd.h>, which the MSVC runtime
 *  does not have.  Only one thing is actually used from it -- getpid(), in
 *  BaseTools/SPMD.cpp and BaseTools/CH_Timer.cpp -- so this header is a much
 *  smaller change than guarding twenty-five vendored sources, and it keeps the
 *  edits out of files that are otherwise untouched.
 *
 *  It reaches the compiler only through mk/compiler/Make.defs.LLVM, which adds
 *  this directory to the include path when $(system) is CYGWIN.  That matters:
 *  a header named unistd.h on the include path everywhere would shadow the real
 *  one on Linux and macOS.
 *
 *  Deliberately minimal.  If something here starts needing more of POSIX than
 *  getpid(), the right answer is almost certainly to guard that use rather than
 *  to grow this file into an emulation layer.
 */

#ifndef CH_COMPAT_WINDOWS_UNISTD_H
#define CH_COMPAT_WINDOWS_UNISTD_H

#include <process.h>   /* _getpid */

inline int getpid()
{
  return _getpid();
}

#endif
