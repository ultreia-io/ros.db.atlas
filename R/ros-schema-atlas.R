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
#' @param metadata Metadata list returned by db.atlas::read_metadata().
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
  metadata <- db.atlas::read_metadata(root_directory)
  db.atlas::build_schema_model(ros_subset_metadata(metadata, schemas))
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
  dependencies <- db.atlas::model_dependencies(model)
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
  metadata <- db.atlas::read_metadata(root_directory)
  schemas <- unique(c(ROS_SCHEMAS[[domain]], ROS_SCHEMAS$CODE_LIST))
  model <- db.atlas::build_schema_model(ros_subset_metadata(metadata, schemas))
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
#' Internal links use stable anchors provided by db.atlas.
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
  sprintf("<a href='#table_%s'>%s</a>", db.atlas::atlas_anchor(schema, table), schema_and_table)
}

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
  config <- db.atlas::atlas_report_config(
    title = sprintf("IOTC ROS Database (version: %s %s)", version, timestamp),
    abstract = paste0("This document describes the ROS database tables",
                      if (domain == "ALL") "." else sprintf(" used by the %s domain.", domain)),
    author = "IOTC Secretariat <IOTC-Secretariat@fao.org>",
    logo = system.file("templates", "IOTC_with_text.png",
                          package = "ros.db.atlas", mustWork = TRUE),
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
                          package = "ros.db.atlas", mustWork = TRUE),
      style = system.file("templates", "atlas-report.css",
                          package = "ros.db.atlas", mustWork = TRUE)
    )
  )
  report <- db.atlas::render_schema_report(model, config, timestamp = Sys.time())
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
      db.atlas::dependency_graph(model, graph_config),
      graph_file,
      title = graph_config$title,
      selfcontained = FALSE,
      libdir = "graph-assets"
    )
  }
  invisible(report)
}

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
  db.atlas::generate_report_indexes(DB_REPORT_DIRECTORY,
                                          title = "IOTC ROS database 4.0.0",
                                          exclude_directories = "graph-assets")
  invisible(reports)
}
