#' ROS database metadata and documentation
#'
#' Extract metadata, apply database comments and generate documentation for ROS 4.0.0.
#' @import data.table
#' @importFrom stringr str_length
#' @importFrom stats setNames
#' @keywords internal
"_PACKAGE"

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
                                      package = "ros.db.atlas", mustWork = TRUE))

# Internal helpers

# Register data.table column names for R CMD check.
utils::globalVariables(c(
  "schema", "table", "table_id", "target_schema", "target_table",
  "target_table_id", "usage_table_id", "outer_dependency",
  "direct_dependency", "outer_transitive_dependency", "codelist", "codelist_url"
))

#' Initialise the session report date
#'
#' Refresh the shared report date when the package is loaded, including installed packages.
#' @param libname Library directory passed by R.
#' @param pkgname Package name passed by R.
#' @return NULL invisibly.
#' @name ros_atlas_on_load
#' @keywords internal
.onLoad <- function(libname, pkgname) {
  assign("DEFAULT_TIME_STAMP", format(Sys.Date(), "%Y-%m-%d"),
         envir = asNamespace(pkgname))
  invisible(NULL)
}
