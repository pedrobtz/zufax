# HTTP access is limited to instance metadata endpoints. Anything not on the
# allowlist is refused before any connection is made, so identity and token
# endpoints can never be reached.
http_allowlist <- c(
  "^http://169\\.254\\.169\\.254/metadata/instance\\?api-version=[0-9-]+$"
)

http_allowed <- function(url) {
  is_string(url) && any(vapply(http_allowlist, \(p) grepl(p, url), logical(1)))
}

# Returns list(status, body). Tests replace the transport with
# `options(zufax.http_mock = function(url, headers) ...)`.
http_get <- function(url, headers = character(), timeout = 1) {
  if (!http_allowed(url)) {
    zufax_abort(
      "Refusing to request %s: not on the zufax allowlist.",
      url,
      class = "zufax_http_refused"
    )
  }
  mock <- getOption("zufax.http_mock")
  if (is.function(mock)) {
    return(mock(url, headers))
  }
  http_transport(url, headers, timeout)
}

# Base R libcurl: sends headers, and options(timeout) bounds connect and read
# (1.07 s against a non-responding address in the Stage 6 spike). The metadata
# address is added to no_proxy so a configured proxy is never used for it.
http_transport <- function(url, headers, timeout) {
  old_timeout <- options(timeout = max(1, ceiling(timeout)))
  on.exit(options(old_timeout), add = TRUE)
  host <- sub("^https?://([^/:]+).*$", "\\1", url)
  old_env <- Sys.getenv(c("no_proxy", "NO_PROXY"), unset = NA)
  no_proxy <- paste(c(stats::na.omit(old_env[1]), host), collapse = ",")
  Sys.setenv(no_proxy = no_proxy, NO_PROXY = no_proxy)
  on.exit(restore_env(old_env), add = TRUE)

  reason <- NULL
  con <- url(url, method = "libcurl", headers = headers)
  on.exit(close(con), add = TRUE)
  body <- withCallingHandlers(
    tryCatch(readLines(con, warn = FALSE), error = function(e) {
      reason <<- reason %||% conditionMessage(e)
      NULL
    }),
    warning = function(w) {
      reason <<- conditionMessage(w)
      invokeRestart("muffleWarning")
    }
  )
  if (is.null(body)) {
    unavailable(paste("Request failed:", reason %||% "no response"))
  }
  list(status = 200L, body = paste(body, collapse = "\n"))
}

restore_env <- function(old) {
  for (name in names(old)) {
    if (is.na(old[[name]])) Sys.unsetenv(name) else do.call(Sys.setenv, as.list(old[name]))
  }
}
