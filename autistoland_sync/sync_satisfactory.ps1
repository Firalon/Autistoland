# Script de synchronisation automatique Satisfactory <-> GitHub
# 100% portable : aucune information personnelle ni chemin en dur
$ErrorActionPreference = "Continue"

$ScriptDir = $PSScriptRoot
if ((Test-Path (Join-Path $ScriptDir "..\save.sav")) -or (Test-Path (Join-Path $ScriptDir "..\.git"))) {
    $SaveDir = (Resolve-Path (Join-Path $ScriptDir "..")).Path
} else {
    $SaveDir = $ScriptDir
}

$BackupDir = Join-Path $SaveDir "backups"
$SteamAppId = "526870"
$ProcessName = "FactoryGameSteam"

Set-Location $SaveDir

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "   SATISFACTORY - AUTO SYNC GITHUB                        " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host ""

# 0. S'assurer que seuls save.sav et le dossier autistoland_sync sont suivis par Git
$ExcludeFile = Join-Path $SaveDir ".git\info\exclude"
if (Test-Path (Split-Path $ExcludeFile)) {
    @"
/*
!/save.sav
!/autistoland_sync/
!/autistoland_sync/**
"@ | Set-Content $ExcludeFile -Encoding UTF8
}

# Creer ou mettre a jour automatiquement le raccourci sur le Bureau
$Desktop = [Environment]::GetFolderPath("Desktop")
$ShortcutPath = Join-Path $Desktop "Satisfactory (Auto-Sync).lnk"
$BatPath = Join-Path $ScriptDir "Lancer_Satisfactory_Sync.bat"
if (-not (Test-Path $ShortcutPath)) {
    try {
        $wsh = New-Object -ComObject WScript.Shell
        $sc = $wsh.CreateShortcut($ShortcutPath)
        $sc.TargetPath = $BatPath
        $sc.WorkingDirectory = $ScriptDir
        $steamInstall = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Steam App 526870" -ErrorAction SilentlyContinue).InstallLocation
        if ($steamInstall -and (Test-Path "$steamInstall\FactoryGameSteam.exe")) {
            $sc.IconLocation = "$steamInstall\FactoryGameSteam.exe,0"
        }
        $sc.Description = "Lance Satisfactory avec synchronisation automatique GitHub (Pull avant, Push apres)"
        $sc.Save()
        Write-Host "[INIT] Raccourci 'Satisfactory (Auto-Sync)' cree sur le Bureau !" -ForegroundColor Green
    } catch {}
}

# 1. Creation d'un dossier de backup local de securite (ignore par Git)
if (-not (Test-Path $BackupDir)) {
    New-Item -ItemType Directory -Path $BackupDir | Out-Null
}

function Backup-SaveFile([string]$Tag) {
    if (Test-Path "$SaveDir\save.sav") {
        $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
        $dest = Join-Path $BackupDir "save_${timestamp}_${Tag}.sav"
        Copy-Item "$SaveDir\save.sav" $dest -Force
        # Garder uniquement les 15 derniers backups pour ne pas prendre de place
        Get-ChildItem $BackupDir -Filter "save_*.sav" |
            Sort-Object LastWriteTime -Descending |
            Select-Object -Skip 15 |
            Remove-Item -Force -ErrorAction SilentlyContinue
    }
}

# 2. Recuperation de la derniere sauvegarde sur GitHub (PULL)
Write-Host "[1/3] Verification des mises a jour sur GitHub..." -ForegroundColor Yellow
Backup-SaveFile "avant_pull"

git fetch origin main
if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERREUR] Impossible de contacter GitHub (verifie ta connexion)." -ForegroundColor Red
    Read-Host "Appuie sur Entree pour lancer le jeu quand meme ou ferme la fenetre"
} else {
    $localStatus = git status --porcelain save.sav
    $localHead = git rev-parse HEAD
    $remoteHead = git rev-parse origin/main

    if ($localHead -ne $remoteHead) {
        if ($localStatus) {
            Write-Host "[ATTENTION] Ta save.sav locale a ete modifiee ET une nouvelle save est sur GitHub !" -ForegroundColor Magenta
            Write-Host "Une copie de ta save locale a ete mise de cote dans : $BackupDir" -ForegroundColor Gray
            $choice = Read-Host "Taper [G] pour prendre celle de GitHub (recommande), ou [L] pour garder la tienne"
            if ($choice -notmatch "^[Ll]") {
                git checkout -- save.sav
                git pull --ff-only origin main
                Write-Host "[OK] Sauvegarde GitHub recuperee avec succes !" -ForegroundColor Green
            } else {
                Write-Host "[INFO] Sauvegarde locale conservee." -ForegroundColor Yellow
            }
        } else {
            git pull --ff-only origin main
            Write-Host "[OK] Nouvelle sauvegarde telechargee depuis GitHub !" -ForegroundColor Green
        }
    } else {
        Write-Host "[OK] Ta sauvegarde est deja a jour avec GitHub." -ForegroundColor Green
    }
}

Write-Host ""
# 3. Lancement de Satisfactory
$runningProc = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue
if (-not $runningProc) {
    Write-Host "[2/3] Lancement de Satisfactory via Steam..." -ForegroundColor Yellow
    Start-Process "steam://rungameid/$SteamAppId"
    
    Write-Host "En attente du demarrage du jeu..." -ForegroundColor Gray
    $timeout = 90
    $elapsed = 0
    while (-not $runningProc -and $elapsed -lt $timeout) {
        Start-Sleep -Seconds 2
        $elapsed += 2
        $runningProc = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue
    }
}

if ($runningProc) {
    Write-Host "[EN JEU] Satisfactory est en cours d'execution." -ForegroundColor Cyan
    Write-Host "         Ne ferme pas cette fenetre : le push se fera tout seul quand tu quitteras le jeu !" -ForegroundColor Gray
    Wait-Process -Name $ProcessName
    Write-Host ""
    Write-Host "Fermeture du jeu detectee. Attente de 3 secondes pour la finalisation des fichiers..." -ForegroundColor Gray
    Start-Sleep -Seconds 3
} else {
    Write-Host "[ATTENTION] Le lancement de Satisfactory n'a pas ete detecte." -ForegroundColor Yellow
    Read-Host "Appuie sur Entree une fois que tu as fini de jouer pour envoyer la sauvegarde"
}

# 4. Envoi de la sauvegarde sur GitHub (PUSH)
Write-Host ""
Write-Host "[3/3] Verification et envoi de la sauvegarde sur GitHub..." -ForegroundColor Yellow

$changes = git status --porcelain save.sav
if (-not $changes) {
    Write-Host "[OK] Aucun changement sur save.sav, rien a envoyer." -ForegroundColor Green
    Start-Sleep -Seconds 3
    exit 0
}

Backup-SaveFile "avant_push"

$playerName = (git config user.name)
if (-not $playerName) { $playerName = $env:USERNAME }
$dateStr = Get-Date -Format "dd/MM/yyyy HH:mm"

git add save.sav
git commit -m "Auto-save update ($dateStr - $playerName)"

# Verifier si le pote a push pendant qu'on jouait
git fetch origin main
$remoteHeadAfter = git rev-parse origin/main
$mergeBase = git merge-base HEAD origin/main

if ($remoteHeadAfter -ne $mergeBase) {
    Write-Host "[ATTENTION] Une autre sauvegarde a ete push pendant que tu jouais !" -ForegroundColor Red
    Write-Host "Ta sauvegarde est en securite dans le commit local et dans $BackupDir." -ForegroundColor Yellow
    $forceChoice = Read-Host "Taper [O] pour ecraser avec ta sauvegarde actuelle sur GitHub, ou [N] pour annuler"
    if ($forceChoice -match "^[OoYy]") {
        git push --force-with-lease origin main
    } else {
        Write-Host "Push annule. Tu pourras resoudre avec ton pote." -ForegroundColor Yellow
        Read-Host "Appuie sur Entree pour fermer"
        exit 1
    }
} else {
    git push origin main
}

if ($LASTEXITCODE -eq 0) {
    Write-Host "==========================================================" -ForegroundColor Green
    Write-Host "   [SUCCES] save.sav envoyee sur GitHub avec succes !     " -ForegroundColor Green
    Write-Host "==========================================================" -ForegroundColor Green
    Start-Sleep -Seconds 4
} else {
    Write-Host "==========================================================" -ForegroundColor Red
    Write-Host "   [ERREUR] Echec du git push vers GitHub.                " -ForegroundColor Red
    Write-Host "==========================================================" -ForegroundColor Red
    Read-Host "Appuie sur Entree pour fermer"
}
