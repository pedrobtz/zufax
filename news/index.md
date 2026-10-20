# Changelog

## zufax 0.1.0

- Initial CRAN submission.
- [`effective_cores()`](https://pedrobtz.github.io/zufax/reference/effective_cores.md)
  and
  [`effective_memory()`](https://pedrobtz.github.io/zufax/reference/effective_cores.md)
  return the CPU cores and memory the process can actually use, taking
  cgroup v1/v2 limits, cpusets and CPU affinity into account.
- [`facts()`](https://pedrobtz.github.io/zufax/reference/facts.md),
  [`fact()`](https://pedrobtz.github.io/zufax/reference/fact.md) and
  [`facts_df()`](https://pedrobtz.github.io/zufax/reference/facts_df.md)
  provide a lazy, cached snapshot of facts with per-fact status and
  source. Resolver errors never escape unless `strict = TRUE`.
- Facts describe the OS (`os.*`), CPU, memory and cgroups, and where the
  process runs: bare metal or VM (`virtualization.*`, including WSL),
  container (`container.*`), Kubernetes pod (`k8s.*`, including the
  Downward API) and cloud provider (`cloud.provider`).
- [`facts_json()`](https://pedrobtz.github.io/zufax/reference/facts_json.md)
  writes facts as JSON, optionally with their status and source;
  [`print()`](https://rdrr.io/r/base/print.html) on a
  [`facts()`](https://pedrobtz.github.io/zufax/reference/facts.md)
  snapshot shows a short summary of where the process runs and what it
  can use.
- Runtime facts describe R (version, BLAS/LAPACK, library paths,
  repositories with credentials removed, renv, thread settings), the
  process (pid, user, uid, privileges) and Python (interpreter, version,
  venv/uv/conda/system, site-packages) without starting Python inside R.
- `env.vars` reports environment variables with secrets redacted by
  default (`zufax.redact`, `zufax.redact_allowlist`); `env.proxies` and
  `disk.tmpdir.*` describe proxies and the temporary directory.
- macOS and Windows are supported for host facts: OS, CPU model and
  topology, memory, boot time, virtualization (and Azure on Windows),
  the temporary directory and Python discovery (py launcher, per-user
  installs).
- Azure: `cloud.azure.platform` tells a VM, AKS, App Service, Functions,
  Container Apps, Batch, Azure ML and Databricks apart without network
  access. With `facts(cloud = TRUE)` the instance metadata service adds
  region, zone, VM size and id, resource group, subscription, spot
  settings, image, tags (redacted) and IP addresses. Requests go only to
  the instance metadata endpoint, time out after 1 second and are made
  at most once per session.
- The opt-in `packages` namespace lists installed system packages (dpkg,
  rpm, apk, pacman, Homebrew, Windows), R packages and Python packages,
  read from package databases rather than by running `pip` or package
  managers where possible.
- [`facts()`](https://pedrobtz.github.io/zufax/reference/facts.md) stays
  quiet: warnings raised while resolving facts are muffled, and
  `os.timezone` avoids the slow
  [`Sys.timezone()`](https://rdrr.io/r/base/timezones.html) lookup when
  the time zone can be read from `TZ` or `/etc/localtime`.
- cgroup v2 pressure stall information (`memory.cgroup.pressure`,
  `cpu.cgroup.pressure`) and OOM kill counts
  (`memory.cgroup.oom_kills`); `usage(extra = "pressure")` adds them to
  a usage sample, and [`print()`](https://rdrr.io/r/base/print.html)
  notes OOM kills and a
  [`tempdir()`](https://rdrr.io/r/base/tempfile.html) on tmpfs in
  containers.
- `runtime.r.connections` reports free R connection slots (each parallel
  worker needs one) and `runtime.rlimit.nofile` the open-files limit.
- [`usage()`](https://pedrobtz.github.io/zufax/reference/usage.md) and
  [`usage_line()`](https://pedrobtz.github.io/zufax/reference/usage.md)
  report current process and container CPU and memory use cheaply enough
  to call on every log line.
