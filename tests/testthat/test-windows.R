registry <- list(
  "HARDWARE\\DESCRIPTION\\System\\CentralProcessor\\0" = list(
    ProcessorNameString = "Intel(R) Xeon(R) Platinum 8370C CPU @ 2.80GHz   ",
    VendorIdentifier = "GenuineIntel"
  ),
  "HARDWARE\\DESCRIPTION\\System\\BIOS" = list(
    SystemManufacturer = "Microsoft Corporation",
    SystemProductName = "Virtual Machine",
    BaseBoardManufacturer = "Microsoft Corporation",
    BIOSVendor = "Microsoft Corporation"
  )
)

local_windows <- function(registry, memory = TRUE, env = parent.frame()) {
  withr::local_options(zufax.os = "windows", .local_envir = env)
  withr::local_envvar(
    NUMBER_OF_PROCESSORS = "4",
    PROCESSOR_IDENTIFIER = "Intel64 Family 6 Model 106 Stepping 6, GenuineIntel",
    .local_envir = env
  )
  local_azure_env(env = env)
  local_mocked_bindings(
    windows_registry = function(key) registry[[key]],
    ps_call = function(fun, ...) {
      switch(
        fun,
        ps_system_memory = if (memory) list(total = 16 * 1024^3, avail = 9 * 1024^3),
        ps_boot_time = as.POSIXct(1790000000, tz = "UTC"),
        NULL
      )
    },
    .env = env
  )
}

test_that("Windows facts come from the registry, environment and ps", {
  local_windows(registry)
  f <- facts(refresh = TRUE)
  expect_equal(f[["os.id"]], "windows")
  expect_equal(f[["cpu.model"]], "Intel(R) Xeon(R) Platinum 8370C CPU @ 2.80GHz")
  expect_equal(f[["cpu.vendor"]], "Intel")
  expect_equal(f[["cpu.host.logical"]], 4)
  expect_equal(f[["cpu.effective"]], 4L)
  expect_equal(f[["memory.host.total"]], 16 * 1024^3)
  expect_equal(f[["memory.host.available"]], 9 * 1024^3)
  expect_equal(f[["os.boot_time"]], as.POSIXct(1790000000, tz = "UTC"))
  expect_equal(f[["virtualization.type"]], "vm")
  expect_equal(f[["virtualization.hypervisor"]], "hyperv")
  df <- facts_df(f)
  expect_equal(df$fact[df$status == "error"], character())
  expect_equal(df$status[df$fact == "cpu.load"], "not_applicable")
})

test_that("Azure Windows VMs are recognized by the guest agent directory", {
  local_windows(registry)
  local_mocked_bindings(file_exists = function(path, root) path == "C:/WindowsAzure")
  expect_equal(fact("cloud.provider"), "azure")
})

test_that("Windows without ps reads memory with one PowerShell query", {
  local_windows(registry, memory = FALSE)
  withr::local_options(zufax.cmd_mock = function(cmd, args) {
    if (cmd == "powershell") "16777216 9437184" else NULL
  })
  expect_equal(fact("memory.host.total"), 16 * 1024^3)
  expect_equal(fact("memory.host.available"), 9 * 1024^3)
})

test_that("Windows falls back to PROCESSOR_IDENTIFIER without the registry", {
  local_windows(list())
  f <- facts(refresh = TRUE)
  expect_equal(f[["cpu.model"]], "Intel64 Family 6 Model 106 Stepping 6, GenuineIntel")
  expect_equal(f[["cpu.vendor"]], "Intel")
  expect_equal(f[["virtualization.type"]], "unknown")
})

test_that("Windows Python comes from the py launcher or LOCALAPPDATA", {
  local_python_env()
  withr::local_options(zufax.os = "windows")
  local_mocked_bindings(sys_which = function(name) {
    c(
      python3 = "C:\\Users\\u\\AppData\\Local\\Microsoft\\WindowsApps\\python3.exe",
      py = "C:\\Windows\\py.exe"
    )[name] %|NA|%
      ""
  })
  withr::local_options(zufax.cmd_mock = function(cmd, args) {
    if (identical(args, "-0p")) {
      c(
        " -V:3.13 *        C:\\Python313\\python.exe",
        " -V:3.12          C:\\Python312\\python.exe"
      )
    }
  })
  expect_equal(fact("runtime.python.path"), "C:\\Python313\\python.exe")

  local <- write_files(
    withr::local_tempdir(),
    list(
      "Programs/Python/Python39/python.exe" = "",
      "Programs/Python/Python312/python.exe" = ""
    )
  )
  withr::local_envvar(LOCALAPPDATA = local)
  local_mocked_bindings(sys_which = function(name) "")
  expect_equal(
    fact("runtime.python.path"),
    file.path(local, "Programs", "Python", "Python312", "python.exe")
  )
})
