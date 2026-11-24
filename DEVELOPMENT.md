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

**Build** runs one Linux R-release job. Coverage comes from the runnable documentation.

Run **Actions → Check All Platforms** to check Linux release and R-devel, macOS, and Windows.

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

## GitHub Release

1. **Prepare the release on `develop`:**

   1. **Prepare the release files:** update the version in `DESCRIPTION`, finalize `NEWS.md` and documentation.
   2. **Perform the [local checks](#local-verification).**
   3. **Commit the changes:** use `[ros.db.atlas] Release <version>`.
   4. **Push the release commit.**

2. **Start the release on GitHub:**

   1. Open **Actions → Start Release**.
   2. Click **Run workflow**, select `develop`, then click **Run workflow** to confirm.
   3. The workflow checks the selected commit on all four environments and saves the checked Linux archive.
   4. After all four checks pass, it opens the release PR at the checked commit.

3. **Merge the release PR:**

   1. Review the release PR and merge it. Its checks already passed in **Start Release**.
   2. Merging starts **Publish Release**, which verifies that the merged files match the checked candidate.

**Publish Release** publishes the checked archive and checksum, then deploys the documentation.

If the merge changes the checked files, update `develop` and rerun **Start Release** before merging a new PR.

### Enable CRAN submission

The **Submit to CRAN** job is skipped by default. Enable it when the package's required dependencies are on CRAN.

1. Open the repository's **Settings → Secrets and variables → Actions → Variables**.
2. Click **New repository variable** and set `SUBMIT_TO_CRAN` to `true`.

To disable submission, remove the variable or set it to `false`.

## License

GPL-3. See [LICENSE](LICENSE).
