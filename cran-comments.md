## R CMD check results

0 errors | 0 warnings | 1 note

* New submission.

## Test environments

* GitHub Actions (pedrobtz/r-actions `r-cmd-check`, `R CMD check --as-cran`):
  macos-latest, windows-latest and ubuntu-latest (R release), ubuntu-latest
  (R oldrel-1)
* CRAN-like R-devel containers from R-hub: clang23, ubuntu-clang and
  ubuntu-gcc16
* Live checks in Debian, Alpine and Fedora containers with CPU and memory
  limits, and in a 'Kubernetes' (kind) pod

## Notes for reviewers

* zufax reads system files such as `/proc` and `/sys` on Linux and runs a few
  read-only system commands where no file exists, each with a timeout:
  `sysctl`, `sw_vers`, `vm_stat`, `id -u`/`id -g` and `sh -c 'ulimit -n'`
  on macOS; `df -Pk` on Unix; `getconf PAGESIZE` on Linux when
  `/proc/self/auxv` cannot be read; `whoami /groups` and,
  only when the ps package is not installed, `powershell Get-CimInstance` on
  Windows; `py -0p` (Windows) and `python3 -c <probe>` to describe a Python
  interpreter found on the PATH; and `rpm -qa` only for the opt-in
  `packages` facts. It never writes outside `tempdir()` and never changes
  system state. Examples, tests and the vignette never start Python.
* It makes no network requests unless the user explicitly asks for cloud
  instance metadata with `facts(cloud = TRUE)` or `options(zufax.cloud = TRUE)`.
  Requests then go only to the link-local instance metadata address
  (169.254.169.254) with a 1 second timeout. No example, test or vignette
  makes a network request.
* Tests use recorded fixture files (shipped as tarballs in
  `tests/testthat/fixtures/`), so they do not depend on the machine running
  them; a few checks of the live system assert only what holds everywhere.

## Method references

There are no published references describing the methods in this package. It
reads documented kernel and operating system interfaces (Linux control groups
v1 and v2, `/proc`, DMI, the 'Kubernetes' Downward API and the 'Azure' Instance
Metadata Service).
