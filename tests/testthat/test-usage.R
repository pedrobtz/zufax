test_that("usage() reports container usage and rates between calls", {
  local_usage_reset()
  root <- local_fixture_copy("docker-v2-cpus1.5-mem512m")
  clock <- c(cpu = 1, elapsed = 10)
  local_mocked_bindings(usage_now = function() clock)

  u1 <- usage()
  expect_s3_class(u1, "zufax_usage")
  expect_equal(u1[["cpu_process"]], 0.1)
  expect_equal(u1[["cpu_cgroup"]], NA_real_)
  expect_equal(u1[["cpu_limit"]], 1.5)
  expect_equal(u1[["mem_rss"]], 187 * 4096)
  expect_equal(u1[["mem_cgroup"]], 1449984)
  expect_equal(u1[["mem_limit"]], 536870912)
  expect_equal(u1[["mem_pct"]], 1449984 / 536870912)

  writeLines(
    c("usage_usec 3093869", "nr_periods 12", "nr_throttled 5", "throttled_usec 100"),
    file.path(root, "sys/fs/cgroup/cpu.stat")
  )
  clock <- c(cpu = 2, elapsed = 12)
  u2 <- usage()
  expect_equal(u2[["cpu_process"]], 0.5)
  expect_equal(u2[["cpu_cgroup"]], 1.5)
  expect_equal(u2[["cpu_throttled"]], 0.5)
})

test_that("usage() reads cgroup v1 CPU usage in nanoseconds", {
  local_usage_reset()
  root <- local_fixture_copy("docker-v1-cpus1.5-mem512m")
  clock <- c(cpu = 1, elapsed = 10)
  local_mocked_bindings(usage_now = function() clock)
  usage()
  writeLines("7000000000", file.path(root, "sys/fs/cgroup/cpu,cpuacct/cpuacct.usage"))
  writeLines(
    c("nr_periods 520", "nr_throttled 30", "throttled_time 1"),
    file.path(root, "sys/fs/cgroup/cpu,cpuacct/cpu.stat")
  )
  clock <- c(cpu = 1, elapsed = 14)
  u <- usage()
  expect_equal(u[["cpu_cgroup"]], 0.5)
  expect_equal(u[["cpu_throttled"]], 0.5)
  expect_equal(u[["mem_cgroup"]], 209715200)
})

test_that("max_age and identical timestamps reuse the last sample", {
  local_usage_reset()
  local_fixture("docker-v2-unlimited")
  clock <- c(cpu = 1, elapsed = 10)
  local_mocked_bindings(usage_now = function() clock)
  u1 <- usage()
  expect_identical(usage(), u1)
  clock <- c(cpu = 2, elapsed = 10.5)
  expect_identical(usage(max_age = 1), u1)
  expect_false(identical(usage(), u1))
})

test_that("usage() starts a new baseline after fork", {
  local_usage_reset()
  local_fixture("docker-v2-unlimited")
  clock <- c(cpu = 1, elapsed = 10)
  pid <- 1L
  local_mocked_bindings(usage_now = function() clock, current_pid = function() pid)
  usage()
  clock <- c(cpu = 3, elapsed = 12)
  expect_equal(usage()[["cpu_process"]], 1)
  pid <- 2L
  clock <- c(cpu = 4, elapsed = 16)
  expect_equal(usage()[["cpu_process"]], 0.25)
  expect_equal(usage()[["cpu_cgroup"]], NA_real_)
})

test_that("usage() extras add host and working set memory", {
  local_usage_reset()
  local_fixture("k8s-v2-limits")
  u <- usage(extra = c("host", "working_set"))
  expect_equal(u[["mem_host_available"]], 20 * 1024^3)
  expect_equal(u[["mem_working_set"]], 200 * 1024^2)
})

test_that("usage() never errors when files are missing", {
  local_usage_reset()
  local_root()
  withr::local_options(zufax.os = "linux")
  u <- usage()
  expect_equal(u[["mem_rss"]], NA_real_)
  expect_equal(u[["mem_cgroup"]], NA_real_)
  expect_type(u[["cpu_process"]], "double")
})

test_that("usage() works on the live system", {
  local_usage_reset()
  u <- usage()
  expect_gte(u[["cpu_limit"]], 1)
  expect_type(usage_line(), "character")
})

test_that("format() gives a compact log line", {
  u <- structure(
    c(
      time = 0,
      cpu_process = 0.3,
      cpu_cgroup = 1.84,
      cpu_throttled = 0.031,
      cpu_limit = 4,
      mem_rss = 1.2 * 1024^3,
      mem_cgroup = 2.1 * 1024^3,
      mem_limit = 8 * 1024^3,
      mem_pct = 2.1 / 8
    ),
    class = "zufax_usage"
  )
  expect_snapshot(print(u))
  host <- u
  host[c("cpu_cgroup", "cpu_throttled", "mem_cgroup")] <- NA
  host[["mem_limit"]] <- Inf
  host[["mem_pct"]] <- 0.15
  expect_snapshot(print(host))
  empty <- u
  empty[] <- NA
  expect_equal(format(empty), "usage unavailable")
})

test_that("fmt_bytes() picks a readable unit", {
  expect_equal(fmt_bytes(512), "512B")
  expect_equal(fmt_bytes(512 * 1024^2), "512M")
  expect_equal(fmt_bytes(2.14 * 1024^3), "2.1G")
  expect_equal(fmt_bytes(0), "0B")
})

test_that("usage() can add pressure and OOM kills", {
  local_usage_reset()
  local_fixture("aks-pod-downward-api")
  u <- usage(extra = "pressure")
  expect_equal(u[["mem_pressure"]], 23.4)
  expect_equal(u[["cpu_pressure"]], 1)
  expect_equal(u[["oom_kills"]], 2)
})

test_that("usage() never errors on empty, zero or huge cgroup memory files", {
  local_usage_reset()
  root <- local_fixture_copy("docker-v2-cpus1.5-mem512m")
  current <- file.path(root, "sys/fs/cgroup/memory.current")

  writeBin(raw(), current)
  u <- usage()
  expect_equal(u[["mem_cgroup"]], NA_real_)
  expect_type(usage_line(), "character")

  local_usage_reset()
  writeLines("99999999999999999999999999", current)
  expect_equal(usage()[["mem_cgroup"]], 1e26)
  expect_match(usage_line(), "mem=")

  local_usage_reset()
  writeLines("1449984", current)
  writeLines("0", file.path(root, "sys/fs/cgroup/memory.max"))
  writeLines("0", file.path(root, "proc/meminfo"))
  cache_clear()
  expect_type(usage_line(), "character")
})

test_that("format() handles percentages beyond the integer range", {
  u <- structure(
    c(
      time = 0,
      cpu_process = 1,
      cpu_cgroup = NA,
      cpu_throttled = 1e10,
      cpu_limit = 2,
      mem_rss = 1024,
      mem_cgroup = 1e26,
      mem_limit = 1024,
      mem_pct = 1e23
    ),
    class = "zufax_usage"
  )
  expect_match(format(u), "thr=1000000000000% mem=", fixed = TRUE)
  u[["mem_pct"]] <- Inf
  expect_match(format(u), "mem=[^ ]+/1K rss=")
})

test_that("a broken cgroup layout only disables the container fields", {
  local_usage_reset()
  root <- local_fixture_copy("docker-v2-cpus1.5-mem512m")
  local_mocked_bindings(read_cgroup_layout = function(ctx) stop("broken"))
  u <- usage()
  expect_s3_class(u, "zufax_usage")
  expect_equal(u[["mem_cgroup"]], NA_real_)
})
