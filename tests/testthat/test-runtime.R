test_that("R facts describe the running session", {
  f <- facts("runtime")
  expect_equal(f[["runtime.r.version"]], paste(R.version$major, R.version$minor, sep = "."))
  expect_equal(f[["runtime.r.home"]], R.home())
  expect_equal(f[["runtime.r.libpaths"]], .libPaths())
  expect_equal(f[["runtime.pid"]], Sys.getpid())
  expect_named(f[["runtime.r.lapack"]], c("version", "library"))
})

test_that("repository URLs lose their credentials", {
  withr::local_options(
    repos = c(
      CRAN = "https://cloud.r-project.org",
      private = "https://user:s3cret@ppm.example.com/cran/latest",
      signed = "https://repo.example.com/cran?token=abc&x=1"
    )
  )
  expect_equal(
    fact("runtime.r.repos"),
    c(
      CRAN = "https://cloud.r-project.org",
      private = "https://<redacted>@ppm.example.com/cran/latest",
      signed = "https://repo.example.com/cran?token=<redacted>&x=1"
    )
  )
})

test_that("repository URLs that are not valid UTF-8 still resolve", {
  withr::local_options(repos = c(CRAN = "https://cran.example.com/caf\xe9"))
  df <- facts_df(facts("runtime", refresh = TRUE))
  expect_equal(df$status[df$fact == "runtime.r.repos"], "ok")
  expect_equal(fact("runtime.r.repos"), c(CRAN = "https://cran.example.com/caf<e9>"))
})

test_that("thread settings are reported", {
  withr::local_envvar(
    OMP_NUM_THREADS = "2",
    MKL_NUM_THREADS = NA,
    R_PARALLELLY_AVAILABLECORES_FALLBACK = "1"
  )
  withr::local_options(mc.cores = 3, Ncpus = NULL)
  env <- fact("runtime.threads.env")
  expect_equal(env[["OMP_NUM_THREADS"]], "2")
  expect_equal(env[["R_PARALLELLY_AVAILABLECORES_FALLBACK"]], "1")
  expect_false("MKL_NUM_THREADS" %in% names(env))
  expect_equal(fact("runtime.threads.options"), c(mc.cores = 3, Ncpus = NA))
})

test_that("renv projects are detected", {
  withr::local_envvar(RENV_PROJECT = "/work/project")
  expect_equal(
    fact("runtime.r.renv"),
    c(project = "/work/project", lockfile = "/work/project/renv.lock")
  )
  withr::local_envvar(RENV_PROJECT = NA)
  withr::local_dir(withr::local_tempdir())
  df <- facts_df(facts("runtime"))
  expect_equal(df$status[df$fact == "runtime.r.renv"], "not_applicable")
})

test_that("uid and privilege come from /proc/self/status on Linux", {
  local_fixture("docker-v2-unlimited")
  expect_equal(fact("runtime.uid"), 0L)
  expect_equal(fact("runtime.gid"), 0L)
  expect_true(fact("runtime.privileged"))
  local_root(list(
    "proc/self/status" = c("Uid:\t1000\t1000\t1000\t1000", "Gid:\t1000\t1000\t1000\t1000")
  ))
  withr::local_options(zufax.os = "linux")
  expect_false(fact("runtime.privileged"))
})

test_that("uid uses id on other Unix systems and whoami on Windows", {
  withr::local_options(zufax.os = "darwin", zufax.cmd_mock = function(cmd, args) {
    switch(paste(cmd, args), "id -u" = "501", "id -g" = "20", NULL)
  })
  expect_equal(fact("runtime.uid"), 501L)
  expect_equal(fact("runtime.gid"), 20L)
  expect_false(fact("runtime.privileged"))
  withr::local_options(zufax.os = "windows", zufax.cmd_mock = function(cmd, args) {
    c("Mandatory Label\\High Mandatory Level Label S-1-16-12288")
  })
  expect_true(fact("runtime.privileged"))
})

test_that("parallelly is used when installed", {
  skip_if_not_installed("parallelly")
  expect_equal(fact("runtime.parallelly_cores"), as.integer(parallelly::availableCores()))
})

test_that("R connection slots are counted", {
  conns <- fact("runtime.r.connections")
  expect_named(conns, c("max", "used", "free"))
  expect_equal(conns[["free"]], conns[["max"]] - conns[["used"]])
  con <- file(tempfile(), "w")
  on.exit(close(con))
  expect_equal(fact("runtime.r.connections")[["used"]], conns[["used"]] + 1L)
})

test_that("the open-files limit comes from /proc/self/limits or ulimit", {
  local_root(list(
    "proc/self/limits" = c(
      "Limit                     Soft Limit           Hard Limit           Units     ",
      "Max open files            1024                 1048576              files     "
    )
  ))
  withr::local_options(zufax.os = "linux")
  expect_equal(fact("runtime.rlimit.nofile"), 1024)
  withr::local_options(zufax.os = "darwin", zufax.cmd_mock = function(cmd, args) {
    if (cmd == "sh") "256"
  })
  expect_equal(fact("runtime.rlimit.nofile"), 256)
})
