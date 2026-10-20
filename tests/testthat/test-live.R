# Checks against the machine running the tests. They assert only what holds
# everywhere, except on GitHub-hosted Linux runners, which are Azure VMs.

test_that("no fact errors on this machine", {
  skip_on_cran()
  withr::local_options(zufax.root = NULL, zufax.os = NULL)
  df <- facts_df(facts(refresh = TRUE))
  expect_equal(df[df$status == "error", c("fact", "message")], df[0, c("fact", "message")])
})

test_that("effective values are sane on this machine", {
  withr::local_options(zufax.root = NULL, zufax.os = NULL)
  n <- effective_cores()
  expect_gte(n, 1L)
  expect_lte(n, max(1L, parallel::detectCores(), na.rm = TRUE))
  m <- effective_memory()
  if (!is.na(m)) {
    expect_gt(m, 0)
  }
})

test_that("GitHub-hosted Linux runners are Azure VMs", {
  skip_on_cran()
  skip_if_not(identical(Sys.getenv("GITHUB_ACTIONS"), "true"), "not on GitHub Actions")
  skip_if_not(identical(Sys.getenv("RUNNER_ENVIRONMENT"), "github-hosted"), "not a hosted runner")
  skip_if_not(identical(Sys.info()[["sysname"]], "Linux"), "not Linux")
  withr::local_options(zufax.root = NULL, zufax.os = NULL)
  expect_equal(fact("virtualization.type"), "vm")
  expect_equal(fact("virtualization.hypervisor"), "hyperv")
  expect_equal(fact("cloud.provider"), "azure")
  expect_false(fact("container.detected"))
})

test_that("IMDS on GitHub-hosted Linux runners answers quickly or is reported blocked", {
  skip_on_cran()
  skip_if_not(identical(Sys.getenv("GITHUB_ACTIONS"), "true"), "not on GitHub Actions")
  skip_if_not(identical(Sys.getenv("RUNNER_ENVIRONMENT"), "github-hosted"), "not a hosted runner")
  skip_if_not(identical(Sys.info()[["sysname"]], "Linux"), "not Linux")
  skip_if_not_installed("jsonlite")
  withr::local_options(zufax.root = NULL, zufax.os = NULL)
  start <- proc.time()[["elapsed"]]
  f <- facts(cloud = TRUE, refresh = TRUE)
  df <- facts_df(f, "cloud")
  expect_lt(proc.time()[["elapsed"]] - start, 3)
  region <- df[df$fact == "cloud.region", ]
  if (region$status != "ok") {
    skip(paste("IMDS not reachable on this runner:", region$message))
  }
  expect_type(region$value[[1]], "character")
  expect_match(f[["cloud.instance.type"]], "^Standard_")
})

test_that("host facts resolve natively on every CI OS", {
  skip_on_cran()
  skip_if_not(identical(Sys.getenv("GITHUB_ACTIONS"), "true"), "not on GitHub Actions")
  withr::local_options(zufax.root = NULL, zufax.os = NULL)
  df <- facts_df(facts(refresh = TRUE))
  row <- \(fact) df[df$fact == fact, ]
  for (fact in c(
    "os.name",
    "cpu.host.logical",
    "cpu.model",
    "memory.host.total",
    "virtualization.type"
  )) {
    expect_equal(row(fact)$status, "ok", label = fact)
  }
  expect_false(grepl("detectCores", row("cpu.host.logical")$resolver))
  expect_gt(row("memory.host.total")$value[[1]], 0)
})
