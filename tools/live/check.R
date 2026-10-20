# Live checks run inside containers and pods by .github/workflows/live.yaml.
# Expectations come from environment variables; unset ones are not checked.
library(zufax)

failures <- 0
check <- function(ok, what) {
  ok <- isTRUE(ok)
  cat(if (ok) "ok  " else "FAIL", what, "\n")
  if (!ok) failures <<- failures + 1
}
expect <- function(name) {
  value <- Sys.getenv(name)
  if (nzchar(value)) value else NULL
}

print(facts())
df <- facts_df(facts(refresh = TRUE))
errors <- df$fact[df$status == "error"]
check(!length(errors), paste("no fact errors", paste(errors, collapse = ", ")))
check(isTRUE(fact("container.detected")), "container detected")
check(identical(fact("cgroup.version"), "2"), "cgroup v2")

if (!is.null(cores <- expect("EXPECT_CORES"))) {
  check(effective_cores() == as.integer(cores), sprintf("effective_cores() = %s (want %s)", effective_cores(), cores))
}
if (!is.null(memory <- expect("EXPECT_MEMORY"))) {
  check(effective_memory() == as.numeric(memory), sprintf("effective_memory() = %s (want %s)", effective_memory(), memory))
}
if (!is.null(manager <- expect("EXPECT_MANAGER"))) {
  f <- facts("packages")
  check(identical(f[["packages.system.manager"]], manager), sprintf("package manager %s (want %s)", f[["packages.system.manager"]], manager))
  check(f[["packages.system.count"]] > 0, sprintf("%s system packages", f[["packages.system.count"]]))
}
if (requireNamespace("parallelly", quietly = TRUE)) {
  theirs <- parallelly::availableCores(methods = c("system", "cgroups.cpuset", "cgroups2.cpu.max", "nproc"))
  check(abs(fact("cpu.effective_exact") - theirs) < 1, sprintf("parallelly::availableCores() = %s, cpu.effective_exact = %s", theirs, fact("cpu.effective_exact")))
}

if (nzchar(Sys.getenv("EXPECT_THROTTLE"))) {
  usage()
  start <- proc.time()[["elapsed"]]
  x <- 0
  while (proc.time()[["elapsed"]] - start < 3) x <- x + 1
  u <- usage()
  print(u)
  check(u[["cpu_cgroup"]] > 0.3 && u[["cpu_cgroup"]] < 0.7, sprintf("busy loop under --cpus=0.5 uses %.2f cores", u[["cpu_cgroup"]]))
  check(u[["cpu_throttled"]] > 0.2, sprintf("throttled in %.0f%% of periods", 100 * u[["cpu_throttled"]]))
}

# Timings, for the record.
times <- vapply(1:5, \(i) system.time(facts_df(facts(refresh = TRUE)))[["elapsed"]], numeric(1))
cat(sprintf("default snapshot: %.1f ms (median of 5)\n", 1000 * stats::median(times)))
tick <- 0
assignInNamespace("usage_now", function() {
  tick <<- tick + 1
  c(cpu = tick / 2, elapsed = tick)
}, "zufax")
usage()
n <- 5000
elapsed <- system.time(for (i in seq_len(n)) usage())[["elapsed"]]
cat(sprintf("usage(): %.0f us per call\n", 1e6 * elapsed / n))

if (failures) quit(status = 1)
