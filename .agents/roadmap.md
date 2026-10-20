# zufax — roadmap to 0.1.0 (first CRAN release)

Companion to [zufax-design.md](zufax-design.md), which is the source of truth for fact names, formulas and decisions. Section references (§) point there.

Status: **final** — 2026-10-01 · Progress: Stages 0–9 and 11 done; Stage 10 waiting on the maintainer

---

## 0.1.0 in one paragraph

A pure-R, zero-dependency package that answers *"where am I running?"*, *"what can I actually use?"* and *"what is installed?"* on Linux bare metal, VMs, Docker/Podman containers, Kubernetes pods and Azure, with host-level facts on macOS and Windows. It ships the resolver engine; the `os`, `cpu`, `memory`, `cgroup`, `virtualization`, `container`, `k8s`, `cloud`, `runtime` (R and Python), `env` and `disk.tmpdir` facts; package inventories (system, R, Python); Azure detection offline and via IMDS (opt-in); `effective_cores()` / `effective_memory()`; and list / data frame / JSON / printed output.

## Scope

| In 0.1.0 | Deferred |
|---|---|
| Engine: resolvers, registry, root-aware readers, `run_cmd()`, `http_get()`, mocks, session cache, opt-in namespaces, `zufax.skip` (§4) | Public `register_resolver()`, external facts `facts.d` / `ZUFAX_FACT_*` (0.2.0) |
| Linux `os`, `cpu` (incl. `isa_level`), `memory` (incl. working set, rlimits), `cgroup` v1/v2/hybrid, effective values (§5.1–5.4, §6) | AWS and GCP IMDS, Azure scheduled events (0.2.0) |
| `virtualization`, `container` (incl. `pid1`), `k8s` (env + Downward API), WSL (§5.5–5.7) | `facts_duckdb()`, CLI, exported `capture_fixture()` (0.2.0) |
| `cloud`: provider guess from DMI; Azure platform detection offline; Azure IMDS with `cloud = TRUE` (§5.8) | `disk.mounts`, `network.interfaces`, tmpdir inodes (0.2.0) |
| `runtime`: R, Python, uid/privileged; `env` with redaction; `disk.tmpdir` (§5.9–5.11) | `dmi.*`, FIPS/SELinux (0.2.0) |
| `packages`: system, R, Python inventories (§5.12) | Cross-session fact cache with TTL (later) |
| macOS & Windows: `os`, `cpu.host.*`, `memory.host.*`, `runtime`, `env`, `packages` | Process facts, Windows containers, Rust core (later / maybe never) |
| `facts()`, `fact()`, `facts_df()`, `facts_json()`, `print()`, `effective_cores()`, `effective_memory()` (§7) | Sensors, users/sessions, other languages (non-goals, §2) |
| `usage()` / `usage_line()`: fast CPU/memory usage probe for logging, ≤ 200 µs on Linux (§4.6) | |

---

## Stage 0 — Housekeeping

**Goal:** a clean, correctly described empty package. Design decisions are already recorded in §12.

