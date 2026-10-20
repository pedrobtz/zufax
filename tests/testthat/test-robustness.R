# Every parser must turn bad input into "unavailable", never "error".

errors_in <- function() {
  df <- facts_df(facts(refresh = TRUE))
  df$fact[df$status == "error"]
}

corrupt_each_file <- function(fixture, variants) {
  skip_on_cran()
  root <- local_fixture_copy(fixture)
  local_azure_env()
  withr::local_envvar(container = NA)
  files <- list.files(root, recursive = TRUE, all.files = TRUE)
  failures <- character()
  for (file in files) {
    path <- file.path(root, file)
    original <- readBin(path, "raw", file.size(path))
    for (name in names(variants)) {
      writeBin(variants[[name]](original), path)
      bad <- errors_in()
      # usage() and print() must not throw either.
      local_usage_reset()
      thrown <- tryCatch(
        {
          usage_line(extra = c("host", "working_set", "pressure"))
          format(facts())
          NULL
        },
        error = conditionMessage
      )
      bad <- c(bad, if (!is.null(thrown)) paste("throws:", thrown))
      if (length(bad)) {
        failures <- c(failures, sprintf("%s (%s): %s", file, name, paste(bad, collapse = ", ")))
      }
    }
    writeBin(original, path)
  }
  expect_equal(failures, character())
}

# Rewrite the text of a file; binary files (with NUL bytes) are left alone.
edit_text <- function(x, fun) {
  if (any(x == 0)) {
    return(x)
  }
  charToRaw(fun(rawToChar(x)))
}

variants <- list(
  empty = \(x) raw(),
  garbage = \(x) charToRaw("\x01\x02 not:what = you\texpect\n-1 max -\n"),
  truncated = \(x) x[seq_len(length(x) %/% 2)],
  non_utf8 = \(x) c(as.raw(c(0xff, 0xfe, 0xe9)), x, as.raw(c(0xe9, 0x0a))),
  crlf = \(x) edit_text(x, \(s) gsub("\n", "\r\n", s, fixed = TRUE, useBytes = TRUE)),
  no_newline = \(x) edit_text(x, \(s) sub("\n+$", "", s, useBytes = TRUE)),
  huge = \(x) edit_text(x, \(s) gsub("[0-9]+", "99999999999999999999999999", s, useBytes = TRUE)),
  negative = \(x) edit_text(x, \(s) gsub("([0-9]+)", "-\\1", s, useBytes = TRUE)),
  duplicated = \(x) edit_text(x, \(s) gsub("([^\n]*\n)", "\\1\\1", s, useBytes = TRUE))
)

test_that("corrupt files in a cgroup v2 pod never cause errors", {
  corrupt_each_file("k8s-v2-limits", variants)
})

test_that("corrupt files in a cgroup v1 container never cause errors", {
  corrupt_each_file("docker-v1-cpus1.5-mem512m", variants)
})

test_that("corrupt files in an AKS pod never cause errors", {
  corrupt_each_file("aks-pod-downward-api", variants)
})

test_that("an empty root gives no errors", {
  local_root()
  withr::local_options(zufax.os = "linux")
  local_azure_env()
  expect_equal(errors_in(), character())
  df <- facts_df(facts(refresh = TRUE))
  linux <- df[startsWith(df$fact, "cgroup.") | startsWith(df$fact, "memory.cgroup."), ]
  expect_true(all(linux$status %in% c("unavailable", "not_applicable")))
})

test_that("unreadable files are unavailable, not errors", {
  skip_on_os("windows")
  root <- local_fixture_copy("docker-v2-cpus1.5-mem512m")
  path <- file.path(root, "sys/fs/cgroup/memory.max")
  Sys.chmod(path, "000")
  withr::defer(Sys.chmod(path, "644"))
  skip_if(file.access(path, 4) == 0, "running as root: permissions are not enforced")
  expect_equal(errors_in(), character())
  expect_equal(fact("memory.cgroup.limit", refresh = TRUE), NA)
})

test_that("the service account token is never read", {
  root <- local_fixture_copy("aks-pod-downward-api")
  token <- "eyJhbGciOiJSUzI1NiJ9.SECRET-TOKEN"
  writeLines(token, file.path(root, "var/run/secrets/kubernetes.io/serviceaccount/token"))
  local_azure_env(KUBERNETES_SERVICE_HOST = "10.0.0.1")
  df <- facts_df(facts("k8s", refresh = TRUE))
  values <- unlist(lapply(df$value, \(v) if (is.data.frame(v)) unlist(v) else as.character(v)))
  expect_false(any(grepl("SECRET-TOKEN", values, fixed = TRUE)))
  expect_false(any(grepl("serviceaccount/token", df$source, fixed = TRUE)))
})

test_that("garbage command output never causes errors", {
  outputs <- list(
    character(),
    "",
    c("x", ": :", "key:", "hw.memsize: lots", "{ sec = nope }", "Pages free: many."),
    list(status = 1L, stdout = "error: something failed")
  )
  local_azure_env()
  local_python_env()
  for (os in c("darwin", "windows", "linux")) {
    for (out in outputs) {
      withr::local_options(zufax.os = os, zufax.cmd_mock = function(cmd, args) out)
      local_root()
      expect_equal(errors_in(), character(), label = paste(os, deparse(out)))
    }
  }
})
