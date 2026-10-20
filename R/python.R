# Python discovery never starts Python inside R: it reads environment
# variables and files, and at most runs the interpreter once in a separate
# process (memoized per interpreter for the session).

python_bin <- function(prefix, windows) {
  if (windows) {
    return(file.path(prefix, c("python.exe", "Scripts/python.exe")))
  }
  file.path(prefix, "bin", c("python3", "python"))
}

sys_which <- function(name) Sys.which(name)

# Windows interpreters not on PATH: the py launcher's default, else the newest
# per-user install under %LOCALAPPDATA%\\Programs\\Python.
windows_python <- function(ctx) {
  py <- sys_which("py")
  if (nzchar(py)) {
    out <- ctx$cmd(unname(py), "-0p", timeout = 5)
    lines <- if (!is.null(out) && out$status == 0L) out$stdout else character()
    pick <- c(grep("\\*", lines, value = TRUE), lines)
    path <- regmatches(pick, regexpr("[A-Za-z]:\\\\.*\\.exe", pick))
    if (length(path)) {
      return(list(path = trimws(path[1]), prefix = NA_character_, how = "py launcher"))
    }
  }
  local <- ctx$env("LOCALAPPDATA")
  if (is.null(local)) {
    return(NULL)
  }
  dirs <- grep(
    "^Python3[0-9]+$",
    ctx$list_dir(file.path(local, "Programs", "Python")),
    value = TRUE
  )
  if (!length(dirs)) {
    return(NULL)
  }
  newest <- dirs[order(as.integer(sub("^Python3", "", dirs)), decreasing = TRUE)][1]
  prefix <- file.path(local, "Programs", "Python", newest)
  list(path = file.path(prefix, "python.exe"), prefix = NA_character_, how = "LOCALAPPDATA")
}

# The interpreter to describe and how it was found.
python_interpreter <- function(ctx) {
  ctx$shared("python_interpreter", function(ctx) {
    windows <- ctx$os == "windows"
    from_prefix <- function(prefix, how) {
      bins <- python_bin(prefix, windows)
      bin <- bins[vapply(bins, ctx$exists, logical(1))][1]
      list(path = if (is.na(bin)) bins[1] else bin, prefix = prefix, how = how)
    }
    reticulate <- ctx$env("RETICULATE_PYTHON")
    if (!is.null(reticulate)) {
      # An environment root holds pyvenv.cfg or conda-meta, one level up from
      # bin/ or Scripts/, or right next to python.exe for conda on Windows.
      is_env <- \(dir) {
        ctx$exists(file.path(dir, "pyvenv.cfg")) || ctx$exists(file.path(dir, "conda-meta"))
      }
      prefix <- Find(is_env, c(dirname(dirname(reticulate)), dirname(reticulate))) %||%
        NA_character_
      return(list(path = reticulate, prefix = prefix, how = "RETICULATE_PYTHON"))
    }
    venv <- ctx$env("VIRTUAL_ENV")
    if (!is.null(venv)) {
      return(from_prefix(venv, "VIRTUAL_ENV"))
    }
    conda <- ctx$env("CONDA_PREFIX")
    if (!is.null(conda)) {
      return(from_prefix(conda, "CONDA_PREFIX"))
    }
    for (name in c("python3", "python")) {
      path <- sys_which(name)
      # The Windows Store "python" alias opens the Store instead of running.
      if (nzchar(path) && !grepl("WindowsApps", path, fixed = TRUE)) {
        ctx$note(paste0("Sys.which(\"", name, "\")"))
        return(list(path = unname(path), prefix = NA_character_, how = "PATH"))
      }
    }
    if (windows) {
      return(windows_python(ctx))
    }
    NULL
  })
}

# pyvenv.cfg "key = value" lines.
pyvenv_cfg <- function(ctx, prefix) {
  if (is.na(prefix)) {
    return(NULL)
  }
  ctx$read_kv(file.path(prefix, "pyvenv.cfg"), sep = "=")
}

conda_python_version <- function(ctx, prefix) {
  if (is.na(prefix)) {
    return(NULL)
  }
  files <- ctx$list_dir(file.path(prefix, "conda-meta"))
  hit <- regmatches(files, regexpr("^python-[0-9]+\\.[0-9]+\\.[0-9]+", files))
  if (length(hit)) sub("^python-", "", hit[1]) else NULL
}

python_probe_script <- paste0(
  "import sys,site;",
  "print('version='+'.'.join(map(str,sys.version_info[:3])));",
  "print('implementation='+sys.implementation.name);",
  "print('prefix='+sys.prefix);",
  "print('base_prefix='+getattr(sys,'base_prefix',sys.prefix));",
  "[print('site='+p) for p in getattr(site,'getsitepackages',lambda:[])()];",
  "print('usersite='+str(site.getusersitepackages()))"
)

