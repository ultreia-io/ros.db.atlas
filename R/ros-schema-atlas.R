# IOTC ROS 4.0.0 ----

# ROS 4.0.0 configuration ----

#' ROS database metadata and documentation
#'
#' Extract metadata, apply database comments and generate documentation for ROS 4.0.0.
#' @import data.table
#' @importFrom stringr str_length
#' @importFrom stats setNames
#' @keywords internal
"_PACKAGE"

utils::globalVariables(c(
  "schema", "table", "table_id", "target_schema", "target_table",
  "target_table_id", "usage_table_id", "outer_dependency",
  "direct_dependency", "outer_transitive_dependency", "codelist", "codelist_url"
))

# Model version and schema selections ----

#' Supported ROS model version
#'
#' Version used to select metadata and report directories. This does not select the database name.
#' @format Character scalar, currently "4.0.0".
#' @examples
#' IOTC_ROS
#' @export
IOTC_ROS <- "4.0.0"
#' Schemas included in each ROS report domain
#'
#' ALL includes every ROS gear. LL, PS, PL and GN include shared schemas and their own gear.
#' CODE_LIST lists the reference schemas added to every domain model.
#' @format Named list of character vectors: ALL, LL, PS, PL, GN and CODE_LIST.
#' @examples
#' ROS_SCHEMAS$LL
#' @export
ROS_SCHEMAS <- list(
  ALL = c("ros_meta", "ros_common", "ros_ps", "ros_ll", "ros_pl", "ros_gn"),
  LL = c("ros_meta", "ros_common", "ros_ll"),
  PS = c("ros_meta", "ros_common", "ros_ps"),
  PL = c("ros_meta", "ros_common", "ros_pl"),
  GN = c("ros_meta", "ros_common", "ros_gn"),
  CODE_LIST = c("refs_admin", "refs_biology", "refs_data", "refs_fishery",
                "refs_fishery_config", "refs_gis", "refs_meta")
)
# Default paths and report date ----

#' Default report generation date
#'
#' Captures the current date when the package is loaded. Supply date or timestamp to override it.
#' @format Character scalar in YYYY-MM-DD format.
#' @examples
#' DEFAULT_TIME_STAMP
#' @export
DEFAULT_TIME_STAMP <- format(Sys.Date(), "%Y-%m-%d")
#' Saved metadata directory
#'
#' Directory containing the extracted CSV files, relative to the project working directory.
#' Individual metadata functions accept root_directory to override this default.
#' @format Character path, models/4.0.0 for the current model version.
#' @examples
#' DB_METADATA_DIRECTORY
#' @export
DB_METADATA_DIRECTORY <- file.path("models", IOTC_ROS)
#' Generated ROS model documentation directory
#'
#' Parent directory for dated model reports, relative to the project working directory.
#' Individual report functions accept export_directory to override this default.
#' @format Character path, output/model/4.0.0 for the current model version.
#' @examples
#' DB_REPORT_DIRECTORY
#' @export
DB_REPORT_DIRECTORY <- file.path("output", "model", IOTC_ROS)

#' SQL export directory
#'
#' Directory used by ros_save_comments_sql(), relative to the project working directory.
#' Created only when saving SQL files.
#' @format Character path, output/sql.
#' @examples
#' DB_SQL_DIRECTORY
#' @export
DB_SQL_DIRECTORY <- file.path("output", "sql")
#' Official reference-data links
#'
#' Loaded from the packaged code-list URL mapping.
#' Used by ros_link_to_url() to link reference tables to their configured official URLs.
#' @format A data.table containing codelist (schema.table) and codelist_url columns.
#' @examples
#' head(ROS_CODE_LIST_URLS)
#' @export
ROS_CODE_LIST_URLS <- fread(system.file("config", "ros-code-list-urls.csv",
                                      package = "rosschemaatlas", mustWork = TRUE))

# Report palette ----

#' Schema colours used in model reports
#'
#' Assigns a colour to each ROS and reference schema. Changes affect subsequent report renders.
#' @format Named character vector of hexadecimal colour codes, indexed by schema name.
#' @examples
#' ros_report_colors["ros_ll"]
#' @export
ros_report_colors <- c(
  ros_meta = "#D1D5DB", ros_common = "#93C5FD", ros_ps = "#FDBA74",
  ros_ll = "#86EFAC", ros_pl = "#C4B5FD", ros_gn = "#F9A8D4",
  refs_admin = "#FDE68A", refs_biology = "#FDE68A", refs_data = "#FDE68A",
  refs_fishery = "#FDE68A", refs_fishery_config = "#FDE68A",
  refs_gis = "#FDE68A", refs_meta = "#FDE68A"
)

