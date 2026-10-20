test_that("resolver() validates its inputs", {
  expect_snapshot(resolver("CPU", \(ctx) 1), error = TRUE)
  expect_snapshot(resolver("cpu", \(ctx) 1), error = TRUE)
  expect_snapshot(resolver("cpu.x", 1), error = TRUE)
  expect_snapshot(resolver("cpu.x", \(ctx) 1, confine = list("linux")), error = TRUE)
  expect_snapshot(resolver("cpu.x", \(ctx) 1, weight = "high"), error = TRUE)
  expect_s3_class(resolver("cpu.host.logical", \(ctx) 1), "zufax_resolver")
})

test_that("register() keeps resolvers ordered by weight and replaces by id", {
  local_registry(
    resolver("toy.a", \(ctx) "low", weight = 10, id = "low"),
    resolver("toy.a", \(ctx) "high", weight = 50, id = "high"),
    resolver("toy.a", \(ctx) "high2", weight = 60, id = "high")
  )
  ids <- vapply(.zufax$resolvers[["toy.a"]], `[[`, character(1), "id")
  expect_equal(ids, c("high", "low"))
})

test_that("register() rejects a fact that is also a group", {
  local_registry(resolver("toy.a.b", \(ctx) 1))
  expect_snapshot(register(resolver("toy.a", \(ctx) 1)), error = TRUE)
  expect_snapshot(register(resolver("toy.a.b.c", \(ctx) 1)), error = TRUE)
})

test_that("known_namespaces() follows the canonical order", {
  local_registry(
    resolver("zeta.a", \(ctx) 1),
    resolver("memory.a", \(ctx) 1),
    resolver("os.a", \(ctx) 1),
    resolver("packages.a", \(ctx) 1)
  )
  expect_equal(known_namespaces(), c("os", "memory", "packages", "zeta"))
  expect_equal(default_namespaces(), c("os", "memory", "zeta"))
})

test_that("every fact is documented in fact_docs", {
  expect_setequal(fact_docs$fact, known_facts())
  expect_false(anyNA(fact_docs$type))
  expect_true(all(nzchar(fact_docs$description)))
})

test_that("fact_platforms() summarizes resolver confinement", {
  expect_equal(fact_platforms("os.family"), "all")
  expect_equal(fact_platforms("cgroup.version"), "Linux")
  expect_equal(fact_platforms("cpu.load"), "Linux, macOS")
  expect_equal(fact_platforms("virtualization.type"), "all")
})
