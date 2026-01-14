<!-- Copilot instructions for AI coding agents working on this repository -->
# Repo intent
This repository is a personal Windows/IT automation portfolio of PowerShell scripts and small deploy helpers. The codebase is not a web app or service; treat it as a collection of operational scripts that are executed on Windows hosts.

# Quick architecture / layout
- Top-level PowerShell assets: multiple standalone scripts such as `Windows_11_Upgrade.ps1`, `Windows__Backup_Job_Report.ps1`, `Continuous_Port_Ping.ps1`.
- `Deploy_DHCP/`: contains CSV-driven DHCP deployment helpers (`Deploy-DhcpFromCsv.ps1`, `User_Deploy.ps1`).
- `vTPM/`: VM-related helpers and artifacts (`List_VMs_In_Folder.ps1`, `vTPM_Install_V4.ps1`, `VMList.txt`).

# What an agent should know
- This repo is Windows-centric. Most runnable files are PowerShell scripts intended to be executed on Windows (local or remote). Expect scripts to require elevated privileges.
- Many file names include spaces (e.g., `Install Google Chrome.ps1`). When referencing or executing, quote or escape paths.
- There is no unit-test framework or CI configuration in the repo. Changes are likely manual and validated by running scripts in a Windows environment.

# Developer workflows (concrete commands)
- Run a script locally (PowerShell):
```
# In an elevated PowerShell prompt
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\\Windows_11_Upgrade.ps1
```
- For scripts with spaces in the name:
```
& "./Install Google Chrome.ps1"
```
- For `Deploy_DHCP/Deploy-DhcpFromCsv.ps1`, run from the folder or specify full path; supply CSV input as documented in the header of that script.

# Project-specific conventions and patterns
- Scripts are standalone: avoid trying to refactor into modules unless requested — users maintain them as independent runnable artifacts.
- Prefer minimal, non-breaking edits. If changing behavior, add a clear changelog entry in the script header and preserve backward-compatible command-line parameters.
- Output is often plain text or log files (see `vTPM/vTPM_Add_Log.txt` and `vTPM/VMList.txt`). Preserve exact output formats if other scripts parse them.

# Integration points & external dependencies
- Scripts assume Windows host utilities (PowerShell core/cmdlets) and administrative privileges. They may call Windows APIs or cmdlets that are not present on non-Windows platforms.
- No external package manifests (no npm, pip, or NuGet files). If you add dependencies, include an explicit README note about installation and required Windows features.

# Guidance for code edits by an AI agent
- When editing scripts, run a quick static check for unintended changes to paths, quoting, and privileges.
- If you add new scripts, update this file and the top-level `README.md` with a one-line description and example invocation.
- Do not attempt to run or validate scripts in a non-Windows environment — indicate when verification requires Windows, elevation, or the Cosmos DB emulator (if added later).

# Files to reference for examples
- Root scripts: `Windows_11_Upgrade.ps1`, `Windows__Backup_Job_Report.ps1`, `Continuous_Port_Ping.ps1`.
- DHCP helpers: `Deploy_DHCP/Deploy-DhcpFromCsv.ps1`.
- VM helpers: `vTPM/List_VMs_In_Folder.ps1`, `vTPM/vTPM_Install_V4.ps1`.

# When uncertain, ask the user
- If a change requires privileged execution, access to real infrastructure, or assumptions about the target environment, stop and ask the repository owner before proceeding.

Please review and tell me which sections are unclear or need examples expanded.