# Run the interpreter once per session, memoized per path. Failures are
# memoized too (a broken or hung interpreter costs its timeout once) and are
# retried only with refresh = TRUE, at most once per facts() call.
python_probe <- function(ctx, path) {
  ctx$shared(paste0("python_probe:", path), function(ctx) {
    cached <- .zufax$python_probe[[path]]
    if (!is.null(cached) && (!isTRUE(cached$failed) || !ctx$refresh)) {
      ctx$note(paste(path, "-c <probe>"))
      return(if (isTRUE(cached$failed)) NULL else cached)
    }
    quote <- if (.Platform$OS.type == "windows") "cmd" else "sh"
    out <- ctx$cmd(path, c("-c", shQuote(python_probe_script, type = quote)), timeout = 5)
    if (is.null(out) || out$status != 0L || !length(out$stdout)) {
      .zufax$python_probe[[path]] <- list(failed = TRUE)
      return(NULL)
    }
    kv <- parse_kv(out$stdout, sep = "=")
    probe <- list(
      version = unname(kv["version"]),
      implementation = unname(kv["implementation"]),
      prefix = unname(kv["prefix"]),
      base_prefix = unname(kv["base_prefix"]),
      site = unname(kv[names(kv) == "site"]),
      usersite = unname(kv["usersite"])
    )
    .zufax$python_probe[[path]] <- probe
    probe
  })
}

python_env_type <- function(ctx, interp) {
  cfg <- pyvenv_cfg(ctx, interp$prefix)
  if (!is.null(cfg)) {
    return(if ("uv" %in% names(cfg)) "uv" else "venv")
  }
  if (!is.na(interp$prefix) && ctx$exists(file.path(interp$prefix, "conda-meta"))) {
    return("conda")
  }
  "system"
}

register_python_facts <- function() {
  py <- function(name, fun, cache = FALSE) {
    register(resolver(paste0("runtime.python.", name), cache = cache, function(ctx) {
      interp <- python_interpreter(ctx)
      if (is.null(interp)) {
        not_applicable("No Python interpreter found.")
      }
      fun(ctx, interp)
    }))
  }

  py("path", \(ctx, interp) interp$path)

  py("env_type", python_env_type)

  py("env_path", function(ctx, interp) {
    if (python_env_type(ctx, interp) == "system") {
      not_applicable("Not a virtual or conda environment.")
    }
    interp$prefix
  })

  py("version", function(ctx, interp) {
    cfg <- pyvenv_cfg(ctx, interp$prefix)
    from_cfg <- if (!is.null(cfg)) {
      cfg[c("version_info", "version")][!is.na(cfg[c("version_info", "version")])]
    }
    version <- if (length(from_cfg)) from_cfg[[1]] else conda_python_version(ctx, interp$prefix)
    version <- version %||% python_probe(ctx, interp$path)$version
    if (is.null(version) || is.na(version)) {
      NULL
    } else {
      sub("^([0-9]+\\.[0-9]+\\.[0-9]+).*$", "\\1", version)
    }
  })

  py("implementation", \(ctx, interp) python_probe(ctx, interp$path)$implementation)

  py("prefix", function(ctx, interp) {
    if (!is.na(interp$prefix)) interp$prefix else python_probe(ctx, interp$path)$prefix
  })

  py("site_packages", function(ctx, interp) {
    windows <- ctx$os == "windows"
    if (!is.na(interp$prefix)) {
      if (windows) {
        return(file.path(interp$prefix, "Lib", "site-packages"))
      }
      lib <- file.path(interp$prefix, "lib")
      versions <- grep("^python[0-9.]+$", ctx$list_dir(lib), value = TRUE)
      dirs <- file.path(lib, versions, "site-packages")
      dirs <- dirs[vapply(dirs, ctx$exists, logical(1))]
      if (length(dirs)) {
        return(dirs)
      }
    }
    probe <- python_probe(ctx, interp$path)
    if (is.null(probe)) NULL else c(probe$site, probe$usersite)
  })

  register(resolver("runtime.python.reticulate", cache = FALSE, function(ctx) {
    if (!"reticulate" %in% loadedNamespaces()) {
      not_applicable("reticulate is not loaded.")
    }
    ns <- asNamespace("reticulate")
    if (!isTRUE(get("py_available", envir = ns)(initialize = FALSE))) {
      not_applicable("reticulate has not initialized Python.")
    }
    r_note(ctx, "reticulate::py_config()")
    get("py_config", envir = ns)()$python
  }))
}
