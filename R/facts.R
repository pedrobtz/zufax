#' Collect facts about the host, container and runtime
#'
#' `facts()` returns a snapshot that resolves facts lazily: a namespace such as
#' `cpu` is resolved the first time you access it, and each fact is cached for
#' the rest of the session.
#'
#' Facts are grouped in namespaces (`os`, `cpu`, `memory`, ...). The `packages`
#' namespace is opt-in: it is only resolved when you ask for it by name, and is
#' left out of [as.list()] and [facts_df()] otherwise.
#'
#' Resolution never fails: a fact that cannot be determined has value `NA` and
#' a `status` other than `"ok"`, visible with [facts_df()].
#'
#' @param namespaces Namespaces to resolve immediately, e.g.
#'   `c("cpu", "memory")`. With `NULL`, nothing is resolved until accessed.
#' @param cloud Allow network requests to the cloud instance metadata service.
#'   Defaults to the `zufax.cloud` option, else `FALSE`.
#' @param refresh If `TRUE`, ignore cached values and resolve facts again.
#' @param strict If `TRUE`, re-raise errors from resolvers instead of recording
#'   them as `status = "error"`. Defaults to the `zufax.strict` option, else
#'   `FALSE`.
#' @returns An object of class `zufax`:
#'   * `x$cpu` or `x[["cpu"]]` returns a namespace as a nested list of values.
#'   * `x[["cpu.host"]]` returns a group of facts the same way.
#'   * `x[["cpu.effective"]]` returns the value of a single fact.
#'   * `names(x)` lists the available namespaces.
#'   * `as.list(x)` resolves and returns all default namespaces.
#' @seealso [fact()] for a single value, [facts_df()] for values with their
#'   status and source.
#' @export
#' @examples
#' f <- facts()
#' names(f)
facts <- function(
  namespaces = NULL,
  cloud = getOption("zufax.cloud", FALSE),
  refresh = FALSE,
  strict = getOption("zufax.strict", FALSE)
) {
  check_namespaces(namespaces)
  x <- structure(list(state = new_state(cloud, refresh, strict)), class = "zufax")
  for (ns in namespaces) {
    resolve_group(ns, zufax_state(x))
  }
  x
}

#' Get the value of a single fact
#'
#' @param name A fact name, e.g. `"cpu.effective"`.
#' @inheritParams facts
#' @returns The fact's value, or `NA` if it could not be determined.
#' @seealso [facts()] for a lazy snapshot of many facts.
#' @export
#' @examples
#' fact("cpu.effective")
#' fact("os.family")
fact <- function(
  name,
  cloud = getOption("zufax.cloud", FALSE),
  refresh = FALSE,
  strict = getOption("zufax.strict", FALSE)
) {
  if (!is_string(name)) {
    zufax_abort("`name` must be a single string.")
  }
  if (!name %in% known_facts()) {
    if (any(startsWith(known_facts(), paste0(name, ".")))) {
      zufax_abort("`%s` is a group of facts; use `facts()[[\"%s\"]]`.", name, name)
    }
    zufax_abort("Unknown fact `%s`.", name, class = "zufax_unknown_fact")
  }
  resolve_fact(name, new_state(cloud, refresh, strict))$value
}

#' Facts with their status and source
#'
#' Returns one row per fact, with the metadata recorded while resolving it.
#'
#' @param x A `zufax` object from [facts()].
#' @param namespaces Namespaces to include. With `NULL`, all default namespaces
#'   plus any opt-in namespace already resolved in `x`.
#' @returns A data frame with columns:
#'   * `fact`: the fact name.
#'   * `value`: a list-column of values (`NA` when not available).
#'   * `status`: `"ok"`, `"not_applicable"`, `"unavailable"` or `"error"`.
#'   * `source`: the files, commands, environment variables or URLs used.
#'   * `resolver`: the id of the resolver that produced the value.
#'   * `elapsed`: resolution time in seconds.
#'   * `message`: why the status is not `"ok"`.
#' @export
#' @examples
#' facts_df(facts(), "cpu")
facts_df <- function(x = facts(), namespaces = NULL) {
  check_zufax(x)
  check_namespaces(namespaces)
  state <- zufax_state(x)
  if (is.null(namespaces)) {
    resolved <- unique(fact_namespace(names(state$memo)))
    namespaces <- union(default_namespaces(), intersect(resolved, .zufax$opt_in))
    namespaces <- namespaces[order(match(namespaces, known_namespaces()))]
  }
  records <- unlist(
    lapply(namespaces, \(ns) resolve_group(ns, state)),
    recursive = FALSE,
    use.names = FALSE
  )
  field <- function(name, type) vapply(records, `[[`, type, name)
  out <- data.frame(
    fact = field("name", character(1)),
    status = field("status", character(1)),
    source = field("source", character(1)),
    resolver = field("resolver", character(1)),
    elapsed = field("elapsed", numeric(1)),
    message = field("message", character(1))
  )
  out$value <- lapply(records, `[[`, "value")
  out[c("fact", "value", "status", "source", "resolver", "elapsed", "message")]
}

#' @export
`$.zufax` <- function(x, name) zufax_get(x, name)

#' @export
`[[.zufax` <- function(x, i, ...) zufax_get(x, i)

#' @export
names.zufax <- function(x) known_namespaces()

#' @export
as.list.zufax <- function(x, ...) {
  ns <- default_namespaces()
  out <- lapply(ns, \(name) zufax_get(x, name))
  names(out) <- ns
  out
}

# Helpers ----------------------------------------------------------------

zufax_state <- function(x) .subset2(x, "state")

check_zufax <- function(x) {
  if (!inherits(x, "zufax")) {
    zufax_abort("`x` must be a zufax object created by `facts()`.")
  }
}

check_namespaces <- function(namespaces) {
  if (is.null(namespaces)) {
    return(invisible())
  }
  if (!is.character(namespaces) || anyNA(namespaces)) {
    zufax_abort("`namespaces` must be a character vector or NULL.")
  }
  unknown <- setdiff(namespaces, known_namespaces())
  if (length(unknown)) {
    zufax_abort(
      "Unknown namespace %s. Available: %s.",
      paste0("`", unknown, "`", collapse = ", "),
      paste(known_namespaces(), collapse = ", ")
    )
  }
}

zufax_get <- function(x, name) {
  if (!is_string(name)) {
    zufax_abort("Index a zufax object with a single name.")
  }
  state <- zufax_state(x)
  if (name %in% known_facts()) {
    return(resolve_fact(name, state)$value)
  }
  records <- resolve_group(name, state)
  if (!length(records)) {
    zufax_abort("Unknown namespace or fact `%s`.", name, class = "zufax_unknown_fact")
  }
  nest_values(records, name)
}

# Resolve every fact under a namespace or group prefix.
resolve_group <- function(prefix, state) {
  names <- known_facts()
  names <- names[startsWith(names, paste0(prefix, "."))]
  records <- lapply(names, resolve_fact, state = state)
  names(records) <- names
  records
}

# list("cpu.host.logical" = rec) with prefix "cpu" -> list(host = list(logical = value))
nest_values <- function(records, prefix) {
  out <- list()
  for (name in names(records)) {
    path <- strsplit(substring(name, nchar(prefix) + 2), ".", fixed = TRUE)[[1]]
    out <- set_path(out, path, records[[name]]$value)
  }
  out
}

set_path <- function(x, path, value) {
  if (length(path) == 1) {
    x[path] <- list(value)
    return(x)
  }
  x[[path[1]]] <- set_path(x[[path[1]]] %||% list(), path[-1], value)
  x
}
