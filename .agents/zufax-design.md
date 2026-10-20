# zufax — design

*zufax (named fax until 2026-10-20, a pun on facts). A small R package that reports OS, hardware, runtime, environment and package facts, and behaves correctly on bare metal, VMs, containers, Kubernetes pods and Azure.*

Status: **final for 0.1.0** — 2026-10-01. Implementation plan: [roadmap.md](roadmap.md).

Everything in §5 ships in 0.1.0 unless marked *(0.2.0)* or *(later)*.

---

## 1. Motivation

Existing tools report the **host's** resources, not what the current process is actually allowed to use. Inside a container `parallel::detectCores()` returns the node's 64 cores while the pod is limited to 4; `/proc/meminfo` shows the node's RAM while the cgroup memory limit is 8 GiB. This causes oversubscribed thread pools (future, data.table, BLAS, Spark local mode), OOM kills, and misleading diagnostics.

zufax answers three questions reliably, on any substrate:

1. **Where am I running?** OS, hardware, virtualization, container, Kubernetes, cloud (Azure first), R and Python runtimes.
2. **What can I actually use?** Effective CPU and memory, side by side with host values.
3. **What is installed?** System, R and Python package inventories.

## 2. Goals / non-goals

**Goals**
- One call returns a structured, namespaced snapshot of facts.
- Host vs effective values for CPU and memory, cgroup v1, v2 and hybrid.
- Correct detection of bare metal / VM / container / Kubernetes / WSL, and of the Azure service in use.
- Package inventories (system, R, Python) read from package databases on disk, without starting Python or calling `pip`.
- A fast usage probe (process and container CPU/memory, §4.6) cheap enough to call on every log line.
- Lazy, fast, no network by default, safe by default (redaction).
- Extensible: custom resolvers (R functions) and external facts (files, env vars) *(0.2.0)*.
- Outputs usable everywhere: nested list, JSON, flat data frame; DuckDB views *(0.2.0)*.
- Testable on CI via fixture filesystem trees and command/HTTP mocks.
- Pure R, no compiled code; CRAN-friendly.

