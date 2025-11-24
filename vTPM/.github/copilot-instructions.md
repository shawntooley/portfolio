Purpose
This repository contains a small set of PowerShell/PowerCLI automation scripts used to enumerate VMs and add a virtual TPM (vTPM) to guest VMs in a vCenter environment. The guidance below captures the project's conventions, runtime expectations, critical files, and safe editing patterns so an AI coding agent can be productive immediately.

**Repository Overview**
- **Main language**: PowerShell (PowerCLI).
- **Primary scripts**: `List_VMs_In_Folder.ps1`, `vTPM_Install.ps1`, `vTPM_Install_V2.ps1`, `vTPM_Install_V3.ps1`, `vTPM_Install_V4.ps1`.
- **Purpose**: `List_VMs_In_Folder.ps1` produces a `VMList.txt` for batch operations; the `vTPM_Install*.ps1` scripts iterate VM names and add a vTPM using VMware PowerCLI commands.

**How to run (developer workflow)**
- Ensure VMware PowerCLI is installed:
  - `pwsh` (or Windows PowerShell) then `Install-Module -Name VMware.PowerCLI -Scope CurrentUser` (run once).
  - Optional: `Import-Module VMware.PowerCLI`.
- Typical execution flow:
  1. Run `.\List_VMs_In_Folder.ps1` to generate `VMList.txt` (default path: `C:\Users\seitech\Documents\VMList.txt`).
  2. Run `.\vTPM_Install_V4.ps1` (recommended latest) which reads that `VMList.txt`, adds vTPM, and writes `vTPM_Add_Log.txt`.
- Example command (from repo folder):
  - `pwsh -NoProfile -ExecutionPolicy RemoteSigned -File .\vTPM_Install_V4.ps1`

**Important runtime assumptions & hard-coded values**
- `vCenter` hostname is hard-coded as `vc.ohiogratings.com` in the scripts — do not modify silently. If you change it, update each script consistently.
- Paths expected by scripts (hard-coded):
  - VM list: `C:\Users\seitech\Documents\VMList.txt` (`$vmListFile`)
  - Log file: `C:\Users\seitech\Documents\vTPM_Add_Log.txt` (`$logFile`)
- Scripts prompt for credentials using `Get-Credential`; credentials are not stored in the repo.
- `Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false` is used to avoid TLS/ certificate prompts.

**Observable patterns and conventions to follow when editing**
- Top-of-file configuration: variables like `$vcServer`, `$vmListFile`, `$logFile`, `$NewCPU`, and `$NewMemoryGB` appear at the top of `vTPM_Install_V3.ps1`/`V4.ps1`. When adding options or flags, expose them as top-level variables (or parameters) to mirror style.
- Logging: scripts create a CSV header `"Date,VMName,Status,Message"` and append rows with a timestamp formatted `yyyy-MM-dd HH:mm:ss`. Preserve this header and format when modifying logging behavior.
- Error handling: `try { ... } catch { ... }` with exception text logged via `$_.Exception.Message`. Keep this pattern for consistent log parsing.
- Power operations: operations use `-Confirm:$false` and `-ErrorAction Stop` to force fail-fast behavior; preserve these flags unless adding an explicit interactive mode.
- VM checks: scripts check `if ($vm.ExtensionData.Config.Version -lt "vmx-14")` and `if ($vm.ExtensionData.Config.Firmware -ne "efi")` before making changes — keep these hardware/firmware checks or ask before removing.
- Wait loops: when powering off, scripts poll the VM's `PowerState` by re-calling `Get-VM` in a loop. Preserve this polling pattern if you modify power operations.

**Which file to change and how**
- Use `vTPM_Install_V4.ps1` as the canonical script for enhancements — it contains the most recent behavior (resizing + logging). If you introduce flags (dry-run, verbose, path overrides), add them as top variables and update the log format accordingly.
- If you must change hard-coded paths or the vCenter host, prompt the user for confirmation — these are environment-specific and likely intentional.

**Safety & security notes for agents**
- Never hardcode plaintext credentials in the repository. Keep `Get-Credential` usage or replace it with a documented, user-provided secret mechanism.
- Avoid changing `Set-PowerCLIConfiguration -InvalidCertificateAction Ignore` unless the maintainer asks — this was intentionally set to avoid TLS interruptions in the environment.

**Quick references (examples from repo)**
- CSV logging header: `"Date,VMName,Status,Message"` (see `vTPM_Install*.ps1`).
- Hardware check example: `if ($vm.ExtensionData.Config.Version -lt "vmx-14") { throw "Hardware version too low" }`.
- Add vTPM call: `New-VTpm -VM $vm -ErrorAction Stop`.

If anything here is unclear or you want the instructions to include more operational detail (for example: CI steps, preferred dry-run flags, or alternate log locations), tell me which area to expand and I will iterate.
