# Get the value of a single fact

Get the value of a single fact

## Usage

``` r
fact(
  name,
  cloud = getOption("zufax.cloud", FALSE),
  refresh = FALSE,
  strict = getOption("zufax.strict", FALSE)
)
```

## Arguments

- name:

  A fact name, e.g. `"cpu.effective"`.

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

The fact's value, or `NA` if it could not be determined.

## See also

[`facts()`](https://pedrobtz.github.io/zufax/reference/facts.md) for a
lazy snapshot of many facts.

## Examples

``` r
fact("cpu.effective")
#> [1] 4
fact("os.family")
#> [1] "linux"
```
