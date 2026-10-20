# Resolution state for one facts() call. `memo` holds facts resolved during
# this call (so `refresh = TRUE` still resolves each fact once); the session
# cache in `.zufax$cache` is shared across calls.
new_state <- function(cloud = FALSE, refresh = FALSE, strict = FALSE) {
  state <- new.env(parent = emptyenv())
  state$root <- zufax_root()
  state$os <- zufax_os()
  state$cloud <- isTRUE(cloud)
  state$refresh <- isTRUE(refresh)
  state$strict <- isTRUE(strict)
  state$memo <- new.env(parent = emptyenv())
  state$shared <- new.env(parent = emptyenv())
  state$volatile <- new.env(parent = emptyenv())
  state$stack <- character()
  state
}

zufax_os <- function() {
  getOption("zufax.os") %||% .zufax$sysname %||% tolower(Sys.info()[["sysname"]])
}

fact_record <- function(
  name,
  value = NA,
  status = "ok",
  source = NA_character_,
  resolver = NA_character_,
  elapsed = NA_real_,
  message = NA_character_,
  cache = TRUE
) {
  list(
    name = name,
    value = value,
    status = status,
    source = source,
    resolver = resolver,
    elapsed = elapsed,
    message = message,
    cache = cache
  )
}

resolve_fact <- function(name, state) {
  memo <- state$memo[[name]]
  if (!is.null(memo)) {
    return(volatile_to_parent(state, memo))
  }
  if (is_skipped(name)) {
    rec <- fact_record(
      name,
      status = "not_applicable",
      message = "Skipped by `zufax.skip`.",
      cache = FALSE
    )
    return(volatile_to_parent(state, remember(state, name, rec)))
  }
  key <- paste(state$root, state$os, state$cloud, name, sep = "\r")
  cached <- .zufax$cache[[key]]
  if (!state$refresh && !is.null(cached)) {
    return(remember(state, name, cached))
  }
  if (name %in% state$stack) {
    zufax_abort(
      "Dependency cycle: %s.",
      paste(c(state$stack, name), collapse = " -> "),
      class = "zufax_cycle"
    )
  }
  candidates <- .zufax$resolvers[[name]]
  if (is.null(candidates)) {
    zufax_abort("Unknown fact `%s`.", name, class = "zufax_unknown_fact")
  }

  depth <- length(state$stack)
  state$stack <- c(state$stack, name)
  rec <- tryCatch(
    run_candidates(name, candidates, state),
    finally = state$stack <- state$stack[seq_len(depth)]
  )
  # A fact computed from an uncached fact (e.g. one read from an environment
  # variable) must not be cached either.
  if (isTRUE(state$volatile[[name]])) {
    rec$cache <- FALSE
  }
  # Errors may be transient (and must re-raise under strict), so never cache them.
  if (rec$cache && rec$status != "error") {
    .zufax$cache[[key]] <- rec
  }
  volatile_to_parent(state, remember(state, name, rec))
}

remember <- function(state, name, rec) {
  state$memo[[name]] <- rec
  rec
}

# Mark the fact currently being resolved as volatile when it used `rec`.
volatile_to_parent <- function(state, rec) {
  depth <- length(state$stack)
  if (!rec$cache && depth) {
    state$volatile[[state$stack[depth]]] <- TRUE
  }
  rec
}

is_skipped <- function(name) {
  skip <- getOption("zufax.skip")
  length(skip) > 0 && any(name == skip | startsWith(name, paste0(skip, ".")))
}

run_candidates <- function(name, candidates, state) {
  first <- NULL
  gated <- FALSE
  for (r in candidates) {
    if (r$network && !state$cloud) {
      gated <- TRUE
      next
    }
    ok <- tryCatch(confine_ok(r, state), error = function(cnd) {
      if (state$strict) {
        stop(cnd)
      }
      cnd
    })
    if (inherits(ok, "error")) {
      return(fact_record(name, status = "error", resolver = r$id, message = conditionMessage(ok)))
    }
    if (!ok) {
      next
    }
    rec <- run_resolver(r, state)
    if (rec$status != "unavailable") {
      return(rec)
    }
    first <- first %||% rec
  }
  if (!is.null(first)) {
    return(first)
  }
  message <- if (gated) {
    "Needs network access: use `cloud = TRUE`."
  } else {
    "No resolver applies on this system."
  }
  cache <- all(vapply(candidates, `[[`, logical(1), "cache"))
  fact_record(name, status = "not_applicable", message = message, cache = cache)
}

