# Every fact zufax reports

Facts are grouped in namespaces. Values that are unknown are `NA`;
unlimited limits are `Inf`. Types: `bytes` are numbers of bytes, `cores`
are numbers of CPU cores and may be fractional, `df` are data frames.
Facts in opt-in namespaces are only resolved when asked for by name,
e.g. `facts("packages")`. Use
[`facts_df()`](https://pedrobtz.github.io/zufax/reference/facts_df.md)
to see each fact's status and source on your machine.

## Details

Fact names are part of the API: from version 0.1.0 a renamed or removed
fact is announced in NEWS and kept working for at least one release.

## os

|  |  |  |  |
|----|----|----|----|
| Fact | Type | Platforms | Description |
| `os.family` | chr | all | Operating system family: `linux`, `darwin` or `windows`. |
| `os.name` | chr | all | Distribution or product name, e.g. Ubuntu, macOS, Windows 11. |
| `os.id` | chr | all | Machine-readable OS id, e.g. `ubuntu`, `macos`, `windows`. |
| `os.id_like` | chr vector | Linux | OS ids this one derives from (`ID_LIKE` in os-release). |
| `os.release.full` | chr | all | Full release version. |
| `os.release.major` | chr | Linux, macOS | Major release version. |
| `os.release.minor` | chr | Linux, macOS | Minor release version. |
| `os.kernel.release` | chr | all | Kernel release. |
| `os.kernel.version` | chr | all | Kernel build string. |
| `os.hostname` | chr | all | Host name; in a Kubernetes pod usually the pod name. |
| `os.arch` | chr | all | Machine architecture, e.g. `x86_64`, `arm64`. |
| `os.boot_time` | POSIXct | all | When the system booted, in UTC. |
| `os.uptime` | dbl | all | Seconds since boot. |
| `os.timezone` | chr | all | System time zone. |
| `os.locale` | chr | all | Character-type locale of the R session. |

## cpu

|  |  |  |  |
|----|----|----|----|
| Fact | Type | Platforms | Description |
| `cpu.model` | chr | all | CPU model name. |
| `cpu.vendor` | chr | all | CPU vendor, e.g. Intel, AMD, ARM, Apple. |
| `cpu.flags` | chr vector | Linux, macOS | CPU feature flags, with Linux names (on macOS, Intel Macs only). |
| `cpu.isa_level` | chr | Linux, macOS | x86-64 microarchitecture level (`x86-64` to `x86-64-v4`), or `arm64` with `+sve`/`+sve2`. |
| `cpu.host.logical` | dbl | all | Logical CPUs of the host. |
| `cpu.host.physical` | dbl | all | Physical cores of the host. |
| `cpu.host.sockets` | dbl | Linux, macOS | CPU sockets of the host. |
| `cpu.affinity` | int | Linux | CPUs this process may run on (its affinity mask). |
| `cpu.load` | named dbl | Linux, macOS | Load averages over 1, 5 and 15 minutes. |
| `cpu.cgroup.quota` | cores | Linux | cgroup CPU quota in cores, the smallest over parent cgroups (`Inf` if unlimited). |
| `cpu.cgroup.cpuset` | int | Linux | CPUs in the cgroup's cpuset. |
| `cpu.cgroup.weight` | dbl | Linux | cgroup CPU weight on the v2 scale (v1 shares converted). |
| `cpu.cgroup.pressure` | named dbl | Linux | cgroup v2 CPU pressure: percentage of the last 10 seconds in which some or all tasks waited for CPU. |
| `cpu.effective` | int | all | CPU cores to size thread pools with: the smallest limit, a fractional quota rounded up. |
| `cpu.effective_exact` | cores | all | The smallest CPU limit, keeping a fractional quota. |

## memory

|  |  |  |  |
|----|----|----|----|
| Fact | Type | Platforms | Description |
| `memory.host.total` | bytes | all | Host memory. |
| `memory.host.available` | bytes | all | Host memory that can be used without swapping. |
| `memory.swap.total` | bytes | Linux | Swap space. |
| `memory.swap.free` | bytes | Linux | Free swap space. |
| `memory.cgroup.limit` | bytes | Linux | cgroup memory limit, the smallest over parent cgroups (`Inf` if unlimited). |
| `memory.cgroup.high` | bytes | Linux | cgroup v2 `memory.high` throttling threshold. |
| `memory.cgroup.usage` | bytes | Linux | Memory used by the cgroup, including page cache. |
| `memory.cgroup.swap_limit` | bytes | Linux | cgroup swap limit. |
| `memory.cgroup.working_set` | bytes | Linux | cgroup memory in use, not counting inactive page cache. |
| `memory.cgroup.pressure` | named dbl | Linux | cgroup v2 memory pressure: percentage of the last 10 seconds in which some or all tasks stalled on memory. |
| `memory.cgroup.oom_kills` | dbl | Linux | Processes killed in this cgroup for running out of memory. |
| `memory.rlimit.as` | bytes | Linux | Address-space limit of the process (`ulimit -v`). |
| `memory.rlimit.data` | bytes | Linux | Data-segment limit of the process (`ulimit -d`). |
| `memory.effective.limit` | bytes | all | Memory the process may use: the smaller of host memory and the cgroup limit. |
| `memory.effective.available` | bytes | all | Memory that can still be allocated, counting reclaimable cache as free. |
| `memory.lxcfs` | lgl | Linux | Whether `/proc/meminfo` is virtualized by LXCFS. |

## cgroup

|  |  |  |  |
|----|----|----|----|
| Fact | Type | Platforms | Description |
| `cgroup.version` | chr | Linux | cgroup version: `1`, `2` or `hybrid`. |
| `cgroup.path` | chr | Linux | This process's cgroup path. |
| `cgroup.mountpoint` | chr | Linux | Where the cgroup hierarchy is mounted. |
| `cgroup.namespaced` | lgl | Linux | Whether the process has a private cgroup namespace. |
| `cgroup.pids.max` | dbl | Linux | Maximum number of processes in the cgroup (`Inf` if unlimited). |

## virtualization

|  |  |  |  |
|----|----|----|----|
| Fact | Type | Platforms | Description |
| `virtualization.hypervisor` | chr | all | Hypervisor, e.g. `kvm`, `hyperv`, `vmware`, `xen`, `apple`, `aws-nitro`. |
| `virtualization.type` | chr | all | `physical`, `vm` or `unknown`. |
| `virtualization.wsl` | int | Linux | WSL version (1 or 2) when running under WSL. |

## container

|  |  |  |  |
|----|----|----|----|
| Fact | Type | Platforms | Description |
| `container.pid1` | chr | Linux | Name of process 1, a hint for containers. |
| `container.detected` | lgl | Linux | Whether the process runs in a container. |
| `container.runtime` | chr | Linux | Container runtime: `docker`, `podman`, `containerd`, `cri-o`, `lxc`, ... |
| `container.id` | chr | Linux | Container id, when it can be found. |

## k8s

|  |  |  |  |
|----|----|----|----|
| Fact | Type | Platforms | Description |
| `k8s.detected` | lgl | all | Whether the process runs in a Kubernetes pod. |
| `k8s.namespace` | chr | all | Pod namespace. |
| `k8s.pod.name` | chr | all | Pod name. |
| `k8s.node.name` | chr | all | Node name, from the Downward API. |
| `k8s.pod.ip` | chr | all | Pod IP address, from the Downward API. |
| `k8s.pod.uid` | chr | all | Pod UID. |
| `k8s.pod.labels` | named chr | all | Pod labels, from a Downward API volume. |
| `k8s.pod.annotations` | named chr | all | Pod annotations, from a Downward API volume. |
| `k8s.resources.limits` | named dbl | all | CPU (cores) and memory (bytes) limits. |
| `k8s.resources.requests` | named dbl | all | CPU (cores) and memory (bytes) requests, from the Downward API. |

## cloud

|  |  |  |  |
|----|----|----|----|
| Fact | Type | Platforms | Description |
| `cloud.provider` | chr | all | Cloud provider: `azure`, `aws` or `gcp`. |
| `cloud.azure.platform` | chr | all | Azure service: `vm`, `aks`, `app-service`, `functions`, `container-apps`, `batch`, `azureml` or `databricks`. |
| `cloud.azure.service` | named chr | all | Non-secret identifiers of the Azure service, e.g. the App Service site name. |
| `cloud.region` | chr | all | Cloud region. Needs `cloud = TRUE`. |
| `cloud.zone` | chr | all | Availability zone. Needs `cloud = TRUE`. |
| `cloud.instance.type` | chr | all | VM size. Needs `cloud = TRUE`. |
| `cloud.instance.id` | chr | all | VM id. Needs `cloud = TRUE`. |
| `cloud.azure.vm_name` | chr | all | Azure VM name. Needs `cloud = TRUE`. |
| `cloud.azure.resource_group` | chr | all | Azure resource group. Needs `cloud = TRUE`. |
| `cloud.azure.subscription_id` | chr | all | Azure subscription id. Needs `cloud = TRUE`. |
| `cloud.azure.vmss_name` | chr | all | Azure virtual machine scale set name. Needs `cloud = TRUE`. |
| `cloud.azure.priority` | chr | all | VM priority: `Regular` or `Spot`. Needs `cloud = TRUE`. |
| `cloud.azure.eviction_policy` | chr | all | Spot VM eviction policy. Needs `cloud = TRUE`. |
| `cloud.azure.os_type` | chr | all | OS type reported by Azure. Needs `cloud = TRUE`. |
| `cloud.azure.environment` | chr | all | Azure cloud, e.g. `AzurePublicCloud`. Needs `cloud = TRUE`. |
| `cloud.azure.image` | named chr | all | Image publisher, offer, sku and version. Needs `cloud = TRUE`. |
| `cloud.azure.tags` | named chr | all | VM tags, with secret-looking ones redacted. Needs `cloud = TRUE`. |
| `cloud.azure.network.private_ip` | chr vector | all | Private IP addresses. Needs `cloud = TRUE`. |
| `cloud.azure.network.public_ip` | chr vector | all | Public IP addresses. Needs `cloud = TRUE`. |

## runtime

|  |  |  |  |
|----|----|----|----|
| Fact | Type | Platforms | Description |
| `runtime.r.version` | chr | all | R version. |
| `runtime.r.platform` | chr | all | R platform triplet. |
| `runtime.r.home` | chr | all | [`R.home()`](https://rdrr.io/r/base/Rhome.html). |
| `runtime.r.blas` | chr | all | BLAS library in use. |
| `runtime.r.lapack` | named chr | all | LAPACK version and library. |
| `runtime.r.libpaths` | chr vector | all | Library paths. |
| `runtime.r.repos` | named chr | all | Package repositories, with credentials removed. |
| `runtime.r.renv` | named chr | all | Active renv project and lockfile. |
| `runtime.threads.env` | named chr | all | Thread-count environment variables that are set (`OMP_NUM_THREADS`, ...). |
| `runtime.threads.options` | named dbl | all | `mc.cores` and `Ncpus` options. |
| `runtime.parallelly_cores` | int | all | [`parallelly::availableCores()`](https://parallelly.futureverse.org/reference/availableCores.html), when parallelly is installed. |
| `runtime.r.connections` | named int | all | R connection slots: max, used and free. Each parallel worker needs one. |
| `runtime.rlimit.nofile` | dbl | Linux, macOS | Open-files limit of the process (`ulimit -n`). |
| `runtime.pid` | int | all | Process id. |
| `runtime.user` | chr | all | User name. |
| `runtime.uid` | int | Linux, macOS | Effective user id. |
| `runtime.gid` | int | Linux, macOS | Effective group id. |
| `runtime.privileged` | lgl | all | Whether the process runs as root or elevated. |
| `runtime.python.path` | chr | all | Python interpreter. |
| `runtime.python.env_type` | chr | all | `venv`, `uv`, `conda` or `system`. |
| `runtime.python.env_path` | chr | all | Virtual or conda environment directory. |
| `runtime.python.version` | chr | all | Python version. |
| `runtime.python.implementation` | chr | all | Python implementation, e.g. `cpython`. |
| `runtime.python.prefix` | chr | all | Python `sys.prefix`. |
| `runtime.python.site_packages` | chr vector | all | site-packages directories. |
| `runtime.python.reticulate` | chr | all | Interpreter reticulate has already started, if any. |

## env

|  |  |  |  |
|----|----|----|----|
| Fact | Type | Platforms | Description |
| `env.vars` | named chr | all | Environment variables, with secrets redacted. |
| `env.proxies` | named chr | all | Proxy settings, with credentials removed. |

## disk

|  |  |  |  |
|----|----|----|----|
| Fact | Type | Platforms | Description |
| `disk.tmpdir.path` | chr | all | [`tempdir()`](https://rdrr.io/r/base/tempfile.html). |
| `disk.tmpdir.fstype` | chr | all | File system type of [`tempdir()`](https://rdrr.io/r/base/tempfile.html). |
| `disk.tmpdir.free` | bytes | all | Free space in [`tempdir()`](https://rdrr.io/r/base/tempfile.html). |

## packages (opt-in)

|  |  |  |  |
|----|----|----|----|
| Fact | Type | Platforms | Description |
| `packages.system.installed` | df | all | Installed system packages: name, version and arch, kind or publisher. |
| `packages.system.manager` | chr | all | Package manager: `dpkg`, `rpm`, `apk`, `pacman`, `homebrew` or `windows`. |
| `packages.system.count` | int | all | Number of installed system packages. |
| `packages.r` | df | all | Installed R packages: name, version, libpath, priority, built, source, remote_sha. |
| `packages.python` | df | all | Installed Python packages: name, version, location, installer, source; one row per site-packages directory that holds the package, so it can list a package more than once where `pip list` lists it once. |

## See also

[`facts()`](https://pedrobtz.github.io/zufax/reference/facts.md),
[`fact()`](https://pedrobtz.github.io/zufax/reference/fact.md),
[`facts_df()`](https://pedrobtz.github.io/zufax/reference/facts_df.md).