# Offline metadata helpers ----

#' Split a qualified table identifier
#'
#' Internal helper for dependency classification.
#'
#' @param value Character scalar in schema.table format.
#' @return A list containing character scalars schema and table.
#' @keywords internal
ros_split_table_id <- function(value) {
  parts <- strsplit(value, ".", fixed = TRUE)[[1L]]
  if (length(parts) != 2L) stop("Expected a schema.table identifier: ", value)
  list(schema = parts[[1L]], table = parts[[2L]])
}

#' Select metadata belonging to a set of schemas
#'
#' Filter all five snapshot components by their owning schema.
#'
#' Foreign keys are selected by source schema; referenced tables may belong to another schema.
#'
#' @param metadata Metadata list returned by dbschemaatlas::read_metadata().
#' @param schemas Character vector of schema names to retain.
#' @return The filtered metadata list.
#' @keywords internal
ros_subset_metadata <- function(metadata, schemas) {
  metadata$schemas_description <- metadata$schemas_description[schema %in% schemas]
  metadata$tables_description <- metadata$tables_description[schema %in% schemas]
  metadata$tables_columns <- metadata$tables_columns[schema %in% schemas]
  metadata$tables_foreign_keys <- metadata$tables_foreign_keys[schema %in% schemas]
  metadata$tables_primary_keys <- metadata$tables_primary_keys[schema %in% schemas]
  metadata
}

#' Build an offline model from selected schemas
#'
#' Read a saved snapshot and build its dependency model.
#'
#' @param root_directory Directory containing the five metadata CSV files.
#' @param schemas Character vector of schema names to include.
#' @return A dbschema_model object. No database connection is opened.
#' @keywords internal
ros_metadata_model <- function(root_directory, schemas) {
  metadata <- dbschemaatlas::read_metadata(root_directory)
  dbschemaatlas::build_schema_model(ros_subset_metadata(metadata, schemas))
}

#' Restrict a model to selected tables
#'
#' Filter tables, columns, keys, dependencies and reverse usages consistently.
#'
#' @param model A dbschema_model object.
#' @param keep_tables Character vector of qualified schema.table identifiers.
#' @return The filtered model; both ends of retained relationships belong to keep_tables.
#' @keywords internal
ros_filter_model <- function(model, keep_tables) {
  model$tables <- model$tables[table_id %in% keep_tables]
  model$columns <- model$columns[paste(schema, table, sep = ".") %in% keep_tables]
  model$primary_keys <- model$primary_keys[paste(schema, table, sep = ".") %in% keep_tables]
  model$foreign_keys <- model$foreign_keys[
    paste(schema, table, sep = ".") %in% keep_tables &
      paste(target_schema, target_table, sep = ".") %in% keep_tables
  ]
  model$dependencies <- model$dependencies[table_id %in% keep_tables & target_table_id %in% keep_tables]
  model$usages <- model$usages[table_id %in% keep_tables & usage_table_id %in% keep_tables]
  model
}

#' Find the connected dependency neighbourhood of ROS tables
#'
#' Traverse foreign keys in both directions until no additional table is found.
#'
#' All matching ROS tables are retained, including tables without foreign keys.
#' Reference tables disconnected from the selected roots are omitted.
#'
#' @param model A dbschema_model object.
#' @param schema_filter Function taking one schema name and returning one logical value.
#' @return A sorted data.table with table_id, direct_dependency, outer_dependency
#' and outer_transitive_dependency columns.
#' @keywords internal
ros_shell_dependencies <- function(model, schema_filter) {
  dependencies <- dbschemaatlas::model_dependencies(model)
  direct <- sort(unique(c(
    dependencies[vapply(schema, schema_filter, logical(1L)), target_table_id],
    dependencies[vapply(target_schema, schema_filter, logical(1L)), table_id]
  )))
  roots <- model$tables[vapply(schema, schema_filter, logical(1L)), table_id]
  shell <- sort(unique(c(roots, direct)))
  repeat {
    expanded <- sort(unique(c(
      shell,
      dependencies[table_id %in% shell, target_table_id],
      dependencies[target_table_id %in% shell, table_id]
    )))
    if (identical(expanded, shell)) break
    shell <- expanded
  }
  data.table::data.table(
    table_id = shell,
    direct_dependency = shell %in% direct,
    outer_dependency = vapply(shell, function(id) !schema_filter(ros_split_table_id(id)$schema), logical(1L))
  )[, outer_transitive_dependency := outer_dependency & !direct_dependency][order(table_id)]
}

