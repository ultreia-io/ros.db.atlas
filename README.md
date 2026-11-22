# ros.db.atlas

[![Build](https://github.com/ultreia-io/ros.db.atlas/actions/workflows/Build.yaml/badge.svg?branch=develop)](https://github.com/ultreia-io/ros.db.atlas/actions/workflows/Build.yaml?query=branch%3Adevelop)
[![Website](https://img.shields.io/badge/website-documentation-blue?logo=readthedocs&logoColor=white)](https://ultreia-io.github.io/ros.db.atlas/index.html)
[![License](https://img.shields.io/badge/license-GPL--3-blue?logo=gnu&logoColor=white)](https://github.com/ultreia-io/ros.db.atlas/blob/main/LICENSE)

[![Latest release](https://img.shields.io/github/v/release/ultreia-io/ros.db.atlas?label=Latest%20release&logo=github)](https://github.com/ultreia-io/ros.db.atlas/releases/latest)

## About this project

> `ros.db.atlas` maintains database descriptions and publishes schema documentation for IOTC ROS 4.0.0.

The editable snapshot in `models/4.0.0/` holds descriptions for schemas, tables, and columns.

See [Terminology][terminology] for the database and report concepts.

## Features

**Metadata and database descriptions**

- Extract PostgreSQL descriptions, columns, and keys to CSV.
- Edit descriptions and preview the SQL changes before applying them.
- Save the generated SQL for reuse on another ROS database.

**Reports and dependencies**

- Generate HTML reports and dependency graphs for ALL, LL, PS, PL, and GN from the saved snapshot.
- Link reference tables to their IOTC code lists where a URL is configured.
- Share graph assets within each dated report directory.

## Related packages

- [db.tools](https://github.com/ultreia-io/db.tools) provides database connection and SQL helpers.
- [db.atlas](https://github.com/ultreia-io/db.atlas) builds the models, reports, and graphs.

## Installation

With GitHub access to this repository, install the latest published release.

```r
# Install the package installer once.
install.packages("pak")
# Install the latest GitHub release.
pak::pak("ultreia-io/ros.db.atlas@*release")
```

For development, install from `develop`.

```r
# Install the development version.
pak::pak("ultreia-io/ros.db.atlas@develop")
```

## Getting started

Follow [Getting started][getting-started] to extract, edit, and apply descriptions, then generate the reports.

[terminology]: https://ultreia-io.github.io/ros.db.atlas/articles/terminology.html
[getting-started]: https://ultreia-io.github.io/ros.db.atlas/articles/atlas.html

## Guides

- [ROS reports](https://ultreia-io.github.io/ros.db.atlas/articles/reports.html)
- [Package resources](https://ultreia-io.github.io/ros.db.atlas/articles/resources.html)
- [API reference](https://ultreia-io.github.io/ros.db.atlas/reference/index.html)
- [Contributing](CONTRIBUTING.md) and [maintenance](DEVELOPMENT.md)
