# Type and one-line description of every fact. The ?zufax_facts help page is
# generated from this table plus the registry (platforms, opt-in, network), and
# a test checks that every registered fact is described here.
# nolint start: line_length_linter. One fact per line reads better than wrapped.
fact_docs <- read.table(
  sep = "|",
  strip.white = TRUE,
  col.names = c("fact", "type", "description"),
  quote = "",
  text = "
os.family | chr | Operating system family: `linux`, `darwin` or `windows`.
os.name | chr | Distribution or product name, e.g. Ubuntu, macOS, Windows 11.
os.id | chr | Machine-readable OS id, e.g. `ubuntu`, `macos`, `windows`.
os.id_like | chr vector | OS ids this one derives from (`ID_LIKE` in os-release).
os.release.full | chr | Full release version.
os.release.major | chr | Major release version.
os.release.minor | chr | Minor release version.
os.kernel.release | chr | Kernel release.
os.kernel.version | chr | Kernel build string.
os.hostname | chr | Host name; in a Kubernetes pod usually the pod name.
os.arch | chr | Machine architecture, e.g. `x86_64`, `arm64`.
os.boot_time | POSIXct | When the system booted, in UTC.
os.uptime | dbl | Seconds since boot.
os.timezone | chr | System time zone.
os.locale | chr | Character-type locale of the R session.
cgroup.version | chr | cgroup version: `1`, `2` or `hybrid`.
cgroup.path | chr | This process's cgroup path.
cgroup.mountpoint | chr | Where the cgroup hierarchy is mounted.
cgroup.namespaced | lgl | Whether the process has a private cgroup namespace.
cgroup.pids.max | dbl | Maximum number of processes in the cgroup (`Inf` if unlimited).
cpu.model | chr | CPU model name.
cpu.vendor | chr | CPU vendor, e.g. Intel, AMD, ARM, Apple.
cpu.flags | chr vector | CPU feature flags, with Linux names (on macOS, Intel Macs only).
cpu.isa_level | chr | x86-64 microarchitecture level (`x86-64` to `x86-64-v4`), or `arm64` with `+sve`/`+sve2`.
cpu.host.logical | dbl | Logical CPUs of the host.
cpu.host.physical | dbl | Physical cores of the host.
cpu.host.sockets | dbl | CPU sockets of the host.
cpu.affinity | int | CPUs this process may run on (its affinity mask).
cpu.load | named dbl | Load averages over 1, 5 and 15 minutes.
cpu.cgroup.quota | cores | cgroup CPU quota in cores, the smallest over parent cgroups (`Inf` if unlimited).
cpu.cgroup.cpuset | int | CPUs in the cgroup's cpuset.
cpu.cgroup.weight | dbl | cgroup CPU weight on the v2 scale (v1 shares converted).
cpu.cgroup.pressure | named dbl | cgroup v2 CPU pressure: percentage of the last 10 seconds in which some or all tasks waited for CPU.
cpu.effective | int | CPU cores to size thread pools with: the smallest limit, a fractional quota rounded up.
cpu.effective_exact | cores | The smallest CPU limit, keeping a fractional quota.
memory.host.total | bytes | Host memory.
memory.host.available | bytes | Host memory that can be used without swapping.
memory.swap.total | bytes | Swap space.
memory.swap.free | bytes | Free swap space.
memory.cgroup.limit | bytes | cgroup memory limit, the smallest over parent cgroups (`Inf` if unlimited).
memory.cgroup.high | bytes | cgroup v2 `memory.high` throttling threshold.
memory.cgroup.usage | bytes | Memory used by the cgroup, including page cache.
memory.cgroup.swap_limit | bytes | cgroup swap limit.
memory.cgroup.working_set | bytes | cgroup memory in use, not counting inactive page cache.
memory.cgroup.pressure | named dbl | cgroup v2 memory pressure: percentage of the last 10 seconds in which some or all tasks stalled on memory.
memory.cgroup.oom_kills | dbl | Processes killed in this cgroup for running out of memory.
memory.rlimit.as | bytes | Address-space limit of the process (`ulimit -v`).
memory.rlimit.data | bytes | Data-segment limit of the process (`ulimit -d`).
memory.effective.limit | bytes | Memory the process may use: the smaller of host memory and the cgroup limit.
memory.effective.available | bytes | Memory that can still be allocated, counting reclaimable cache as free.
memory.lxcfs | lgl | Whether `/proc/meminfo` is virtualized by LXCFS.
virtualization.hypervisor | chr | Hypervisor, e.g. `kvm`, `hyperv`, `vmware`, `xen`, `apple`, `aws-nitro`.
virtualization.type | chr | `physical`, `vm` or `unknown`.
virtualization.wsl | int | WSL version (1 or 2) when running under WSL.
container.pid1 | chr | Name of process 1, a hint for containers.
container.detected | lgl | Whether the process runs in a container.
container.runtime | chr | Container runtime: `docker`, `podman`, `containerd`, `cri-o`, `lxc`, ...
container.id | chr | Container id, when it can be found.
k8s.detected | lgl | Whether the process runs in a Kubernetes pod.
k8s.namespace | chr | Pod namespace.
k8s.pod.name | chr | Pod name.
k8s.node.name | chr | Node name, from the Downward API.
k8s.pod.ip | chr | Pod IP address, from the Downward API.
k8s.pod.uid | chr | Pod UID.
k8s.pod.labels | named chr | Pod labels, from a Downward API volume.
k8s.pod.annotations | named chr | Pod annotations, from a Downward API volume.
k8s.resources.limits | named dbl | CPU (cores) and memory (bytes) limits.
k8s.resources.requests | named dbl | CPU (cores) and memory (bytes) requests, from the Downward API.
cloud.provider | chr | Cloud provider: `azure`, `aws` or `gcp`.
cloud.azure.platform | chr | Azure service: `vm`, `aks`, `app-service`, `functions`, `container-apps`, `batch`, `azureml` or `databricks`.
cloud.azure.service | named chr | Non-secret identifiers of the Azure service, e.g. the App Service site name.
cloud.region | chr | Cloud region.
cloud.zone | chr | Availability zone.
cloud.instance.type | chr | VM size.
cloud.instance.id | chr | VM id.
cloud.azure.vm_name | chr | Azure VM name.
cloud.azure.resource_group | chr | Azure resource group.
cloud.azure.subscription_id | chr | Azure subscription id.
cloud.azure.vmss_name | chr | Azure virtual machine scale set name.
cloud.azure.priority | chr | VM priority: `Regular` or `Spot`.
cloud.azure.eviction_policy | chr | Spot VM eviction policy.
cloud.azure.os_type | chr | OS type reported by Azure.
cloud.azure.environment | chr | Azure cloud, e.g. `AzurePublicCloud`.
cloud.azure.image | named chr | Image publisher, offer, sku and version.
cloud.azure.tags | named chr | VM tags, with secret-looking ones redacted.
cloud.azure.network.private_ip | chr vector | Private IP addresses.
cloud.azure.network.public_ip | chr vector | Public IP addresses.
runtime.r.version | chr | R version.
runtime.r.platform | chr | R platform triplet.
runtime.r.home | chr | `R.home()`.
runtime.r.blas | chr | BLAS library in use.
runtime.r.lapack | named chr | LAPACK version and library.
runtime.r.libpaths | chr vector | Library paths.
runtime.r.repos | named chr | Package repositories, with credentials removed.
runtime.r.renv | named chr | Active renv project and lockfile.
runtime.threads.env | named chr | Thread-count environment variables that are set (`OMP_NUM_THREADS`, ...).
runtime.threads.options | named dbl | `mc.cores` and `Ncpus` options.
runtime.parallelly_cores | int | `parallelly::availableCores()`, when parallelly is installed.
runtime.r.connections | named int | R connection slots: max, used and free. Each parallel worker needs one.
runtime.rlimit.nofile | dbl | Open-files limit of the process (`ulimit -n`).
runtime.pid | int | Process id.
runtime.user | chr | User name.
runtime.uid | int | Effective user id.
runtime.gid | int | Effective group id.
runtime.privileged | lgl | Whether the process runs as root or elevated.
runtime.python.path | chr | Python interpreter.
runtime.python.env_type | chr | `venv`, `uv`, `conda` or `system`.
runtime.python.env_path | chr | Virtual or conda environment directory.
runtime.python.version | chr | Python version.
runtime.python.implementation | chr | Python implementation, e.g. `cpython`.
runtime.python.prefix | chr | Python `sys.prefix`.
runtime.python.site_packages | chr vector | site-packages directories.
runtime.python.reticulate | chr | Interpreter reticulate has already started, if any.
env.vars | named chr | Environment variables, with secrets redacted.
env.proxies | named chr | Proxy settings, with credentials removed.
disk.tmpdir.path | chr | `tempdir()`.
disk.tmpdir.fstype | chr | File system type of `tempdir()`.
disk.tmpdir.free | bytes | Free space in `tempdir()`.
packages.system.installed | df | Installed system packages: name, version and arch, kind or publisher.
packages.system.manager | chr | Package manager: `dpkg`, `rpm`, `apk`, `pacman`, `homebrew` or `windows`.
packages.system.count | int | Number of installed system packages.
packages.r | df | Installed R packages: name, version, libpath, priority, built, source, remote_sha.
packages.python | df | Installed Python packages: name, version, location, installer, source; one row per site-packages directory that holds the package, so it can list a package more than once where `pip list` lists it once.
"
)
# nolint end

