test_that("the highest-weight applicable resolver wins", {
  local_registry(
    resolver("toy.a", \(ctx) "low", weight = 10, id = "low"),
    resolver("toy.a", \(ctx) "high", weight = 50, id = "high")
  )
  expect_equal(fact("toy.a"), "high")
  expect_equal(facts_df()$resolver, "high")
})

test_that("confine filters on os and on other facts", {
  local_registry(
    resolver("toy.os", \(ctx) "linux only", confine = list(os = "linux")),
    resolver("toy.flag", \(ctx) TRUE),
    resolver("toy.dep", \(ctx) "flag set", confine = list(toy.flag = TRUE)),
    resolver("toy.fun", \(ctx) "big", confine = list(toy.flag = \(v) isFALSE(v)))
  )
  withr::local_options(zufax.os = "linux")
  expect_equal(fact("toy.os"), "linux only")
  expect_equal(fact("toy.dep"), "flag set")
  expect_equal(fact("toy.fun"), NA)

  withr::local_options(zufax.os = "windows")
  df <- facts_df()
  expect_equal(df$status[df$fact == "toy.os"], "not_applicable")
  expect_equal(df$message[df$fact == "toy.os"], "No resolver applies on this system.")
})

test_that("an unavailable resolver falls through to the next one", {
  local_registry(
    resolver("toy.a", \(ctx) NULL, weight = 50, id = "first"),
    resolver("toy.a", \(ctx) "fallback", weight = 10, id = "second"),
    resolver("toy.b", \(ctx) unavailable("Nothing here."), weight = 50, id = "only")
  )
  df <- facts_df()
  expect_equal(df$resolver, c("second", "only"))
  expect_equal(df$value, list("fallback", NA))
  expect_equal(df$status, c("ok", "unavailable"))
  expect_equal(df$message, c(NA, "Nothing here."))
})

test_that("resolvers can report not_applicable", {
  local_registry(resolver("toy.a", \(ctx) not_applicable("Not on this platform.")))
  df <- facts_df()
  expect_equal(df$status, "not_applicable")
  expect_equal(df$message, "Not on this platform.")
})

test_that("network resolvers only run with cloud = TRUE", {
  r <- counting_resolver("toy.region", "westeurope", network = TRUE)
  local_registry(r)
  df <- facts_df(facts(cloud = FALSE))
  expect_equal(df$status, "not_applicable")
  expect_equal(df$message, "Needs network access: use `cloud = TRUE`.")
  expect_equal(r$calls(), 0)
  expect_equal(fact("toy.region", cloud = TRUE), "westeurope")
})

test_that("zufax.skip skips facts and namespaces", {
  a <- counting_resolver("toy.a")
  b <- counting_resolver("other.b")
  local_registry(a, b)
  withr::local_options(zufax.skip = c("toy.a", "other"))
  df <- facts_df()
  expect_equal(df$status, c("not_applicable", "not_applicable"))
  expect_equal(df$message, rep("Skipped by `zufax.skip`.", 2))
  expect_equal(c(a$calls(), b$calls()), c(0, 0))
})

test_that("errors become status = 'error' unless strict", {
  local_registry(resolver("toy.a", \(ctx) stop("boom")))
  df <- facts_df()
  expect_equal(df$status, "error")
  expect_equal(df$message, "boom")
  expect_snapshot(facts_df(facts(strict = TRUE)), error = TRUE)
})

test_that("errors in nested facts are reported once in strict mode", {
  local_registry(
    resolver("toy.inner", \(ctx) stop("boom")),
    resolver("toy.outer", \(ctx) ctx$fact("toy.inner"))
  )
  expect_snapshot(fact("toy.outer", strict = TRUE), error = TRUE)
})

test_that("NULL values are unavailable", {
  local_registry(resolver("toy.a", \(ctx) NULL))
  df <- facts_df()
  expect_equal(df$status, "unavailable")
  expect_equal(df$message, "No data found.")
})

test_that("facts can depend on other facts", {
  local_registry(
    resolver("toy.base", \(ctx) 2),
    resolver("toy.double", \(ctx) ctx$fact("toy.base") * 2)
  )
  expect_equal(fact("toy.double"), 4)
})

test_that("dependency cycles are reported as errors", {
  local_registry(
    resolver("toy.a", \(ctx) ctx$fact("toy.b")),
    resolver("toy.b", \(ctx) ctx$fact("toy.a"))
  )
  df <- facts_df(facts(refresh = TRUE))
  expect_equal(df$status[df$fact == "toy.b"], "error")
  expect_match(df$message[df$fact == "toy.b"], "Dependency cycle: toy.a -> toy.b -> toy.a")
})

test_that("confine errors are contained", {
  local_registry(resolver("toy.a", \(ctx) 1, confine = list(toy.missing = TRUE)))
  df <- facts_df()
  expect_equal(df$status, "error")
  expect_equal(df$message, "Unknown fact `toy.missing`.")
})

test_that("facts are cached per session, root and os", {
  r <- counting_resolver("toy.a")
  local_registry(r)
  fact("toy.a")
  fact("toy.a")
  expect_equal(r$calls(), 1)
  fact("toy.a", refresh = TRUE)
  expect_equal(r$calls(), 2)
  local_root()
  fact("toy.a")
  expect_equal(r$calls(), 3)
  withr::local_options(zufax.os = "plan9")
  fact("toy.a")
  expect_equal(r$calls(), 4)
})

test_that("errors are not cached", {
  calls <- 0
  local_registry(resolver("toy.a", function(ctx) {
    calls <<- calls + 1
    stop("boom")
  }))
  fact("toy.a")
  fact("toy.a")
  expect_equal(calls, 2)
})

