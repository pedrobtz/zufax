`%||%` <- function(x, y) if (is.null(x)) y else x

`%|NA|%` <- function(x, y) if (!length(x) || is.na(x[1])) y else x # nolint: object_name_linter.

zufax_abort <- function(message, ..., class = NULL) {
  if (...length()) {
    message <- sprintf(message, ...)
  }
  cnd <- structure(
    class = c(class, "zufax_error", "error", "condition"),
    list(message = message, call = NULL)
  )
  stop(cnd)
}

is_string <- function(x) is.character(x) && length(x) == 1 && !is.na(x)

is_flag <- function(x) is.logical(x) && length(x) == 1 && !is.na(x)
