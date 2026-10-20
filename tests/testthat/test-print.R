test_that("print() summarizes substrate and resources", {
  withr::local_options(zufax.skip = "runtime")
  withr::local_envvar(container = NA)
  local_azure_env()
  for (name in c(
    "k8s-v2-limits",
    "aks-pod-downward-api",
    "linux-baremetal",
    "azure-vm",
    "wsl2",
    "docker-v1-cpus1.5-mem512m"
  )) {
    local_fixture(name)
    expect_snapshot(print(facts(refresh = TRUE)), variant = NULL)
  }
})

test_that("print() shows R and Python when available", {
  local_python_env()
  local_mocked_bindings(sys_which = function(name) "")
  out <- format(facts(refresh = TRUE))
  expect_match(
    out[startsWith(out, "runtime")],
    paste("R", paste(R.version$major, R.version$minor, sep = ".")),
    fixed = TRUE
  )
})

test_that("print() warns about OOM kills and a tmpfs tempdir() in containers", {
  withr::local_options(zufax.skip = "runtime")
  local_azure_env()
  local_fixture("aks-pod-downward-api")
  local_mocked_bindings(mount_for = function(mounts, path) data.frame(fstype = "tmpfs"))
  out <- format(facts(refresh = TRUE))
  expect_match(out, "tempdir\\(\\) is on tmpfs", all = FALSE)
  expect_match(out, "2 process\\(es\\) in this container were killed", all = FALSE)
})

test_that("print() notes OOM kill counts beyond the integer range", {
  withr::local_options(zufax.skip = "runtime")
  local_azure_env()
  root <- local_fixture_copy("docker-v2-cpus1.5-mem512m")
  writeLines(c("low 0", "oom_kill 3000000000"), file.path(root, "sys/fs/cgroup/memory.events"))
  out <- format(facts(refresh = TRUE))
  expect_match(out, "3000000000 process(es) in this container", all = FALSE, fixed = TRUE)
})