- [x] Add `^\.agents$` to `.Rbuildignore` (otherwise it ends up in the tarball and `R CMD check` notes it).
- [x] Fill in `DESCRIPTION`: Title, Description, `Authors@R` (**todo:** real name, ORCID if available), `BugReports`, `URL` with the GitHub repo, `Depends: R (>= 4.1.0)`, Suggests per §10.
- [x] `README.Rmd` stub with the motivation from §1.
- [x] Check the name `zufax` on CRAN, the CRAN archive and r-universe (§12 #1): free as of 2026-10-01.
- [x] Add a `lintr` config (no CI lint job yet).

**Done when:** `R CMD check` is clean on the empty package in CI.

---

## Stage 1 — Engine

**Goal:** the machinery every fact uses (§4), exercised with toy resolvers.

Files (suggested): `R/resolver.R`, `R/registry.R`, `R/context.R`, `R/read.R`, `R/cmd.R`, `R/http.R`, `R/cache.R`, `R/facts.R`, `R/df.R`, `R/types.R`.

- [x] `resolver()` constructor and validation: `name`, `confine`, `weight`, `depends`, `network`, `resolve` (§4.1). Internal in 0.1.0.
- [x] Registry: built-ins registered at load time; highest-weight resolver whose `confine` predicates pass wins; `not_applicable` when none pass.
- [x] Confine predicates on `os` and on other facts' values, evaluated lazily.
- [x] Namespaces: default vs opt-in (`packages`); `network = TRUE` resolvers run only with `cloud = TRUE` / `zufax.cloud`; `zufax.skip` blocklist (§4.2). Each case sets `status` and `message`.
- [x] Context `ctx`: `root`, `read()`, `cmd()`, `http()`, `fact()` (dependency resolution, cycle detection).
- [x] Readers `read_file()`, `read_lines()`, `read_kv()`, `list_dir()`, `file_exists()` with root prefix; `NULL` on missing/unreadable; path recorded as `source` (§4.3).
- [x] `run_cmd()`: `Sys.which()` check, `system2(timeout = )`, stdout/stderr capture, `zufax.cmd_mock` hook.
- [x] `http_get()` skeleton: URL allowlist, `zufax.http_mock` hook (real transport comes in Stage 6).
- [x] Fact record with `value`, `status`, `source`, `resolver`, `elapsed`, `message`; error containment; `strict`.
- [x] Session cache keyed by fact + root; `refresh = TRUE`; invalidated when `zufax.root` changes.
- [x] `facts()` lazy `zufax` object (§4.5) with `$`, `[[`, `names()`, `as.list()`; `fact()`; `facts_df()` with list-column for vector and `df` values.
- [x] Type helpers: bytes, cores, range lists (`0-3,8`), `"max"` → `Inf`, kB/MiB parsing.

Tests: toy resolvers covering weight selection, confinement, opt-in namespaces, network gating, `zufax.skip`, dependencies, cycles, error → status, strict, cache/refresh, root switching, command and HTTP mocks.

**Done when:** a toy resolver set produces a correct `facts_df()` against a fixture root, and errors never escape `facts()` unless strict.

---

## Stage 2 — Linux CPU, memory and cgroups

**Goal:** host vs effective CPU and memory, correct under cgroup v1, v2 and hybrid (§5.2–5.4, §6).

- [x] `cgroup.*` from `/proc/self/cgroup` and `/proc/self/mountinfo`, v1/v2/hybrid.
- [x] v2 readers: `cpu.max`, `cpuset.cpus.effective`, `memory.max`, `memory.high`, `memory.current`, `memory.swap.max`, `memory.stat`; walk up the visible hierarchy taking the minimum.
- [x] v1 readers: CFS quota/period, `cpuset.cpus`, `hierarchical_memory_limit` (fallback `memory.limit_in_bytes`, ≈2^63 → `Inf`), `memory.usage_in_bytes`, `total_inactive_file`, soft limit.
- [x] `cpu.host.*`, `cpu.model`, `cpu.vendor`, `cpu.flags`, `cpu.isa_level` (x86-64 v1–v4; arm64 features), `cpu.affinity`, `cpu.load`.
- [x] `cpu.cgroup.quota/cpuset/weight`; `cpu.effective` and `cpu.effective_exact` (§6).
- [x] `memory.host.*`, `memory.swap.*`, `memory.cgroup.*` incl. `working_set`; `memory.rlimit.as/data` from `/proc/self/limits`; `memory.lxcfs`.
- [x] `memory.effective.limit` and `memory.effective.available` (working-set based, §6).
- [x] `effective_cores()` (integer ≥ 1; falls back to `parallel::detectCores()`, then 1) and `effective_memory(what = c("limit", "available"))` (`Inf` → host total).

Fast usage probe (§4.6), built on the same parsers but outside the engine:
- [x] Static setup cached in a package environment: cgroup dir and available usage files, page size (`/proc/self/auxv` `AT_PAGESZ` via `readBin`, fallback `getconf PAGESIZE` once, fallback 4096), `cpu.effective_exact`, `memory.effective.limit`. Recomputed when the pid or `zufax.root` changes.
- [x] Per-call reads: `proc.time()`, `/proc/self/statm`, cgroup `memory.current` / `memory.usage_in_bytes`, cgroup `cpu.stat` / `cpuacct.usage`. Optional `extra = c("host", "working_set")`.
- [x] Rates from the previous sample (process CPU, cgroup CPU, throttling); reset after fork; `max_age` reuse.
- [x] `usage()` returns a named double vector of class `zufax_usage`; `format()` / `print()` / `usage_line()`.
- [x] Micro-optimize the readers used here: benchmark `readLines(n = 1)`, `readChar()` and `readBin()` on `/proc` files and use the fastest; `strsplit(fixed = TRUE)`, no regex; never `gc()`.
- [x] Never errors: every field falls back to `NA`.

Fixtures (trees in `data-raw/fixtures/`, shipped as tarballs in `tests/testthat/fixtures/`). Captured with `data-raw/capture-fixture.sh` on a podman cgroup v2 VM: `linux-vm-host`, `docker-v2-unlimited`, `docker-v2-cpus2-mem1g`, `docker-v2-cpus1.5-mem512m`, `docker-v2-cgroupns-host` (nested non-namespaced path), `cpuset-pinned`. Synthetic (`data-raw/synthetic-fixtures.R`): `docker-v1-cpus1.5-mem512m`, `hybrid`, `k8s-v2-limits` (limit only on the pod cgroup), `lxcfs`. A true bare-metal fixture comes with Stage 3 (DMI).

Tests: per-fixture expectations on effective values; `expect_snapshot()` of `facts_df()` per scenario; malformed/empty/missing files → `unavailable`, never `error`. For `usage()`: rates computed from two fixture states (swap fixture files between calls), first-call behaviour, pid-change reset, `max_age`, `NA` on missing files, `usage_line()` snapshot.

**Done when:** every fixture gives the right `effective_cores()` / `effective_memory()`; on the CI Ubuntu runner both return sane values (≥ 1, ≤ host); and `usage()` has a median ≤ 200 µs there.

**Result:** in a `--cpus=1.5 --memory=512m` container, `effective_cores()` = 2 (`detectCores()` = 4), `effective_memory()` = 512 MiB, full snapshot 10.6 ms, `usage()` ~170 µs.

---

## Stage 3 — Linux OS and substrate detection

**Goal:** answer *"where am I running?"* on Linux (§5.1, §5.5–5.7, offline part of §5.8).

- [x] `os.*` from `Sys.info()` and os-release; boot time and uptime; timezone, locale.
- [x] `virtualization.type/hypervisor` from DMI, cpuinfo `hypervisor` flag, `/sys/hypervisor/type`; `virtualization.wsl`.
- [x] `container.detected/runtime/id/pid1` from the §5.6 signals; document which signal wins.
- [x] `k8s.*`: detection, namespace (never the token), Downward API env mapping with defaults (`zufax.k8s.env`), labels/annotations volume (`zufax.k8s.podinfo`), limits derived from cgroup when not mapped.
- [x] `cloud.provider` from DMI (Azure asset tag / Microsoft + waagent, Amazon EC2, Google Compute Engine).

Fixtures (add, synthetic): `linux-baremetal`, `azure-vm`, `aws-ec2`, `gcp-vm`, `wsl2`, `aks-pod-downward-api`. Rootless podman is covered by the captured `docker-v2-*` fixtures.

Tests: per-fixture classification; "no false positives" on bare metal (physical, no container, no k8s, no cloud).

**Done when:** each fixture is classified correctly and the GitHub Ubuntu runner reports `vm` / `azure` (asserted by `test-live.R` on hosted runners).

**Result:** live in a podman container: Ubuntu 24.04, `vm`/`apple`, container `podman` with its 64-hex id, PID 1 `R`. Also added: uncached-ness propagates through dependencies, so env-dependent facts stay fresh.

---

## Stage 4 — Runtime (R and Python), environment, outputs

**Goal:** language-runtime facts, safe environment reporting, every output format (§5.9–5.11, §7).

R and process:
- [x] `runtime.r.*` (version, platform, home, BLAS/LAPACK, libpaths, repos with credentials stripped, renv detection), `runtime.threads.*`, `runtime.parallelly_cores`, `runtime.pid/user`.
- [x] `runtime.uid/gid/privileged`: Linux `/proc/self/status`; macOS `id`; Windows `whoami /groups` lazily, `NA` if too slow.

Python, without starting Python in the R session:
- [x] Interpreter discovery order per §5.9; the winning source recorded as `source`.
- [x] `pyvenv.cfg` and `conda-meta/python-*.json` first; otherwise one probe command printing JSON (`sys.version_info`, `sys.implementation.name`, `sys.prefix`, `sys.base_prefix`, `site.getsitepackages()`, `site.getusersitepackages()`), 5 s timeout.
- [x] `runtime.python.reticulate` only if reticulate is loaded and already initialized; never call `py_config()` or anything that initializes Python.

Environment:
- [x] `env.vars` with the §5.10 pattern and modes; URL userinfo stripping; `env.proxies`.
- [x] Redaction test table: `AZURE_STORAGE_CONNECTION_STRING`, `AZURE_CLIENT_SECRET`, `IDENTITY_HEADER`, `MSI_SECRET`, `GITHUB_PAT`, `AWS_SECRET_ACCESS_KEY`, `DATABASE_URL` with password, `*_SAS`; and must-not-redact: `PATH`, `R_HOME`, `PWD`.
- [x] `disk.tmpdir`: path, fs type, free space.

Outputs:
- [x] `print.zufax()`: substrate line (bare metal / VM / container / pod, cloud, Azure platform), host-vs-effective table for CPU and memory, R and Python versions; human-readable bytes; no `cli` dependency; package counts only if already resolved.
- [x] `facts_json()` via jsonlite (clear error if missing); `Inf` → `"Inf"`; `metadata = FALSE` default.
- [x] `format()` / `str()` that don't force resolution.

Fixtures (add): venv tree with `pyvenv.cfg`, conda prefix with `conda-meta/`, recorded Python probe output.

Tests: `print()` snapshots per fixture; JSON round-trip (`Inf`, `NA`, named vectors, lists, `df`); redaction table; reticulate never initialized (skip if not installed).

**Done when:** `print(facts())` on the `k8s-v2-limits` fixture shows pod limits next to node values on one screen, and `runtime.python.*` is right for the venv, conda and system fixtures.

**Result:** live in a `--cpus=1.5 --memory=512m` container the summary reads `cpu host 4 | effective 1.5 (2 threads)`, `memory host 5.8G | limit 512M | available 433M`, 0 errors. The default snapshot grew to ~41 ms (runtime, env and disk add `df` and other calls): still under 50 ms, revisit in Stage 8. `disk.tmpdir` became three facts (`path`, `fstype`, `free`). Code is formatted with air (`air.toml`, line width 100).

---

## Stage 5 — Package inventories

**Goal:** answer *"what is installed?"* (§5.12). Opt-in namespace; one `df` fact per source.

- [x] `packages.system.installed`, one resolver per manager, highest applicable weight wins: dpkg (installed entries only), apk, pacman, rpm (`rpm -qa --qf '%{NAME}\t%{VERSION}-%{RELEASE}\t%{ARCH}\n'`), Homebrew (`HOMEBREW_PREFIX` or standard prefixes; `Cellar/` and `Caskroom/` listing), Windows (`readRegistry()` on HKLM, HKLM WOW6432Node and HKCU `Uninstall` keys, behind a mockable wrapper). Plus `packages.system.manager` and `packages.system.count`.
- [x] `packages.r` from `installed.packages(fields = c("Repository", "RemoteType", "RemoteSha"))`.
- [x] `packages.python` from dist-info/egg-info directory names (read `METADATA` only when the name can't be parsed), `INSTALLER`, conda `conda-meta/*.json`.

Fixtures (add): `dpkg-status`, `apk-installed`, `pacman-local`, recorded `rpm -qa`, Homebrew Cellar tree, mocked registry listing, site-packages tree.

Tests: parser per manager; malformed entries skipped; `packages` never resolved by `print(facts())` / `as.list(facts())`.

**Done when:** on each CI OS `facts("packages")` returns non-empty system and R inventories, and the Python inventory matches `pip list` in a CI venv.

**Result:** non-empty system and R inventories are asserted on every GitHub Actions OS (`test-packages.R`); the `pip list` comparison moves to the Stage 8 Python job. In an Ubuntu container zufax lists 273 dpkg packages in 43 ms, exactly the `ii` entries of `dpkg-query` (the other 29 are removed `rc` packages). Fixtures are inline test roots rather than tarballs. Distroless `status.d/` is supported.

---

## Stage 6 — Azure

**Goal:** know which Azure service the process runs on, and fetch instance metadata when allowed (§5.8).

- [x] **Spike first:** confirm base R `url(method = "libcurl", headers = c(Metadata = "true"))` can reach IMDS with a reliable 1 s timeout and proxy bypass (temporarily set `no_proxy` for `169.254.169.254`). If not, use `curl` from Suggests and report `unavailable` without it. Record the outcome in §12.
- [x] Offline: `cloud.azure.platform` and `cloud.azure.service.*` from platform env vars; verify each variable name against current Azure docs.
- [x] `http_get()` transport: allowlist, 1 s timeout, no retries, no redirects.
- [x] IMDS resolver: one `GET /metadata/instance?api-version=<pinned>`; map fields per §5.8; tags redacted; pinned API version recorded in `source`.
- [x] Blocked IMDS (network policy, App Service, Container Apps) → `unavailable` with the reason. `print()` notes "node VM" when `k8s.detected`.

Fixtures (add): env-var sets per PaaS platform; recorded IMDS JSON with IDs and IPs replaced.

Tests: platform detection per env set; IMDS parsing; timeout and connection-refused give `unavailable` within ~1 s; HTTP mock never called without `cloud = TRUE`; requests outside the allowlist (e.g. `/metadata/identity/oauth2/token`) refused.

**Done when:** on a real Azure VM and an AKS pod, `facts(cloud = TRUE)` returns region, size, resource group and platform in under 1.5 s; off Azure, `cloud = TRUE` makes no request because the offline guess rules Azure out.

**Result:** spike done (base R, no `curl`). IMDS parsing, the once-per-session request, failure handling and "no request off Azure or without `cloud = TRUE`" are covered by mocked tests; `test-live.R` probes IMDS on GitHub-hosted runners (Azure VMs) and skips with the reason if it is blocked. A check on a real Azure VM and an AKS pod moves to Stage 8, together with confirming the PaaS env var names. `cloud.azure.service` became one named fact instead of `cloud.azure.service.*`; `vmss` is not a platform (use `cloud.azure.vmss_name`).

---

## Stage 7 — macOS and Windows

**Goal:** pass `R CMD check` on every CRAN platform with useful host-level facts.

macOS:
- [x] `sw_vers`; one batched `sysctl` call (`machdep.cpu.brand_string`, `hw.logicalcpu`, `hw.physicalcpu`, `hw.memsize`, `kern.boottime`, `vm.loadavg`, `kern.hv_vmm_present`); `vm_stat` for available memory; `id` for uid.

Windows:
- [x] `os.*` from `Sys.info()` / `osVersion`; `NUMBER_OF_PROCESSORS`, `PROCESSOR_IDENTIFIER`.
- [x] `memory.host.*` from `ps::ps_system_memory()` when installed, else one lazy PowerShell `Get-CimInstance` call with timeout; `unavailable` on failure.
- [x] Python discovery adds the `py` launcher and `%LOCALAPPDATA%\Programs\Python`; site-packages under `Lib\site-packages`.

Both:
- [x] Linux-only facts report `not_applicable`, never `error`.
- [x] `usage()`: process CPU from `proc.time()`; `mem_rss` from `ps::ps_memory_info()` when installed, else `NA`; container fields `NA`. No commands per call.

Tests: recorded command outputs in `tests/testthat/fixtures/cmd/`, run on all OSes; live tests assert invariants only.

**Done when:** the CI matrix (macOS, Windows, Ubuntu release/devel/oldrel) is green and every command parser has mocked tests.

**Result:** macOS uses one batched `sysctl` (status ignored: unknown keys such as `hw.optional.arm64` on Intel make it exit 1 but the rest is printed), `sw_vers` and `vm_stat`; Intel flags are mapped to Linux names so `isa_level` works (`x86-64-v3` on an i5-8500B). Windows reads the CPU and BIOS registry keys (virtualization and Azure via `C:/WindowsAzure`), `NUMBER_OF_PROCESSORS`, memory and boot time from `ps` (PowerShell CIM fallback), and finds Python via the py launcher or `%LOCALAPPDATA%`, skipping the Store alias. `disk.tmpdir.fstype` uses `ps` off Linux. Live on this Mac: macOS 15.7.9, bare metal, no errors. CI asserts native resolvers on every OS.

---

## Stage 8 — Hardening

**Goal:** prove fixtures match reality; fast and safe.

- [x] Docker job (cgroup v2): `--cpus=1.5 --memory=512m` → `effective_cores() == 2`, `effective_memory() == 512 MiB`; `--cpuset-cpus=0` variant; run in Debian, Alpine and Fedora images (dpkg, apk, rpm inventories).
- [x] `kind` job: pod with limits, Downward API env and volume; assert `k8s.*` and effective values.
- [x] Python job: venv and conda; `packages.python` vs `pip list --format=json`.
- [x] Azure: IMDS check on the Azure-hosted GitHub runner if reachable; otherwise a manual script for a real VM / AKS pod, results noted in the release PR.
- [x] Cross-check `cpu.effective` with `parallelly::availableCores(methods = c("system", "cgroups.cpuset", "cgroups2.cpu.max", "nproc"))` in container jobs.
- [x] Benchmark: default Linux snapshot < 50 ms (`skip_on_cran()` test + bench script); packages timed separately.
- [x] Benchmark `usage()`: median ≤ 200 µs on Linux (≤ 20 µs via `max_age`), tracked in CI so regressions show up; check memory allocation per call with `bench::mark()`. In the Docker job, verify `cpu_cgroup` and `cpu_throttled` respond to a busy loop under `--cpus=1`.
- [x] Robustness: garbage/truncated files for every parser; permission denied; empty root (all `unavailable` / `not_applicable`, none `error`).
- [x] Security review against §9.
- [x] covr: every resolver exercised by at least one fixture; `.github/workflows/coverage.yaml` calls pedrobtz/r-actions `coverage.yml` (pinned to the v1 commit).

**Done when:** live jobs are green and agree with the corresponding fixtures.

**Result:**
- `.github/workflows/live.yaml` runs `tools/live/check.R` in Debian (rocker), Alpine and Fedora images under `--cpus`/`--memory`/`--cpuset-cpus` limits (effective values, package manager, `parallelly` cross-check, timings), a `--cpus=0.5` busy loop for `usage()` throttling, a `kind` pod with limits and the Downward API (`tools/live/k8s.R`), and venv/conda environments against `pip list` (`tools/live/python.R`). Locally with podman: Debian and Alpine all ok; `usage()` showed 0.50 cores and 100% throttled periods under `--cpus=0.5`.
- Robustness tests corrupt every file of three fixtures (empty, garbage, truncated) and feed garbage command output on every OS: they found two real bugs (`cgroup.path` with no controllers, `memory.rlimit.*` without `/proc/self/limits`), now fixed. Empty root, unreadable files and "the service account token is never read" are tested.
- Performance: the default snapshot is 30–35 ms in containers (target 50 ms). Alpine was 520 ms because `Sys.timezone()` scans the tz database when `/etc/localtime` is not a link; `os.timezone` now reads `TZ`, the link, `/etc/timezone`, and reports UTC when `/etc/localtime` is missing. `usage()` is ~165–175 µs. Resolver warnings are now muffled (`Sys.timezone()` warned on Alpine).
- Coverage 92% (helpers re-register resolvers so covr instruments their closures).
- Security review against §9: no writes; the only environment change is `no_proxy` during an IMDS request (restored); network only through the allowlisted `http_get()`; commands only where no file can be read; no token or `/proc/*/environ` reads.
- Not done here: a real AKS cluster (the `kind` job stands in) and confirming the Azure PaaS env var names on real services (needs Azure access).

---

## Stage 9 — Documentation and site

**Goal:** a reader understands what zufax reports and why it differs from `detectCores()`.

- [x] roxygen docs and fast, network-free examples for every export (IMDS examples in `\dontrun{}`, noting they need Azure).
- [x] Fact reference page generated from the registry: name, type, platforms, sources, default/opt-in, `Inf` / `NA` meaning.
- [x] Vignette `zufax`: motivation, host vs effective, containers/k8s walkthrough (output pre-rendered from fixtures), options reference.
- [x] Vignette `azure`: offline detection per service, what IMDS adds, the AKS "node, not pod" caveat, what is never read.
- [x] Article `logging`: `usage_line()` with logger, lgr and `message()`; what each field means; `cpu_throttled` as the signal that a container is CPU-starved; cost per call.
- [x] Article `inventory`: system / R / Python packages, e.g. attaching an environment report to a bug report or job log.
- [x] `README.Rmd`: pitch, install, `print(facts())`, `effective_cores()` with `future` / `data.table`.
- [x] pkgdown reference grouped by topic; `NEWS.md` for 0.1.0; lifecycle note (fact names frozen per §3; changes need NEWS + deprecation).

**Done when:** pkgdown builds cleanly and every export has an example.

**Result:** `?zufax_facts` is generated from `fact_docs` (type and description of all 118 facts) and the registry (platforms, opt-in, network); a test fails if a fact is undocumented. One CRAN vignette (`zufax`: snapshot, status and source, effective cores and memory, a Kubernetes walkthrough pre-rendered from the `k8s-v2-limits` fixture, outputs, options) and three pkgdown-only articles (`azure`, `logging`, `inventory`) under `vignettes/articles/`. README rewritten with a live example and the pod example; knitr and rmarkdown added to Suggests. pkgdown builds cleanly; `R CMD check` clean apart from the NEWS heading note.

---

## Stage 10 — CRAN release

**Goal:** 0.1.0 accepted on CRAN.

- [x] Run the `cran-extrachecks` skill and fix everything it flags.
- [x] `urlchecker::url_check()`, `spelling::spell_check_package()`.
- [ ] `R CMD check --as-cran` clean locally; pedrobtz/r-actions r-cmd-check green on main.
- [x] Confirm CRAN-safety (§10): no network, no Python, fixture-only scenario assertions, inventory tests on fixtures only.
- [x] `cran-comments.md`: new release; test environments; network access only on explicit `cloud = TRUE`, 1 s timeout, never in checks.
- [x] `Version: 0.1.0`, final `NEWS.md`.
- [ ] `devtools::submit_cran()`; confirm maintainer email.
- [ ] After acceptance: tag `v0.1.0`, GitHub release, bump to `0.1.0.9000`, open the 0.2.0 milestone from the deferred column.

**Done when:** zufax 0.1.0 is on CRAN.

**Progress (2026-10-01):** cran-extrachecks done (Description expands 'cgroup', README has the CRAN install line, `Language: en-US`, US spellings, `inst/WORDLIST`), `urlchecker` clean, spelling clean, `R CMD check --as-cran` 0 errors / 0 warnings, version 0.1.0, `cran-comments.md` written. **Waiting on the maintainer:** the CRAN submission itself.

---

## Stage 11 — Pre-release extras

**Goal:** three small additions found by comparing with other tools (2026-10-01), shipped in 0.1.0.

- [x] Pressure and OOM kills: `memory.cgroup.pressure`, `cpu.cgroup.pressure` (cgroup v2 PSI, `some`/`full` avg10 %), `memory.cgroup.oom_kills` (v2 `memory.events`, v1 `memory.oom_control`); `usage(extra = "pressure")` adds `mem_pressure`, `cpu_pressure`, `oom_kills`; `print()` notes OOM kills.
- [x] tmpfs warning: `print()` notes when `tempdir()` is on tmpfs inside a container (files count against the memory limit).
- [x] Connection and file limits: `runtime.r.connections` (max / used / free R connection slots; each parallel worker needs one) and `runtime.rlimit.nofile`.
- [x] `data-raw/pack-fixtures.R` only re-packs fixtures whose content changed.

---

## After 0.1.0 — ideas from other tools

Recorded 2026-10-01 from a comparison with automaxprocs/automemlimit, the JVM/.NET container support, parallelly, lscpu/hwloc, nvidia-smi, systemd-detect-virt, ci-info and sessioninfo.

**0.2.0**
- `apply_limits()`: set `OMP_NUM_THREADS`, `options(mc.cores)`, data.table threads from `effective_cores()`, and R's vector heap limit (`mem.maxVSize()`) just below the container memory limit, so R fails with a catchable "vector memory exhausted" error instead of an OOM kill (the R analogue of automaxprocs/automemlimit).
- `hpc` namespace: Slurm, PBS, SGE and LSF allocations (`SLURM_CPUS_PER_TASK`, `PBS_NUM_PPN`, `LSB_DJOB_NUMPROC`, job ids).
- `platform` namespace: CI (GitHub Actions, GitLab, …), Posit Workbench/Connect, RStudio, Positron, VS Code, Codespaces, SageMaker — all from environment variables.
- Effective privileges: decode `CapEff` from `/proc/self/status`, read-only root filesystem, seccomp mode.
- BLAS identification (OpenBLAS, MKL, Accelerate, reference) from the library path; current BLAS/OpenMP threads via `RhpcBLASctl` when installed.

**Later**
- `gpu` namespace: count and models (`nvidia-smi`), `CUDA_VISIBLE_DEVICES`, `nvidia.com/gpu` resources.
- NUMA nodes and CPU caches from `/sys/devices/system/node` and `cpu*/cache`.
- Hybrid CPUs: performance vs efficiency cores (`hw.perflevel*` on Apple silicon, Intel hybrid).
- More substrates: chroot, OpenVZ, proot, gVisor, Firecracker, a reliable LXC system-container signal.
- CI runner coverage: Linux and Windows arm64, Intel macOS, oldrel on macOS/Windows, an arm64 container job.

## Stage dependencies

```
0 ─► 1 ─► 2 ─┬─► 3 ─► 4 ─┬─► 5 ─┬─► 8 ─► 9 ─► 10
             │           └─► 6 ─┤
             └─► 7 ─────────────┘
```

- Stage 7 (macOS/Windows) can start once the engine (1) and the CPU/memory fact shapes (2) exist.
- Stages 5 and 6 are independent of each other: 5 needs `runtime.python.*` from 4, 6 needs `k8s.*` from 3 and redaction from 4.
