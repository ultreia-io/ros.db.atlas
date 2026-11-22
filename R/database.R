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
#' Use db.tools to resolve YAML !env values and create an RPostgres connection.
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
  connection <- db.tools::db_connect_from_yaml(RPostgres::Postgres(), config_file)
  tryCatch({
    DBI::dbExecute(connection, paste("SET default_transaction_read_only =", if (read_only) "on" else "off"))
    connection
  }, error = function(error) {
    DBI::dbDisconnect(connection)
    stop(error)
  })
}

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
  metadata <- db.atlas::extract_schema_metadata(
    unique(c(ROS_SCHEMAS$ALL, ROS_SCHEMAS$CODE_LIST)),
    function() connect_to_ros(config_file)
  )
  db.atlas::write_metadata(metadata, DB_METADATA_DIRECTORY)
  ros_db_generate_shell_dependencies()
  invisible(metadata)
}

#' Preview or apply descriptions from the saved metadata
#'
#' Generate schema, table and column COMMENT statements using db.atlas.
#'
#' Only nonempty description values are applied; NA and blank values are skipped.
#' Applying comments requires ownership or equivalent database privileges.
#' The temporary connection is closed by db.tools; local CSV files are not changed.
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
  db.atlas::apply_metadata_comments(
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