# Session credentials and database connections ----

#' Read the password environment-variable name
#'
#' Read the local YAML configuration without resolving its !env password value.
#'
#' Configure password as !env VARIABLE_NAME. This function does not retrieve a password.
#'
#' @param config_file YAML connection file; defaults to ros-db.yaml in the working directory.
#' @return The character scalar naming the password environment variable.
#' @export
ros_password_variable <- function(config_file = "ros-db.yaml") {
  config <- yaml::read_yaml(config_file, handlers = list(env = identity))
  variable <- config$password
  if (!is.character(variable) || length(variable) != 1L ||
      !grepl("^[A-Za-z_][A-Za-z0-9_]*$", variable)) {
    stop("Configure the YAML password as !env followed by an environment variable name.")
  }
  variable
}

#' Set the database password for the current R session
#'
#' Prompt securely and set the variable named by the YAML connection configuration.
#'
#' The password is not saved to a file or persistent keyring. It remains in this R process
#' until Sys.unsetenv(ros_password_variable(config_file)) or session termination.
#' Cancellation or an empty response raises an error without changing the variable.
#'
#' @param config_file YAML connection file; defaults to ros-db.yaml.
#' @param prompt Optional function accepting a prompt label and returning one password string.
#' NULL uses askpass::askpass(); supplying a function allows a custom password prompt.
#' @return TRUE invisibly after setting the environment variable.
#' @export
ros_set_password <- function(config_file = "ros-db.yaml", prompt = NULL) {
  variable <- ros_password_variable(config_file)
  if (is.null(prompt)) {
    if (!requireNamespace("askpass", quietly = TRUE)) stop("Install askpass to use the secure password prompt.")
    prompt <- askpass::askpass
  }
  password <- prompt("ROS database password")
  if (is.null(password)) stop("Password entry cancelled.")
  if (length(password) != 1L || is.na(password) || !nzchar(password)) stop("The password must not be empty.")
  do.call(Sys.setenv, setNames(list(password), variable))
  invisible(TRUE)
}

#' Open a PostgreSQL connection with an explicit transaction policy
#'
#' Use dbiutils to resolve YAML !env values and create an RPostgres connection.
#'
#' Set the password in the session before connecting. The connection is closed if setting
#' the transaction policy fails. This function never stores the password.
#'
#' @param config_file YAML connection file; defaults to ros-db.yaml.
#' @param read_only Logical scalar; TRUE by default. FALSE explicitly permits database writes.
#' @return An open DBI connection. The caller owns it and must disconnect it.
#' @export
connect_to_ros <- function(config_file = "ros-db.yaml", read_only = TRUE) {
  if (!is.logical(read_only) || length(read_only) != 1L || is.na(read_only)) {
    stop("read_only must be TRUE or FALSE.")
  }
  connection <- dbiutils::db_connect_from_yaml(RPostgres::Postgres(), config_file)
  tryCatch({
    DBI::dbExecute(connection, paste("SET default_transaction_read_only =", if (read_only) "on" else "off"))
    connection
  }, error = function(error) {
    DBI::dbDisconnect(connection)
    stop(error)
  })
}

# Database comment updates ----

#' Preview or apply descriptions from the saved metadata
#'
#' Generate schema, table and column COMMENT statements using dbschemaatlas.
#'
#' Only nonempty description values are applied; NA and blank values are skipped.
#' Applying comments requires ownership or equivalent database privileges.
#' The temporary connection is closed by dbiutils; local CSV files are not changed.
#'
#' @param apply Logical scalar. FALSE returns SQL using a read-only connection;
#' TRUE executes all generated statements in one transaction using a writable connection.
#' @param config_file YAML connection file; defaults to ros-db.yaml.
#' @param root_directory Metadata CSV directory; defaults to models/4.0.0.
#' @return A character vector of generated SQL statements, also returned when applied.
#' @export
ros_apply_comments <- function(apply = FALSE, config_file = "ros-db.yaml",
                               root_directory = DB_METADATA_DIRECTORY) {
  if (!is.logical(apply) || length(apply) != 1L || is.na(apply)) stop("apply must be TRUE or FALSE.")
  dbschemaatlas::apply_metadata_comments(
    root_directory,
    function() connect_to_ros(config_file, read_only = !apply),
    apply = apply
  )
}

