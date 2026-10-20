# Compares packages.python with pip in the environment named by VIRTUAL_ENV
# or CONDA_PREFIX. Run by .github/workflows/live.yaml.
library(zufax)
f <- facts(c("runtime", "packages"), refresh = TRUE)
print(f$runtime$python)
ours <- f[["packages.python"]]
ours <- ours[ours$source == "site-packages", ]
pip <- system2(f[["runtime.python.path"]], c("-m", "pip", "list", "--format=freeze"), stdout = TRUE)
pip <- pip[grepl("==", pip, fixed = TRUE)]
theirs <- data.frame(
  name = gsub("[-_.]+", "-", tolower(sub("==.*$", "", pip))),
  version = sub("^.*==", "", pip)
)
missing <- setdiff(paste(theirs$name, theirs$version), paste(ours$name, ours$version))
cat(nrow(theirs), "packages from pip,", nrow(ours), "from zufax\n")
if (length(missing)) {
  cat("pip lists packages zufax does not:", missing, sep = "\n  ")
  quit(status = 1)
}
expected <- Sys.getenv("EXPECT_ENV_TYPE")
if (nzchar(expected) && !identical(f[["runtime.python.env_type"]], expected)) {
  cat("env_type", f[["runtime.python.env_type"]], "want", expected, "\n")
  quit(status = 1)
}
cat("ok\n")
