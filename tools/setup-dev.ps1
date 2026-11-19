# Encore Essentials: development setup for Windows.
# Clones (or updates) the repository and links its addon folders into WoW Forever's Interface\AddOns
# with directory junctions, so `git pull` updates the addon in game. Changes nothing it did not create:
# an existing addon folder that is not already our link is left alone.
#
# Run in PowerShell:
#   powershell -ExecutionPolicy Bypass -File setup-dev.ps1
# Options:
#   -RepoDir  where to clone (default C:\dev\Encore-Essentials)
#   -Forever  the WoW Forever game folder (default: found automatically)

param(
    [string]$RepoDir = "C:\dev\Encore-Essentials",
    [string]$Forever = ""
)
$ErrorActionPreference = "Stop"
$RepoUrl = "https://github.com/Detroph/Encore-Essentials.git"
$Addons = @("EncoreEssentials", "EncoreEssentials_DB", "EncoreEssentials_Stonks")

function Say($msg, $color = "Gray") { Write-Host $msg -ForegroundColor $color }

# 1. git
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Say "Git is not installed. Install it with:  winget install --id Git.Git -e" Yellow
    Say "or from https://git-scm.com/download/win, then open a new PowerShell window and run this script again." Yellow
    exit 1
}

# 2. clone or update
if (Test-Path (Join-Path $RepoDir ".git")) {
    Say "Updating $RepoDir"
    git -C $RepoDir pull --ff-only
} elseif (Test-Path $RepoDir) {
    Say "$RepoDir exists but is not a git clone. Choose another folder with -RepoDir." Red
    exit 1
} else {
    New-Item -ItemType Directory -Force -Path (Split-Path $RepoDir) | Out-Null
    Say "Cloning into $RepoDir"
    git clone $RepoUrl $RepoDir
}
if ($LASTEXITCODE -ne 0) { Say "git failed; see the message above." Red; exit 1 }

# 3. find the WoW Forever folder (the one that contains Interface/WTF or the game executable)
function Test-Forever($path) {
    if (-not $path -or -not (Test-Path $path)) { return $false }
    return (Test-Path (Join-Path $path "WTF")) -or (Test-Path (Join-Path $path "Interface")) -or
           (@(Get-ChildItem $path -Filter "Wow*.exe" -ErrorAction SilentlyContinue).Count -gt 0)
}
if (-not $Forever) {
    $roots = New-Object System.Collections.Generic.List[string]
    foreach ($key in @("HKLM:\SOFTWARE\WOW6432Node\Blizzard Entertainment\World of Warcraft",
                       "HKLM:\SOFTWARE\Blizzard Entertainment\World of Warcraft")) {
        $p = (Get-ItemProperty $key -ErrorAction SilentlyContinue).InstallPath
        if ($p) { $roots.Add((Split-Path ($p.TrimEnd('\')) -Parent)); $roots.Add($p.TrimEnd('\')) }
    }
    foreach ($drive in (Get-PSDrive -PSProvider FileSystem | Select-Object -ExpandProperty Root)) {
        foreach ($sub in @("Program Files (x86)\World of Warcraft", "Program Files\World of Warcraft",
                           "World of Warcraft", "Games\World of Warcraft", "Blizzard\World of Warcraft")) {
            $roots.Add((Join-Path $drive $sub))
        }
    }
    foreach ($root in ($roots | Select-Object -Unique)) {
        $candidate = Join-Path $root "_forever_"
        if (Test-Forever $candidate) { $Forever = $candidate; break }
    }
}
if (-not (Test-Forever $Forever)) {
    Say "Could not find the WoW Forever folder automatically." Yellow
    $Forever = (Read-Host "Paste the full path of your _forever_ folder").Trim('"', ' ')
    if (-not (Test-Forever $Forever)) { Say "That folder does not look like a WoW game folder: $Forever" Red; exit 1 }
}
Say "WoW Forever folder: $Forever" Green

# 4. junctions
$addonsDir = Join-Path $Forever "Interface\AddOns"
New-Item -ItemType Directory -Force -Path $addonsDir | Out-Null
foreach ($name in $Addons) {
    $link = Join-Path $addonsDir $name
    $target = Join-Path $RepoDir $name
    $item = Get-Item $link -ErrorAction SilentlyContinue
    if ($item) {
        if ($item.LinkType -eq "Junction" -and ((@($item.Target)[0]).TrimEnd('\') -ieq $target.TrimEnd('\'))) {
            Say "Already linked: $name" Green
        } else {
            Say "Skipped $name : $link already exists and is not a link to $target. Move or delete it yourself, then run this again." Yellow
        }
        continue
    }
    New-Item -ItemType Junction -Path $link -Target $target | Out-Null
    Say "Linked $name -> $target" Green
}

Say ""
Say "Done. Start WoW Forever, enable Encore Essentials, Encore-DB and Encore-Stonks in the AddOns list, then type /encore info." Cyan
Say "To update later: git -C `"$RepoDir`" pull   then /reload in game (restart the game if a .toc file changed)." Cyan
