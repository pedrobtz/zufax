# Collect facts about the host, container and runtime

`facts()` returns a snapshot that resolves facts lazily: a namespace
such as `cpu` is resolved the first time you access it, and each fact is
cached for the rest of the session.

## Usage

``` r
facts(
  namespaces = NULL,
  cloud = getOption("zufax.cloud", FALSE),
  refresh = FALSE,
  strict = getOption("zufax.strict", FALSE)
)
```

## Arguments

- namespaces:

  Namespaces to resolve immediately, e.g. `c("cpu", "memory")`. With
  `NULL`, nothing is resolved until accessed.

- cloud:

  Allow network requests to the cloud instance metadata service.
  Defaults to the `zufax.cloud` option, else `FALSE`.

- refresh:

  If `TRUE`, ignore cached values and resolve facts again.

- strict:

  If `TRUE`, re-raise errors from resolvers instead of recording them as
  `status = "error"`. Defaults to the `zufax.strict` option, else
  `FALSE`.

## Value

An object of class `zufax`:

- `x$cpu` or `x[["cpu"]]` returns a namespace as a nested list of
  values.

- `x[["cpu.host"]]` returns a group of facts the same way.

- `x[["cpu.effective"]]` returns the value of a single fact.

- `names(x)` lists the available namespaces.

- `as.list(x)` resolves and returns all default namespaces.

## Details

Facts are grouped in namespaces (`os`, `cpu`, `memory`, ...). The
`packages` namespace is opt-in: it is only resolved when you ask for it
by name, and is left out of
[`as.list()`](https://rdrr.io/r/base/list.html) and
[`facts_df()`](https://pedrobtz.github.io/zufax/reference/facts_df.md)
otherwise.

Resolution never fails: a fact that cannot be determined has value `NA`
and a `status` other than `"ok"`, visible with
[`facts_df()`](https://pedrobtz.github.io/zufax/reference/facts_df.md).

## See also

[`fact()`](https://pedrobtz.github.io/zufax/reference/fact.md) for a
single value,
[`facts_df()`](https://pedrobtz.github.io/zufax/reference/facts_df.md)
for values with their status and source.

## Examples

``` r
f <- facts()
names(f)
#>  [1] "os"             "cpu"            "memory"         "cgroup"        
#>  [5] "virtualization" "container"      "k8s"            "cloud"         
#>  [9] "runtime"        "env"            "disk"           "packages"      
```
