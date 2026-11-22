# ROS schema atlas

Metadata and HTML documentation for the IOTC ROS database **4.0.0**, using `db.tools` and `db.atlas`.

Open `ros.db.atlas.Rproj` in RStudio, or use an R session in PyCharm from the project directory.

## Setup

Choose one of the following setups.

### Local sibling projects

Use your local `../db.tools` and `../db.atlas` checkouts directly.

Install their CRAN dependencies once, if needed:

```r
install.packages(c("pkgload", "DBI", "data.table", "yaml", "htmltools",
                   "htmlwidgets", "visNetwork", "whisker", "DT", "RPostgres",
                   "stringr", "rmarkdown", "roxygen2", "askpass"))
```

Load the local projects in this order at the start of each R session, before loading the ROS package:

```r
pkgload::load_all("../db.tools", helpers = FALSE)
pkgload::load_all("../db.atlas", helpers = FALSE)
pkgload::load_all(".", helpers = FALSE)
```

This uses your working copies, including local changes, without installing the projects from GitHub.

### Packages from GitHub

If you do not have the sibling projects, install them from GitHub once:

```r
install.packages("pak")
pak::pak("ultreia-io/ros.db.atlas")
```

Load the installed package at the start of each R session:

```r
library(ros.db.atlas)
```

The package requires `db.atlas` 0.3.0 or later. GitHub installation resolves its dependencies.

### Database connection

Pandoc is required for HTML reports and self-contained graphs.

Create your local connection file once:

```r
file.copy(system.file("config", "ros-db.example.yaml", package = "ros.db.atlas"),
          "ros-db.yaml", overwrite = FALSE)
```

Edit its host, database name and user to select the ROS 4.0.0 database. The file is ignored by Git.

Keep the password as `!env IOTC_ROS_DB_PASSWORD`, or retain your existing `!env IOTC_DB_PASSWORD` name.

## Work in your R session

In RStudio, open `ros.db.atlas.Rproj`. The project directory becomes the working directory.

The files in `R/` group database operations, metadata and reports.

After loading the package with either setup above, enter the password once for the session:

```r
config_file <- "ros-db.yaml"
ros_set_password(config_file)
```

The secure dialog sets the password only in this R session. It is removed when the session ends.

Use the same session for the actions below. Change `config_file` above if you use another connection file.

### Extract database metadata

```r
ros_extract_metadata(config_file)
```

Read-only extraction saves schemas, tables, columns and keys in `models/4.0.0/`.

Extraction replaces the CSV files. Apply any edited descriptions before extracting again.

### Edit descriptions

Edit the `description` column in these files:

- `models/4.0.0/schemas_description.csv`
- `models/4.0.0/tables_description.csv`
- `models/4.0.0/tables_columns.csv`

### Preview database comment updates

```r
comments_sql <- ros_apply_comments(config_file = config_file)
cat(comments_sql, sep = "\n")
```

This returns the SQL without changing the database.

### Apply database comment updates

```r
comments_sql <- ros_apply_comments(apply = TRUE, config_file = config_file)
comments_file <- ros_save_comments_sql(comments_sql)
```

This applies the comments and saves the SQL in `output/sql/`, creating the directory when needed.

The filename uses the model version and `DEFAULT_TIME_STAMP`; pass `date` to match a custom report date.

For example: `output/sql/ros-comments-4.0.0-2026-09-29.sql`.

Run the saved SQL with your SQL client against the other ROS 4.0.0 database.

Empty or `NA` descriptions are skipped; blank CSV cells do not clear existing comments.

### Generate documentation

```r
ros_generate_documentation()
```

Generation works offline from the saved metadata and creates reports for ALL, LL, PS, PL and GN.

The reports include searchable tables in their natural order in Columns, Dependencies, and Usages tabs.

Report CSS and JavaScript are embedded in the HTML. Dependency graphs share a `graph-assets/` directory
within each dated output directory. Navigation indexes omit that asset directory.

To choose a generation date:

```r
ros_generate_documentation(date = "2026-09-29")
```

### Build the project website

From the repository, load the local packages as above, then run:

```r
roxygen2::roxygenise()
pkgdown::build_site(devel = TRUE)
```

Roxygen generates standard R help files in `man/` and exports in `NAMESPACE`.

Pkgdown uses this README for the guide and the generated help files for the function reference.

Use `?ros_generate_documentation` in R to read the same function documentation.

RStudio's Build pane provides the package install and document actions.

Generated pages and supporting files are written to `docs/`.

It builds independently of the ROS model reports and requires no database connection or password.

Publish the contents of `docs/` to serve the project website.

## Layout and output

```text
ros.db.atlas.Rproj RStudio package project
DESCRIPTION           Package metadata and dependencies
NAMESPACE             Exports and imports generated by Roxygen
R/                    ROS package source files
man/                  R help generated from Roxygen comments
_pkgdown.yml          Project website configuration
docs/                 Generated project website
inst/config/          Packaged connection example and code-list mapping
inst/templates/       Packaged branding and report presentation
models/4.0.0/         Editable extracted metadata in the repository
output/model/4.0.0/   Generated HTML and graphs, grouped by date
output/sql/           Dated SQL comment exports
```

The package supports only the ROS 4.0.0 model; its package version starts at 4.0.0.

Metadata and output paths are relative to the working directory.

The saved snapshot stays editable in the repository; it is not included in the installed package.

With a GitHub installation, extract metadata first or copy a snapshot into `models/4.0.0/`.

RStudio uses UTF-8, two-space indentation, and code indexing. Workspace restore and saving are disabled.

Editor and Git settings keep text files consistent. Local RStudio state is ignored by Git.

Output is written to `output/model/4.0.0/YYYY-MM-DD/`, with a version index in `output/model/4.0.0/index.html`.

Regenerating the same date replaces that date's output. Generated HTML is ignored by Git.

Deploy the contents of `output/model/4.0.0/` to `https://ros.ultreia.io/model/4.0.0/` after review.

## License

GNU GPL version 3. See [LICENSE](LICENSE).
