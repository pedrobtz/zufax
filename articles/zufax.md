# Getting started with zufax

zufax reports facts about where R is running and what it may use. This
article shows the main functions on the machine that built it, then
walks through a container in Kubernetes, where the numbers zufax gives
you differ most from the usual ones.

``` r

library(zufax)
```

## A snapshot

[`facts()`](https://pedrobtz.github.io/zufax/reference/facts.md) returns
a snapshot. Printing it gives a summary:

``` r

f <- facts()
f
#> <zufax facts>
#> os       Ubuntu 24.04
#> runs in  no container
#> runs on  vm (hyperv), cloud azure
#> cpu      host 4 | effective 4
#> memory   host 15.6G | available 14.3G
#> runtime  R 4.6.1
#> Use facts_df() for every fact with its status and source.
```

Facts are grouped in namespaces such as `os`, `cpu` and `memory`. Access
a namespace with `$`, a group or a single fact with `[[`:

``` r

names(f)
#>  [1] "os"             "cpu"            "memory"         "cgroup"        
#>  [5] "virtualization" "container"      "k8s"            "cloud"         
#>  [9] "runtime"        "env"            "disk"           "packages"
f[["cpu.host"]]
#> $logical
#> [1] 4
#> 
#> $physical
#> [1] 2
#> 
#> $sockets
#> [1] 1
f[["memory.effective.limit"]]
#> [1] 16760340480
```

Nothing is read until you ask for it, and each fact is read once per
session. `facts(refresh = TRUE)` reads again.
[`fact()`](https://pedrobtz.github.io/zufax/reference/fact.md) gets one
value directly:

``` r

fact("cpu.effective")
#> [1] 4
```

The help page
[`?zufax_facts`](https://pedrobtz.github.io/zufax/reference/zufax_facts.md)
lists every fact.

## Status and source

A fact that cannot be determined is `NA`; zufax never stops with an
error.
[`facts_df()`](https://pedrobtz.github.io/zufax/reference/facts_df.md)
says why, and where each value came from:

``` r

df <- facts_df(facts("cpu"))
rows <- df$fact %in% c("cpu.model", "cpu.affinity", "cpu.cgroup.quota", "cpu.effective")
df[rows, c("fact", "status", "source")]
#>                fact status
#> 16        cpu.model     ok
#> 23     cpu.affinity     ok
#> 25 cpu.cgroup.quota     ok
#> 29    cpu.effective     ok
#>                                                                                                                                            source
#> 16                                                                                                                                  /proc/cpuinfo
#> 23                                                                                                                              /proc/self/status
#> 25 /proc/self/cgroup; /proc/self/mountinfo; /sys/fs/cgroup/system.slice/hosted-compute-agent.service/cpu.max; /sys/fs/cgroup/system.slice/cpu.max
#> 29                                                                                                                                           <NA>
```

`status` is `"ok"`, `"not_applicable"` (e.g. cgroup facts on macOS),
`"unavailable"` (the data is missing) or `"error"`. Use `strict = TRUE`
to turn errors into R errors while debugging.

## How many cores, how much memory?

[`parallel::detectCores()`](https://rdrr.io/r/parallel/detectCores.html)
counts the host’s CPUs. Inside a container the process is usually
allowed far fewer.
[`effective_cores()`](https://pedrobtz.github.io/zufax/reference/effective_cores.md)
takes the smallest of:

- the host’s logical CPUs,
- the process’s CPU affinity,
- the cgroup’s cpuset,
- the cgroup’s CPU quota, rounded up (a 1.5-core quota can keep 2
  threads busy).

``` r

effective_cores()
#> [1] 4
effective_memory()
#> [1] 16760340480
```

[`effective_memory()`](https://pedrobtz.github.io/zufax/reference/effective_cores.md)
is the smaller of host memory and the cgroup memory limit.
`effective_memory("available")` is what can still be allocated, counting
reclaimable page cache as free.

Use them to size worker pools:

``` r

future::plan(future::multisession, workers = effective_cores())
data.table::setDTthreads(effective_cores())
options(mc.cores = effective_cores())
```

Both ignore settings such as `mc.cores` or `MC_CORES` on purpose: they
describe the resources, not a policy.
[`parallelly::availableCores()`](https://parallelly.futureverse.org/reference/availableCores.html)
combines both.

## In a Kubernetes pod

Here is zufax in a pod limited to 2 CPUs and 1 GiB on a node with 8 CPUs
and 32 GiB. The limits are set on the pod’s cgroup, a parent of the
container’s:

``` r

facts()
#> <zufax facts>
#> os       Ubuntu 22.04
#> runs in  Kubernetes pod default/web-6b8f9-2xkqz, containerd container
#> runs on  vm (unknown)
#> cpu      host 8 | effective 2
#> memory   host 32G | limit 1G | available 824M
#> Use facts_df() for every fact with its status and source.
```

`detectCores()` would say 8. The CPU facts show where 2 comes from:

``` r

str(facts()$cpu[c("host", "affinity", "cgroup", "effective")])
#> List of 4
#>  $ host     :List of 3
#>   ..$ logical : int 8
#>   ..$ physical: int 4
#>   ..$ sockets : int 1
#>  $ affinity : int 8
#>  $ cgroup   :List of 3
#>   ..$ quota : num 2
#>   ..$ cpuset: int 8
#>   ..$ weight: num 79
#>  $ effective: int 2
```

For memory, the container has used 300 MiB, of which 100 MiB is inactive
page cache the kernel can reclaim. Like the kubelet, zufax counts the
remaining 200 MiB as the working set, leaving 824 MiB available.

Kubernetes facts come from the environment and from files the kubelet
mounts. The node name, pod IP and resources are only visible through the
Downward API: expose them as environment variables (zufax looks for
`NODE_NAME`, `POD_IP`, `POD_UID`, `POD_NAME`, `CPU_LIMIT`,
`MEMORY_LIMIT`, `CPU_REQUEST` and `MEMORY_REQUEST`, or set
`options(zufax.k8s.env = )`) and mount labels and annotations at
`/etc/podinfo` (or set `options(zufax.k8s.podinfo = )`). zufax never
reads the service account token.

## Output formats

[`facts_df()`](https://pedrobtz.github.io/zufax/reference/facts_df.md)
gives a data frame, [`as.list()`](https://rdrr.io/r/base/list.html) a
nested list, and
[`facts_json()`](https://pedrobtz.github.io/zufax/reference/facts_json.md)
JSON (with the jsonlite package):

``` r

facts_json(namespaces = "cgroup", pretty = TRUE)
#> {
#>   "cgroup": {
#>     "version": "2",
#>     "path": "/system.slice/hosted-compute-agent.service",
#>     "mountpoint": "/sys/fs/cgroup",
#>     "namespaced": false,
#>     "pids": {
#>       "max": 17436
#>     }
#>   }
#> }
```

## Options

| Option | Purpose |
|:---|:---|
| `zufax.root` (or env `ZUFAX_ROOT`) | Read `/proc`, `/sys` and `/etc` below another root, e.g. a host mounted at `/host`. |
| `zufax.cloud` | Allow network requests to the cloud metadata service (same as `cloud = TRUE`). |
| `zufax.strict` | Re-raise resolver errors. |
| `zufax.skip` | Facts or namespaces to skip, e.g. `c("packages", "runtime.python")`. |
| `zufax.redact`, `zufax.redact_allowlist` | How `env.vars` hides secrets: `"default"`, `"allowlist"` or `"none"`. |
| `zufax.k8s.env`, `zufax.k8s.podinfo` | Downward API environment variable names and volume path. |

## Further reading

Articles on the package website cover:

- Azure: what zufax detects offline and what instance metadata adds.
- Logging:
  [`usage()`](https://pedrobtz.github.io/zufax/reference/usage.md) for
  CPU and memory in every log line.
- Inventory: installed system, R and Python packages.
