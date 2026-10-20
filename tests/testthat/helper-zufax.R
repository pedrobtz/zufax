# Resolvers are closures created in .onLoad(), before covr instruments the
# package. Registering them again makes their code count towards coverage.
register_builtins()

# Replace the registry with the given resolvers for the rest of the test.
local_registry <- function(..., opt_in = "packages", env = parent.frame()) {
  old_resolvers <- .zufax$resolvers
  old_opt_in <- .zufax$opt_in
  .zufax$resolvers <- list()
  .zufax$opt_in <- opt_in
  cache_clear()
  for (r in list(...)) {
    register(r)
  }
  withr::defer(
    {
      .zufax$resolvers <- old_resolvers
      .zufax$opt_in <- old_opt_in
      cache_clear()
    },
    envir = env
  )
  invisible()
}

# Write `files` (a named list of path = lines) under a temporary root and point
# `zufax.root` at it for the rest of the test.
local_root <- function(files = list(), env = parent.frame()) {
  root <- withr::local_tempdir(.local_envir = env)
  for (path in names(files)) {
    full <- file.path(root, path)
    dir.create(dirname(full), recursive = TRUE, showWarnings = FALSE)
    writeLines(files[[path]], full)
  }
  withr::local_options(zufax.root = root, .local_envir = env)
  root
}

# A resolver that counts how often it runs.
counting_resolver <- function(name, value = 1, ...) {
  calls <- 0
  r <- resolver(
    name,
    function(ctx) {
      calls <<- calls + 1
      value
    },
    ...
  )
  r$calls <- function() calls
  r
}

# Fixture trees ship as tarballs (see data-raw/pack-fixtures.R) and are
# extracted once per session.
fixture_names <- function() {
  sub("\\.tar\\.gz$", "", list.files(test_path("fixtures"), "\\.tar\\.gz$"))
}

fixture_root <- function(name) {
  dir <- file.path(tempdir(), "zufax-fixtures", name)
  if (!dir.exists(dir)) {
    utils::untar(test_path("fixtures", paste0(name, ".tar.gz")), exdir = dir, tar = "internal")
  }
  dir
}

# Point zufax at a fixture, pretending to be Linux.
local_fixture <- function(name, os = "linux", env = parent.frame()) {
  withr::local_options(zufax.root = fixture_root(name), zufax.os = os, .local_envir = env)
}

# A writable copy of a fixture, for tests that change files between calls.
local_fixture_copy <- function(name, env = parent.frame()) {
  dir <- withr::local_tempdir(.local_envir = env)
  files <- list.files(fixture_root(name), full.names = TRUE, all.files = TRUE, no.. = TRUE)
  file.copy(files, dir, recursive = TRUE)
  withr::local_options(zufax.root = dir, zufax.os = "linux", .local_envir = env)
  dir
}

# One line per fact, for snapshots: name = value [status] source
fixture_report <- function(name) {
  local_fixture(name)
  local_azure_env()
  withr::local_envvar(container = NA, TZ = NA)
  df <- facts_df(facts(refresh = TRUE))
  # runtime, env and disk describe the R session, not the fixture.
  df <- df[!fact_namespace(df$fact) %in% c("runtime", "env", "disk"), ]
  as_text <- \(v) paste(if (is.character(v)) v else format(v), collapse = " ")
  value <- vapply(df$value, as_text, character(1))
  # Values read from the live system (not the fixture) differ between machines.
  live <- grepl("^(Sys\\.|parallel::)", df$source)
  value[live] <- "<live>"
  value <- ifelse(nchar(value) > 60, paste0(substr(value, 1, 57), "..."), value)
  paste0(df$fact, " = ", value, " [", df$status, "] ", df$source)
}

local_usage_reset <- function(env = parent.frame()) {
  reset <- function() {
    .usage$pid <- NULL
    .usage$setup <- NULL
    .usage$prev <- NULL
    .usage$last <- NULL
  }
  reset()
  withr::defer(reset(), envir = env)
}

# No Python-related environment variables, a fresh probe memo, and the Python
# facts not skipped (see setup-zufax.R).
local_python_env <- function(..., env = parent.frame()) {
  vars <- list(RETICULATE_PYTHON = NA, VIRTUAL_ENV = NA, CONDA_PREFIX = NA)
  overrides <- list(...)
  vars[names(overrides)] <- overrides
  withr::local_envvar(.new = vars, .local_envir = env)
  withr::local_options(zufax.skip = NULL, .local_envir = env)
  .zufax$python_probe <- list()
  withr::defer(.zufax$python_probe <- list(), envir = env)
}

# Create files (path = lines) below `dir`.
write_files <- function(dir, files) {
  for (path in names(files)) {
    full <- file.path(dir, path)
    dir.create(dirname(full), recursive = TRUE, showWarnings = FALSE)
    writeLines(files[[path]], full)
  }
  dir
}

# Answer IMDS requests with `body` (or fail with `error`), counting requests.
local_imds <- function(body = NULL, error = NULL, env = parent.frame()) {
  calls <- 0
  withr::local_options(
    zufax.http_mock = function(url, headers) {
      calls <<- calls + 1
      if (!is.null(error)) {
        unavailable(error)
      }
      list(status = 200L, body = body)
    },
    .local_envir = env
  )
  .zufax$imds <- list()
  withr::defer(.zufax$imds <- list(), envir = env)
  function() calls
}

imds_body <- function() paste(readLines(test_path("fixtures", "azure-imds.json")), collapse = "\n")

azure_env_vars <- c(
  "FUNCTIONS_WORKER_RUNTIME",
  "WEBSITE_SITE_NAME",
  "WEBSITE_INSTANCE_ID",
  "WEBSITE_SKU",
  "CONTAINER_APP_NAME",
  "CONTAINER_APP_REVISION",
  "CONTAINER_APP_REPLICA_NAME",
  "AZ_BATCH_NODE_ID",
  "AZ_BATCH_POOL_ID",
  "AZ_BATCH_JOB_ID",
  "AZ_BATCH_TASK_ID",
  "AZUREML_RUN_ID",
  "AZUREML_EXPERIMENT_NAME",
  "DATABRICKS_RUNTIME_VERSION",
  "KUBERNETES_SERVICE_HOST"
)

# Clear every Azure platform variable, then set the given ones.
local_azure_env <- function(..., env = parent.frame()) {
  vars <- as.list(stats::setNames(rep(NA, length(azure_env_vars)), azure_env_vars))
  set <- list(...)
  vars[names(set)] <- set
  withr::local_envvar(.new = vars, .local_envir = env)
}

# Answer commands from recorded outputs in tests/testthat/fixtures/cmd.
local_cmd_outputs <- function(..., env = parent.frame()) {
  outputs <- list(...)
  withr::local_options(
    zufax.cmd_mock = function(cmd, args) {
      file <- outputs[[basename(cmd)]]
      if (is.null(file)) NULL else readLines(test_path("fixtures", "cmd", file))
    },
    .local_envir = env
  )
}
