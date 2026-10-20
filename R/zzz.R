.onLoad <- function(libname, pkgname) {
  .zufax$sysname <- tolower(Sys.info()[["sysname"]])
  register_builtins()
}

# Each namespace adds its resolvers here as it is implemented.
register_builtins <- function() {
  registry_reset()
  register_os_facts()
  register_cgroup_facts()
  register_cpu_facts()
  register_memory_facts()
  register_virtualization_facts()
  register_container_facts()
  register_k8s_facts()
  register_macos_facts()
  register_windows_facts()
  register_cloud_facts()
  register_azure_facts()
  register_runtime_facts()
  register_python_facts()
  register_env_facts()
  register_disk_facts()
  register_packages_facts()
  invisible()
}
