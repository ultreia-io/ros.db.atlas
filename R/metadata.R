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

# Internal helpers

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
