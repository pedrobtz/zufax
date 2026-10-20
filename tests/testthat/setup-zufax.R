# Tests never start Python (design section 10): the Python facts are skipped unless a
# test describes a fake interpreter with local_python_env().
withr::local_options(zufax.skip = "runtime.python", .local_envir = teardown_env())
