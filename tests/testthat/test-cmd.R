test_that("run_cmd() returns NULL for missing commands", {
  expect_null(run_cmd("zufax-command-that-does-not-exist"))
})

test_that("run_cmd() captures stdout and status", {
  skip_on_os("windows")
  out <- run_cmd("echo", "hello")
  expect_equal(out, list(status = 0L, stdout = "hello"))
})

test_that("run_cmd() uses the mock hook", {
  withr::local_options(zufax.cmd_mock = function(cmd, args) {
    switch(
      cmd,
      sysctl = c("hw.memsize: 1024"),
      fails = list(status = 1L, stdout = character()),
      NULL
    )
  })
  expect_equal(run_cmd("sysctl", "hw.memsize"), list(status = 0L, stdout = "hw.memsize: 1024"))
  expect_equal(run_cmd("fails"), list(status = 1L, stdout = character()))
  expect_null(run_cmd("missing"))
})

test_that("run_cmd() output with non-UTF-8 bytes becomes valid strings", {
  withr::local_options(zufax.cmd_mock = function(cmd, args) c("ok", "Intel\xae Core"))
  out <- run_cmd("sysctl")
  expect_true(all(validUTF8(out$stdout)))
  expect_equal(out$stdout, c("ok", "Intel<ae> Core"))
})
