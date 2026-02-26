# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-02-26

### Added
- `Build-PSModule` — Merges dev-structure modules into distributable packages
- `Initialize-PSModule` — Scaffolds new PowerShell modules with conventional folder structure
- `Split-PSModule` — Splits monolithic .psm1 files into individual dev files
- `Update-PSModuleVersion` — Semantic versioning based on Conventional Commits
- Private helper functions for AST parsing, file merging, manifest updates
- Pester v5 test suite (unit + integration)
- GitHub Actions CI/CD pipeline (Windows + Linux)
- Self-build capability (dogfooding via build.ps1)