test_that("cache = FALSE resolvers run on every call", {
  r <- counting_resolver("toy.a", cache = FALSE)
  local_registry(r)
  fact("toy.a")
  fact("toy.a")
  expect_equal(r$calls(), 2)
})

test_that("a fact is resolved once per call even with refresh = TRUE", {
  base <- counting_resolver("toy.base")
  local_registry(
    base,
    resolver("toy.x", \(ctx) ctx$fact("toy.base")),
    resolver("toy.y", \(ctx) ctx$fact("toy.base"))
  )
  facts_df(facts(refresh = TRUE))
  expect_equal(base$calls(), 1)
})

test_that("sources record files, env vars, commands and URLs", {
  local_root(list("proc/loadavg" = "0.1 0.2 0.3 1/2 3", "etc/kv" = "a: 1"))
  withr::local_envvar(ZUFAX_TEST_VAR = "x")
  withr::local_options(
    zufax.cmd_mock = \(cmd, args) "out",
    zufax.http_mock = \(url, headers) list(status = 200L, body = "{}")
  )
  url <- "http://169.254.169.254/metadata/instance?api-version=2021-02-01"
  local_registry(
    resolver("toy.file", \(ctx) ctx$read("/proc/loadavg")),
    resolver("toy.kv", \(ctx) ctx$read_kv("/etc/kv")),
    resolver("toy.env", \(ctx) ctx$env("ZUFAX_TEST_VAR")),
    resolver("toy.unset", \(ctx) ctx$env("ZUFAX_TEST_UNSET")),
    resolver("toy.cmd", \(ctx) ctx$cmd("sysctl", c("-n", "hw.ncpu"))$stdout),
    resolver("toy.http", \(ctx) ctx$http(url)$body, network = TRUE)
  )
  df <- facts_df(facts(cloud = TRUE))
  expect_equal(
    df$source,
    c("/proc/loadavg", "/etc/kv", "env:ZUFAX_TEST_VAR", NA, "sysctl -n hw.ncpu", url)
  )
  expect_equal(df$value[[2]], c(a = "1"))
  expect_equal(df$status[4], "unavailable")
})

test_that("a zufax object gives namespaces, groups and facts", {
  local_registry(
    resolver("cpu.host.logical", \(ctx) 8),
    resolver("cpu.host.physical", \(ctx) 4),
    resolver("cpu.effective", \(ctx) 2),
    resolver("packages.r", \(ctx) "lots")
  )
  f <- facts()
  expect_equal(f$cpu, list(host = list(logical = 8, physical = 4), effective = 2))
  expect_equal(f[["cpu.host"]], list(logical = 8, physical = 4))
  expect_equal(f[["cpu.effective"]], 2)
  expect_equal(names(f), c("cpu", "packages"))
  expect_equal(as.list(f), list(cpu = f$cpu))
  expect_snapshot(f$nope, error = TRUE)
})

test_that("opt-in namespaces are only included once requested", {
  local_registry(
    resolver("cpu.effective", \(ctx) 2),
    resolver("packages.r", \(ctx) "lots")
  )
  f <- facts()
  expect_equal(facts_df(f)$fact, "cpu.effective")
  f$packages
  expect_equal(facts_df(f)$fact, c("cpu.effective", "packages.r"))
  expect_equal(facts_df(facts("packages"))$fact, c("cpu.effective", "packages.r"))
  expect_equal(facts_df(f, namespaces = "packages")$fact, "packages.r")
})

test_that("facts() with namespaces resolves eagerly", {
  r <- counting_resolver("cpu.effective")
  local_registry(r)
  withr::local_options(zufax.os = "linux", zufax.root = "/")
  f <- facts("cpu")
  expect_equal(r$calls(), 1)
  expect_snapshot(f)
})

test_that("facts_df() has the documented columns", {
  local_registry(resolver("toy.a", \(ctx) c(1, 2)))
  df <- facts_df()
  expect_named(df, c("fact", "value", "status", "source", "resolver", "elapsed", "message"))
  expect_equal(df$value, list(c(1, 2)))
  expect_type(df$elapsed, "double")
})

test_that("facts_df() works with no facts", {
  local_registry()
  expect_equal(nrow(facts_df()), 0)
})

test_that("user errors are informative", {
  local_registry(resolver("cpu.host.logical", \(ctx) 8))
  expect_snapshot(fact("nope"), error = TRUE)
  expect_snapshot(fact("cpu.host"), error = TRUE)
  expect_snapshot(facts("nope"), error = TRUE)
  expect_snapshot(facts_df(list()), error = TRUE)
})

test_that("facts that depend on uncached facts are not cached", {
  flag <- TRUE
  local_registry(
    resolver("toy.flag", \(ctx) flag, cache = FALSE),
    resolver("toy.derived", \(ctx) ctx$fact("toy.flag")),
    resolver("toy.confined", \(ctx) "yes", confine = list(toy.flag = TRUE)),
    resolver("toy.stable", \(ctx) "stable")
  )
  expect_equal(fact("toy.derived"), TRUE)
  expect_equal(fact("toy.confined"), "yes")
  flag <- FALSE
  expect_equal(fact("toy.derived"), FALSE)
  expect_equal(fact("toy.confined"), NA)
  flag <- TRUE
  expect_equal(fact("toy.confined"), "yes")
  fact("toy.stable")
  expect_named(as.list(.zufax$cache), paste("/", zufax_os(), FALSE, "toy.stable", sep = "\r"))
})

test_that("warnings inside resolvers are muffled", {
  local_registry(resolver("toy.a", function(ctx) {
    warning("noisy")
    1
  }))
  expect_no_warning(df <- facts_df())
  expect_equal(df$value, list(1))
})
