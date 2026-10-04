# Verify a staged Windows release is self-contained (SOLVER-RELEASE.md):
#
#   pwsh packaging/check-windows.ps1 <stage-dir>
#
# There is deliberately no bundler here, unlike bundle-linux.sh and
# bundle_macos.py. The Windows profile builds with compiler.runtime=static and
# shared=False, so the CRT, the Conan dependencies (HDF5, zlib, libzip) and
# flang's Fortran runtime are all linked in. The executables import nothing but
# core Windows system DLLs:
#
#   KERNEL32.dll  ADVAPI32.dll  bcrypt.dll
#
# So this script is the verification half of a bundler with no copying half. It
# is the counterpart of the glibc floor check at the end of bundle-linux.sh: the
# point is that a change which quietly introduces a DLL dependency fails the
# build here, rather than shipping an archive that cannot run on a machine
# without that DLL.
#
# The allowlist is DLLs that ship with Windows itself. Notably absent:
# VCRUNTIME140.dll and MSVCP140.dll, which come from the Visual C++
# redistributable and are not present on a clean machine -- if those appear,
# something has moved the build to the dynamic CRT and the archive needs either
# a bundler or compiler.runtime=static put back.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$stage = $args[0]
if (-not $stage) { throw "usage: check-windows.ps1 <stage-dir>" }
if (-not (Test-Path $stage)) { throw "no such directory: $stage" }

# Shipped with Windows. ucrtbase and the api-ms-win-* apisets are part of the
# OS from Windows 10 onward; the rest are long-standing Win32 libraries.
$systemDlls = @(
    'kernel32.dll', 'kernelbase.dll', 'advapi32.dll', 'bcrypt.dll',
    'ntdll.dll', 'user32.dll', 'shell32.dll', 'shlwapi.dll',
    'ole32.dll', 'oleaut32.dll', 'rpcrt4.dll', 'ws2_32.dll',
    'secur32.dll', 'crypt32.dll', 'userenv.dll', 'version.dll',
    'dbghelp.dll', 'psapi.dll', 'ucrtbase.dll'
)

$exes = Get-ChildItem -Path $stage -Filter '*.exe' -File
if ($exes.Count -eq 0) { throw "no executables in $stage" }

$status = 0
foreach ($exe in $exes) {
    $out = & dumpbin /nologo /dependents $exe.FullName 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "dumpbin failed on $($exe.Name):`n$out" }

    $imports = [regex]::Matches($out, '(?im)^\s{4}(\S+\.dll)\s*$') |
               ForEach-Object { $_.Groups[1].Value } |
               Sort-Object -Unique

    if ($imports.Count -eq 0) { throw "could not parse dumpbin output for $($exe.Name):`n$out" }

    Write-Host "  $($exe.Name) imports:"
    foreach ($dll in $imports) {
        if ($systemDlls -contains $dll.ToLower()) {
            Write-Host "    $dll"
        } else {
            Write-Host "    $dll   <-- not a Windows system DLL"
            Write-Host "::error::$($exe.Name) imports $dll, which does not ship with Windows. Either bundle it next to the executables or link it statically; see the note at the top of packaging/check-windows.ps1."
            $status = 1
        }
    }
}

if ($status -eq 0) { Write-Host "  all imports are Windows system DLLs; the archive is self-contained" }
exit $status
