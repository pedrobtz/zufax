test_that("http_get() only allows the instance metadata endpoint", {
  expect_true(http_allowed("http://169.254.169.254/metadata/instance?api-version=2021-02-01"))
  expect_false(http_allowed("http://169.254.169.254/metadata/identity/oauth2/token"))
  expect_false(http_allowed(
    "http://169.254.169.254/metadata/instance?api-version=2021-02-01&resource=x"
  ))
  expect_false(http_allowed("https://example.com"))
  expect_false(http_allowed(NA_character_))
})

test_that("http_get() refuses URLs off the allowlist before any request", {
  called <- FALSE
  withr::local_options(zufax.http_mock = function(url, headers) {
    called <<- TRUE
    list(status = 200L, body = "{}")
  })
  expect_snapshot(
    http_get("http://169.254.169.254/metadata/identity/oauth2/token"),
    error = TRUE
  )
  expect_false(called)
})

test_that("http_get() uses the mock hook", {
  withr::local_options(zufax.http_mock = function(url, headers) {
    list(status = 200L, body = headers[["Metadata"]])
  })
  out <- http_get(
    "http://169.254.169.254/metadata/instance?api-version=2021-02-01",
    headers = c(Metadata = "true")
  )
  expect_equal(out, list(status = 200L, body = "true"))
})
