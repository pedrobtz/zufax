platforms <- list(
  list(
    env = list(FUNCTIONS_WORKER_RUNTIME = "python", WEBSITE_SITE_NAME = "fn-etl"),
    platform = "functions"
  ),
  list(
    env = list(
      WEBSITE_SITE_NAME = "app-api",
      WEBSITE_INSTANCE_ID = "abc123",
      WEBSITE_SKU = "PremiumV3"
    ),
    platform = "app-service"
  ),
  list(
    env = list(CONTAINER_APP_NAME = "worker", CONTAINER_APP_REVISION = "worker--r7"),
    platform = "container-apps"
  ),
  list(env = list(AZ_BATCH_NODE_ID = "tvmps_1", AZ_BATCH_POOL_ID = "pool-r"), platform = "batch"),
  list(
    env = list(AZUREML_RUN_ID = "run_42", AZUREML_EXPERIMENT_NAME = "churn"),
    platform = "azureml"
  )
)

for (p in platforms) {
  test_that(paste("Azure platform from env:", p$platform), {
    local_fixture("linux-baremetal")
    do.call(local_azure_env, p$env)
    f <- facts(refresh = TRUE)
    expect_equal(f[["cloud.provider"]], "azure")
    expect_equal(f[["cloud.azure.platform"]], p$platform)
    service <- f[["cloud.azure.service"]]
    expect_true(all(unlist(p$env) %in% service))
  })
}

test_that("App Service identifiers are named", {
  local_fixture("linux-baremetal")
  local_azure_env(WEBSITE_SITE_NAME = "app-api", WEBSITE_INSTANCE_ID = "abc123")
  expect_equal(fact("cloud.azure.service"), c(site = "app-api", instance = "abc123"))
})

test_that("Azure VMs, AKS and Databricks are told apart", {
  local_azure_env()
  local_fixture("azure-vm")
  expect_equal(fact("cloud.azure.platform"), "vm")
  local_fixture("aks-pod-downward-api")
  expect_equal(fact("cloud.azure.platform"), "aks")
  local_fixture("azure-vm")
  local_azure_env(DATABRICKS_RUNTIME_VERSION = "15.4")
  expect_equal(fact("cloud.azure.platform"), "databricks")
  expect_equal(fact("cloud.azure.service"), c(runtime = "15.4"))
})

test_that("Databricks outside Azure is not Azure", {
  local_fixture("aws-ec2")
  local_azure_env(DATABRICKS_RUNTIME_VERSION = "15.4")
  expect_equal(fact("cloud.provider"), "aws")
  df <- facts_df(facts("cloud"), "cloud")
  expect_equal(df$status[df$fact == "cloud.azure.platform"], "not_applicable")
})

test_that("instance metadata is read from IMDS with cloud = TRUE", {
  skip_if_not_installed("jsonlite")
  local_fixture("azure-vm")
  local_azure_env()
  calls <- local_imds(imds_body())
  f <- facts(cloud = TRUE, refresh = TRUE)
  expect_equal(f[["cloud.region"]], "westeurope")
  expect_equal(f[["cloud.zone"]], "2")
  expect_equal(f[["cloud.instance.type"]], "Standard_D4s_v5")
  expect_equal(f[["cloud.instance.id"]], "11111111-2222-3333-4444-555555555555")
  expect_equal(f[["cloud.azure.resource_group"]], "rg-analytics")
  expect_equal(f[["cloud.azure.priority"]], "Spot")
  expect_equal(
    f[["cloud.azure.image"]],
    c(publisher = "canonical", offer = "ubuntu-24_04-lts", sku = "server", version = "latest")
  )
  expect_equal(f[["cloud.azure.tags"]], c(team = "data", `deploy-token` = "<redacted>"))
  expect_equal(f[["cloud.azure.network.private_ip"]], "10.0.0.4")
  df <- facts_df(f, "cloud")
  expect_equal(df$status[df$fact == "cloud.azure.network.public_ip"], "not_applicable")
  expect_equal(df$status[df$fact == "cloud.azure.vmss_name"], "not_applicable")
  expect_equal(unique(df$source[df$fact == "cloud.region"]), imds_url)
  facts_df(facts(cloud = TRUE), "cloud")
  expect_equal(calls(), 1)
  facts_df(facts(cloud = TRUE, refresh = TRUE), "cloud")
  expect_equal(calls(), 2)
})

test_that("no request is made without cloud = TRUE or off Azure", {
  local_azure_env()
  calls <- local_imds(imds_body())
  local_fixture("azure-vm")
  df <- facts_df(facts(refresh = TRUE), "cloud")
  expect_equal(df$message[df$fact == "cloud.region"], "Needs network access: use `cloud = TRUE`.")
  local_fixture("linux-baremetal")
  facts_df(facts(cloud = TRUE, refresh = TRUE), "cloud")
  expect_equal(calls(), 0)
})

test_that("a blocked IMDS is unavailable, and only tried once", {
  skip_if_not_installed("jsonlite")
  local_fixture("azure-vm")
  local_azure_env()
  calls <- local_imds(error = "Request failed: Couldn't connect to server")
  df <- facts_df(facts(cloud = TRUE, refresh = TRUE), "cloud")
  expect_equal(df$status[df$fact == "cloud.region"], "unavailable")
  expect_equal(df$message[df$fact == "cloud.region"], "Request failed: Couldn't connect to server")
  facts_df(facts(cloud = TRUE), "cloud")
  expect_equal(calls(), 1)
})

test_that("print() shows the Azure platform and, with cloud = TRUE, the VM", {
  skip_if_not_installed("jsonlite")
  withr::local_options(zufax.skip = "runtime")
  local_azure_env()
  local_imds(imds_body())
  local_fixture("aks-pod-downward-api")
  expect_snapshot(print(facts(refresh = TRUE)))
  expect_snapshot(print(facts(cloud = TRUE, refresh = TRUE)))
})

test_that("the HTTP transport fails fast and restores no_proxy", {
  skip_on_cran()
  # Clear upper case first: on Windows NO_PROXY and no_proxy are one variable.
  withr::local_envvar(NO_PROXY = NA)
  withr::local_envvar(no_proxy = "example.com")
  start <- proc.time()[["elapsed"]]
  cnd <- tryCatch(
    http_transport("http://127.0.0.1:9/", character(), 1),
    zufax_unavailable = identity
  )
  expect_s3_class(cnd, "zufax_unavailable")
  expect_match(conditionMessage(cnd), "^Request failed")
  expect_lt(proc.time()[["elapsed"]] - start, 5)
  expect_equal(Sys.getenv("no_proxy"), "example.com")
})
