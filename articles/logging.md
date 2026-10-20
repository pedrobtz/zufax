# CPU and memory in log lines

[`usage()`](https://pedrobtz.github.io/zufax/reference/usage.md) reads
the current CPU and memory use of the R process and its container. It is
built to be called on every log line: everything static is worked out
once per session, and each call reads three small files on Linux (about
170 microseconds).

``` r

library(zufax)
u <- usage()
u
#> cpu=1.5/4 mem=2.8G/15.6G(18%) rss=113.9M
unclass(u)
#>          time   cpu_process    cpu_cgroup cpu_throttled     cpu_limit 
#>  1.792502e+09  1.533066e+00            NA            NA  4.000000e+00 
#>       mem_rss    mem_cgroup     mem_limit       mem_pct 
#>  1.194680e+08  2.980209e+09  1.676034e+10  1.778131e-01
```

[`usage_line()`](https://pedrobtz.github.io/zufax/reference/usage.md)
gives the same as one string:

``` r

message("batch 12 done ", usage_line())
#> batch 12 done cpu=1.8/4 thr=3% mem=2.1G/8G(26%) rss=1.2G
```

## Fields

| Field | Meaning |
|:---|:---|
| `cpu_process` | CPU cores used by this R process since the previous call. |
| `cpu_cgroup` | CPU cores used by the whole container since the previous call, including parallel workers. |
| `cpu_throttled` | Share of CPU scheduling periods in which the container was throttled. |
| `cpu_limit` | CPU cores the process may use. |
| `mem_rss` | Resident memory of this process. |
| `mem_cgroup` | Memory used by the container, including page cache. |
| `mem_limit` | The memory limit. |
| `mem_pct` | `mem_cgroup / mem_limit`, or `mem_rss` as a share of host memory outside containers. |

CPU values are rates, so they need two calls: the first reports the
process’s average since it started, and the container fields start on
the second call. After `fork()` (for example in
[`parallel::mclapply()`](https://rdrr.io/r/parallel/mclapply.html)
workers) the baseline starts again.

`cpu_throttled` is the number to watch in containers: a high value means
the container keeps hitting its CPU quota, which makes everything slower
without showing up as high CPU use.

On macOS and Windows `mem_rss` needs the ps package, and the container
fields are `NA`.

## With logging packages

zufax depends on none of them;
[`usage_line()`](https://pedrobtz.github.io/zufax/reference/usage.md) is
just a string.

``` r

# logger
logger::log_info("model fitted {zufax::usage_line()}")

# lgr: as a custom field, or the numbers themselves for JSON appenders
lgr::lgr$info("model fitted", usage = zufax::usage_line())
lgr::lgr$info("model fitted", usage = as.list(unclass(zufax::usage())))
```

In very hot loops, `max_age` returns the previous result if it is recent
enough:

``` r

for (i in seq_len(1e6)) {
  if (i %% 1000 == 0) message(usage_line(max_age = 5))
}
```
