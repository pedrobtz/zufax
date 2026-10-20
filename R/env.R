# Environment variable names whose values are hidden by default.
secret_name_pattern <- paste0(
  "key|token|secret|password|passwd|credential|auth|conn(ection)?_?str|sas|header|",
  "(^|_)pat($|_)"
)

redact_env <- function(vars, mode = "default", allowlist = character()) {
  vars <- strip_credentials(vars)
  if (mode == "none") {
    return(vars)
  }
  if (mode == "allowlist") {
    return(vars[names(vars) %in% allowlist])
  }
  secret <- grepl(secret_name_pattern, names(vars), ignore.case = TRUE) &
    !names(vars) %in% allowlist
  vars[secret] <- "<redacted>"
  vars
}

# Every environment variable as valid UTF-8. Sys.getenv() fails in a UTF-8
# locale when a variable holds invalid bytes; it is then read in the C locale.
all_env <- function() {
  vars <- tryCatch(Sys.getenv(), error = function(e) {
    old <- Sys.getlocale("LC_CTYPE")
    on.exit(Sys.setlocale("LC_CTYPE", old), add = TRUE)
    Sys.setlocale("LC_CTYPE", "C")
    Sys.getenv()
  })
  as_utf8(stats::setNames(as.character(vars), names(vars)))
}

proxy_vars <- c("http_proxy", "https_proxy", "no_proxy", "HTTP_PROXY", "HTTPS_PROXY", "NO_PROXY")

register_env_facts <- function() {
  register(resolver("env.vars", cache = FALSE, function(ctx) {
    mode <- getOption("zufax.redact", "default")
    if (!mode %in% c("default", "allowlist", "none")) {
      stop("`zufax.redact` must be \"default\", \"allowlist\" or \"none\".", call. = FALSE)
    }
    r_note(ctx, "Sys.getenv()")
    vars <- all_env()
    redact_env(vars, mode, getOption("zufax.redact_allowlist", character()))
  }))

  register(resolver("env.proxies", cache = FALSE, function(ctx) {
    values <- vapply(proxy_vars, \(name) ctx$env(name) %||% NA_character_, character(1))
    # Windows variable names are case-insensitive: http_proxy is HTTP_PROXY.
    values <- values[!is.na(values) & !duplicated(tolower(names(values)))]
    if (!length(values)) {
      not_applicable("No proxy is configured.")
    }
    strip_credentials(values)
  }))
}
