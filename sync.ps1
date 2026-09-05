# ==================================================
#  NIGHT OWL  <->  GITHUB   sync
#  Ашиглах: sync.bat дээр давхар товш
# ==================================================

$ErrorActionPreference = 'Continue'
Set-Location -Path $PSScriptRoot

$WebPort = 5556

function Line { Write-Host "  --------------------------------------" -ForegroundColor DarkGray }
function Bye  { Write-Host ""; Read-Host "  Хаахын тулд Enter дар" | Out-Null }

Write-Host ""
Write-Host "  NIGHT OWL  <->  GITHUB" -ForegroundColor Cyan
Write-Host "  ======================" -ForegroundColor Cyan
Write-Host ""

$branch = (git rev-parse --abbrev-ref HEAD).Trim()
Write-Host "  Салбар: $branch" -ForegroundColor DarkGray
Write-Host ""

# ---------- ЦЭС ----------
Write-Host "  Юу хиймээр байна?" -ForegroundColor White
Write-Host ""
Write-Host "    1) ТАТАХ     " -ForegroundColor Cyan -NoNewline
Write-Host "- GitHub дээрх шинэ өөрчлөлтийг авах" -ForegroundColor Gray
Write-Host "    2) ИЛГЭЭХ    " -ForegroundColor Green -NoNewline
Write-Host "- миний өөрчлөлтийг GitHub руу явуулах" -ForegroundColor Gray
Write-Host "    3) АЖИЛЛУУЛАХ" -ForegroundColor Magenta -NoNewline
Write-Host "- аппыг Chrome дээр нээх" -ForegroundColor Gray
Write-Host ""
Write-Host "    0) Гарах" -ForegroundColor DarkGray
Write-Host ""
$choice = (Read-Host "  Сонголт").Trim()

if ($choice -eq '0' -or $choice -eq '') { exit 0 }

if ($choice -notin @('1','2','3')) {
    Write-Host ""
    Write-Host "  1, 2 эсвэл 3 гэж бич." -ForegroundColor Yellow
    Bye; exit 1
}

# ==================================================
#  3) АЖИЛЛУУЛАХ
# ==================================================
if ($choice -eq '3') {
    Write-Host ""
    Line

    $busy = $null
    try { $busy = Get-NetTCPConnection -LocalPort $WebPort -State Listen -ErrorAction Stop } catch { $busy = $null }

    if ($busy) {
        Write-Host "  Апп аль хэдийн ажиллаж байна." -ForegroundColor Yellow
        Write-Host "  http://localhost:$WebPort" -ForegroundColor Blue
        Write-Host ""
        Write-Host "  Дахин асаах бол хуучин хар цонхон дээр 'q' дараад" -ForegroundColor DarkGray
        Write-Host "  дахин оролдоно уу." -ForegroundColor DarkGray
        Bye; exit 0
    }

    Write-Host "  АППЫГ АСААЖ БАЙНА..." -ForegroundColor Magenta
    Line
    Write-Host ""
    Write-Host "  Шинэ цонх нээгдэнэ. Эхний удаа 1 орчим минут болно." -ForegroundColor Gray
    Write-Host "  Хаяг: http://localhost:$WebPort" -ForegroundColor Blue
    Write-Host ""
    Write-Host "  Тэр цонхон дээр:" -ForegroundColor White
    Write-Host "    r  - хурдан шинэчлэх (hot reload)" -ForegroundColor Gray
    Write-Host "    R  - бүтнээр дахин ачаалах" -ForegroundColor Gray
    Write-Host "    q  - аппыг унтраах" -ForegroundColor Gray
    Write-Host ""

    $inner = "Set-Location '$PSScriptRoot'; flutter run -d chrome --web-port $WebPort --dart-define=DEVICE_PREVIEW=false"
    Start-Process -FilePath 'powershell.exe' -WorkingDirectory $PSScriptRoot -ArgumentList @(
        '-NoExit','-NoProfile','-ExecutionPolicy','Bypass','-Command', $inner
    )

    Write-Host "  Асаалаа. Энэ цонхыг хааж болно." -ForegroundColor Green
    Bye; exit 0
}

