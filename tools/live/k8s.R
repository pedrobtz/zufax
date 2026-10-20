# Runs inside the kind pod defined in tools/live/pod.yaml.
library(zufax)

failures <- 0
check <- function(ok, what) {
  ok <- isTRUE(ok)
  cat(if (ok) "ok  " else "FAIL", what, "\n")
  if (!ok) failures <<- failures + 1
}

print(facts())
f <- facts(refresh = TRUE)
df <- facts_df(f)
errors <- df$fact[df$status == "error"]
check(!length(errors), paste("no fact errors", paste(errors, collapse = ", ")))
check(isTRUE(f[["k8s.detected"]]), "Kubernetes detected")
check(identical(f[["k8s.namespace"]], "default"), paste("namespace", f[["k8s.namespace"]]))
check(identical(f[["k8s.pod.name"]], Sys.getenv("POD_NAME")), paste("pod name", f[["k8s.pod.name"]]))
check(nzchar(f[["k8s.node.name"]] %||% ""), paste("node name", f[["k8s.node.name"]]))
check(identical(f[["k8s.pod.uid"]], Sys.getenv("POD_UID")), paste("pod uid", f[["k8s.pod.uid"]]))
check(identical(unname(f[["k8s.pod.labels"]]["app"]), "zufax-live"), "label app=zufax-live")
check(identical(f[["container.runtime"]], "containerd"), paste("runtime", f[["container.runtime"]]))
check(effective_cores() == 2L, paste("effective_cores()", effective_cores()))
check(effective_memory() == 512 * 1024^2, paste("effective_memory()", effective_memory()))
check(identical(unname(f[["k8s.resources.limits"]]["memory"]), 512 * 1024^2), "memory limit from the Downward API")
if (failures) quit(status = 1)
