serviceaccount_dir <- "/var/run/secrets/kubernetes.io/serviceaccount"

# Downward API environment variables. Their names are chosen in the pod spec,
# so the mapping is configurable; these are the conventional defaults.
k8s_env_defaults <- c(
  pod.name = "POD_NAME",
  node.name = "NODE_NAME",
  pod.ip = "POD_IP",
  pod.uid = "POD_UID",
  cpu.limit = "CPU_LIMIT",
  memory.limit = "MEMORY_LIMIT",
  cpu.request = "CPU_REQUEST",
  memory.request = "MEMORY_REQUEST"
)

k8s_env <- function(ctx, field) {
  mapping <- getOption("zufax.k8s.env")
  name <- mapping[field] %|NA|% k8s_env_defaults[[field]]
  value <- ctx$env(unname(name))
  if (is.null(value) || !nzchar(value)) NULL else value
}

# Downward API volume files hold `key="value"` lines.
k8s_podinfo <- function(ctx, file) {
  dir <- getOption("zufax.k8s.podinfo", "/etc/podinfo")
  lines <- ctx$read(paste0(dir, "/", file))
  if (is.null(lines)) {
    unavailable(sprintf(
      "No Downward API file %s/%s; mount one or set `zufax.k8s.podinfo`.",
      dir,
      file
    ))
  }
  parse_os_release(lines)
}

not_mapped <- function(field) {
  unavailable(sprintf(
    paste(
      "Not exposed: add a Downward API env var %s or map one with",
      "`options(zufax.k8s.env = c(%s = ...))`."
    ),
    k8s_env_defaults[[field]],
    field
  ))
}

register_k8s_facts <- function() {
  in_k8s <- list(k8s.detected = TRUE)

  register(resolver("k8s.detected", cache = FALSE, function(ctx) {
    !is.null(ctx$env("KUBERNETES_SERVICE_HOST")) || ctx$exists(serviceaccount_dir)
  }))

  register(resolver("k8s.namespace", confine = in_k8s, function(ctx) {
    line <- ctx$read(paste0(serviceaccount_dir, "/namespace"), n = 1L)
    if (length(line) && nzchar(line)) trimws(line) else NULL
  }))

  register(resolver("k8s.pod.name", confine = in_k8s, cache = FALSE, function(ctx) {
    name <- k8s_env(ctx, "pod.name")
    if (!is.null(name)) {
      return(name)
    }
    # Kubernetes sets the hostname to the pod name unless the spec overrides it.
    host <- ctx$fact("os.hostname")
    if (is.na(host)) NULL else host
  }))

  register(resolver("k8s.node.name", confine = in_k8s, cache = FALSE, function(ctx) {
    k8s_env(ctx, "node.name") %||% not_mapped("node.name")
  }))

  register(resolver("k8s.pod.ip", confine = in_k8s, cache = FALSE, function(ctx) {
    k8s_env(ctx, "pod.ip") %||% not_mapped("pod.ip")
  }))

  register(resolver("k8s.pod.uid", confine = in_k8s, cache = FALSE, function(ctx) {
    uid <- k8s_env(ctx, "pod.uid")
    if (!is.null(uid)) {
      return(uid)
    }
    # Kubelet volume mounts come from /var/lib/kubelet/pods/<uid>/...
    roots <- mountinfo(ctx)$root
    hit <- regmatches(roots, regexpr("/kubelet/pods/[0-9a-f-]{36}/", roots))
    if (length(hit)) sub("^/kubelet/pods/(.*)/$", "\\1", hit[1]) else not_mapped("pod.uid")
  }))

  # The volume path is an option, so these are read on every call.
  register(resolver(
    "k8s.pod.labels",
    confine = in_k8s,
    cache = FALSE,
    \(ctx) k8s_podinfo(ctx, "labels")
  ))
  register(resolver(
    "k8s.pod.annotations",
    confine = in_k8s,
    cache = FALSE,
    \(ctx) k8s_podinfo(ctx, "annotations")
  ))

  # Downward API resourceFieldRef values use the default divisor of 1: cores
  # and bytes. Without them, limits come from the cgroup.
  register(resolver("k8s.resources.limits", confine = in_k8s, cache = FALSE, function(ctx) {
    cpu <- k8s_env(ctx, "cpu.limit")
    memory <- k8s_env(ctx, "memory.limit")
    c(
      cpu = if (is.null(cpu)) ctx$fact("cpu.cgroup.quota") else as.numeric(cpu),
      memory = if (is.null(memory)) ctx$fact("memory.cgroup.limit") else as.numeric(memory)
    )
  }))

  register(resolver("k8s.resources.requests", confine = in_k8s, cache = FALSE, function(ctx) {
    cpu <- k8s_env(ctx, "cpu.request")
    memory <- k8s_env(ctx, "memory.request")
    if (is.null(cpu) && is.null(memory)) {
      not_mapped("cpu.request")
    }
    c(cpu = as.numeric(cpu %||% NA), memory = as.numeric(memory %||% NA))
  }))
}