#' Save database comment SQL for reuse
#'
#' Write the SQL returned by ros_apply_comments() beneath output/sql.
#' The filename includes the model version and shared report date.
#' Creates the directory when needed; saving again for the same date replaces the file.
#'
#' @param comments_sql Character vector of SQL statements returned by ros_apply_comments().
#' @param date Report date used in the filename; defaults to DEFAULT_TIME_STAMP.
#' @return The saved SQL file path invisibly. No database connection is opened.
#' @examples
#' \dontrun{
#' comments_sql <- ros_apply_comments()
#' ros_save_comments_sql(comments_sql)
#' }
#' @export
ros_save_comments_sql <- function(comments_sql, date = DEFAULT_TIME_STAMP) {
  dir.create(DB_SQL_DIRECTORY, recursive = TRUE, showWarnings = FALSE)
  path <- file.path(DB_SQL_DIRECTORY, sprintf("ros-comments-%s-%s.sql", IOTC_ROS, date))
  writeLines(comments_sql, path)
  invisible(path)
}

# Model selection and dependency snapshots ----

#' Build the offline metadata model for one ROS domain
#'
#' Read the saved snapshot and select domain schemas plus configured reference schemas.
#'
#' No database connection is opened. Without dependencies.csv, pruning is not performed.
#'
#' @param domain Character scalar: ALL, LL, PS, PL or GN; case-sensitive.
#' @param version Model version; only 4.0.0 is accepted. Defaults to IOTC_ROS.
#' @param root_directory Metadata CSV directory; defaults to models/4.0.0.
#' @param remove_unused_tables Logical flag, FALSE by default. If TRUE and dependencies.csv exists,
#' retain only table identifiers listed in that file.
#' @return A dbschema_model with domain and version attributes.
#' @export
ros_db_metadata_create <- function(domain, version = IOTC_ROS,
                                   root_directory = DB_METADATA_DIRECTORY,
                                   remove_unused_tables = FALSE) {
  if (!identical(version, IOTC_ROS)) stop("This project supports only ROS 4.0.0.")
  if (!domain %in% c("ALL", "LL", "PS", "PL", "GN")) stop("Unknown ROS domain: ", domain)
  metadata <- dbschemaatlas::read_metadata(root_directory)
  schemas <- unique(c(ROS_SCHEMAS[[domain]], ROS_SCHEMAS$CODE_LIST))
  model <- dbschemaatlas::build_schema_model(ros_subset_metadata(metadata, schemas))
  if (isTRUE(remove_unused_tables) && !is.null(metadata$dependencies)) {
    model <- ros_filter_model(model, metadata$dependencies$table_id)
  }
  attr(model, "domain") <- domain
  attr(model, "version") <- version
  model
}

#' Save the ROS dependency selection
#'
#' Build the ALL model and compute its connected reference-table neighbourhood.
#'
#' Writes or replaces dependencies.csv in root_directory using UTF-8 with a byte-order mark.
#' All ROS tables are included, even when they have no foreign keys.
#'
#' @param version Model version; only 4.0.0 is accepted.
#' @param root_directory Metadata CSV directory; defaults to models/4.0.0.
#' @return The dependency data.table invisibly.
#' @export
ros_db_generate_shell_dependencies <- function(version = IOTC_ROS,
                                               root_directory = DB_METADATA_DIRECTORY) {
  model <- ros_db_metadata_create("ALL", version, root_directory)
  dependencies <- ros_shell_dependencies(
    model,
    function(schema) schema %like% "^ros_(meta|common|ps|ll|pl|gn)$"
  )
  data.table::fwrite(dependencies, file.path(root_directory, "dependencies.csv"), bom = TRUE, na = "NA")
  invisible(dependencies)
}

# Read-only extraction ----

#' Extract the ROS 4.0.0 database metadata
#'
#' Read PostgreSQL catalog metadata for the configured ROS and reference schemas.
#'
#' Uses a managed read-only connection and never modifies database data or comments.
#' Writes or replaces the five metadata CSV files and dependencies.csv in models/4.0.0.
#' Apply edited CSV descriptions before re-extracting, because extraction overwrites them.
#'
#' @param config_file YAML connection file; defaults to ros-db.yaml. Set its password first.
#' @return The five-component extracted metadata list invisibly.
#' @export
ros_extract_metadata <- function(config_file = "ros-db.yaml") {
  if (!requireNamespace("RPostgres", quietly = TRUE)) stop("Install RPostgres to extract metadata.")
  metadata <- dbschemaatlas::extract_schema_metadata(
    unique(c(ROS_SCHEMAS$ALL, ROS_SCHEMAS$CODE_LIST)),
    function() connect_to_ros(config_file)
  )
  dbschemaatlas::write_metadata(metadata, DB_METADATA_DIRECTORY)
  ros_db_generate_shell_dependencies()
  invisible(metadata)
}

