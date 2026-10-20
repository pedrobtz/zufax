# CPU cores and memory this process can actually use

`effective_cores()` is a safe default for the size of a thread pool or
worker pool. It takes the smallest of the host's logical CPUs, the
process's CPU affinity, the cgroup cpuset and the cgroup CPU quota
(rounded up, since a 1.5-core quota can keep 2 threads busy). Inside a
container this is often much smaller than
[`parallel::detectCores()`](https://rdrr.io/r/parallel/detectCores.html).

## Usage

``` r
effective_cores()

effective_memory(what = c("limit", "available"))
```

## Arguments

- what:

  `"limit"` for the memory limit, `"available"` for the memory that can
  still be allocated.

## Value

`effective_cores()`: an integer, at least 1. `effective_memory()`: a
number of bytes, `NA` if unknown.

## Details

`effective_memory()` returns the memory limit that applies to the
process (`"limit"`): the smaller of the host's total memory and the
cgroup memory limit. With `what = "available"` it returns how much more
can be allocated now, counting reclaimable page cache as free, as the
Kubernetes kubelet does.

Both are resource-based: they ignore settings such as `mc.cores` or
`MC_CORES`. Use
[`parallelly::availableCores()`](https://parallelly.futureverse.org/reference/availableCores.html)
if you want those honored.

## See also

[`facts()`](https://pedrobtz.github.io/zufax/reference/facts.md) for the
individual limits behind these values, e.g. `facts()$cpu` and
`facts()$memory`.

## Examples

``` r
effective_cores()
#> [1] 4
effective_memory()
#> [1] 16760340480
```
