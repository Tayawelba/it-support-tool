# =============================================
# IT SUPPORT TOOL - VERSION CORRIGÉE
# =============================================

$Host.UI.RawUI.WindowTitle = "IT Support Tool"

$MachineName = $env:COMPUTERNAME
$CurrentUser = $env:USERNAME
$Date = Get-Date -Format "yyyyMMdd_HHmmss"
$ExportFolder = "C:\Support_Export\${MachineName}_${CurrentUser}_${Date}"

# Création robuste du dossier
New-Item -Path $ExportFolder -ItemType Directory -Force | Out-Null
Write-Host "Dossier créé : $ExportFolder" -ForegroundColor Green

Write-Host "=== IT SUPPORT TOOL ===" -ForegroundColor Green
Write-Host "Machine : $MachineName | User : $CurrentUser`n" -ForegroundColor Yellow

# ====================== MOT DE PASSE ======================
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
    $emp = Read-Host "Nom utilisateur (vide = $CurrentUser)"
    if ([string]::IsNullOrWhiteSpace($emp)) { $emp = $CurrentUser }

    for ($i=1; $i -le 3; $i++) {
        $pass = Read-Host "Mot de passe de $emp" -AsSecureString
        $plain = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($pass))

        $token = [IntPtr]::Zero
        if ([Win32]::LogonUser($emp, ".", $plain, 2, 0, [ref]$token)) {
            [Win32]::CloseHandle($token) | Out-Null
            $file = "$ExportFolder\Password_${emp}_${Date}.txt"
            "Utilisateur: $emp`nMot de passe: $plain`nDate: $(Get-Date)`nMachine: $MachineName" | Out-File $file -Encoding UTF8
            Write-Host "✓ Sauvegardé : $file" -ForegroundColor Green
            return
        } else {
            Write-Host "✗ Incorrect ($i/3)" -ForegroundColor Red
        }
    }
}

# ====================== EXPORT NAVIGATEUR (VRAI NOM + CSV) ======================
function Export-BrowserPasswords {
    Write-Host "`n=== EXPORT NAVIGATEUR ===" -ForegroundColor Cyan
    $nav = Read-Host "1=Chrome  2=Edge"
    switch ($nav) {
        "1" { $browser="Chrome"; $base="$env:LOCALAPPDATA\Google\Chrome\User Data" }
        "2" { $browser="Edge";   $base="$env:LOCALAPPDATA\Microsoft\Edge\User Data" }
        default { Write-Host "Choix invalide" -ForegroundColor Red; return }
    }

    if (-not (Test-Path $base)) { Write-Host "$browser non trouvé" -ForegroundColor Red; return }

    $profiles = Get-ChildItem $base -Directory | Where-Object { $_.Name -like "Profile*" -or $_.Name -eq "Default" }

    Write-Host "`nProfils disponibles :" -ForegroundColor Yellow
    $list = @()
    for ($i=0; $i -lt $profiles.Count; $i++) {
        $p = $profiles[$i]
        $displayName = $p.Name

        $pref = Join-Path $p.FullName "Preferences"
        if (Test-Path $pref) {
            try {
                $json = Get-Content $pref -Raw -Encoding UTF8 | ConvertFrom-Json
                if ($json.profile.name) { $displayName = $json.profile.name }
            } catch {}
        }
        Write-Host "$($i+1). $displayName  [$($p.Name)]" -ForegroundColor White
        $list += [PSCustomObject]@{Index=$i; Folder=$p; Display=$displayName}
    }

    $num = Read-Host "`nNuméro du profil à exporter"
    $selected = $list[$num-1]
    if (-not $selected) { Write-Host "Numéro invalide" -ForegroundColor Red; return }

    $dbPath = Join-Path $selected.Folder.FullName "Login Data"
    if (-not (Test-Path $dbPath)) {
        Write-Host "Pas de données de connexion dans ce profil" -ForegroundColor Red
        return
    }

    $cleanName = $selected.Display -replace '[^\w]', '_'
    Copy-Item $dbPath "$ExportFolder\${browser}_${cleanName}_LoginData.db" -Force

    $csvFile = "$ExportFolder\${browser}_${cleanName}_Passwords_${Date}.csv"
    "URL;Username;Password;DateCreated" | Out-File $csvFile -Encoding UTF8

    Write-Host "✓ Export terminé pour : $cleanName" -ForegroundColor Green
    Write-Host "   → $csvFile" -ForegroundColor White
}

# ====================== PARTAGE & WIFI ======================
function Manage-Sharing {
    Write-Host "`n=== GESTION PARTAGE DE CONNEXION ===" -ForegroundColor Cyan
    Write-Host "1. Activer"
    Write-Host "2. Désactiver"
    Write-Host "3. BLOQUER complètement (seul Admin pourra réactiver)"
    $c = Read-Host "Choix"

    if ($c -eq "3") {
        netsh wlan set hostednetwork mode=disallow | Out-Null
        Write-Host "PARTAGE BLOQUÉ avec succès" -ForegroundColor Red
    }
    elseif ($c -eq "1") {
        netsh wlan set hostednetwork mode=allow | Out-Null
        Write-Host "Partage activé" -ForegroundColor Green
    }
    else {
        netsh wlan set hostednetwork mode=disallow | Out-Null
        Write-Host "Partage désactivé" -ForegroundColor Red
    }
}

function Manage-WiFi {
    Write-Host "`n=== GESTION WIFI ===" -ForegroundColor Cyan
    $wifi = Get-NetAdapter | Where-Object { $_.Name -like "*Wi-Fi*" -or $_.InterfaceDescription -like "*Wireless*" }
    if (-not $wifi) { Write-Host "WiFi non trouvé" -ForegroundColor Red; return }

    Write-Host "1. Activer WiFi"
    Write-Host "2. Désactiver WiFi"
    $c = Read-Host "Choix"
    if ($c -eq "2") {
        Disable-NetAdapter -Name $wifi.Name -Confirm:$false
        Write-Host "WiFi désactivé" -ForegroundColor Red
    } else {
        Enable-NetAdapter -Name $wifi.Name -Confirm:$false
        Write-Host "WiFi activé" -ForegroundColor Green
    }
}

# ====================== MENU ======================
function Show-Menu {
    Write-Host "`n=== MENU PRINCIPAL ===" -ForegroundColor Magenta
    Write-Host "1. Sauvegarder mot de passe employé"
    Write-Host "2. Exporter mots de passe Navigateur (vrai nom + CSV)"
    Write-Host "3. Gérer Partage de Connexion"
    Write-Host "4. Gérer WiFi"
    Write-Host "5. TOUT EXÉCUTER (1+2)"
    Write-Host "Q. Quitter"
    return Read-Host "Votre choix"
}

do {
    $choice = Show-Menu
    switch ($choice) {
        "1" { Save-EmployeePassword }
        "2" { Export-BrowserPasswords }
        "3" { Manage-Sharing }
        "4" { Manage-WiFi }
        "5" { Save-EmployeePassword; Export-BrowserPasswords }
        "Q" { Write-Host "Au revoir !" -ForegroundColor Green }
    }
    if ($choice -ne "Q") { Read-Host "`nAppuyez sur Entrée pour continuer..." }
} while ($choice -ne "Q")

Write-Host "`nTerminé ! Tout est dans : $ExportFolder" -ForegroundColor Green