# Operating systems a fact has a resolver for.
fact_platforms <- function(name) {
  oses <- c("linux", "darwin", "windows")
  supported <- unique(unlist(lapply(.zufax$resolvers[[name]], function(r) {
    os <- r$confine$os
    if (is.null(os)) {
      oses
    } else if (is.function(os)) {
      oses[vapply(oses, os, logical(1))]
    } else {
      os
    }
  })))
  labels <- c(linux = "Linux", darwin = "macOS", windows = "Windows")
  if (setequal(supported, oses)) {
    "all"
  } else {
    paste(labels[intersect(oses, supported)], collapse = ", ")
  }
}

fact_reference <- function() {
  lines <- character()
  for (ns in known_namespaces()) {
    facts <- known_facts(ns)
    docs <- fact_docs[match(facts, fact_docs$fact), ]
    network <- vapply(
      facts,
      \(f) any(vapply(.zufax$resolvers[[f]], `[[`, logical(1), "network")),
      logical(1)
    )
    notes <- ifelse(network, " Needs `cloud = TRUE`.", "")
    title <- if (ns %in% .zufax$opt_in) paste0(ns, " (opt-in)") else ns
    lines <- c(
      lines,
      paste0("@section ", title, ":"),
      "",
      "| Fact | Type | Platforms | Description |",
      "|:--|:--|:--|:--|",
      sprintf(
        "| `%s` | %s | %s | %s%s |",
        facts,
        docs$type,
        vapply(facts, fact_platforms, character(1)),
        docs$description,
        notes
      ),
      ""
    )
  }
  lines
}

#' Every fact zufax reports
#'
#' Facts are grouped in namespaces. Values that are unknown are `NA`;
#' unlimited limits are `Inf`. Types: `bytes` are numbers of bytes, `cores`
#' are numbers of CPU cores and may be fractional, `df` are data frames. Facts
#' in opt-in namespaces are only resolved when asked for by name, e.g.
#' `facts("packages")`. Use [facts_df()] to see each fact's status and source
#' on your machine.
#'
#' Fact names are part of the API: from version 0.1.0 a renamed or removed
#' fact is announced in NEWS and kept working for at least one release.
#'
#' @eval fact_reference()
#' @seealso [facts()], [fact()], [facts_df()].
#' @name zufax_facts
NULL
