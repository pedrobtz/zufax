# Run an external command. Returns list(status, stdout), or NULL when the
# command does not exist or cannot be started. Tests replace it with
# `options(zufax.cmd_mock = function(cmd, args) ...)`, which may return a
# character vector (stdout, status 0), a list(status, stdout), or NULL.
run_cmd <- function(cmd, args = character(), timeout = 5) {
  mock <- getOption("zufax.cmd_mock")
  if (is.function(mock)) {
    return(as_cmd_result(mock(cmd, args)))
  }
  if (!nzchar(Sys.which(cmd))) {
    return(NULL)
  }
  out <- tryCatch(
    suppressWarnings(
      system2(cmd, args, stdout = TRUE, stderr = FALSE, timeout = timeout)
    ),
    error = function(e) NULL
  )
  if (is.null(out)) {
    return(NULL)
  }
  list(
    status = as.integer(attr(out, "status") %||% 0L),
    stdout = as_utf8(as.character(out))
  )
}

as_cmd_result <- function(x) {
  if (is.null(x)) {
    return(NULL)
  }
  if (is.character(x)) {
    return(list(status = 0L, stdout = as_utf8(x)))
  }
  list(
    status = as.integer(x$status %||% 0L),
    stdout = as_utf8(as.character(x$stdout %||% character()))
  )
}
