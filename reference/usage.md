# Current CPU and memory usage, cheap enough for every log line

`usage()` reads the process's and the container's current CPU and memory
use. It skips the fact engine: everything static (cgroup paths, limits,
page size) is worked out once per session, and each call reads only a
few small files on Linux. `usage_line()` formats the result as a compact
string for log messages.

## Usage

``` r
usage(extra = NULL, max_age = 0)

usage_line(...)
```

## Arguments

- extra:

  Additional, slightly more expensive fields: `"host"` adds
  `mem_host_available`, `"working_set"` adds `mem_working_set`, and
  `"pressure"` adds `mem_pressure` and `cpu_pressure` (percentage of the
  last 10 seconds in which tasks stalled waiting for memory or CPU) and
  `oom_kills` (processes killed in the container for running out of
  memory).

- max_age:

  Return the previous result if it is at most this many seconds old, for
  very hot loops.

- ...:

  Passed on to `usage()`.

## Value

`usage()`: a named numeric vector of class `zufax_usage` with

- `time`: when the sample was taken, as seconds since the epoch.

- `cpu_process`: CPU cores used by this R process since the previous
  call.

- `cpu_cgroup`: CPU cores used by the whole container since the previous
  call, including other processes such as parallel workers.

- `cpu_throttled`: share of CPU scheduling periods since the previous
  call in which the container was throttled for hitting its CPU quota.

- `cpu_limit`: CPU cores the process may use (see
  [`effective_cores()`](https://pedrobtz.github.io/zufax/reference/effective_cores.md)).

- `mem_rss`: resident memory of this process, in bytes.

- `mem_cgroup`: memory used by the container, including page cache.

- `mem_limit`: the memory limit (see
  [`effective_memory()`](https://pedrobtz.github.io/zufax/reference/effective_cores.md)).

- `mem_pct`: `mem_cgroup / mem_limit`, or `mem_rss` as a share of host
  memory when there is no container.

`usage_line()`: a string such as
`"cpu=1.8/4 thr=3% mem=2.1G/8G(26%) rss=1.2G"`.

## Details

CPU values are rates, so they compare against the previous call: the
first call reports the process's average since it started, and
`cpu_cgroup` and `cpu_throttled` are `NA` until the second call. After a
`fork()` (e.g. in
[`parallel::mclapply()`](https://rdrr.io/r/parallel/mclapply.html)
workers) the baseline starts again.

On macOS and Windows, `mem_rss` needs the ps package, and the container
fields are always `NA`.

## Examples

``` r
usage()
#> cpu=0.5/4 mem=2.6G/15.6G(17%) rss=152.9M
message("step done ", usage_line())
#> step done cpu=0.7/4 thr=0% mem=2.6G/15.6G(17%) rss=152.9M
```
