# Maintainer guide

Work on `develop`. `main` contains releases.

## Code organization

Each R file groups public functions above the helpers that implement them.

| File                     | Responsibility                                           |
|--------------------------|----------------------------------------------------------|
| `database.R`             | Connection settings, metadata extraction, and comments.  |
| `metadata.R`             | Domain metadata models and dependency selection.         |
| `reports.R`              | ROS reports, graph presentation, and relationship links. |
| `ros.db.atlas-package.R` | Package help, shared settings, and load-time setup.      |

## Editable metadata

Keep `models/4.0.0/` in Git. It records the descriptions, keys, and dependencies shared by the ROS reports.

The Getting started guide covers extraction, editing, and applying descriptions to PostgreSQL.

Local connection files, generated reports, and SQL exports stay in ignored paths.

## Local verification

From the package root, with development dependencies, Pandoc, and LaTeX installed, run the shared workflow.

```sh
Rscript tools/check.R
```

It regenerates help, checks the archive with `--as-cran`, and builds the package website.

Local and CI checks share the CRAN mirror configuration in `tools/check.Renviron`.

Build checks Linux, macOS, and Windows. Linux release coverage comes from the runnable documentation.

Archives and check output stay in `build/`.

## Website

Build the package website and its versioned download archive from the package root.

```r
# Prepare downloads of the packaged connection template and report resources.
source("tools/prepare-site-assets.R")
# Build the package website.
pkgdown::build_site()
```

Use the ROS report functions separately to render the tracked metadata into `output/model/4.0.0/`.

## GitHub release

1. Set the release version in `DESCRIPTION` and finalize the matching `NEWS.md` heading.
2. Run local checks, then commit and push the release changes on `develop`.
3. Run **Actions → Start Release** on `develop` to open the release pull request.
4. Wait for the checks to pass, then merge the pull request into `main`.

**Publish Release** checks the merge commit and publishes its archive, checksum, and website.

## License

GPL-3. See [LICENSE](LICENSE).
