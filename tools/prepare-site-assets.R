# Identify the resource archive with the package version being built.
resources_version <- read.dcf("DESCRIPTION", fields = "Version")[[1L]]
resources_archive <- paste0("ros.db.atlas-resources-", resources_version, ".zip")

# Replace generated downloads with the current installed resources.
website_assets <- "pkgdown/assets"
unlink(website_assets, recursive = TRUE)
dir.create(website_assets, recursive = TRUE, showWarnings = FALSE)
resource_directories <- c("config", "templates")
if (!all(file.copy(file.path("inst", resource_directories), website_assets,
    recursive = TRUE, overwrite = TRUE)))
  stop("Could not prepare package resource downloads.", call. = FALSE)

# Keep the archive layout identical to the installed resources.
zip::zipr(resources_archive, resource_directories, root = website_assets)

# Publish the licence linked from the website.
if (!file.copy("LICENSE", file.path(website_assets, "LICENSE"), overwrite = TRUE))
  stop("Could not prepare the website licence.", call. = FALSE)
