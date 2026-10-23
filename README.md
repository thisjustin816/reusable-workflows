# Reusable PowerShell workflows

## Build and test

`.github/workflows/ps-ci.yml` builds a PowerShell module on `windows-latest`, runs
its tests, publishes NUnit results, and converts JaCoCo coverage to Cobertura and
a pull request summary. The caller supplies `build.ps1` and one module manifest directly under `src`.
Callers that enable publication also supply `publish.ps1`. The build script must return the built
manifest as a `FileInfo` object.

The `psmoduleutils_version` input installs an exact PSModuleUtils release. It
defaults to `4.2.3`, which uses Pester 5. A caller prepared for Pester 6 can select
PSModuleUtils `5.0.0` after that version is published:

```yaml
jobs:
  build:
    permissions:
      checks: write
      contents: write
      pull-requests: write
    uses: thisjustin816/reusable-workflows/.github/workflows/ps-ci.yml@main
    with:
      psmoduleutils_version: '5.0.0'
    secrets: inherit
```

The workflow installs runtime dependencies from the source manifest. The caller's
build script is responsible for selecting the requested build-tool major and
failing when its tests fail. Each PowerShell step starts a fresh process, keeping
Pester assemblies from separate major versions out of the same session.

The workflow expects `out/tests/testResults.xml` and `out/tests/coverage.xml`.
Coverage paths must be relative to `src`, which is passed to ReportGenerator as
the source root. ReportGenerator runs on .NET 8.

The `publish_module` input defaults to `true`, preserving existing callers. When enabled,
a successful build on `main` calls `publish.ps1` with the inherited `PSGALLERYAPIKEY` secret and
creates a GitHub release. Pull request builds do not publish.

For maintenance-only CI, set `publish_module: false`. This skips the PSGallery version lookup,
package publication, and release creation. Such callers need `contents: read`, `checks: write`,
and `pull-requests: write`; they do not need to inherit secrets or provide `publish.ps1`.

## Static analysis

`.github/workflows/ps-scriptAnalyzer.yml` runs the PSModuleUtils analyzer and
uploads SARIF results. It accepts these inputs:

| Input | Default | Purpose |
|---|---|---|
| `path` | `src` | Source directory to analyze. |
| `settings` | Empty | Caller-relative settings file; empty uses the module's bundled settings. |
| `psmoduleutils_version` | `4.2.3` | Exact PSModuleUtils release to install and import. |
| `use_local_psmoduleutils` | `false` | Load analyzer commands and dependency bounds from the caller's PSModuleUtils source. |

The caller needs `contents: read`, `security-events: write`, and `actions: read`.

## Updating consumers

Publish compatible workflow changes first, then the PSModuleUtils release, then
update callers to select that release. Keep the default version until existing
callers have migrated. Action references use maintained major tags, except
ReportGenerator, which uses its published release tag.

## Workflow tests

The `Workflow tests` check runs `tests/DependencyInstallation.Tests.ps1` with Pester 6.2.0.
It exercises the dependency-installation step from the workflow using temporary module manifests
and PowerShell's real module lookup. Downloads are mocked. The cases cover name-only dependencies,
exact versions, version ranges, and installation failures.
