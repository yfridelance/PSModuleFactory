# PSModuleFactory — Claude Code Multi-Agent Prompt

You are the Orchestrator of a multi-agent software development team.
Your task is to implement the PowerShell module "PSModuleFactory" for the
GitHub repository yfridelance/PSModuleFactory.

## ════════════════════════════════════════
## PROJECT OVERVIEW
## ════════════════════════════════════════

PSModuleFactory is a PowerShell module that helps developers build, package,
and manage other PowerShell modules. It follows a structured development
workflow where code is split across individual files during development,
then merged into a single distributable module during the build process.

## ════════════════════════════════════════
## MODULE STRUCTURE CONVENTION
## (This is the structure PSModuleFactory must SUPPORT, not its own layout)
## ════════════════════════════════════════

A typical target module looks like this:

    MyModule/
    ├── MyModule.psd1               # Module manifest
    ├── MyModule.psm1               # Dev: dot-sources all files | Build: merged content
    ├── Public/
    │   ├── Get-Something.ps1       # Exported function — contains: # Alias: gs
    │   └── Set-Something.ps1       # Exported function — no alias
    ├── Private/
    │   └── Invoke-InternalHelper.ps1  # NOT exported
    ├── Classes/
    │   ├── 01_BaseClass.Class.ps1  # Loaded first (numeric prefix = load order)
    │   └── 02_DerivedClass.Class.ps1
    └── Enums/
        └── Status.Enum.ps1

### Key conventions:
- Files in Public/    → exported via FunctionsToExport in .psd1
- Files in Private/   → NOT exported
- Classes/ and Enums/ → loaded by numeric prefix order
- Alias comments:     → `# Alias: gs` anywhere in a Public function file
                         gets extracted and written to AliasesToExport in .psd1
- Dev .psm1:          → uses dot-sourcing to load all individual files
- Build .psm1:        → all file contents merged in correct order (Enums → Classes → Private → Public)

## ════════════════════════════════════════
## PSMODULEFACTORY — FEATURES TO IMPLEMENT
## ════════════════════════════════════════

