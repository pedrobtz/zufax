#' Current CPU and memory usage, cheap enough for every log line
#'
#' `usage()` reads the process's and the container's current CPU and memory
#' use. It skips the fact engine: everything static (cgroup paths, limits,
#' page size) is worked out once per session, and each call reads only a few
#' small files on Linux. `usage_line()` formats the result as a compact string
#' for log messages.
#'
#' CPU values are rates, so they compare against the previous call: the first
#' call reports the process's average since it started, and `cpu_cgroup` and
#' `cpu_throttled` are `NA` until the second call. After a `fork()` (e.g. in
#' [parallel::mclapply()] workers) the baseline starts again.
#'
#' On macOS and Windows, `mem_rss` needs the \pkg{ps} package, and the
#' container fields are always `NA`.
#'
#' @param extra Additional, slightly more expensive fields: `"host"` adds
#'   `mem_host_available`, `"working_set"` adds `mem_working_set`, and
#'   `"pressure"` adds `mem_pressure` and `cpu_pressure` (percentage of the
#'   last 10 seconds in which tasks stalled waiting for memory or CPU) and
#'   `oom_kills` (processes killed in the container for running out of
#'   memory).
#' @param max_age Return the previous result if it is at most this many seconds
#'   old, for very hot loops.
#' @param ... Passed on to `usage()`.
#' @returns `usage()`: a named numeric vector of class `zufax_usage` with
#'   * `time`: when the sample was taken, as seconds since the epoch.
#'   * `cpu_process`: CPU cores used by this R process since the previous call.
#'   * `cpu_cgroup`: CPU cores used by the whole container since the previous
#'     call, including other processes such as parallel workers.
#'   * `cpu_throttled`: share of CPU scheduling periods since the previous call
#'     in which the container was throttled for hitting its CPU quota.
#'   * `cpu_limit`: CPU cores the process may use (see [effective_cores()]).
#'   * `mem_rss`: resident memory of this process, in bytes.
#'   * `mem_cgroup`: memory used by the container, including page cache.
#'   * `mem_limit`: the memory limit (see [effective_memory()]).
#'   * `mem_pct`: `mem_cgroup / mem_limit`, or `mem_rss` as a share of host
#'     memory when there is no container.
#'
#'   `usage_line()`: a string such as
#'   `"cpu=1.8/4 thr=3% mem=2.1G/8G(26%) rss=1.2G"`.
#' @export
#' @examples
#' usage()
#' message("step done ", usage_line())
usage <- function(extra = NULL, max_age = 0) {
  setup <- usage_setup()
  now <- usage_now()
  prev <- .usage$prev
  if (!is.null(.usage$last) && now[["elapsed"]] - prev$elapsed <= max_age) {
    return(.usage$last)
  }

  sample <- list(elapsed = now[["elapsed"]], cpu = now[["cpu"]])
  mem_rss <- NA_real_
  mem_cgroup <- NA_real_
  if (setup$linux) {
    # One handler for the whole sample: a missing file leaves its fields NA.
    tryCatch(
      {
        if (!is.null(setup$statm)) {
          rss_pages <- strsplit(fast_read(setup$statm), " ", fixed = TRUE)[[1]][2]
          mem_rss <- first_num(rss_pages) * setup$page_size
        }
        if (!is.null(setup$mem_current)) {
          mem_cgroup <- first_num(fast_read(setup$mem_current))
        }
        if (!is.null(setup$cpu_stat)) {
          stat <- parse_cpu_stat(fast_read(setup$cpu_stat))
          sample$periods <- stat[[2]]
          sample$throttled <- stat[[3]]
          sample$cg_cpu <- if (is.null(setup$cpu_usage)) {
            stat[[1]] / 1e6
          } else {
            first_num(fast_read(setup$cpu_usage)) / 1e9
          }
        }
      },
      error = \(e) NULL,
      warning = \(w) NULL
    )
  } else if (!is.null(setup$ps)) {
    mem_rss <- tryCatch(ps::ps_memory_info(setup$ps)[["rss"]], error = \(e) NA_real_)
  }

  cpu_process <- now[["cpu"]] / now[["elapsed"]]
  cpu_cgroup <- NA_real_
  cpu_throttled <- NA_real_
  if (!is.null(prev)) {
    dt <- sample$elapsed - prev$elapsed
    if (dt <= 0) {
      return(.usage$last)
    }
    cpu_process <- (sample$cpu - prev$cpu) / dt
    if (!is.null(sample$cg_cpu) && !is.null(prev$cg_cpu)) {
      cpu_cgroup <- unname((sample$cg_cpu - prev$cg_cpu) / dt)
      periods <- sample$periods - prev$periods
      throttled <- sample$throttled - prev$throttled
      cpu_throttled <- unname(if (isTRUE(periods > 0)) throttled / periods else 0)
    }
  }

  mem_pct <- if (!is.na(mem_cgroup) && isTRUE(is.finite(setup$mem_limit) && setup$mem_limit > 0)) {
    mem_cgroup / setup$mem_limit
  } else if (isTRUE(setup$host_total > 0)) {
    mem_rss / setup$host_total
  } else {
    NA_real_
  }

  out <- c(
    time = as.numeric(Sys.time()),
    cpu_process = cpu_process,
    cpu_cgroup = cpu_cgroup,
    cpu_throttled = cpu_throttled,
    cpu_limit = setup$cpu_limit,
    mem_rss = mem_rss,
    mem_cgroup = mem_cgroup,
    mem_limit = setup$mem_limit,
    mem_pct = mem_pct
  )
  if ("host" %in% extra) {
    out["mem_host_available"] <- if (setup$linux) fact("memory.host.available") else NA
  }
  if ("working_set" %in% extra) {
    out["mem_working_set"] <- if (setup$linux) fact("memory.cgroup.working_set") else NA
  }
  if ("pressure" %in% extra) {
    pressure <- function(name) {
      value <- if (setup$linux) fact(name) else NA
      if (length(value) && !is.na(value[1]) && "some" %in% names(value)) {
        value[["some"]]
      } else {
        NA_real_
      }
    }
    out["mem_pressure"] <- pressure("memory.cgroup.pressure")
    out["cpu_pressure"] <- pressure("cpu.cgroup.pressure")
    out["oom_kills"] <- if (setup$linux) first_num(fact("memory.cgroup.oom_kills")) else NA
  }
  out <- structure(out, class = "zufax_usage")
  .usage$prev <- sample
  .usage$last <- out
  out
}

