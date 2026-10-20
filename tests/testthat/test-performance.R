# Regression guards with generous limits; the targets (50 ms snapshot,
# 200 us usage()) are tracked in the roadmap with measured values.

test_that("a default snapshot is fast once warm", {
  skip_on_cran()
  skip_if_not(identical(Sys.info()[["sysname"]], "Linux"), "timed on Linux only")
  withr::local_options(zufax.root = NULL, zufax.os = NULL)
  facts_df(facts(refresh = TRUE))
  times <- vapply(1:5, \(i) system.time(facts_df(facts(refresh = TRUE)))[["elapsed"]], numeric(1))
  # Generous: shared CI machines and R-devel builds are slow and noisy. This
  # catches gross regressions such as a 500 ms Sys.timezone() call.
  median <- stats::median(times)
  expect_lt(median, 0.25, label = sprintf("median snapshot time (%.0f ms)", 1000 * median))
})

test_that("usage() costs well under a millisecond per call", {
  skip_on_cran()
  skip_if_not(identical(Sys.info()[["sysname"]], "Linux"), "timed on Linux only")
  withr::local_options(zufax.root = NULL, zufax.os = NULL)
  local_usage_reset()
  tick <- 0
  local_mocked_bindings(usage_now = function() {
    tick <<- tick + 1
    c(cpu = tick / 2, elapsed = tick)
  })
  usage()
  n <- 2000
  elapsed <- system.time(
    for (i in seq_len(n)) {
      usage()
    }
  )[["elapsed"]]
  expect_lt(elapsed / n, 0.001)
})