# ==================================================
#  1) ТАТАХ
# ==================================================
if ($choice -eq '1') {
    Write-Host ""
    Line
    Write-Host "  ТАТАЖ БАЙНА..." -ForegroundColor Cyan
    Line
    Write-Host ""

    $before = (git rev-parse HEAD).Trim()

    git pull --rebase --autostash origin $branch
    if ($LASTEXITCODE -ne 0) {
        Write-Host ""
        Write-Host "  ЗӨРЧИЛ ГАРЛАА (conflict)." -ForegroundColor Red
        Write-Host "  Та хоёр нэг файлын нэг мөрийг зэрэг зассан байна." -ForegroundColor Yellow
        Write-Host ""
        $ab = (Read-Host "  Буцааж хуучин байдалд оруулах уу? (T/u)").Trim().ToLower()
        if ($ab -eq '' -or $ab -eq 't' -or $ab -eq 'y' -or $ab -eq 'tiim') {
            git rebase --abort
            Write-Host "  Буцаалаа. Юу ч алдагдаагүй." -ForegroundColor Green
            Write-Host "  Claude-д хэлээд зөрчлийг засуулаарай." -ForegroundColor Yellow
        }
        Bye; exit 1
    }

    $after = (git rev-parse HEAD).Trim()

    Write-Host ""
    if ($before -eq $after) {
        Write-Host "  Шинэ өөрчлөлт алга. Чи хамгийн сүүлийн хувилбартай." -ForegroundColor Green
        Bye; exit 0
    }

    Write-Host "  ШИНЭ ӨӨРЧЛӨЛТ ОРЖ ИРЛЭЭ:" -ForegroundColor Green
    Write-Host ""
    git log --oneline --no-decorate "$before..$after"
    Write-Host ""

    $files = git diff --name-only $before $after
    Write-Host "  Өөрчлөгдсөн файл: $($files.Count)" -ForegroundColor DarkGray

    if ($files -match 'pubspec\.(yaml|lock)') {
        Write-Host ""
        Write-Host "  ! Багц (package) өөрчлөгдсөн байна." -ForegroundColor Yellow
        Write-Host "  ! Аппаа дахин асаахаас өмнө ажиллуул:  flutter pub get" -ForegroundColor Yellow
    } else {
        Write-Host ""
        Write-Host "  Аппын цонхон дээр 'R' дарж дахин ачаалла." -ForegroundColor Yellow
    }

    $ahead = (git rev-list --count "origin/$branch..HEAD").Trim()
    if ([int]$ahead -gt 0) {
        Write-Host ""
        Write-Host "  Санамж: чамд илгээгээгүй $ahead өөрчлөлт байна." -ForegroundColor Yellow
        Write-Host "  Дахин нээгээд '2' (ИЛГЭЭХ) сонго." -ForegroundColor Yellow
    }

    Bye; exit 0
}

# ==================================================
#  2) ИЛГЭЭХ
# ==================================================
$changes = git status --porcelain
$ahead0  = (git rev-list --count "origin/$branch..HEAD").Trim()

if ([string]::IsNullOrWhiteSpace($changes) -and [int]$ahead0 -eq 0) {
    Write-Host ""
    Write-Host "  Илгээх зүйл алга. Бүх зүйл GitHub дээр байна." -ForegroundColor Green
    Bye; exit 0
}

if (-not [string]::IsNullOrWhiteSpace($changes)) {
    Write-Host ""
    Write-Host "  Өөрчлөгдсөн файлууд:" -ForegroundColor White
    git status --short
    Write-Host ""

    $msg = (Read-Host "  Юу өөрчилсөн бэ? (Enter = огноо)").Trim()
    if ([string]::IsNullOrWhiteSpace($msg)) {
        $msg = "Шинэчлэлт " + (Get-Date -Format "yyyy-MM-dd HH:mm")
    }

    git add -A
    git commit -m $msg
    if ($LASTEXITCODE -ne 0) {
        Write-Host ""
        Write-Host "  Хадгалж чадсангүй." -ForegroundColor Red
        Bye; exit 1
    }
}

# Нөгөө хүний өөрчлөлтийг эхлээд авна — тэгэхгүй бол push татгалзана
Write-Host ""
Line
Write-Host "  Эхлээд нөгөө талын өөрчлөлтийг татаж байна..." -ForegroundColor DarkGray
Line

git pull --rebase --autostash origin $branch
if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "  ЗӨРЧИЛ ГАРЛАА (conflict)." -ForegroundColor Red
    Write-Host "  Та хоёр нэг файлын нэг мөрийг зэрэг зассан байна." -ForegroundColor Yellow
    Write-Host ""
    $ab = (Read-Host "  Буцааж хуучин байдалд оруулах уу? (T/u)").Trim().ToLower()
    if ($ab -eq '' -or $ab -eq 't' -or $ab -eq 'y' -or $ab -eq 'tiim') {
        git rebase --abort
        Write-Host "  Буцаалаа. Чиний өөрчлөлт хадгалагдсан хэвээр." -ForegroundColor Green
        Write-Host "  Claude-д хэлээд зөрчлийг засуулаарай." -ForegroundColor Yellow
    }
    Bye; exit 1
}

Write-Host ""
Write-Host "  GitHub руу илгээж байна..." -ForegroundColor DarkGray

git push origin $branch
if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "  ИЛГЭЭЖ ЧАДСАНГҮЙ." -ForegroundColor Red
    Write-Host "  Интернэт эсвэл GitHub нэвтрэлтээ шалгана уу." -ForegroundColor Yellow
    Bye; exit 1
}

Write-Host ""
Write-Host "  БЭЛЭН! GitHub руу илгээгдлээ." -ForegroundColor Green
Write-Host "  https://github.com/danzkaravjaa23-svg/night-owl/tree/$branch" -ForegroundColor Blue
Bye
