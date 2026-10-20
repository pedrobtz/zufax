test_that("rlimits are read from /proc/self/limits", {
  local_root(list(
    "proc/self/limits" = c(
      "Limit                     Soft Limit           Hard Limit           Units     ",
      "Max data size             1073741824           unlimited            bytes     ",
      "Max address space         unlimited            unlimited            bytes     "
    )
  ))
  withr::local_options(zufax.os = "linux")
  expect_equal(fact("memory.rlimit.data"), 1024^3)
  expect_equal(fact("memory.rlimit.as"), Inf)
})

test_that("memory.host.available is approximated on old kernels", {
  local_root(list(
    "proc/meminfo" = c(
      "MemTotal:       1000 kB",
      "MemFree:         100 kB",
      "Buffers:          10 kB",
      "Cached:          200 kB"
    )
  ))
  withr::local_options(zufax.os = "linux")
  expect_equal(fact("memory.host.available"), 310 * 1024)
})

test_that("dynamic memory facts are not cached", {
  root <- local_fixture_copy("docker-v2-cpus1.5-mem512m")
  expect_equal(fact("memory.cgroup.usage"), 1449984)
  expect_equal(fact("memory.cgroup.limit"), 536870912)
  writeLines("2000000", file.path(root, "sys/fs/cgroup/memory.current"))
  expect_equal(fact("memory.cgroup.usage"), 2e6)
  writeLines("1", file.path(root, "sys/fs/cgroup/memory.max"))
  expect_equal(fact("memory.cgroup.limit"), 536870912)
})

test_that("effective_memory() falls back to host total when unlimited", {
  local_fixture("docker-v2-unlimited")
  expect_equal(fact("memory.cgroup.limit"), Inf)
  expect_equal(effective_memory(), fact("memory.host.total"))
  expect_snapshot(effective_memory("nope"), error = TRUE)
})

test_that("pressure stall information is parsed", {
  expect_equal(
    parse_pressure(c(
      "some avg10=23.40 avg60=10.20 avg300=4.00 total=8800000",
      "full avg10=11.10 avg60=5.00 avg300=2.00 total=4100000"
    )),
    c(some = 23.4, full = 11.1)
  )
  expect_null(parse_pressure(NULL))
  expect_null(parse_pressure("garbage"))
})

test_that("memory pressure and OOM kills come from cgroup v2 files", {
  local_fixture("aks-pod-downward-api")
  f <- facts(refresh = TRUE)
  expect_equal(f[["memory.cgroup.pressure"]], c(some = 23.4, full = 11.1))
  expect_equal(f[["cpu.cgroup.pressure"]], c(some = 1, full = 0))
  expect_equal(f[["memory.cgroup.oom_kills"]], 2)
  local_fixture("k8s-v2-limits")
  expect_equal(fact("cpu.cgroup.pressure"), c(some = 12.5, full = 0))
  expect_equal(fact("memory.cgroup.oom_kills"), 0)
})

test_that("cgroup v1 reports OOM kills but no pressure", {
  local_fixture("docker-v1-cpus1.5-mem512m")
  expect_equal(fact("memory.cgroup.oom_kills"), 0)
  df <- facts_df(facts("memory", refresh = TRUE))
  expect_equal(df$status[df$fact == "memory.cgroup.pressure"], "not_applicable")
})

test_that("available memory never exceeds the limit when usage is unreadable", {
  root <- local_fixture_copy("docker-v2-cpus1.5-mem512m")
  unlink(file.path(root, "sys/fs/cgroup/memory.current"))
  expect_equal(effective_memory(), 536870912)
  expect_lte(effective_memory("available"), effective_memory())
})
