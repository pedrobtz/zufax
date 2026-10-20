test_that("dpkg packages come from the status file, installed only", {
  local_root(list(
    "var/lib/dpkg/status" = c(
      "Package: adduser",
      "Status: install ok installed",
      "Priority: important",
      "Architecture: all",
      "Version: 3.137ubuntu1",
      "Description: add and remove users",
      " adduser, addgroup: add a user or group",
      "",
      "Package: libc6",
      "Status: install ok installed",
      "Architecture: amd64",
      "Version: 2.39-0ubuntu8.3",
      "",
      "Package: oldpkg",
      "Status: deinstall ok config-files",
      "Architecture: amd64",
      "Version: 1.0"
    )
  ))
  withr::local_options(zufax.os = "linux")
  f <- facts("packages")
  expect_equal(
    f[["packages.system.installed"]],
    data.frame(
      name = c("adduser", "libc6"),
      version = c("3.137ubuntu1", "2.39-0ubuntu8.3"),
      arch = c("all", "amd64")
    )
  )
  expect_equal(f[["packages.system.manager"]], "dpkg")
  expect_equal(f[["packages.system.count"]], 2L)
})

test_that("apk packages come from the installed database", {
  local_root(list(
    "lib/apk/db/installed" = c(
      "C:Q1abc=",
      "P:musl",
      "V:1.2.5-r0",
      "A:x86_64",
      "",
      "C:Q1def=",
      "P:busybox",
      "V:1.36.1-r29",
      "A:x86_64",
      ""
    )
  ))
  withr::local_options(zufax.os = "linux")
  f <- facts("packages")
  expect_equal(f[["packages.system.installed"]]$name, c("musl", "busybox"))
  expect_equal(f[["packages.system.manager"]], "apk")
})

test_that("pacman packages come from local desc files", {
  local_root(list(
    "var/lib/pacman/local/ALPM_DB_VERSION" = "9",
    "var/lib/pacman/local/glibc-2.40-1/desc" = c(
      "%NAME%",
      "glibc",
      "",
      "%VERSION%",
      "2.40-1",
      "",
      "%ARCH%",
      "x86_64"
    ),
    "var/lib/pacman/local/r-4.4.1-1/desc" = c(
      "%NAME%",
      "r",
      "",
      "%VERSION%",
      "4.4.1-1",
      "",
      "%ARCH%",
      "x86_64"
    )
  ))
  withr::local_options(zufax.os = "linux")
  out <- fact("packages.system.installed")
  expect_equal(out$name, c("glibc", "r"))
  expect_equal(out$version, c("2.40-1", "4.4.1-1"))
})

test_that("rpm packages come from one rpm query", {
  local_root(list("usr/lib/sysimage/rpm/rpmdb.sqlite" = ""))
  withr::local_options(zufax.os = "linux", zufax.cmd_mock = function(cmd, args) {
    if (cmd != "rpm") {
      return(NULL)
    }
    c("bash\t5.2.26-3.fc40\tx86_64", "glibc\t2.39-22.fc40\tx86_64", "")
  })
  f <- facts("packages")
  expect_equal(f[["packages.system.installed"]]$name, c("bash", "glibc"))
  expect_equal(f[["packages.system.manager"]], "rpm")
})

test_that("Homebrew formulae and casks are listed from the Cellar", {
  local_root(list(
    "opt/homebrew/Cellar/r/4.4.1/INSTALL_RECEIPT.json" = "{}",
    "opt/homebrew/Cellar/openssl@3/3.3.2/x" = "",
    "opt/homebrew/Caskroom/rstudio/2024.09.0/x" = "",
    "opt/homebrew/Caskroom/rstudio/.metadata/x" = ""
  ))
  withr::local_options(zufax.os = "darwin")
  withr::local_envvar(HOMEBREW_PREFIX = NA)
  out <- fact("packages.system.installed")
  expect_equal(out$name, c("openssl@3", "r", "rstudio"))
  expect_equal(out$version, c("3.3.2", "4.4.1", "2024.09.0"))
  expect_equal(out$kind, c("formula", "formula", "cask"))
})

test_that("Windows packages come from the Uninstall registry keys", {
  withr::local_options(zufax.os = "windows")
  local_mocked_bindings(read_uninstall_registry = function() {
    list(
      list(
        DisplayName = "R for Windows 4.4.1",
        DisplayVersion = "4.4.1",
        Publisher = "R Core Team"
      ),
      list(DisplayName = "Hidden update", SystemComponent = 1L),
      list(DisplayVersion = "1.0"),
      list(DisplayName = "R for Windows 4.4.1", DisplayVersion = "4.4.1", Publisher = "R Core Team")
    )
  })
  f <- facts("packages", refresh = TRUE)
  expect_equal(
    f[["packages.system.installed"]],
    data.frame(name = "R for Windows 4.4.1", version = "4.4.1", publisher = "R Core Team")
  )
  expect_equal(f[["packages.system.manager"]], "windows")
})

