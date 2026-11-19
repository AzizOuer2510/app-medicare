# Lance le backend MediCare en mode dev sur PostgreSQL, accessible depuis le réseau Wi-Fi.
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\backend\start-dev-postgres.ps1
# Le mot de passe PostgreSQL est demandé en saisie masquée et n'est écrit nulle part.
[CmdletBinding()]
param(
    [string]$Database = 'app_medicare',
    [string]$User = 'postgres',
    [ValidateRange(1, 65535)][int]$Port = 8082
)
$ErrorActionPreference = 'Stop'
Push-Location $PSScriptRoot
try {
    $jdk = Get-ChildItem (Join-Path $env:USERPROFILE '.jdks') -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '21' } | Select-Object -First 1
    if ($jdk) {
        $env:JAVA_HOME = $jdk.FullName
        $env:Path = (Join-Path $jdk.FullName 'bin') + [IO.Path]::PathSeparator + $env:Path
    }
    if (-not $env:DB_PASSWORD) {
        $secure = Read-Host "Mot de passe PostgreSQL de l'utilisateur $User" -AsSecureString
        $env:DB_PASSWORD = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
            [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure))
    }
    $env:DB_URL = "jdbc:postgresql://localhost:5432/$Database"
    $env:DB_USERNAME = $User
    $env:SERVER_PORT = "$Port"
    $ip = (Get-NetIPAddress -AddressFamily IPv4 -InterfaceAlias 'Wi-Fi' -ErrorAction SilentlyContinue).IPAddress
    Write-Host "Base : $Database  |  API locale : http://localhost:$Port/api  |  API Wi-Fi : http://${ip}:$Port/api"
    mvn spring-boot:run "-Dspring-boot.run.profiles=dev,pg"
} finally {
    Pop-Location
}