confine_ok <- function(r, state) {
  for (key in names(r$confine)) {
    accept <- r$confine[[key]]
    value <- if (key == "os") state$os else resolve_fact(key, state)$value
    ok <- if (is.function(accept)) accept(value) else any(value %in% accept)
    if (!isTRUE(ok)) {
      return(FALSE)
    }
  }
  TRUE
}

run_resolver <- function(r, state) {
  ctx <- new_ctx(state)
  start <- proc.time()[["elapsed"]]
  status <- "ok"
  message <- NA_character_
  # Resolvers must not be noisy: warnings from the code they call are muffled.
  value <- tryCatch(
    withCallingHandlers(r$resolve(ctx), warning = \(w) invokeRestart("muffleWarning")),
    zufax_unavailable = function(cnd) {
      status <<- "unavailable"
      message <<- conditionMessage(cnd)
      NULL
    },
    zufax_not_applicable = function(cnd) {
      status <<- "not_applicable"
      message <<- conditionMessage(cnd)
      NULL
    },
    error = function(cnd) {
      if (state$strict) {
        if (inherits(cnd, "zufax_resolve_error")) {
          stop(cnd)
        }
        zufax_abort(
          "Failed to resolve fact `%s`: %s",
          r$name,
          conditionMessage(cnd),
          class = "zufax_resolve_error"
        )
      }
      status <<- "error"
      message <<- conditionMessage(cnd)
      NULL
    }
  )
  if (status == "ok" && is.null(value)) {
    status <- "unavailable"
    message <- "No data found."
  }
  fact_record(
    r$name,
    value = if (status == "ok") value else NA,
    status = status,
    source = ctx$sources(),
    resolver = r$id,
    elapsed = proc.time()[["elapsed"]] - start,
    message = message,
    cache = r$cache
  )
}

# The interface resolvers use for all I/O. Reads, commands, HTTP requests and
# environment variables are recorded as the fact's `source`.
new_ctx <- function(state) {
  used <- character()
  note <- function(source) {
    used <<- c(used, source)
    invisible()
  }
  list(
    root = state$root,
    os = state$os,
    refresh = state$refresh,
    note = note,
    read = function(path, n = -1L) {
      lines <- read_lines(path, state$root, n)
      if (!is.null(lines)) {
        note(path)
      }
      lines
    },
    read_kv = function(path, sep = ":") {
      lines <- read_lines(path, state$root)
      if (is.null(lines)) {
        return(NULL)
      }
      note(path)
      parse_kv(lines, sep)
    },
    exists = function(path) file_exists(path, state$root),
    list_dir = function(path) {
      files <- list_dir(path, state$root)
      if (!is.null(files)) {
        note(path)
      }
      files
    },
    env = function(name) {
      value <- Sys.getenv(name, unset = NA)
      if (is.na(value)) {
        return(NULL)
      }
      note(paste0("env:", name))
      as_utf8(value)
    },
    cmd = function(cmd, args = character(), timeout = 5) {
      note(paste(c(cmd, args), collapse = " "))
      run_cmd(cmd, args, timeout)
    },
    http = function(url, headers = character(), timeout = 1) {
      note(url)
      http_get(url, headers, timeout)
    },
    # Compute a value once per facts() call and share it between resolvers,
    # replaying its sources into every fact that uses it.
    shared = function(key, compute) {
      hit <- state$shared[[key]]
      if (is.null(hit)) {
        sub <- new_ctx(state)
        hit <- list(value = compute(sub), used = sub$used())
        state$shared[[key]] <- hit
      }
      for (source in hit$used) {
        note(source)
      }
      hit$value
    },
    fact = function(name) resolve_fact(name, state)$value,
    fact_record = function(name) resolve_fact(name, state),
    used = function() unique(used),
    sources = function() {
      if (length(used)) paste(unique(used), collapse = "; ") else NA_character_
    }
  )
}