# Relationship labels and hyperlinks ----

#' Identify reference-data table identifiers
#'
#' Internal vectorised classification helper.
#'
#' @param value Character vector of qualified schema.table identifiers.
#' @return A logical vector identifying values matching the refs_ schema convention.
#' @keywords internal
is_column_code_list_function <- function(value) str_length(value) > 0 & value %like% "refs_.+"
#' Identify ROS registry table identifiers
#'
#' Internal vectorised classification helper.
#'
#' @param value Character vector of qualified schema.table identifiers.
#' @return A logical vector identifying values matching the ros_meta schema convention.
#' @keywords internal
is_column_registry_function <- function(value) str_length(value) > 0 & value %like% "ros_meta.+"
#' Identify non-reference, non-registry table identifiers
#'
#' Internal vectorised classification helper.
#'
#' @param value Character vector of qualified schema.table identifiers.
#' @return A logical vector identifying other nonempty table identifiers.
#' @keywords internal
is_column_data_function <- function(value) str_length(value) > 0 & !value %like% "refs_.+|ros_meta.+"

#' Classify one relationship target for display
#'
#' Return the label used in report dependency and usage tables.
#'
#' @param schema_and_table One qualified schema.table identifier.
#' @return One of Code list, ROS registry, ROS data or Database table.
#' @export
ros_link_to_type <- function(schema_and_table) {
  if (is_column_code_list_function(schema_and_table)) return("Code list")
  if (is_column_registry_function(schema_and_table)) return("ROS registry")
  if (is_column_data_function(schema_and_table)) return("ROS data")
  "Database table"
}

#' Build a report link for one relationship target
#'
#' Use the configured official code-list URL when available, otherwise a local table anchor.
#'
#' Code-list mappings are loaded from the packaged config/ros-code-list-urls.csv.
#' Internal links use stable anchors provided by dbschemaatlas.
#'
#' @param schema Character scalar naming the target schema.
#' @param table Character scalar naming the target table.
#' @param schema_and_table Qualified schema.table identifier used as link text and mapping key.
#' @return An HTML anchor string.
#' @export
ros_link_to_url <- function(schema, table, schema_and_table) {
  if (is_column_code_list_function(schema_and_table)) {
    url <- ROS_CODE_LIST_URLS[codelist == schema_and_table, codelist_url]
    if (length(url)) return(sprintf("<a target='_iotc_code_lists' href='%s'>%s</a>", url[[1L]], schema_and_table))
  }
  sprintf("<a href='#table_%s'>%s</a>", dbschemaatlas::atlas_anchor(schema, table), schema_and_table)
}

# Individual domain reports ----

