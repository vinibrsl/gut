# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a
Changelog](https://keepachangelog.com/en/1.0.0/), and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

* Add `defquestion` for reusable named questions

### Security

* Update Mint to 1.11.0 to fix CVE-2026-94194, CVE-2026-91043, and
  CVE-2026-92103.

## [0.2.0] - 2026-09-27

### Added

* `Gut.feel/4` accepts `allow_unsure: true` to offer `:unsure` when none of the
  provided choices fit.
* `Gut.Test.stub/1` registers process-local choice behavior for tests. Stubs
   are also available to tasks started by the test process.
* Emit telemetry events for `Gut.feel/4` calls: `[:gut, :feel, :start]`,
  `[:gut, :feel, :stop]`, and `[:gut, :feel, :exception]`.

### Deprecated

* `Gut.Test` no longer accepts the `:index` adapter option. Use
  `Gut.Test.stub/1` to select a choice in a test.

## [0.1.0] - 2026-09-22

* Initial release.
