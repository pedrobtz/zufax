#' Facts as JSON
#'
#' Writes facts as JSON, either as nested values (`{"cpu": {"effective": 2}}`)
#' or, with `metadata = TRUE`, as one object per fact with its status and
#' source. Requires the \pkg{jsonlite} package.
#'
#' Unlimited values (`Inf`) are written as the string `"Inf"` and unknown
#' values (`NA`) as `null`. Times are ISO 8601 in UTC, named vectors become
#' objects and data frames become arrays of objects. Vectors of length one are
#' written as scalars.
#'
#' @inheritParams facts_df
#' @param pretty Indent the output.
#' @param metadata Include `status`, `source`, `resolver`, `elapsed` and
#'   `message` for every fact.
#' @returns A JSON string of class `json`.
#' @seealso [facts_df()] for the same information as a data frame.
#' @export
#' @examplesIf requireNamespace("jsonlite", quietly = TRUE)
#' facts_json(namespaces = "cpu", pretty = TRUE)
facts_json <- function(x = facts(), namespaces = NULL, pretty = FALSE, metadata = FALSE) {
  if (!requireNamespace("jsonlite", quietly = TRUE)) {
    zufax_abort("`facts_json()` needs the jsonlite package: install.packages(\"jsonlite\").")
  }
  df <- facts_df(x, namespaces)
  values <- lapply(df$value, json_value)
  if (metadata) {
    out <- lapply(seq_len(nrow(df)), function(i) {
      list(
        value = values[[i]],
        status = df$status[i],
        source = df$source[i],
        resolver = df$resolver[i],
        elapsed = df$elapsed[i],
        message = df$message[i]
      )
    })
    names(out) <- df$fact
  } else {
    out <- list()
    for (i in seq_len(nrow(df))) {
      out <- set_path(out, strsplit(df$fact[i], ".", fixed = TRUE)[[1]], values[[i]])
    }
  }
  jsonlite::toJSON(
    out,
    auto_unbox = TRUE,
    pretty = pretty,
    null = "null",
    na = "null",
    digits = NA
  )
}

json_value <- function(v) {
  if (is.null(v) || is.data.frame(v)) {
    return(v)
  }
  if (inherits(v, "POSIXt")) {
    return(format(v, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"))
  }
  if (is.numeric(v) && any(is.infinite(v))) {
    v <- lapply(v, \(e) {
      if (is.infinite(e)) {
        if (e > 0) "Inf" else "-Inf"
      } else {
        e
      }
    })
    return(if (length(v) == 1 && is.null(names(v))) v[[1]] else v)
  }
  if (is.atomic(v) && !is.null(names(v))) {
    return(as.list(v))
  }
  v
}
