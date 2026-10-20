substrate <- data.frame(
  fixture = c(
    "linux-baremetal",
    "linux-vm-host",
    "azure-vm",
    "aws-ec2",
    "gcp-vm",
    "wsl2",
    "docker-v2-unlimited",
    "docker-v1-cpus1.5-mem512m",
    "k8s-v2-limits",
    "aks-pod-downward-api",
    "lxcfs",
    "hybrid"
  ),
  type = c("physical", rep("vm", 11)),
  hypervisor = c(
    NA,
    "apple",
    "hyperv",
    "aws-nitro",
    "kvm",
    "unknown",
    "apple",
    "unknown",
    "unknown",
    "hyperv",
    "unknown",
    "unknown"
  ),
  container = c(rep(FALSE, 6), TRUE, TRUE, TRUE, TRUE, TRUE, FALSE),
  runtime = c(rep(NA, 6), "podman", "docker", "containerd", "containerd", "lxc", NA),
  k8s = c(rep(FALSE, 8), TRUE, TRUE, FALSE, FALSE),
  cloud = c(NA, NA, "azure", "aws", "gcp", NA, NA, NA, NA, "azure", NA, NA)
)

for (i in seq_len(nrow(substrate))) {
  want <- substrate[i, ]
  test_that(paste("substrate:", want$fixture), {
    local_fixture(want$fixture)
    withr::local_envvar(container = NA)
    local_azure_env()
    f <- facts(refresh = TRUE)
    expect_equal(f[["virtualization.type"]], want$type)
    expect_equal(as.character(f[["virtualization.hypervisor"]]), want$hypervisor)
    expect_equal(f[["container.detected"]], want$container)
    expect_equal(as.character(f[["container.runtime"]]), want$runtime)
    expect_equal(f[["k8s.detected"]], want$k8s)
    expect_equal(as.character(f[["cloud.provider"]]), want$cloud)
  })
}

test_that("os facts come from os-release and the kernel", {
  local_fixture("aws-ec2")
  f <- facts("os")
  expect_equal(f$os$name, "Amazon Linux")
  expect_equal(f$os$id, "amzn")
  expect_equal(f$os$id_like, "fedora")
  expect_equal(f$os$release[c("full", "major")], list(full = "2023", major = "2023"))
  expect_equal(f$os$kernel$release, "6.1.109-118.189.amzn2023.x86_64")
  expect_equal(f$os$hostname, "ip-10-0-1-23.ec2.internal")
  expect_equal(f$os$family, "linux")
  expect_equal(f$os$boot_time, as.POSIXct(1790000000, tz = "UTC"))
  expect_equal(f$os$uptime, 86400.5)
})

test_that("parse_os_release() removes quotes and comments", {
  lines <- c("# comment", 'NAME="Fedora Linux"', "ID=fedora", "VERSION_ID='40'", "")
  expect_equal(
    parse_os_release(lines),
    c(NAME = "Fedora Linux", ID = "fedora", VERSION_ID = "40")
  )
})

test_that("WSL versions are told apart by the kernel release", {
  local_root(list("proc/sys/kernel/osrelease" = "4.4.0-19041-Microsoft"))
  withr::local_options(zufax.os = "linux")
  expect_equal(fact("virtualization.wsl"), 1L)
  local_fixture("wsl2")
  expect_equal(fact("virtualization.wsl"), 2L)
  local_fixture("linux-baremetal")
  df <- facts_df(facts("virtualization"))
  expect_equal(df$status[df$fact == "virtualization.wsl"], "not_applicable")
})

test_that("container ids come from cgroup paths and mounts", {
  id_of <- function(fixture) {
    local_fixture(fixture)
    fact("container.id")
  }
  expect_match(id_of("docker-v1-cpus1.5-mem512m"), "^3f1b2c4d5e6f[0-9a-f]{52}$")
  expect_match(id_of("docker-v2-cpus1.5-mem512m"), "^e3c84bc3d002[0-9a-f]{52}$")
  expect_match(id_of("docker-v2-cgroupns-host"), "^089c12a9e577[0-9a-f]{52}$")
})

test_that("container env vars are a detection signal", {
  local_fixture("linux-baremetal")
  withr::local_envvar(container = "systemd-nspawn", KUBERNETES_SERVICE_HOST = NA)
  expect_true(fact("container.detected"))
  expect_equal(fact("container.runtime"), "systemd-nspawn")
})

