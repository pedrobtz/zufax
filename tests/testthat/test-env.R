test_that("secret-looking variables are redacted", {
  vars <- c(
    AZURE_STORAGE_CONNECTION_STRING = "DefaultEndpointsProtocol=https;AccountKey=abc",
    AZURE_CLIENT_SECRET = "x",
    IDENTITY_HEADER = "x",
    MSI_SECRET = "x",
    GITHUB_PAT = "ghp_x",
    AWS_SECRET_ACCESS_KEY = "x",
    BLOB_SAS = "sv=2022",
    API_TOKEN = "x",
    DB_PASSWORD = "x",
    PATH = "/usr/bin",
    R_HOME = "/usr/lib/R",
    PWD = "/home/u",
    PATTERN = "ok",
    HOME = "/home/u",
    DATABASE_URL = "postgres://admin:hunter2@db:5432/app"
  )
  out <- redact_env(vars)
  secret <- c(
    "AZURE_STORAGE_CONNECTION_STRING",
    "AZURE_CLIENT_SECRET",
    "IDENTITY_HEADER",
    "MSI_SECRET",
    "GITHUB_PAT",
    "AWS_SECRET_ACCESS_KEY",
    "BLOB_SAS",
    "API_TOKEN",
    "DB_PASSWORD"
  )
  expect_equal(unname(out[secret]), rep("<redacted>", length(secret)))
  expect_equal(
    out[c("PATH", "R_HOME", "PWD", "PATTERN", "HOME")],
    vars[c("PATH", "R_HOME", "PWD", "PATTERN", "HOME")]
  )
  expect_equal(out[["DATABASE_URL"]], "postgres://<redacted>@db:5432/app")
})

test_that("redaction modes are honored", {
  vars <- c(API_TOKEN = "x", HOME = "/home/u", URL = "https://u:p@h")
  expect_equal(redact_env(vars, "allowlist", "HOME"), c(HOME = "/home/u"))
  expect_equal(
    redact_env(vars, "none"),
    c(API_TOKEN = "x", HOME = "/home/u", URL = "https://<redacted>@h")
  )
  expect_equal(redact_env(vars, "default", "API_TOKEN")[["API_TOKEN"]], "x")
})

test_that("env.vars uses the redaction options", {
  withr::local_envvar(ZUFAX_TEST_TOKEN = "s3cret", ZUFAX_TEST_PLAIN = "visible")
  vars <- fact("env.vars")
  expect_equal(vars[["ZUFAX_TEST_TOKEN"]], "<redacted>")
  expect_equal(vars[["ZUFAX_TEST_PLAIN"]], "visible")
  withr::local_options(zufax.redact = "allowlist", zufax.redact_allowlist = "ZUFAX_TEST_PLAIN")
  expect_equal(fact("env.vars"), c(ZUFAX_TEST_PLAIN = "visible"))
  withr::local_options(zufax.redact = "bogus")
  df <- facts_df(facts("env"))
  expect_equal(df$status[df$fact == "env.vars"], "error")
})

test_that("proxies lose their credentials", {
  # Set lower case after clearing upper case: on Windows they are one variable.
  withr::local_envvar(HTTP_PROXY = NA, HTTPS_PROXY = NA, NO_PROXY = NA)
  withr::local_envvar(
    http_proxy = "http://user:pw@proxy:3128",
    https_proxy = NA,
    no_proxy = "localhost"
  )
  expect_equal(unname(fact("env.proxies")), c("http://<redacted>@proxy:3128", "localhost"))
  withr::local_envvar(http_proxy = NA, no_proxy = NA)
  df <- facts_df(facts("env"))
  expect_equal(df$status[df$fact == "env.proxies"], "not_applicable")
})

test_that("tmpdir facts describe tempdir()", {
  expect_equal(fact("disk.tmpdir.path"), tempdir())
  skip_on_os("windows")
  expect_gt(fact("disk.tmpdir.free"), 0)
})

test_that("mount_for() picks the longest matching mount point", {
  mounts <- data.frame(
    root = "/",
    mountpoint = c("/", "/tmp", "/tmpfoo"),
    fstype = c("overlay", "tmpfs", "ext4"),
    superopts = ""
  )
  expect_equal(mount_for(mounts, "/tmp/RtmpX")$fstype, "tmpfs")
  expect_equal(mount_for(mounts, "/tmpbar")$fstype, "overlay")
  expect_equal(mount_for(mounts, "/tmpfoo/x")$fstype, "ext4")
})

test_that("env.vars works when a value is not valid UTF-8", {
  withr::local_envvar(ZUFAX_TEST_LATIN1 = "caf\xe9", ZUFAX_TEST_PLAIN = "visible")
  df <- facts_df(facts("env", refresh = TRUE))
  expect_equal(df$status[df$fact == "env.vars"], "ok")
  vars <- df$value[df$fact == "env.vars"][[1]]
  expect_equal(vars[["ZUFAX_TEST_LATIN1"]], "caf<e9>")
  expect_equal(vars[["ZUFAX_TEST_PLAIN"]], "visible")
  df <- facts_df(facts("runtime", refresh = TRUE))
  expect_equal(df$status[df$fact == "runtime.threads.env"], "ok")
  expect_false(any(df$status == "error"))
})