#' Render one ROS domain report and its dependency graphs
#'
#' Build a domain model from saved CSV metadata and render it with the IOTC presentation.
#'
#' Writes the domain HTML report, its dependency graphs and branding assets beneath
#' export_directory/timestamp. Existing files with the same names are replaced.
#' No database connection is opened. Call ros_generate_documentation() for all domains and indexes.
#'
#' @param domain Character scalar: ALL, LL, PS, PL or GN.
#' @param version Model version; only 4.0.0 is accepted.
#' @param timestamp Generation-date label used in the report title and output subdirectory.
#' Defaults to DEFAULT_TIME_STAMP, captured when the package is loaded.
#' @param root_directory Metadata CSV directory; defaults to models/4.0.0.
#' @param export_directory Parent output directory; defaults to output/model/4.0.0.
#' @return The generated report path invisibly.
#' @export
ros_db_metadata_generate_report <- function(domain, version = IOTC_ROS,
                                            timestamp = DEFAULT_TIME_STAMP,
                                            root_directory = DB_METADATA_DIRECTORY,
                                            export_directory = DB_REPORT_DIRECTORY) {
  model <- ros_db_metadata_create(domain, version, root_directory, remove_unused_tables = TRUE)
  report_suffix <- if (domain == "ALL") "" else paste0("_", domain)
  domain_schemas <- setdiff(ROS_SCHEMAS[[domain]], c("ros_meta", "ros_common"))
  graph_files <- setNames(
    sprintf("ROS_database%s_dependencies_%s.html", report_suffix, domain_schemas),
    domain_schemas
  )
  config <- dbschemaatlas::atlas_report_config(
    title = sprintf("IOTC ROS Database (version: %s %s)", version, timestamp),
    abstract = paste0("This document describes the ROS database tables",
                      if (domain == "ALL") "." else sprintf(" used by the %s domain.", domain)),
    author = "IOTC Secretariat <IOTC-Secretariat@fao.org>",
    logo = system.file("templates", "IOTC_with_text.png",
                          package = "rosschemaatlas", mustWork = TRUE),
    schemas = unique(c(ROS_SCHEMAS[[domain]], ROS_SCHEMAS$CODE_LIST)),
    schema_groups = list(ROS = ROS_SCHEMAS[[domain]], `Reference data` = ROS_SCHEMAS$CODE_LIST),
    schema_colors = ros_report_colors,
    schema_graph_links = graph_files,
    filename_prefix = paste0("ROS_database", report_suffix),
    output_directory = file.path(export_directory, timestamp),
    link_type = ros_link_to_type,
    link_url = ros_link_to_url,
    domain_labels = c(ros_meta = "ROS metadata", ros_common = "ROS common"),
    timestamp_format = "",
    sections = c(columns = TRUE, dependencies = TRUE, usages = TRUE, graphs = FALSE),
    template_overrides = list(
      report = system.file("templates", "atlas-report.Rmd.tpl",
                          package = "rosschemaatlas", mustWork = TRUE),
      style = system.file("templates", "atlas-report.css",
                          package = "rosschemaatlas", mustWork = TRUE)
    )
  )
  report <- dbschemaatlas::render_schema_report(model, config, timestamp = Sys.time())
  for (schema_name in domain_schemas) {
    graph_config <- config
    graph_config$schemas <- c("ros_meta", "ros_common", schema_name)
    graph_config$graph_entry_point <- "ros_common.observation_dataset.id"
    graph_config$graph_standalone_tables <- paste0("ros_meta.", c(
      "observer", "observer_accreditation", "observer_identifier_mapping",
      "contact", "focal_point", "vessel", "vessel_licensed_target_species"
    ))
    graph_config$schema_colors <- setNames(c("lightgray", "lightblue", "orange"), graph_config$schemas)
    graph_config$title <- sprintf(
      "IOTC ROS Database dependency graph (version: %s %s) - Domain %s",
      version, timestamp, toupper(sub("^ros_", "", schema_name))
    )
    graph_file <- file.path(config$output_directory, graph_files[[schema_name]])
    htmlwidgets::saveWidget(
      dbschemaatlas::dependency_graph(model, graph_config),
      graph_file,
      title = graph_config$title,
      selfcontained = TRUE
    )
  }
  invisible(report)
}

# Complete documentation site ----

#' Generate the complete ROS 4.0.0 documentation site
#'
#' Render ALL, LL, PS, PL and GN reports from the saved metadata, then rebuild navigation indexes.
#'
#' Reads models/4.0.0 without connecting to PostgreSQL. Writes dated reports beneath
#' output/model/4.0.0 and replaces indexes in that tree. Reusing a date replaces its reports.
#' R Markdown, Pandoc and htmlwidgets dependencies must be available.
#'
#' @param date Character scalar in YYYY-MM-DD format. Defaults to DEFAULT_TIME_STAMP,
#' which is set to the current date when the package is loaded.
#' @return A list of the five generated report paths invisibly, in ALL, LL, PS, PL, GN order.
#' @export
ros_generate_documentation <- function(date = DEFAULT_TIME_STAMP) {
  if (length(date) != 1L || is.na(date) ||
      !grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", date) || is.na(as.Date(date))) {
    stop("The report date must use YYYY-MM-DD.")
  }
  reports <- lapply(c("ALL", "LL", "PS", "PL", "GN"), function(domain) {
    ros_db_metadata_generate_report(domain, timestamp = date)
  })
  dbschemaatlas::generate_report_indexes(DB_REPORT_DIRECTORY, title = "IOTC ROS database 4.0.0")
  invisible(reports)
}

# Package loading ----

#' Initialise the session report date
#'
#' Refresh the shared report date when the package is loaded, including installed packages.
#' @param libname Library directory passed by R.
#' @param pkgname Package name passed by R.
#' @return NULL invisibly.
#' @noRd
.onLoad <- function(libname, pkgname) {
  assign("DEFAULT_TIME_STAMP", format(Sys.Date(), "%Y-%m-%d"),
         envir = asNamespace(pkgname))
  invisible(NULL)
}