test_that("no package database means not applicable", {
  local_root()
  withr::local_options(zufax.os = "linux")
  withr::local_envvar(HOMEBREW_PREFIX = NA)
  df <- facts_df(facts("packages"), "packages")
  expect_equal(
    df$status[startsWith(df$fact, "packages.system")],
    c("unavailable", "not_applicable", "unavailable")
  )
})

test_that("R packages are listed with their source", {
  out <- fact("packages.r")
  expect_s3_class(out, "data.frame")
  expect_named(out, c("name", "version", "libpath", "priority", "built", "source", "remote_sha"))
  expect_true("base" %in% out$name)
  expect_equal(out$priority[out$name == "base"], "base")
})

test_that("Python packages come from dist-info and egg-info names", {
  venv <- write_files(
    withr::local_tempdir(),
    list(
      "pyvenv.cfg" = "version = 3.12.4",
      "bin/python3" = "",
      "lib/python3.12/site-packages/numpy-2.1.1.dist-info/INSTALLER" = "uv",
      "lib/python3.12/site-packages/typing_extensions-4.12.2.dist-info/METADATA" = "",
      "lib/python3.12/site-packages/Old.Pkg-0.9-py3.12.egg-info/PKG-INFO" = "",
      "lib/python3.12/site-packages/numpy/__init__.py" = ""
    )
  )
  local_python_env(VIRTUAL_ENV = venv)
  withr::local_options(zufax.os = "linux")
  out <- fact("packages.python")
  out <- out[order(out$name), ]
  expect_equal(out$name, c("numpy", "old-pkg", "typing-extensions"))
  expect_equal(out$version, c("2.1.1", "0.9", "4.12.2"))
  expect_equal(out$installer, c("uv", NA, NA))
  expect_equal(unique(out$source), "site-packages")
})

test_that("conda environments add conda-meta packages", {
  conda <- write_files(
    withr::local_tempdir(),
    list(
      "conda-meta/python-3.11.9-h955ad1f_0_cpython.json" = "{}",
      "conda-meta/libblas-3.9.0-24_linux64_openblas.json" = "{}",
      "bin/python" = "",
      "lib/python3.11/site-packages/numpy-1.26.4.dist-info/INSTALLER" = "conda"
    )
  )
  local_python_env(CONDA_PREFIX = conda)
  withr::local_options(zufax.os = "linux")
  out <- fact("packages.python")
  expect_equal(out$name, c("numpy", "libblas", "python"))
  expect_equal(out$version, c("1.26.4", "3.9.0", "3.11.9"))
  expect_equal(out$source, c("site-packages", "conda", "conda"))
})

test_that("packages stay out of default output", {
  local_fixture("docker-v2-unlimited")
  f <- facts()
  expect_false(any(startsWith(facts_df(f)$fact, "packages.")))
  expect_false("packages" %in% names(as.list(f)))
})

test_that("parse_stanzas() handles missing fields and continuation lines", {
  lines <- c("A: 1", "B: x", " continued", "", "A: 2", "")
  expect_equal(parse_stanzas(lines, c("A", "B")), data.frame(A = c("1", "2"), B = c("x", NA)))
})

test_that("system and R inventories are not empty on CI", {
  skip_on_cran()
  skip_if_not(identical(Sys.getenv("GITHUB_ACTIONS"), "true"), "not on GitHub Actions")
  withr::local_options(zufax.root = NULL, zufax.os = NULL)
  f <- facts("packages", refresh = TRUE)
  expect_gt(f[["packages.system.count"]], 0)
  expect_gt(nrow(f[["packages.r"]]), 0)
})

test_that("distroless images use dpkg status.d files", {
  local_root(list(
    "var/lib/dpkg/status.d/libc6" = c(
      "Package: libc6",
      "Status: install ok installed",
      "Version: 2.36-9",
      "Architecture: amd64"
    ),
    "var/lib/dpkg/status.d/libc6.md5sums" = "abc  /lib/x",
    "var/lib/dpkg/status.d/tzdata" = c(
      "Package: tzdata",
      "Status: install ok installed",
      "Version: 2024a-0",
      "Architecture: all"
    )
  ))
  withr::local_options(zufax.os = "linux")
  expect_equal(fact("packages.system.installed")$name, c("libc6", "tzdata"))
})