#' @rdname usage
#' @export
usage_line <- function(...) format(usage(...))

#' @export
format.zufax_usage <- function(x, ...) {
  x <- unclass(x)
  parts <- character()
  cpu <- x[["cpu_cgroup"]] %|NA|% x[["cpu_process"]]
  if (is.finite(cpu)) {
    limit <- x[["cpu_limit"]]
    of <- if (is.finite(limit)) paste0("/", fmt_num(limit))
    parts <- c(parts, paste0("cpu=", fmt_num(cpu), of))
  }
  if (is.finite(x[["cpu_throttled"]])) {
    parts <- c(parts, sprintf("thr=%.0f%%", 100 * x[["cpu_throttled"]]))
  }
  if (is.finite(x[["mem_cgroup"]])) {
    mem <- paste0("mem=", fmt_bytes(x[["mem_cgroup"]]))
    if (is.finite(x[["mem_limit"]])) {
      mem <- paste0(mem, "/", fmt_bytes(x[["mem_limit"]]))
      if (is.finite(x[["mem_pct"]])) {
        mem <- sprintf("%s(%.0f%%)", mem, 100 * x[["mem_pct"]])
      }
    }
    parts <- c(parts, mem)
  }
  if (is.finite(x[["mem_rss"]])) {
    rss <- paste0("rss=", fmt_bytes(x[["mem_rss"]]))
    if (!is.finite(x[["mem_cgroup"]]) && is.finite(x[["mem_pct"]])) {
      rss <- sprintf("%s(%.0f%%)", rss, 100 * x[["mem_pct"]])
    }
    parts <- c(parts, rss)
  }
  if (!length(parts)) "usage unavailable" else paste(parts, collapse = " ")
}

#' @export
print.zufax_usage <- function(x, ...) {
  cat(format(x), "\n", sep = "")
  invisible(x)
}

# Internals ------------------------------------------------------------

.usage <- new.env(parent = emptyenv())

current_pid <- function() Sys.getpid()

# Process CPU time (user + system, all threads) and wall time since start.
usage_now <- function() {
  t <- proc.time()
  c(cpu = t[[1]] + t[[2]], elapsed = t[[3]])
}

