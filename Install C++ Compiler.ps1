<#
    This script will install MinGW-w64, which provides the g++ C++ compiler.
#>

try {
    Start-Process -FilePath "winget.exe" -ArgumentList "install --id mingw-w64 --accept-source-agreements --accept-package-agreements" -Verb RunAs -Wait
}
catch {
    Write-Output "Failed to install MinGW-w64."
}