test_that("isa_level() finds the highest complete x86-64 level", {
  v2 <- x86_levels[["x86-64-v2"]]
  v3 <- x86_levels[["x86-64-v3"]]
  expect_equal(isa_level(c("fpu", "sse2"), x86 = TRUE), "x86-64")
  expect_equal(isa_level(v2, x86 = TRUE), "x86-64-v2")
  expect_equal(isa_level(c(v2, v3), x86 = TRUE), "x86-64-v3")
  expect_equal(isa_level(c(v2, v3, x86_levels[["x86-64-v4"]]), x86 = TRUE), "x86-64-v4")
  expect_equal(isa_level(c(v3, x86_levels[["x86-64-v4"]]), x86 = TRUE), "x86-64")
})

test_that("isa_level() reports arm64 extensions", {
  expect_equal(isa_level(c("fp", "asimd"), x86 = FALSE), "arm64")
  expect_equal(isa_level(c("fp", "asimd", "sve", "sve2"), x86 = FALSE), "arm64+sve+sve2")
  expect_equal(isa_level(c("half", "neon"), x86 = FALSE), "arm")
})

test_that("arm64 cpuinfo gives vendor, flags and topology from sysfs", {
  local_root(list(
    "proc/cpuinfo" = c(
      "processor\t: 0",
      "BogoMIPS\t: 50.00",
      "Features\t: fp asimd evtstrm sve",
      "CPU implementer\t: 0x41",
      "CPU part\t: 0xd40",
      "",
      "processor\t: 1",
      "Features\t: fp asimd evtstrm sve",
      "CPU implementer\t: 0x41"
    ),
    "sys/devices/system/cpu/online" = "0-1",
    "sys/devices/system/cpu/cpu0/topology/core_id" = "0",
    "sys/devices/system/cpu/cpu0/topology/physical_package_id" = "0",
    "sys/devices/system/cpu/cpu1/topology/core_id" = "1",
    "sys/devices/system/cpu/cpu1/topology/physical_package_id" = "0"
  ))
  withr::local_options(zufax.os = "linux")
  f <- facts("cpu")
  expect_equal(f[["cpu.vendor"]], "ARM")
  expect_equal(f[["cpu.isa_level"]], "arm64+sve")
  expect_equal(f[["cpu.flags"]], c("fp", "asimd", "evtstrm", "sve"))
  expect_equal(f[["cpu.host.logical"]], 2)
  expect_equal(f[["cpu.host.physical"]], 2)
  expect_equal(f[["cpu.host.sockets"]], 1)
  expect_equal(f[["cpu.model"]], NA)
})

test_that("cpu.host.logical falls back to counting processors", {
  local_root(list("proc/cpuinfo" = c("processor\t: 0", "", "processor\t: 1", "", "processor\t: 2")))
  withr::local_options(zufax.os = "linux")
  expect_equal(fact("cpu.host.logical"), 3)
})

test_that("cpu.load is a named vector", {
  local_fixture("k8s-v2-limits")
  expect_equal(fact("cpu.load"), c(`1min` = 1.5, `5min` = 0.75, `15min` = 0.25))
})

test_that("cfs_cores() converts quota and period", {
  expect_equal(cfs_cores(150000, 100000), 1.5)
  expect_equal(cfs_cores(-1, 100000), Inf)
  expect_equal(cfs_cores(Inf, 100000), Inf)
  expect_equal(cfs_cores(NA, 100000), NA_real_)
  expect_equal(parse_cpu_max("max 100000"), Inf)
  expect_equal(parse_cpu_max("50000 100000"), 0.5)
  expect_equal(parse_cpu_max("50000"), 0.5)
})