# Paths and limits, recomputed when the pid (after fork), root or OS changes.
usage_setup <- function() {
  pid <- current_pid()
  root <- zufax_root()
  os <- zufax_os()
  if (identical(.usage$pid, pid) && identical(.usage$root, root) && identical(.usage$os, os)) {
    return(.usage$setup)
  }
  .usage$prev <- NULL
  .usage$last <- NULL
  setup <- list(
    linux = os == "linux",
    cpu_limit = first_num(fact("cpu.effective_exact")),
    mem_limit = first_num(fact("memory.effective.limit")),
    host_total = first_num(fact("memory.host.total"))
  )
  if (setup$linux) {
    # A broken cgroup layout only disables the container fields.
    setup <- c(setup, tryCatch(usage_linux_paths(), error = \(e) list()))
  } else if (requireNamespace("ps", quietly = TRUE)) {
    setup$ps <- tryCatch(ps::ps_handle(), error = \(e) NULL)
  }
  .usage$setup <- setup
  .usage$pid <- pid
  .usage$root <- root
  .usage$os <- os
  setup
}

usage_linux_paths <- function() {
  root <- zufax_root()
  ctx <- new_ctx(new_state())
  layout <- read_cgroup_layout(ctx)
  existing <- function(dir, file) {
    if (is.null(dir)) {
      return(NULL)
    }
    path <- root_path(paste0(dir, "/", file), root)
    if (file.exists(path)) path else NULL
  }
  memory <- cgroup_controller(layout, "memory")
  cpu <- cgroup_controller(layout, "cpu")
  cpuacct <- cgroup_controller(layout, "cpuacct")
  v2 <- identical(cpu$version, 2L)
  list(
    statm = existing("/proc/self", "statm"),
    page_size = page_size(root),
    mem_current = existing(
      memory$dir,
      if (identical(memory$version, 2L)) "memory.current" else "memory.usage_in_bytes"
    ),
    cpu_stat = existing(cpu$dir, "cpu.stat"),
    cpu_usage = if (!v2) existing(cpuacct$dir, "cpuacct.usage")
  )
}

# AT_PAGESZ from the auxiliary vector (64-bit little-endian), else getconf on
# the live system, else 4096.
page_size <- function(root) {
  auxv <- tryCatch(
    {
      con <- file(root_path("/proc/self/auxv", root), "rb")
      on.exit(close(con))
      readBin(con, "integer", n = 1024, size = 4)
    },
    error = \(e) NULL,
    warning = \(w) NULL
  )
  if (length(auxv) >= 4 && .Machine$sizeof.pointer == 8) {
    keys <- auxv[seq(1, length(auxv) - 3, by = 4)]
    values <- auxv[seq(3, length(auxv) - 1, by = 4)]
    size <- values[keys == 6L]
    if (length(size) && size[1] > 0) {
      return(as.numeric(size[1]))
    }
  }
  if (identical(root, "/")) {
    out <- run_cmd("getconf", "PAGESIZE", timeout = 2)
    size <- suppressWarnings(as.numeric(out$stdout[1]))
    if (length(size) && !is.na(size)) {
      return(size)
    }
  }
  4096
}

# readChar() is the cheapest way to read a small file in R. Callers handle
# errors, so a missing file costs nothing on the common path.
fast_read <- function(path) readChar(path, 4096L, useBytes = TRUE)

# cpu.stat text -> c(usage_usec, nr_periods, nr_throttled). v1 has no
# usage_usec (it is read from cpuacct.usage), so that one may be NA.
parse_cpu_stat <- function(text) {
  words <- strsplit(chartr("\n", " ", text), " ", fixed = TRUE)[[1]]
  keys <- words[c(TRUE, FALSE)]
  values <- words[c(FALSE, TRUE)]
  as.numeric(values[match(c("usage_usec", "nr_periods", "nr_throttled"), keys)])
}

# The first element as a number, NA when there is none: a value read from a
# file may be empty or not a number.
first_num <- function(x) {
  x <- suppressWarnings(as.numeric(x))
  if (length(x)) x[[1]] else NA_real_
}

fmt_num <- function(x) as.character(round(x, 1))

fmt_bytes <- function(x) {
  units <- c("B", "K", "M", "G", "T")
  i <- if (x < 1) 0 else min(4, floor(log(x, 1024)))
  paste0(round(x / 1024^i, 1), units[i + 1])
}
