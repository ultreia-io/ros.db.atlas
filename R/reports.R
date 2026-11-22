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

# Internal helpers

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
