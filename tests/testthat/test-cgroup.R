test_that("parse_mountinfo() reads root, mount point and fs type", {
  lines <- c(
    "30 23 0:26 / /sys/fs/cgroup rw,nosuid shared:4 - cgroup2 cgroup2 rw,nsdelegate",
    "35 30 0:31 /docker/abc /sys/fs/cgroup/cpu,cpuacct ro master:1 - cgroup cgroup rw,cpu,cpuacct",
    "40 1 8:1 / /mnt/with\\040space rw - ext4 /dev/sda1 rw",
    "garbage"
  )
  mi <- parse_mountinfo(lines)
  expect_equal(mi$root, c("/", "/docker/abc", "/"))
  expect_equal(mi$mountpoint, c("/sys/fs/cgroup", "/sys/fs/cgroup/cpu,cpuacct", "/mnt/with space"))
  expect_equal(mi$fstype, c("cgroup2", "cgroup", "ext4"))
  expect_equal(mi$superopts[2], "rw,cpu,cpuacct")
  expect_equal(nrow(parse_mountinfo(NULL)), 0)
})

test_that("parse_proc_cgroup() splits id, controllers and path", {
  entries <- parse_proc_cgroup(c("0::/", "4:cpu,cpuacct:/a:b", "1:name=systemd:/x", "bad"))
  expect_length(entries, 3)
  expect_equal(entries[[1]], list(id = "0", controllers = character(), path = "/"))
  expect_equal(entries[[2]]$controllers, c("cpu", "cpuacct"))
  expect_equal(entries[[2]]$path, "/a:b")
})

test_that("cgroup_location() maps cgroup paths below the mount", {
  root <- local_root(list(
    "sys/fs/cgroup/kubepods/pod1/c1/memory.max" = "max",
    "sys/fs/cgroup/c1/memory.max" = "max"
  ))
  ctx <- new_ctx(new_state())
  loc <- function(...) cgroup_location(ctx, ...)$dir
  expect_equal(loc("/sys/fs/cgroup", "/", "/"), "/sys/fs/cgroup")
  expect_equal(loc("/sys/fs/cgroup", "/", "/kubepods/pod1/c1"), "/sys/fs/cgroup/kubepods/pod1/c1")
  expect_equal(loc("/sys/fs/cgroup", "/", "/not/visible"), "/sys/fs/cgroup")
  expect_equal(loc("/sys/fs/cgroup", "/kubepods/pod1", "/kubepods/pod1/c1"), "/sys/fs/cgroup/c1")
  expect_equal(loc("/sys/fs/cgroup", "/docker/abc", "/docker/abc"), "/sys/fs/cgroup")
})

test_that("cgroup_ancestors() walks up to the mount point", {
  loc <- list(dir = "/sys/fs/cgroup/a/b", mount = "/sys/fs/cgroup")
  expect_equal(cgroup_ancestors(loc), c("/sys/fs/cgroup/a/b", "/sys/fs/cgroup/a", "/sys/fs/cgroup"))
  loc <- list(dir = "/sys/fs/cgroup", mount = "/sys/fs/cgroup/")
  expect_equal(cgroup_ancestors(loc), "/sys/fs/cgroup")
})

test_that("v1_limit() treats huge values as unlimited", {
  expect_equal(v1_limit("9223372036854771712"), Inf)
  expect_equal(v1_limit("536870912"), 536870912)
})

test_that("cgroup facts are unavailable without cgroup files", {
  local_root(list("proc/meminfo" = "MemTotal: 1024 kB"))
  withr::local_options(zufax.os = "linux")
  df <- facts_df(facts(refresh = TRUE))
  expect_equal(unique(df$status[startsWith(df$fact, "cgroup.")]), "unavailable")
  expect_equal(fact("memory.effective.limit"), 1024^2)
})
