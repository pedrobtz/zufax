#' @export
format.zufax <- function(x, ...) {
  value <- function(name) {
    if (!name %in% known_facts()) {
      return(NULL)
    }
    v <- zufax_get(x, name)
    if (length(v) == 1 && is.na(v)) NULL else v
  }
  state <- zufax_state(x)
  lines <- "<zufax facts>"
  add <- function(label, text) {
    if (length(text) && !is.na(text) && nzchar(text)) {
      lines <<- c(lines, sprintf("%-8s %s", label, text))
    }
  }

  os <- paste(c(value("os.name") %||% state$os, value("os.release.full")), collapse = " ")
  add("os", os)

  where <- if (isTRUE(value("k8s.detected"))) {
    pod <- paste(c(value("k8s.namespace"), value("k8s.pod.name")), collapse = "/")
    paste(c("Kubernetes pod", if (nzchar(pod)) pod), collapse = " ")
  }
  if (isTRUE(value("container.detected"))) {
    where <- paste(
      c(where, paste(value("container.runtime") %||% "unknown", "container")),
      collapse = ", "
    )
  }
  add("runs in", where %||% "no container")

  wsl <- value("virtualization.wsl")
  on <- switch(
    value("virtualization.type") %||% "unknown",
    physical = "bare metal",
    vm = if (!is.null(wsl)) {
      paste0("WSL", wsl)
    } else {
      sprintf("vm (%s)", value("virtualization.hypervisor") %||% "unknown")
    },
    "unknown"
  )
  cloud <- value("cloud.provider")
  if (!is.null(cloud)) {
    platform <- value("cloud.azure.platform")
    if (!is.null(platform) && platform != "vm") {
      cloud <- sprintf("%s (%s)", cloud, platform)
    }
    if (state$cloud) {
      details <- c(value("cloud.region"), value("cloud.instance.type"))
      if (length(details)) {
        # In a pod, instance metadata describes the node VM.
        node <- if (isTRUE(value("k8s.detected"))) "node " else ""
        cloud <- sprintf("%s, %s%s", cloud, node, paste(details, collapse = " "))
      }
    }
    cloud <- paste("cloud", cloud)
  }
  add("runs on", paste(c(on, cloud), collapse = ", "))

  host_cpu <- value("cpu.host.logical")
  exact <- value("cpu.effective_exact")
  threads <- value("cpu.effective")
  effective <- if (!is.null(exact)) {
    if (!is.null(threads) && threads != exact) {
      sprintf("%s (%.0f threads)", fmt_num(exact), threads)
    } else {
      fmt_num(exact)
    }
  }
  add(
    "cpu",
    paste(
      c(
        if (!is.null(host_cpu)) paste("host", host_cpu),
        if (!is.null(effective)) paste("effective", effective)
      ),
      collapse = " | "
    )
  )

  total <- value("memory.host.total")
  limit <- value("memory.effective.limit")
  available <- value("memory.effective.available")
  add(
    "memory",
    paste(
      c(
        if (!is.null(total)) paste("host", fmt_bytes(total)),
        if (!is.null(limit) && is.finite(limit) && !identical(limit, total)) {
          paste("limit", fmt_bytes(limit))
        },
        if (!is.null(available)) paste("available", fmt_bytes(available))
      ),
      collapse = " | "
    )
  )

  python <- value("runtime.python.version")
  if (!is.null(python)) {
    python <- sprintf("Python %s (%s)", python, value("runtime.python.env_type") %||% "unknown")
  }
  r <- value("runtime.r.version")
  add("runtime", paste(c(if (!is.null(r)) paste("R", r), python), collapse = " | "))

  # Files in a tmpfs tempdir() live in memory and count against the limit.
  if (isTRUE(value("container.detected")) && identical(value("disk.tmpdir.fstype"), "tmpfs")) {
    add("note", "tempdir() is on tmpfs: its files count against the memory limit")
  }
  oom <- value("memory.cgroup.oom_kills")
  if (isTRUE(oom > 0)) {
    add(
      "note",
      sprintf("%.0f process(es) in this container were killed for running out of memory", oom)
    )
  }

  c(lines, "Use facts_df() for every fact with its status and source.")
}

#' @export
print.zufax <- function(x, ...) {
  cat(format(x, ...), sep = "\n")
  invisible(x)
}
