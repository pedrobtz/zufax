# Installed packages

The `packages` namespace lists what is installed: system packages, R
packages and Python packages. It is opt-in, because the lists can be
long: it is left out of `print(facts())`,
[`as.list()`](https://rdrr.io/r/base/list.html) and
[`facts_df()`](https://pedrobtz.github.io/zufax/reference/facts_df.md)
unless you ask for it.

``` r

library(zufax)
f <- facts("packages")
f[["packages.system.manager"]]
#> [1] "dpkg"
f[["packages.system.count"]]
#> [1] 1437
head(f[["packages.r"]][, c("name", "version", "source")])
#>        name version   source
#> 1   askpass   1.2.1 standard
#> 2 base64enc   0.1-6 standard
#> 3      brio   1.1.5 standard
#> 4     bslib  0.12.0 standard
#> 5    cachem   1.1.0 standard
#> 6     callr   3.8.0 standard
```

## Sources

| Fact | Read from |
|:---|:---|
| `packages.system.installed` | dpkg `/var/lib/dpkg/status` (or distroless `status.d/`), apk `/lib/apk/db/installed`, pacman `/var/lib/pacman/local`, one `rpm -qa` query, Homebrew’s `Cellar` and `Caskroom` directories, or the Windows Uninstall registry keys. |
| `packages.r` | [`installed.packages()`](https://rdrr.io/r/utils/installed.packages.html), with where each package came from (`Repository` or the remote type). |
| `packages.python` | `*.dist-info` and `*.egg-info` directories in the Python environment’s site-packages, plus `conda-meta` in conda environments. |

zufax never runs `pip`, `conda`, `brew` or `apt`, and never starts
Python inside R. Python is found through `RETICULATE_PYTHON`,
`VIRTUAL_ENV`, `CONDA_PREFIX` or the `PATH` (and the py launcher on
Windows).

## An environment report

A typical use is attaching the environment to a bug report or a job log:

``` r

namespaces <- c("os", "cpu", "memory", "runtime", "packages")
writeLines(facts_json(facts(namespaces), namespaces, pretty = TRUE), "environment.json")
```
