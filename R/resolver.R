# A resolver computes one fact. Several resolvers may provide the same fact;
# the highest-weight one whose `confine` predicates pass is used, falling
# through to the next one when it reports "unavailable".
#
# `confine` is a named list. The name "os" matches against zufax_os(); any other
# name is a fact whose value is checked. Each element is either a vector of
# accepted values or a function(value) returning TRUE/FALSE.
resolver <- function(
  name,
  resolve,
  confine = list(),
  weight = 100,
  network = FALSE,
  cache = TRUE,
  id = name
) {
  if (!is_string(name) || !grepl(fact_name_pattern, name)) {
    zufax_abort("`name` must be a dotted lower-case fact name, not %s.", format(name)[1])
  }
  if (!is.function(resolve)) {
    zufax_abort("`resolve` must be a function.")
  }
  if (!is.list(confine) || (length(confine) && is.null(names(confine)))) {
    zufax_abort("`confine` must be a named list.")
  }
  if (!is.numeric(weight) || length(weight) != 1 || is.na(weight)) {
    zufax_abort("`weight` must be a single number.")
  }
  if (!is_flag(network) || !is_flag(cache)) {
    zufax_abort("`network` and `cache` must be TRUE or FALSE.")
  }
  structure(
    list(
      name = name,
      resolve = resolve,
      confine = confine,
      weight = weight,
      network = network,
      cache = cache,
      id = id
    ),
    class = "zufax_resolver"
  )
}

fact_name_pattern <- "^[a-z][a-z0-9_]*(\\.[a-z][a-z0-9_]*)+$"

# Signalled by resolvers to set a status other than "ok".
unavailable <- function(message = "No data found.") {
  stop(structure(
    class = c("zufax_unavailable", "condition"),
    list(message = message, call = NULL)
  ))
}

not_applicable <- function(message) {
  stop(structure(
    class = c("zufax_not_applicable", "condition"),
    list(message = message, call = NULL)
  ))
}

# Registry ---------------------------------------------------------------

.zufax <- new.env(parent = emptyenv())
.zufax$resolvers <- list()
.zufax$opt_in <- "packages"
.zufax$cache <- new.env(parent = emptyenv())
.zufax$python_probe <- list()
.zufax$imds <- list()

namespace_order <- c(
  "os",
  "cpu",
  "memory",
  "cgroup",
  "virtualization",
  "container",
  "k8s",
  "cloud",
  "runtime",
  "env",
  "disk",
  "packages"
)

register <- function(r) {
  existing <- setdiff(names(.zufax$resolvers) %||% character(), r$name)
  clash <- startsWith(existing, paste0(r$name, ".")) |
    startsWith(r$name, paste0(existing, "."))
  if (any(clash)) {
    zufax_abort(
      "Fact `%s` clashes with `%s`: a fact cannot also be a group of facts.",
      r$name,
      existing[clash][1]
    )
  }
  current <- .zufax$resolvers[[r$name]]
  current <- Filter(\(x) !identical(x$id, r$id), current)
  current <- c(current, list(r))
  weights <- vapply(current, `[[`, numeric(1), "weight")
  .zufax$resolvers[[r$name]] <- current[order(weights, decreasing = TRUE)]
  invisible(r)
}

registry_reset <- function() {
  .zufax$resolvers <- list()
  cache_clear()
}

cache_clear <- function() {
  .zufax$cache <- new.env(parent = emptyenv())
  .zufax$python_probe <- list()
  .zufax$imds <- list()
}

fact_namespace <- function(name) sub("\\..*$", "", name)

known_facts <- function(namespace = NULL) {
  facts <- names(.zufax$resolvers)
  if (!is.null(namespace)) {
    facts <- facts[fact_namespace(facts) == namespace]
  }
  facts
}

known_namespaces <- function() {
  ns <- unique(fact_namespace(names(.zufax$resolvers)))
  ns[order(match(ns, namespace_order), ns)]
}

default_namespaces <- function() setdiff(known_namespaces(), .zufax$opt_in)