test_that("the Downward API gives pod details", {
  local_fixture("aks-pod-downward-api")
  withr::local_envvar(
    KUBERNETES_SERVICE_HOST = "10.0.0.1",
    NODE_NAME = "aks-nodepool1-12345678-vmss000002",
    POD_IP = NA,
    POD_NAME = NA,
    POD_UID = NA,
    CPU_LIMIT = NA,
    MEMORY_LIMIT = NA,
    CPU_REQUEST = NA,
    MEMORY_REQUEST = NA
  )
  f <- facts("k8s")
  expect_equal(f$k8s$namespace, "analytics")
  expect_equal(f$k8s$pod$name, "spark-driver-7d9f-xk2lp")
  expect_equal(f$k8s$pod$uid, "5d2c7a8e-1f3b-4c6d-9e0a-7b8c9d0e1f2a")
  expect_equal(f$k8s$node$name, "aks-nodepool1-12345678-vmss000002")
  expect_equal(f$k8s$pod$labels, c(app = "spark-driver", `pod-template-hash` = "7d9f"))
  expect_equal(f$k8s$pod$annotations[["team"]], "data")
  expect_equal(f$k8s$resources$limits, c(cpu = 1.5, memory = 4 * 1024^3))
  df <- facts_df(f, "k8s")
  expect_equal(df$status[df$fact == "k8s.pod.ip"], "unavailable")
  expect_match(df$message[df$fact == "k8s.pod.ip"], "POD_IP")
})

test_that("Downward API env names can be remapped", {
  local_fixture("aks-pod-downward-api")
  withr::local_envvar(
    MY_POD = "custom-name",
    MY_CPU = "2",
    MEMORY_LIMIT = "1073741824",
    CPU_LIMIT = NA
  )
  withr::local_options(zufax.k8s.env = c(pod.name = "MY_POD", cpu.limit = "MY_CPU"))
  expect_equal(fact("k8s.pod.name"), "custom-name")
  expect_equal(fact("k8s.resources.limits"), c(cpu = 2, memory = 1024^3))
})

test_that("a missing Downward API volume is reported", {
  local_fixture("aks-pod-downward-api")
  withr::local_options(zufax.k8s.podinfo = "/nowhere")
  df <- facts_df(facts("k8s"))
  expect_equal(df$status[df$fact == "k8s.pod.labels"], "unavailable")
  expect_match(df$message[df$fact == "k8s.pod.labels"], "/nowhere/labels")
})

test_that("KUBERNETES_SERVICE_HOST alone means Kubernetes", {
  local_fixture("docker-v2-unlimited")
  withr::local_envvar(KUBERNETES_SERVICE_HOST = "10.0.0.1")
  expect_true(fact("k8s.detected"))
  expect_true(fact("container.detected"))
})

test_that("the timezone comes from TZ, /etc/localtime or /etc/timezone", {
  skip_on_os("windows")
  root <- local_root(list("usr/share/zoneinfo/America/Chicago" = "x"))
  withr::local_options(zufax.os = "linux")
  withr::local_envvar(TZ = NA)
  expect_equal(fact("os.timezone"), "UTC")
  dir.create(file.path(root, "etc"))
  writeLines("Europe/Zurich", file.path(root, "etc/timezone"))
  withr::local_envvar(TZ = ":America/New_York")
  expect_equal(fact("os.timezone"), "America/New_York")
  withr::local_envvar(TZ = NA)
  expect_equal(fact("os.timezone"), "Europe/Zurich")
  file.symlink(
    file.path(root, "usr/share/zoneinfo/America/Chicago"),
    file.path(root, "etc/localtime")
  )
  expect_equal(fact("os.timezone"), "America/Chicago")
})

test_that("Xen-based EC2 instances are recognized from the BIOS version", {
  local_root(list(
    "sys/class/dmi/id/sys_vendor" = "Xen",
    "sys/class/dmi/id/product_name" = "HVM domU",
    "sys/class/dmi/id/bios_vendor" = "Xen",
    "sys/class/dmi/id/bios_version" = "4.2.amazon"
  ))
  withr::local_options(zufax.os = "linux")
  local_azure_env()
  f <- facts(c("virtualization", "cloud"), refresh = TRUE)
  expect_equal(f[["virtualization.hypervisor"]], "xen")
  expect_equal(f[["cloud.provider"]], "aws")
})
