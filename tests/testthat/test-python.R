probe_output <- function(prefix, site) {
  c(
    "version=3.13.1",
    "implementation=cpython",
    paste0("prefix=", prefix),
    paste0("base_prefix=", prefix),
    paste0("site=", site),
    "usersite=/home/u/.local/lib/python3.13/site-packages"
  )
}

test_that("a venv is described from pyvenv.cfg without running Python", {
  venv <- write_files(
    withr::local_tempdir(),
    list(
      "pyvenv.cfg" = c(
        "home = /usr/bin",
        "include-system-site-packages = false",
        "version = 3.12.4"
      ),
      "bin/python3" = "",
      "lib/python3.12/site-packages/README.txt" = ""
    )
  )
  local_python_env(VIRTUAL_ENV = venv)
  withr::local_options(zufax.os = "linux", zufax.cmd_mock = function(cmd, args) {
    stop("Python must not run")
  })
  f <- facts(refresh = TRUE)
  expect_equal(f[["runtime.python.env_type"]], "venv")
  expect_equal(f[["runtime.python.version"]], "3.12.4")
  expect_equal(f[["runtime.python.path"]], file.path(venv, "bin", "python3"))
  expect_equal(f[["runtime.python.env_path"]], venv)
  expect_equal(f[["runtime.python.prefix"]], venv)
  expect_equal(
    f[["runtime.python.site_packages"]],
    file.path(venv, "lib", "python3.12", "site-packages")
  )
})

test_that("uv environments are recognized", {
  venv <- write_files(
    withr::local_tempdir(),
    list(
      "pyvenv.cfg" = c("home = /opt/python/bin", "uv = 0.4.18", "version_info = 3.12.6"),
      "bin/python3" = ""
    )
  )
  local_python_env(VIRTUAL_ENV = venv)
  withr::local_options(zufax.os = "linux")
  expect_equal(fact("runtime.python.env_type"), "uv")
  expect_equal(fact("runtime.python.version"), "3.12.6")
})

test_that("conda prefixes are described from conda-meta", {
  conda <- write_files(
    withr::local_tempdir(),
    list(
      "conda-meta/python-3.11.9-h955ad1f_0_cpython.json" = "{}",
      "conda-meta/numpy-1.26.4-py311.json" = "{}",
      "bin/python" = ""
    )
  )
  local_python_env(CONDA_PREFIX = conda)
  withr::local_options(zufax.os = "linux")
  f <- facts(refresh = TRUE)
  expect_equal(f[["runtime.python.env_type"]], "conda")
  expect_equal(f[["runtime.python.version"]], "3.11.9")
  expect_equal(f[["runtime.python.path"]], file.path(conda, "bin", "python"))
})

test_that("a system interpreter is probed once in a separate process", {
  local_python_env()
  calls <- 0
  withr::local_options(zufax.cmd_mock = function(cmd, args) {
    if (cmd != "/usr/bin/python3" || args[1] != "-c") {
      return(NULL)
    }
    calls <<- calls + 1
    probe_output("/usr", "/usr/lib/python3/dist-packages")
  })
  local_mocked_bindings(sys_which = function(name) c(python3 = "/usr/bin/python3")[name] %|NA|% "")
  f <- facts(refresh = TRUE)
  expect_equal(f[["runtime.python.env_type"]], "system")
  expect_equal(f[["runtime.python.version"]], "3.13.1")
  expect_equal(f[["runtime.python.implementation"]], "cpython")
  expect_equal(f[["runtime.python.prefix"]], "/usr")
  expect_equal(
    f[["runtime.python.site_packages"]],
    c("/usr/lib/python3/dist-packages", "/home/u/.local/lib/python3.13/site-packages")
  )
  df <- facts_df(f, "runtime")
  expect_equal(df$status[df$fact == "runtime.python.env_path"], "not_applicable")
  facts_df(facts(refresh = TRUE), "runtime")
  expect_equal(calls, 1)
})

test_that("a failing interpreter is probed once per session until refresh", {
  local_python_env()
  calls <- 0
  withr::local_options(zufax.cmd_mock = function(cmd, args) {
    if (cmd != "/usr/bin/python3" || args[1] != "-c") {
      return(NULL)
    }
    calls <<- calls + 1
    list(status = 1L, stdout = character())
  })
  local_mocked_bindings(sys_which = function(name) c(python3 = "/usr/bin/python3")[name] %|NA|% "")
  f <- facts()
  df <- facts_df(f, "runtime")
  expect_equal(df$status[df$fact == "runtime.python.version"], "unavailable")
  expect_false(any(df$status == "error"))
  invisible(format(f))
  fact("runtime.python.version")
  fact("runtime.python.implementation")
  expect_equal(calls, 1)
  facts_df(facts(refresh = TRUE), "runtime")
  expect_equal(calls, 2)
})

test_that("RETICULATE_PYTHON wins over other variables", {
  venv <- write_files(
    withr::local_tempdir(),
    list(
      "pyvenv.cfg" = "version = 3.10.14",
      "bin/python" = ""
    )
  )
  local_python_env(
    RETICULATE_PYTHON = file.path(venv, "bin", "python"),
    CONDA_PREFIX = "/opt/conda"
  )
  withr::local_options(zufax.os = "linux")
  expect_equal(fact("runtime.python.path"), file.path(venv, "bin", "python"))
  expect_equal(fact("runtime.python.version"), "3.10.14")
})

test_that("no interpreter means not applicable", {
  local_python_env()
  local_mocked_bindings(sys_which = function(name) "")
  df <- facts_df(facts(refresh = TRUE), "runtime")
  python <- df[startsWith(df$fact, "runtime.python."), ]
  expect_equal(unique(python$status), "not_applicable")
})

test_that("reticulate is only reported when it already started Python", {
  skip_if("reticulate" %in% loadedNamespaces())
  local_python_env()
  local_mocked_bindings(sys_which = function(name) "")
  df <- facts_df(facts(refresh = TRUE), "runtime")
  expect_equal(df$message[df$fact == "runtime.python.reticulate"], "reticulate is not loaded.")
})

test_that("Windows venvs use Scripts and Lib", {
  venv <- write_files(
    withr::local_tempdir(),
    list(
      "pyvenv.cfg" = "version = 3.12.7",
      "Scripts/python.exe" = "",
      "Lib/site-packages/x" = ""
    )
  )
  local_python_env(VIRTUAL_ENV = venv)
  withr::local_options(zufax.os = "windows")
  f <- facts(refresh = TRUE)
  expect_equal(f[["runtime.python.path"]], file.path(venv, "Scripts/python.exe"))
  expect_equal(f[["runtime.python.site_packages"]], file.path(venv, "Lib", "site-packages"))
  local_python_env(RETICULATE_PYTHON = file.path(venv, "Scripts", "python.exe"))
  same_path <- \(x) normalizePath(x, winslash = "/", mustWork = FALSE)
  expect_equal(same_path(fact("runtime.python.env_path")), same_path(venv))
  expect_equal(fact("runtime.python.version"), "3.12.7")
})
