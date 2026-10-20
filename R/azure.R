# Azure: which service the process runs on (offline, from environment
# variables) and instance metadata from IMDS (network, only with cloud = TRUE).

# Environment variables each Azure service sets, checked in this order, and
# the non-secret identifiers reported for it. Functions run on App Service, so
# they are checked first.
azure_platforms <- list(
  functions = list(
    detect = "FUNCTIONS_WORKER_RUNTIME",
    ids = c(
      site = "WEBSITE_SITE_NAME",
      instance = "WEBSITE_INSTANCE_ID",
      runtime = "FUNCTIONS_WORKER_RUNTIME"
    )
  ),
  "app-service" = list(
    detect = "WEBSITE_SITE_NAME",
    ids = c(site = "WEBSITE_SITE_NAME", instance = "WEBSITE_INSTANCE_ID", sku = "WEBSITE_SKU")
  ),
  "container-apps" = list(
    detect = "CONTAINER_APP_NAME",
    ids = c(
      app = "CONTAINER_APP_NAME",
      revision = "CONTAINER_APP_REVISION",
      replica = "CONTAINER_APP_REPLICA_NAME"
    )
  ),
  batch = list(
    detect = "AZ_BATCH_NODE_ID",
    ids = c(
      pool = "AZ_BATCH_POOL_ID",
      node = "AZ_BATCH_NODE_ID",
      job = "AZ_BATCH_JOB_ID",
      task = "AZ_BATCH_TASK_ID"
    )
  ),
  azureml = list(
    detect = "AZUREML_RUN_ID",
    ids = c(run = "AZUREML_RUN_ID", experiment = "AZUREML_EXPERIMENT_NAME")
  )
)

azure_platform_from_env <- function(ctx) {
  for (name in names(azure_platforms)) {
    if (!is.null(ctx$env(azure_platforms[[name]]$detect))) {
      return(name)
    }
  }
  NULL
}

imds_api_version <- "2021-02-01"
imds_url <- paste0("http://169.254.169.254/metadata/instance?api-version=", imds_api_version)

# One IMDS request per session (failures too, so a blocked IMDS costs its
# timeout once); refresh = TRUE asks again.
azure_imds <- function(ctx) {
  ctx$shared("azure_imds", function(ctx) {
    if (!ctx$refresh && !is.null(.zufax$imds[[imds_url]])) {
      ctx$note(imds_url)
      return(.zufax$imds[[imds_url]])
    }
    result <- tryCatch(
      {
        if (!requireNamespace("jsonlite", quietly = TRUE)) {
          unavailable("Reading instance metadata needs the jsonlite package.")
        }
        response <- ctx$http(imds_url, headers = c(Metadata = "true"), timeout = 1)
        list(ok = TRUE, data = jsonlite::fromJSON(response$body, simplifyVector = FALSE))
      },
      zufax_unavailable = function(cnd) list(ok = FALSE, message = conditionMessage(cnd)),
      error = function(cnd) list(ok = FALSE, message = conditionMessage(cnd))
    )
    .zufax$imds[[imds_url]] <- result
    result
  })
}

# A field of the IMDS document by path, e.g. imds_field(ctx, "compute", "vmSize").
imds_field <- function(ctx, ...) {
  imds <- azure_imds(ctx)
  if (!imds$ok) {
    unavailable(imds$message)
  }
  value <- imds$data
  for (key in c(...)) {
    value <- if (is.list(value)) value[[key]] else NULL
  }
  if (is.null(value) || identical(value, "")) NULL else value
}

register_azure_facts <- function() {
  azure <- list(cloud.provider = "azure")

  register(resolver("cloud.azure.platform", confine = azure, cache = FALSE, function(ctx) {
    platform <- azure_platform_from_env(ctx)
    if (!is.null(platform)) {
      return(platform)
    }
    if (!is.null(ctx$env("DATABRICKS_RUNTIME_VERSION"))) {
      return("databricks")
    }
    if (isTRUE(ctx$fact("k8s.detected"))) "aks" else "vm"
  }))

  register(resolver("cloud.azure.service", confine = azure, cache = FALSE, function(ctx) {
    platform <- ctx$fact("cloud.azure.platform")
    ids <- if (identical(platform, "databricks")) {
      c(runtime = "DATABRICKS_RUNTIME_VERSION")
    } else {
      azure_platforms[[platform]]$ids
    }
    if (is.null(ids)) {
      not_applicable("No service identifiers for this platform.")
    }
    values <- vapply(ids, \(name) ctx$env(name) %||% NA_character_, character(1))
    values[!is.na(values)]
  }))

  imds <- function(name, fun) {
    register(resolver(
      name,
      confine = azure,
      network = TRUE,
      cache = FALSE,
      id = paste0(name, "/azure"),
      fun
    ))
  }

  imds("cloud.region", \(ctx) imds_field(ctx, "compute", "location"))
  imds("cloud.zone", function(ctx) {
    imds_field(ctx, "compute", "zone") %||% not_applicable("Not in an availability zone.")
  })
  imds("cloud.instance.type", \(ctx) imds_field(ctx, "compute", "vmSize"))
  imds("cloud.instance.id", \(ctx) imds_field(ctx, "compute", "vmId"))
  imds("cloud.azure.vm_name", \(ctx) imds_field(ctx, "compute", "name"))
  imds("cloud.azure.resource_group", \(ctx) imds_field(ctx, "compute", "resourceGroupName"))
  imds("cloud.azure.subscription_id", \(ctx) imds_field(ctx, "compute", "subscriptionId"))
  imds("cloud.azure.vmss_name", function(ctx) {
    imds_field(ctx, "compute", "vmScaleSetName") %||% not_applicable("Not part of a scale set.")
  })
  imds("cloud.azure.priority", \(ctx) imds_field(ctx, "compute", "priority"))
  imds("cloud.azure.eviction_policy", function(ctx) {
    imds_field(ctx, "compute", "evictionPolicy") %||% not_applicable("Not a spot VM.")
  })
  imds("cloud.azure.os_type", \(ctx) imds_field(ctx, "compute", "osType"))
  imds("cloud.azure.environment", \(ctx) imds_field(ctx, "compute", "azEnvironment"))

  imds("cloud.azure.image", function(ctx) {
    ref <- imds_field(ctx, "compute", "storageProfile", "imageReference")
    keys <- c("publisher", "offer", "sku", "version")
    values <- vapply(keys, \(k) as.character(ref[[k]] %||% NA_character_), character(1))
    values[!is.na(values) & nzchar(values)]
  })

  imds("cloud.azure.tags", function(ctx) {
    tags <- imds_field(ctx, "compute", "tagsList") %||% list()
    values <- vapply(tags, \(t) as.character(t$value %||% ""), character(1))
    names(values) <- vapply(tags, \(t) as.character(t$name %||% ""), character(1))
    redact_env(values)
  })

  ip_addresses <- function(ctx, field) {
    interfaces <- imds_field(ctx, "network", "interface") %||% list()
    ips <- unlist(lapply(interfaces, function(nic) {
      vapply(nic$ipv4$ipAddress %||% list(), \(a) as.character(a[[field]] %||% ""), character(1))
    }))
    ips[nzchar(ips)]
  }
  imds("cloud.azure.network.private_ip", \(ctx) ip_addresses(ctx, "privateIpAddress"))
  imds("cloud.azure.network.public_ip", function(ctx) {
    ips <- ip_addresses(ctx, "publicIpAddress")
    if (length(ips)) ips else not_applicable("No public IP address.")
  })
}