### 1. BUILD  (Merge → Distribute)
   - Merge all source files into a single .psm1 in correct load order:
     Enums/ → Classes/ (sorted by numeric prefix) → Private/ → Public/
   - Extract `# Alias: <name>` comments from Public/*.ps1
   - Update .psd1:
       • FunctionsToExport = all function names from Public/*.ps1
       • AliasesToExport   = all aliases extracted from # Alias: comments
   - Strip development-only dot-source lines from .psm1
   - Output artifact goes to a configurable /dist or /output folder

### 2. INITIALIZE  (Scaffold new module)
   - Create the full folder structure for a new module
   - Generate a dev .psm1 that dot-sources all files dynamically
   - Generate a starter .psd1 with sane defaults
   - Accept parameters: ModuleName, Author, Description, Version

### 3. SPLIT  (Distribute → Develop)
   - Take an existing monolithic .psm1 and reverse-engineer it back
     into individual files:
       • Each function → Public/ or Private/ (based on FunctionsToExport in .psd1)
       • Each class     → Classes/ with numeric prefix
       • Each enum      → Enums/
   - Regenerate the dev dot-sourcing .psm1

### 4. VERSION  (Semantic Versioning — OPTIONAL, must be opt-in)
   - Analyze Git history since last tag to determine bump type:
       • fix/patch commits  → PATCH bump (0.0.X)
       • feat commits       → MINOR bump (0.X.0)
       • BREAKING CHANGE    → MAJOR bump (X.0.0)
   - Follows Conventional Commits convention
   - Update ModuleVersion in .psd1
   - Create Git tag (optional, with -Tag switch)
   - Dry-run mode: show what version WOULD be set without changing anything

## ════════════════════════════════════════
## AGENT TEAM — SPAWN IN THIS ORDER
## ════════════════════════════════════════

---

### AGENT 1 — Architect
Model: claude-opus-4-6

Responsibility:
- Design the complete module architecture for PSModuleFactory itself
- Define the public API (function names, parameters, output objects)
- Define folder structure of PSModuleFactory as a project
- Specify internal helper conventions
- Define error handling strategy (terminating vs non-terminating errors)
- Define configuration handling (module-level config, parameter defaults)
- Write the ARCHITECTURE.md document

Deliverable:
  ARCHITECTURE.md containing:
  - Folder structure of PSModuleFactory
  - Public function signatures with parameter types
  - Data flow diagrams (ASCII)
  - Design decisions and rationale
  - Error handling conventions

---

### AGENT 2 — Core Engine Agent
Model: claude-sonnet-4-6
Depends on: Agent 1 (ARCHITECTURE.md)

Responsibility:
Implement the private/internal helper functions:
- Private/Resolve-ModuleSourcePaths.ps1   → discovers all source files in correct order
- Private/Get-FunctionNamesFromFile.ps1   → AST-based extraction of function names
- Private/Get-AliasesFromFile.ps1         → regex extraction of # Alias: comments
- Private/Merge-SourceFiles.ps1           → concatenates files with section headers
- Private/Split-PsFileContent.ps1         → splits monolithic psm1 back into functions/classes/enums
- Classes/ and Enums/ as needed

All functions must have full comment-based help.

---

### AGENT 3 — Public Functions Agent
Model: claude-sonnet-4-6
Depends on: Agent 1 (ARCHITECTURE.md), Agent 2 (Private functions exist)

Responsibility:
Implement all public-facing functions:
- Public/Build-PSModule.ps1          → orchestrates the full build
- Public/Initialize-PSModule.ps1     → scaffolds a new module
- Public/Split-PSModule.ps1          → splits monolithic module into dev structure
- Public/Update-PSModuleVersion.ps1  → semantic versioning (with -WhatIf support)

Each function must:
- Have full comment-based help with .EXAMPLE blocks
- Support -WhatIf and -Confirm where state changes occur
- Support -Verbose for detailed progress output
- Return structured output objects (PSCustomObject), not raw strings
- Follow Verb-Noun PowerShell naming conventions

---

### AGENT 4 — Manifest & Dev Experience Agent
Model: claude-sonnet-4-6
Depends on: Agent 3

Responsibility:
- Create PSModuleFactory.psd1 (module manifest)
- Create PSModuleFactory.psm1 (dev version — dot-sources all files)
- Create /dist build script that uses PSModuleFactory to build ITSELF
  (dogfooding: PSModuleFactory builds PSModuleFactory)
- Write .github/workflows/build.yml — GitHub Actions pipeline:
    • Trigger: push to main
    • Steps: Pester tests → Build via PSModuleFactory → Publish artifact

---

### AGENT 5 — Test Agent
Model: claude-sonnet-4-6
Depends on: Agent 2, Agent 3

Responsibility:
Write Pester v5 tests for all functions:
- Tests/Unit/Private/   → unit tests for all private helpers
- Tests/Unit/Public/    → unit tests for all public functions (mock filesystem)
- Tests/Integration/    → end-to-end: scaffold → add files → build → verify output
- Tests/Fixtures/       → sample module files used as test input

Test coverage targets:
- All happy paths
- Edge cases: empty folders, missing psd1, no public functions, circular aliases
- -WhatIf behavior (no filesystem changes)
- Version bump logic (mock git log output)

---

### AGENT 6 — Documentation Agent
Model: claude-sonnet-4-6
Depends on: All agents complete

Responsibility:
- README.md with:
    • Badges (PowerShell Gallery, License, CI Status)
    • Quick start (Install → Initialize → Build workflow)
    • Feature overview with code examples
    • Folder structure diagram
- CHANGELOG.md (initial 0.1.0 entry)
- docs/Build-PSModule.md          → extended docs per function
- docs/Split-PSModule.md
- docs/Initialize-PSModule.md
- docs/Update-PSModuleVersion.md
- docs/ConventionalCommits.md     → guide for semantic versioning

## ════════════════════════════════════════
## ORCHESTRATOR RULES
## ════════════════════════════════════════

1. Run Agent 1 FIRST. Do not proceed until ARCHITECTURE.md is written.
2. Share ARCHITECTURE.md as context with every subsequent agent.
3. Run Agent 2 and Agent 3 sequentially (3 needs 2's private functions).
4. Agents 4, 5, and 6 can run in parallel after Agent 3 completes.
5. After all agents complete, verify:
   - PSModuleFactory can build ITSELF (run the dist script)
   - All Pester tests pass
   - README accurately reflects the implemented API
6. Report any conflicts between agents and resolve before finalizing.

## ════════════════════════════════════════
## FINAL DELIVERABLE CHECKLIST
## ════════════════════════════════════════

[ ] ARCHITECTURE.md
[ ] PSModuleFactory.psd1 (dev manifest)
[ ] PSModuleFactory.psm1 (dev dot-sourcing version)
[ ] Public/Build-PSModule.ps1
[ ] Public/Initialize-PSModule.ps1
[ ] Public/Split-PSModule.ps1
[ ] Public/Update-PSModuleVersion.ps1
[ ] Private/ — all internal helpers
[ ] Tests/ — full Pester v5 suite
[ ] dist/ — self-build script
[ ] .github/workflows/build.yml
[ ] README.md
[ ] CHANGELOG.md
[ ] docs/ — per-function documentation

## ════════════════════════════════════════
## CONSTRAINTS & STANDARDS
## ════════════════════════════════════════

- PowerShell 7.2+ minimum (use modern syntax)
- No external dependencies beyond Pester (for tests)
- Git is optional runtime dependency for Update-PSModuleVersion only
- All code must pass PSScriptAnalyzer with zero warnings
- Encoding: UTF-8 with BOM for .ps1 files (Windows compatibility)
- Line endings: CRLF
- Indentation: 4 spaces
