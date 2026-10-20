test_that("zufax_root() prefers the option, then ZUFAX_ROOT, then /", {
  withr::local_options(zufax.root = NULL)
  withr::local_envvar(ZUFAX_ROOT = NA)
  expect_equal(zufax_root(), "/")
  withr::local_envvar(ZUFAX_ROOT = "/host")
  expect_equal(zufax_root(), "/host")
  withr::local_options(zufax.root = "/fixture")
  expect_equal(zufax_root(), "/fixture")
})

test_that("root_path() joins root and absolute path", {
  expect_equal(root_path("/proc/self/status", "/"), "/proc/self/status")
  expect_equal(root_path("/proc/self/status", "/host/"), "/host/proc/self/status")
  expect_equal(root_path("proc/x", "/host"), "/host/proc/x")
})

test_that("readers read below the root and return NULL when missing", {
  local_root(list("proc/loadavg" = "0.5 0.4 0.3 1/100 42", "etc/a/b" = "x"))
  expect_equal(read_lines("/proc/loadavg"), "0.5 0.4 0.3 1/100 42")
  expect_null(read_lines("/proc/missing"))
  expect_null(read_lines("/etc"))
  expect_true(file_exists("/proc/loadavg"))
  expect_false(file_exists("/proc/missing"))
  expect_equal(list_dir("/etc"), "a")
  expect_null(list_dir("/nope"))
})

test_that("non-UTF-8 bytes in files become valid strings", {
  root <- local_root()
  dir.create(file.path(root, "etc"))
  writeBin(
    charToRaw("NAME=\"D\xe9bian GNU/Linux\"\nID=debian\nVERSION_ID=\"12\"\n"),
    file.path(root, "etc/os-release")
  )
  lines <- read_lines("/etc/os-release")
  expect_true(all(validUTF8(lines)))
  expect_equal(lines[1], "NAME=\"D<e9>bian GNU/Linux\"")
  withr::local_options(zufax.os = "linux")
  df <- facts_df(facts("os", refresh = TRUE))
  expect_false(any(df$status == "error"))
  expect_equal(df$value[df$fact == "os.id"][[1]], "debian")
  expect_equal(df$value[df$fact == "os.name"][[1]], "D<e9>bian GNU/Linux")
})

test_that("as_utf8() keeps valid strings, NA and names", {
  x <- c(a = "caf\xe9", b = "ok", c = NA)
  names(x)[2] <- "b\xff"
  out <- as_utf8(x)
  expect_equal(unname(out), c("caf<e9>", "ok", NA))
  expect_equal(names(out), c("a", "b<ff>", "c"))
  expect_identical(as_utf8(c(x = "fine")), c(x = "fine"))
  expect_null(as_utf8(NULL))
})