**Non-goals**
- Continuous monitoring / time series, including sensors (temperatures, fans). `usage()` is a point read on demand: no background sampling, no stored history beyond the previous sample needed for rates.
- Process listing and per-process stats (that is `ps`'s job).
- Security/forensics inventory à la osquery: users, sessions, SSH keys, kernel modules, routes, ARP.
- Deep hardware inventory (PCI, GPU topology) — maybe later.
- Language runtimes other than R and Python.

## 3. Prior art & what we borrow

| Source | Borrow |
|---|---|
| **Facter** (Ruby) | Hierarchical dotted fact names; resolvers with *confinement* and *weight*; custom & external facts; lazy resolution; `processors.extensions` → `cpu.isa_level`; `identity` → `runtime.uid/privileged`; fact blocklist → `zufax.skip`; DMI facts → `dmi.*` *(0.2.0)*; FIPS/SELinux *(0.2.0)* |
| **Ohai** (Ruby) | Init detection → `container.pid1`; optional plugins → opt-in namespaces; `packages` and `languages` plugins → `packages.*`, `runtime.python.*`; many-cloud metadata; filesystem inodes → `disk.tmpdir` inodes *(0.2.0)*; hints → external facts *(0.2.0)* |
| **gopsutil** (Go) | Module-per-facet layout; per-platform implementations behind one interface; virtualization detection; `HOST_PROC`/`HOST_SYS`-style root redirection |
| **automaxprocs / automemlimit** (Go) | cgroup v1/v2 quota and limit logic |
| **Kubernetes kubelet** | Memory "working set" = usage − inactive file cache |
| **ghw** (Go) | Configurable root path so `/proc`/`/sys` can be redirected to fixtures |
| **parallelly::availableCores()** | R-side precedent for cgroup/scheduler-aware core counts; cross-check in tests |
| **sazgar / system_stats** (DuckDB) | SQL-table view of system facts *(0.2.0)* |

**Lesson from Facter's legacy flat names:** fact names are public API from the first CRAN release. They are frozen in this document; any rename after 0.1.0 needs a NEWS entry and a deprecation period.

**Where zufax differs from all of the above:** none of them reports what the *current process* may use (cgroup limits, affinity, effective cores/memory), knows Kubernetes pods or the Downward API, or reports per-fact status and source. Only parallelly does the CPU part, in R.

## 4. Architecture

```
facts()  ──►  registry ──► resolvers (per fact, per platform)
                 │              │  confine(): os, other facts
                 │              │  resolve(ctx): value + metadata
                 ▼              ▼
             session cache      ctx: read_*() (root-aware) · run_cmd() · http_get() · fact()
                 │
                 ▼
   outputs: lazy "zufax" object · nested list · flat data.frame · JSON
```

### 4.1 Resolver contract

Each resolver is a small object (internal in 0.1.0; `register_resolver()` exported in 0.2.0):

```r
resolver(
  name     = "memory.cgroup.limit",
  confine  = list(os = "linux"),         # predicates; not_applicable (not error) when false
  weight   = 100,                        # highest suitable weight wins
  depends  = c("cgroup.version"),
  network  = FALSE,                      # TRUE → runs only when cloud = TRUE
  resolve  = function(ctx) { ... }       # ctx$root, ctx$read(), ctx$cmd(), ctx$http(), ctx$fact()
)
```

Every resolved fact carries metadata:

| field | meaning |
|---|---|
| `value` | typed value |
| `status` | `ok` · `not_applicable` · `unavailable` · `error` |
| `source` | file / command / env var / URL used (e.g. `/sys/fs/cgroup/memory.max`) |
| `resolver` | resolver id (built-in, custom, external) |
| `elapsed` | resolution time |
| `message` | why a fact is not `ok` (e.g. "skipped by zufax.skip", "needs cloud = TRUE") |

Errors never propagate from `facts()`; they become `status = "error"` with a message. `strict = TRUE` or `options(zufax.strict = TRUE)` re-raises.

### 4.2 Namespaces: default and opt-in

- **Default:** `os`, `cpu`, `memory`, `cgroup`, `virtualization`, `container`, `k8s`, `cloud` (offline facts), `runtime`, `env`, `disk`. Covered by `print(facts())` and `as.list(facts())`.
- **Opt-in:** `packages` (heavy) — resolved only when requested by name.
- **Network facts** (`network = TRUE` resolvers, i.e. IMDS) additionally need `cloud = TRUE` or `options(zufax.cloud = TRUE)`; otherwise `not_applicable` with message "needs cloud = TRUE".
- **Blocklist:** `options(zufax.skip = c(...))` skips facts or whole namespaces.

### 4.3 I/O through three wrappers

- **Files:** readers (`read_file()`, `read_lines()`, `read_kv()`, `list_dir()`, `file_exists()`) prefix the root `getOption("zufax.root", Sys.getenv("ZUFAX_ROOT", "/"))` and return `NULL` on missing/unreadable files. Enables fixture-based tests and inspecting a host mounted into a debug container (`/host`).
- **Commands:** `run_cmd()` — `Sys.which()` check, `system2(timeout = )`, mock hook `options(zufax.cmd_mock = )`.
- **HTTP:** `http_get()` — used only by IMDS resolvers; fixed URL allowlist, 1 s timeout, no retries, no redirects, proxy bypassed for link-local addresses, mock hook `options(zufax.http_mock = )`.

### 4.4 Precedence

`external facts (env / facts.d) > custom resolvers > built-in` by default weight, overridable per fact — the Facter model *(0.2.0; in 0.1.0 only built-ins exist)*.

### 4.5 Snapshot object

`facts()` returns an environment-backed object of class `zufax`. Namespaces resolve lazily on `$`/`[[` access and are cached for the session; `facts(c("cpu", "memory"))` resolves the listed namespaces eagerly. `as.list()` forces the default namespaces only. `refresh = TRUE` bypasses the cache; the cache is keyed by fact, root, OS and `cloud`, so changing `zufax.root` gives fresh values. Records with `status = "error"` are never cached (errors may be transient, and `strict = TRUE` must be able to re-raise them). Resolvers that read environment variables or options are declared `cache = FALSE`, and any fact that consults an uncached fact (through `ctx$fact()` or `confine`) is not cached either. Values that come from the live R session rather than the root (`Sys.info()`, `Sys.timezone()`) record that as their `source`.

### 4.6 Fast usage probe

`usage()` reports current CPU and memory use cheaply enough to call on every log line. It **bypasses the registry, metadata and fact cache**; it shares only the parsers.

**Static part, computed once** per session (recomputed when `Sys.getpid()` or `zufax.root` changes): cgroup directory and which usage files exist, page size (from `/proc/self/auxv` `AT_PAGESZ`, fallback one `getconf PAGESIZE`, fallback 4096), `cpu.effective`, `memory.effective.limit`.

**Dynamic part, per call:**

| source | cost | gives |
|---|---|---|
| `proc.time()` | no I/O | process CPU time (all threads) and wall time |
| `/proc/self/statm` | one 1-line read | process RSS (`resident × page size`) |
| cgroup `memory.current` (v1 `memory.usage_in_bytes`) | one 1-line read | container memory, incl. page cache |
| cgroup `cpu.stat` (v2 `usage_usec`, `throttled_usec`; v1 `cpuacct.usage` + `cpu.stat throttled_time`) | one ~6-line read | container CPU time (all processes, incl. parallel workers) and throttling |

Optional per call, `extra = c("host", "working_set")`: `/proc/meminfo` (host available) and `memory.stat` (working set). Off by default because they are larger files.

**Fields** (named double vector, class `zufax_usage`):

| field | meaning |
|---|---|
| `time` | `Sys.time()` as numeric |
| `cpu_process` | cores used by this R process since the previous call (Δ(user+sys) / Δwall); first call: since process start |
| `cpu_cgroup` | cores used by the whole container since the previous call; `NA` on the first call and off-Linux |
| `cpu_throttled` | fraction of wall time the container was throttled since the previous call |
| `cpu_limit` | `cpu.effective_exact` (static) |
| `mem_rss` | process resident memory, bytes |
| `mem_cgroup` | container memory incl. page cache, bytes |
| `mem_limit` | `memory.effective.limit` (static) |
| `mem_pct` | `mem_cgroup / mem_limit`, or `mem_rss / host total` without a cgroup limit |

**Rules:** no commands or network per call; never `gc()` (it triggers a collection); no regex, no data frames, no metadata; never errors (fields become `NA`); the previous sample lives in a package environment and is reset after `fork()` (pid change). `max_age` (seconds) returns the cached sample if it is younger, for hot loops.

**Formatting:** `format.zufax_usage()` and `usage_line()` give a compact string for log messages, e.g. `cpu=1.8/4 thr=3% mem=2.1G/8G(26%) rss=1.2G`. No dependency on any logging package; works inline with logger (`log_info("done {usage_line()}")`), lgr (custom field) or `message()`.

**macOS / Windows:** process CPU from `proc.time()`; `mem_rss` from `ps::ps_memory_info()` when `ps` is installed (compiled, microseconds), else `NA`; container fields `NA`.

**Target:** median ≤ 200 µs per call on Linux with default fields; ≤ 20 µs when served from `max_age`. Measured 2026-10-01 in a `rocker/r-ver:4.5` container: ~170 µs full path, ~17 µs from `max_age` (per-file `readChar()` ≈ 22 µs is the floor; one `tryCatch()` for the whole sample).

## 5. Fact schema

Types: `chr`, `int`, `dbl`, `lgl`, `bytes` (double, since R integers are 32-bit), `cores` (double, fractional allowed), `df` (data frame). Unlimited limits are `Inf`; unknown is `NA`.

### 5.1 `os`
| fact | Linux | macOS | Windows |
|---|---|---|---|
| `os.family` | `Sys.info()` | same | same |
| `os.name`, `os.release.full/major/minor`, `os.id`, `os.id_like` | `/etc/os-release` (fallback `/usr/lib/os-release`) | `sw_vers` | `Sys.info()`, `osVersion` |
| `os.kernel.release`, `os.kernel.version` | `Sys.info()` | same | same |
| `os.arch` | `Sys.info()["machine"]` | same | same |
| `os.hostname` | `Sys.info()["nodename"]` | same | same |
| `os.boot_time`, `os.uptime` | `/proc/stat` btime, `/proc/uptime` | `sysctl kern.boottime` | `NA` in 0.1.0 |
| `os.timezone`, `os.locale` | `Sys.timezone()`, `Sys.getlocale()` | same | same |

### 5.2 `cpu`
| fact | notes / sources |
|---|---|
| `cpu.model`, `cpu.vendor` | `/proc/cpuinfo`; macOS `sysctl machdep.cpu.brand_string`; Windows `PROCESSOR_IDENTIFIER` |
| `cpu.flags` | `/proc/cpuinfo` flags (avx2, avx512f, …) |
| `cpu.isa_level` | derived from flags: `x86-64`, `x86-64-v2` … `x86-64-v4` (psABI feature lists); `arm64` with `+sve`, `+sve2` appended when present; `arm` for 32-bit |
| `cpu.host.logical`, `cpu.host.physical`, `cpu.host.sockets` | `/sys/devices/system/cpu/online`, `/proc/cpuinfo` (physical/core ids), else sysfs topology; `sysctl hw.*`; `NUMBER_OF_PROCESSORS`; any OS falls back to `parallel::detectCores()` (weight 10) |
| `cpu.affinity` | number of CPUs in `/proc/self/status` `Cpus_allowed_list` |
| `cpu.cgroup.quota` | cores from cgroup quota/period (§6) |
| `cpu.cgroup.cpuset` | cpuset CPU count |
| `cpu.cgroup.weight` | v2 `cpu.weight` / v1 `cpu.shares` (informational only) |
| **`cpu.effective`** | `int`, see §6; `cpu.effective_exact` keeps the fractional quota |
| `cpu.load` | named `c(1min, 5min, 15min)` from `/proc/loadavg`; `sysctl vm.loadavg` |

### 5.3 `memory`
| fact | notes / sources |
|---|---|
| `memory.host.total`, `memory.host.available` | `/proc/meminfo` MemTotal/MemAvailable; macOS `sysctl hw.memsize` + `vm_stat` (free + inactive + speculative, approximate); Windows `ps::ps_system_memory()` if installed, else one lazy PowerShell `Get-CimInstance` call |
| `memory.swap.total/free` | `/proc/meminfo` |
| `memory.cgroup.limit`, `memory.cgroup.high`, `memory.cgroup.usage`, `memory.cgroup.swap_limit` | §6 |
| `memory.cgroup.working_set` | `usage − inactive_file` (v2 `memory.stat inactive_file`, v1 `total_inactive_file`) — same definition as the kubelet |
| `memory.rlimit.as`, `memory.rlimit.data` | `/proc/self/limits` ("Max address space", "Max data size"); virtual-memory caps, reported but **not** part of the effective minimum |
| **`memory.effective.limit`** | `min(host.total, cgroup.limit)` |
| **`memory.effective.available`** | `min(host.available, cgroup.limit − cgroup.working_set)` |
| `memory.lxcfs` | `lgl`: `/proc/meminfo` virtualized by LXCFS (detected via mountinfo) |

`memory.cgroup.high` is a soft throttle and is reported separately, not folded into the effective limit. On macOS and Windows effective = host (Windows job-object limits are out of scope).

### 5.4 `cgroup`
| fact | notes |
|---|---|
| `cgroup.version` | `"2"` if `/sys/fs/cgroup/cgroup.controllers` exists; `"1"` if only v1 hierarchies; `"hybrid"`; `NA` off-Linux |
| `cgroup.path` | from `/proc/self/cgroup` |
| `cgroup.mountpoint` | from `/proc/self/mountinfo` |
| `cgroup.namespaced` | `lgl`: path is `/` (cgroup namespace) |
| `cgroup.pids.max` | v2 `pids.max` / v1 pids controller |

### 5.5 `virtualization`
| fact | notes |
|---|---|
| `virtualization.type` | `physical` · `vm` · `unknown` (Linux DMI, Windows BIOS registry key, macOS `kern.hv_vmm_present`) |
| `virtualization.hypervisor` | `hyperv` · `kvm` · `qemu` · `vmware` · `xen` · `virtualbox` · `aws-nitro` · `apple` · … |
| `virtualization.wsl` | `1` / `2` (`/proc/sys/kernel/osrelease` contains `microsoft`; `WSL2` / `microsoft-standard` → 2); `not_applicable` outside WSL |
| sources | Linux: DMI `/sys/class/dmi/id/{sys_vendor,product_name,board_vendor}`, cpuinfo `hypervisor` flag, `/sys/hypervisor/type` (no `systemd-detect-virt`). macOS: `sysctl kern.hv_vmm_present` |

### 5.6 `container`
| fact | notes |
|---|---|
| `container.detected` | `lgl` |
| `container.runtime` | `docker` · `podman` · `containerd` · `cri-o` · `lxc` · `unknown` |
| `container.id` | from `/proc/self/mountinfo` / `/proc/self/cgroup` when discoverable |
| `container.pid1` | `/proc/1/comm`; anything other than `systemd`/`init` (e.g. `tini`, `dumb-init`, `bash`, `R`) is a strong container signal |
| signals | `/.dockerenv`, `/run/.containerenv`, `container=` env (systemd convention), overlay root in mountinfo, v1 `/proc/1/cgroup` paths, PID 1 name, `KUBERNETES_SERVICE_HOST` |

### 5.7 `k8s`
| fact | notes |
|---|---|
| `k8s.detected` | `KUBERNETES_SERVICE_HOST` set **or** service-account dir exists |
| `k8s.namespace` | `/var/run/secrets/kubernetes.io/serviceaccount/namespace` (never read the token) |
| `k8s.pod.name` | Downward API env if mapped, else hostname |
| `k8s.node.name`, `k8s.pod.ip`, `k8s.pod.uid` (uid also from `/var/lib/kubelet/pods/<uid>/` mount roots) | Downward API env; mapping configurable via `options(zufax.k8s.env = c(node.name = "NODE_NAME", pod.ip = "POD_IP", pod.uid = "POD_UID", pod.name = "POD_NAME"))` (these are the defaults) |
| `k8s.pod.labels`, `k8s.pod.annotations` | Downward API volume files, path `options(zufax.k8s.podinfo = "/etc/podinfo")` |
| `k8s.resources.requests/limits` | Downward API `resourceFieldRef` env if mapped; otherwise limits derived from cgroup |

### 5.8 `cloud`

Offline facts (default namespace, no network):

| fact | notes |
|---|---|
| `cloud.provider` | `azure` · `aws` · `gcp` · `NA`, from DMI: Azure chassis asset tag `7783-7084-3265-9085-8269-3286-77` or `Microsoft Corporation` / `Virtual Machine` + `/var/lib/waagent`; `Amazon EC2`; `Google Compute Engine`. Azure PaaS env vars also imply `azure` |
| `cloud.azure.platform` | `vm` · `aks` · `app-service` · `functions` · `container-apps` · `batch` · `azureml` · `databricks` (scale sets show in `cloud.azure.vmss_name`), from platform env vars (`WEBSITE_SITE_NAME`, `FUNCTIONS_WORKER_RUNTIME`, `CONTAINER_APP_NAME`, `AZ_BATCH_NODE_ID`, `AZUREML_*`, `DATABRICKS_RUNTIME_VERSION`, …; verify names against Azure docs during implementation) and `k8s.*` |
| `cloud.azure.service` | named chr of non-secret identifiers from those env vars (App Service site and instance ID, Container App name/revision/replica, Batch pool/node/job/task, Azure ML run/experiment, Databricks runtime) |

IMDS facts (`network = TRUE`; need `cloud = TRUE` and `cloud.provider == "azure"`):

| fact | Azure IMDS field |
|---|---|
| `cloud.region`, `cloud.zone` | `compute.location`, `compute.zone` |
| `cloud.instance.type`, `cloud.instance.id` | `compute.vmSize`, `compute.vmId` |
| `cloud.azure.vm_name`, `.resource_group`, `.subscription_id`, `.vmss_name` | `compute.name`, `.resourceGroupName`, `.subscriptionId`, `.vmScaleSetName` |
| `cloud.azure.priority`, `.eviction_policy` | spot / regular |
| `cloud.azure.image`, `.os_type`, `.environment` | `storageProfile.imageReference` / publisher-offer-sku-version, `compute.osType`, `compute.azEnvironment` |
| `cloud.azure.tags` | `compute.tagsList`, redacted like env vars |
| `cloud.azure.network.private_ip`, `.public_ip` | `network.interface[*].ipv4` |

JSON (`facts_json()`): `Inf` → `"Inf"`, `NA` → `null`, POSIXct → ISO 8601 UTC, named vectors → objects, data frames → arrays of objects, length-one vectors → scalars.

Rules: one request `GET http://169.254.169.254/metadata/instance?api-version=<pinned>` with header `Metadata: true`; URL allowlist enforced in `http_get()`; **never** `/metadata/identity/*` or `/metadata/attested/*`; in a pod the answer describes the **node VM**; blocked IMDS → `unavailable` with the reason.

*(0.2.0)* AWS IMDSv2 (token PUT first) and GCP (`metadata.google.internal`, header `Metadata-Flavor: Google`); Azure `/metadata/scheduledevents`.

### 5.9 `runtime`

R and process:

| fact | notes |
|---|---|
| `runtime.r.version`, `runtime.r.platform`, `runtime.r.home` | `R.version`, `R.home()` |
| `runtime.r.blas`, `runtime.r.lapack` | BLAS library path from `extSoftVersion()`; LAPACK as `c(version = La_version(), library = La_library())` |
| `runtime.r.libpaths` | `.libPaths()` |
| `runtime.r.repos` | `getOption("repos")`, userinfo/tokens stripped |
| `runtime.r.renv` | active renv project and lockfile path (`RENV_PROJECT`, `renv/activate.R`); no call into renv |
| `runtime.threads.env` | `OMP_NUM_THREADS`, `MKL_NUM_THREADS`, `OPENBLAS_NUM_THREADS`, `R_PARALLELLY_AVAILABLECORES_*`, `MC_CORES` |
| `runtime.threads.options` | `getOption("mc.cores")`, `getOption("Ncpus")` |
| `runtime.parallelly_cores` | `parallelly::availableCores()` if installed, for cross-checking |
| `runtime.pid`, `runtime.user` | `Sys.getpid()`, `Sys.info()["user"]` |
| `runtime.uid`, `runtime.gid`, `runtime.privileged` | `/proc/self/status` (Linux), `id` (macOS), `whoami /groups` (Windows, lazy; `NA` if too slow) |

Python:

| fact | notes |
|---|---|
| `runtime.python.path`, `.version`, `.implementation`, `.prefix`, `.env_type`, `.env_path`, `.site_packages` | discovery: `RETICULATE_PYTHON` → `VIRTUAL_ENV` → `CONDA_PREFIX` → `python3` → `python` (Windows also the `py` launcher); read `pyvenv.cfg` / `conda-meta/` first, else **one** probe command printing JSON (5 s timeout). `env_type`: `venv` · `uv` · `conda` · `system` |
| `runtime.python.reticulate` | interpreter bound by reticulate, **only** if reticulate is loaded and Python already initialized; zufax never initializes Python |

### 5.10 `env`
| fact | notes |
|---|---|
| `env.vars` | named chr, **redacted by default**: names matching `(?i)(key|token|secret|password|passwd|credential|auth|conn(ection)?_?str|sas|header|(^|_)pat($|_))` → `"<redacted>"`; any value that is a URL with `user:pass@` has the userinfo stripped |
| modes | `options(zufax.redact = "default")` · `"allowlist"` (only names in `zufax.redact_allowlist`) · `"none"` (explicit opt-in) |
| `env.proxies` | `http_proxy`, `https_proxy`, `no_proxy` (userinfo stripped) |

### 5.11 `disk`, `network`
- `disk.tmpdir.path`, `disk.tmpdir.fstype` (mountinfo on Linux, longest matching mount point), `disk.tmpdir.free` (`df -Pk`, not on Windows in 0.1.0). Important in pods: emptyDir vs overlay. Free inodes *(0.2.0)*.
- `disk.mounts` *(0.2.0)*: mount point, fs type, size, free; pseudo filesystems filtered.
- `network.interfaces` *(0.2.0)*: name, addresses (`/sys/class/net`).

### 5.12 `packages` (opt-in namespace)
Not resolved by `print(facts())` or `as.list(facts())`; ask for it by name. Each inventory is a `df` fact; `facts_df()` stores it in a list-column, JSON writes an array of objects.

| fact | sources | columns |
|---|---|---|
| `packages.system.installed` (+ `packages.system.manager`, `packages.system.count`) | dpkg `/var/lib/dpkg/status` (installed only; distroless `status.d/`) · apk `/lib/apk/db/installed` · pacman `/var/lib/pacman/local/*/desc` · rpm `rpm -qa --qf …` · Homebrew `Cellar/` and `Caskroom/` listing (no `brew` call) · Windows `readRegistry()` on the `Uninstall` keys | name, version, arch / kind / publisher |
| `packages.r` | `installed.packages(fields = c("Repository", "RemoteType", "RemoteSha"))` over `.libPaths()` | name, version, libpath, priority, built, source (RemoteType, else Repository), remote_sha |
| `packages.python` | `*.dist-info` / `*.egg-info` directory names in each `runtime.python.site_packages`; `INSTALLER` file; conda `conda-meta/*.json` (marked `source = "conda"`); no `pip` call | name (PEP 503-normalized), version, location, installer, source (`site-packages` / `conda`) |

### 5.13 Later
- `dmi.*` *(0.2.0)*: BIOS, board, chassis, product; serials and UUIDs redacted by default.
- `security.fips`, `security.selinux` *(0.2.0, low priority)*.

## 6. cgroup details

### v2
- Own cgroup: `/proc/self/cgroup` → `0::/<path>`; files under `<mount>/<path>` (usually `/sys/fs/cgroup` directly when namespaced).
- CPU: `cpu.max` = `"max 100000"` (unlimited) or `"<quota> <period>"` → cores = quota/period.
- cpuset: `cpuset.cpus.effective` (range list `0-3,8`).
- Memory: `memory.max`, `memory.high` (`"max"` → `Inf`), `memory.current`, `memory.swap.max`, `memory.stat` (`inactive_file`).
- Walk **up** the hierarchy while inside the visible tree and take the minimum limit (parent limits apply).

### v1
- `/proc/self/cgroup` lines `id:controllers:path`; mountpoints per controller from `/proc/self/mountinfo`.
- CPU: `cpu.cfs_quota_us` (`-1` = unlimited) / `cpu.cfs_period_us`.
- cpuset: `cpuset.cpus`.
- Memory: prefer `hierarchical_memory_limit` from `memory.stat` (already the minimum over ancestors, which are often not visible inside a container); fall back to `memory.limit_in_bytes`. Values near `2^63` (page-rounded) mean unlimited → `Inf`. Usage `memory.usage_in_bytes`, `total_inactive_file` from `memory.stat`, `memory.soft_limit_in_bytes`.

### Hybrid
- v1 controllers plus a v2 unified mount; read each controller from wherever it is mounted.

### Effective values
```
cpu.effective              = max(1, min(host.logical, |affinity|, |cpuset|, ceil(quota_cores)))
cpu.effective_exact        = min(host.logical, |affinity|, |cpuset|, quota_cores)
memory.cgroup.working_set  = cgroup.usage − inactive_file
memory.effective.limit     = min(host.total, cgroup.limit)
memory.effective.available = min(host.available, cgroup.limit − cgroup.working_set)
```
`ceil` for thread counts: a 1.5-core quota can keep 2 threads busy. `memory.high`, swap limits and rlimits are reported but not folded in.

## 7. Public API

0.1.0:

```r
f <- facts(namespaces = NULL, cloud = FALSE, refresh = FALSE, strict = FALSE)
f$cpu$effective                           # resolves cpu.* on access
fact("memory.cgroup.limit")               # single fact value
facts(c("cpu", "memory", "k8s"))          # subset, resolved eagerly
facts("packages")                         # opt-in namespace
facts(cloud = TRUE)                       # allow IMDS (Azure in 0.1.0)
facts_df(f)                               # fact | value | status | source | resolver | elapsed | message
facts_json(f, pretty = FALSE, metadata = FALSE)   # requires jsonlite
print(f)                                  # substrate summary + host vs effective + R/Python versions

effective_cores()                         # integer >= 1, safe default for thread pools
effective_memory(what = c("limit", "available"))  # bytes (double)

usage(extra = NULL, max_age = 0)          # fast CPU/memory usage probe (§4.6), class "zufax_usage"
usage_line(...)                           # compact string for log lines
```

S3 methods: `print`, `format`, `as.list`, `$`, `[[`, `names` for class `zufax`; `print`, `format` for class `zufax_usage`.

Options: `zufax.root` (env `ZUFAX_ROOT`), `zufax.strict`, `zufax.skip`, `zufax.cloud`, `zufax.redact`, `zufax.redact_allowlist`, `zufax.k8s.env`, `zufax.k8s.podinfo`; testing only (documented as internal): `zufax.os` (pretend to be another OS, e.g. to run Linux fixtures on macOS), `zufax.cmd_mock`, `zufax.http_mock`.

*(0.2.0)*:

```r
register_resolver(...)                    # custom facts
external_facts(dirs = facts_d_dirs())     # facts.d: *.json / *.yaml / *.txt (k=v) / executables (opt-in)
# env external facts: ZUFAX_FACT_<name>=value
facts_duckdb(con, f)                      # CREATE VIEW per namespace
capture_fixture(path)                     # tar the relevant /proc,/sys,/etc files (redacted)
zufax::main()                               # CLI: zufax [namespace...] --json
```

## 8. Testing strategy

- **Fixture trees** in `data-raw/fixtures/<scenario>/` mirroring `/proc`, `/sys`, `/etc`, `/var/lib`, packed by `data-raw/pack-fixtures.R` into `tests/testthat/fixtures/<scenario>.tar.gz` (R CMD build rejects paths over 100 bytes and flags hidden files like `run/.containerenv`). Tests extract them, set `zufax.root` and `zufax.os`, and snapshot a per-fact report; a source-only test checks tarballs and trees are in sync. Real captures come from `data-raw/capture-fixture.sh` (cgroup v2 via podman); v1, hybrid, a parent-limited k8s pod and LXCFS are written by `data-raw/synthetic-fixtures.R`.
  - Resources: bare-metal Linux · Docker v1 `--cpus=1.5 --memory=512m` · Docker v2 unlimited · Docker v2 `--cpus=2 --memory=1g` · k8s pod v2 with parent limit · cpuset-pinned · LXCFS · hybrid.
  - Substrate: Azure VM · AWS EC2 · GCP VM · WSL2 · rootless Podman · AKS pod with Downward API.
  - Runtime/packages: venv, conda prefix, site-packages with dist-info/egg-info; dpkg status, apk db, pacman local, Homebrew Cellar.
- An internal capture helper builds fixtures from real machines, copying only files resolvers read; redact before committing.
- **Command mocks** (`zufax.cmd_mock`): macOS `sysctl`/`sw_vers`/`vm_stat`, Windows PowerShell, `rpm -qa`, the Python probe. **Registry mock** for Windows packages. **HTTP mock** (`zufax.http_mock`): recorded Azure IMDS response with IDs/IPs replaced.
- **Live CI** (GitHub Actions): ubuntu/macos/windows matrix (invariants only); Docker job (`--cpus`, `--memory`, `--cpuset-cpus`) in Debian, Alpine and Fedora images; `kind` pod with limits and Downward API; Python venv/conda vs `pip list`; IMDS on the Azure-hosted runner if reachable.
- Cross-check `cpu.effective` against `parallelly::availableCores()` where both apply.
- Safety tests: no network unless `cloud = TRUE`; IMDS URL allowlist; reticulate never initialized; redaction table.

## 9. Performance & safety

- Lazy per-namespace resolution; per-session cache; `refresh = TRUE`.
- Target: default Linux snapshot (no `packages`, no IMDS) < 50 ms. Package inventories timed separately.
- Target: `usage()` median ≤ 200 µs on Linux (§4.6).
- No network unless `cloud = TRUE`; IMDS URL allowlist; 1 s timeout.
- No command execution where a file read suffices.
- Never read service-account tokens, cloud credentials, or IMDS identity/attested endpoints.
- Never start Python inside the R session.
- Redaction of env vars, proxy and repo URLs, Azure tags.
- No writes outside `tempdir()`.
- External-fact executables disabled unless `options(zufax.exec_external = TRUE)` *(0.2.0)*.

## 10. Packaging (CRAN)

- `Depends: R (>= 4.1.0)`. Imports: base `utils`, `tools`, `parallel` only.
- Suggests: `jsonlite`, `parallelly`, `ps` (faster Windows memory; process RSS in `usage()` on macOS/Windows), `testthat (>= 3.0.0)`, `withr`; `curl` only if base R can't give IMDS a reliable 1 s timeout (§12). *(0.2.0)*: `duckdb`, `DBI`.
- No compiled code.
- Examples/tests: no network, no Python, no writes outside `tempdir()`, every command guarded by `nzchar(Sys.which())`; scenario assertions only against fixtures; live tests assert invariants only (CRAN machines may themselves be containers or VMs).

## 11. Releases

| release | scope |
|---|---|
| **0.1.0** (first CRAN) | Everything in §5 not marked otherwise: engine, Linux resources and substrate, `usage()` fast probe, Azure (offline + IMDS), R/Python runtime, env, `disk.tmpdir`, package inventories, macOS/Windows basics, list/df/JSON/print. Plan: [roadmap.md](roadmap.md) |
| **0.2.0** | Custom & external facts, `facts_duckdb()`, CLI, `capture_fixture()` export, AWS/GCP IMDS, Azure scheduled events, `disk.mounts`, `network.interfaces`, `dmi.*`, tmpdir inodes, FIPS/SELinux |
| **0.2.0 (added)** | `apply_limits()` incl. R vector heap limit from the container memory limit; `hpc` and `platform` namespaces; effective privileges (capabilities); BLAS identification (see roadmap "After 0.1.0") |
| **later** | GPUs, NUMA and caches, hybrid CPU core types, more substrates (chroot, gVisor, …); cross-session fact cache with TTL; `ps`-based process facts; optional Rust core (sysinfo + cgroup parsing) shared with a DuckDB extension and a standalone CLI |

## 12. Decisions

| # | Question | Decision |
|---|---|---|
| 1 | Name | **zufax** — never on CRAN incl. archive (checked 2026-10-01); check GitHub / r-universe before submission. |
| 2 | Snapshot object | Environment-backed lazy `zufax` object (§4.5). |
| 3 | "No limit" | `Inf` in R; the string `"Inf"` in JSON (documented). `NA` always means unknown. |
| 4 | `memory.high` in effective memory | No; reported separately as a soft limit. |
| 5 | `ps` | No process facts. `ps` only in Suggests as a faster Windows memory source. |
| 6 | `effective_cores()` and `MC_CORES` / `R_PARALLELLY_*` | Purely resource-based. Policy variables reported in `runtime.threads.*`; docs point to `parallelly` for policy. |
| 7 | Windows scope | Host-level facts only; no Windows containers; nothing needing admin rights. |
| 8 | Effective available memory | Uses the working set (usage − inactive file), like the kubelet. |
| 9 | `effective_memory()` | `what = c("limit", "available")`, default `"limit"`; `Inf` falls back to host total. |
| 10 | Package inventories | Opt-in namespace; one `df` fact per source; files over commands. |
| 11 | Cloud | Azure only in 0.1.0 (offline platform detection + IMDS behind `cloud = TRUE`). |
| 12 | Fact names | Frozen as written in §5. |
| 13 | Usage for logging | Separate fast path `usage()` / `usage_line()` outside the fact engine (§4.6); pure R on Linux, `ps` (Suggests) for RSS elsewhere. |

| 14 | IMDS HTTP client | Base R `url(method = "libcurl", headers = )` with `options(timeout = 1)` and the metadata host added to `no_proxy`. Spike (2026-10-01): headers are sent; a non-responding address fails after 1.07 s; no `curl` dependency. JSON parsing uses jsonlite (Suggests); without it IMDS facts are `unavailable`. |
| 15 | IMDS caching | One request per session, including failures (a blocked IMDS costs its timeout once); `refresh = TRUE` asks again. |

Still open:
- **Azure PaaS env var names:** the names used (`WEBSITE_SITE_NAME`, `FUNCTIONS_WORKER_RUNTIME`, `CONTAINER_APP_NAME`, `AZ_BATCH_NODE_ID`, `AZUREML_RUN_ID`, `DATABRICKS_RUNTIME_VERSION`) follow Azure's documentation as known at design time; confirm on real services before release (Stage 8).
