#!/bin/bash
# ============================================================
#  NIGHT OWL  <->  GITHUB   (macOS хувилбар)
#  Windows дээрх sync.ps1 / sync.bat-ийн Mac хувилбар
# ============================================================

# --- Ажлын лавлахыг скриптийн байрлалаар тогтоох ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR" || { echo "Скриптийн фолдер руу орж чадсангүй."; read -r; exit 1; }

REPO_URL="https://github.com/danzkaravjaa23-svg/night-owl"

# --- Өнгө ---
R=$'\033[1;31m'   # улаан
G=$'\033[1;32m'   # ногоон
Y=$'\033[1;33m'   # шар
C=$'\033[1;36m'   # цэнхэр
D=$'\033[0;90m'   # бүдэг
B=$'\033[1m'      # тод
N=$'\033[0m'      # цэвэрлэх

red()   { echo "${R}$*${N}"; }
green() { echo "${G}$*${N}"; }
warn()  { echo "${Y}$*${N}"; }
info()  { echo "${C}$*${N}"; }
dim()   { echo "${D}$*${N}"; }

bye() {
  echo
  echo "${D}------------------------------------------${N}"
  printf "Хаахын тулд Enter дар "
  read -r _dummy
  exit "${1:-0}"
}

# --- git байгаа эсэх ---
if ! command -v git >/dev/null 2>&1; then
  red "git суулгаагүй байна."
  echo "Терминал дээр  xcode-select --install  гэж бичээд суулгана уу."
  bye 1
fi

# --- git репо мөн эсэх ---
if ! git rev-parse --git-dir >/dev/null 2>&1; then
  red "Энэ фолдер git репо биш байна."
  echo "sync.sh нь night-owl репогийн үндсэн фолдерт байх ёстой."
  dim "Одоогийн фолдер: $SCRIPT_DIR"
  bye 1
fi

# --- Салбар ---
BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)"
if [ -z "$BRANCH" ] || [ "$BRANCH" = "HEAD" ]; then
  red "Ямар ч салбар дээр байхгүй байна (detached HEAD)."
  echo "Засах:  git checkout night-owl-features"
  bye 1
fi

# --- Туслах шалгуурууд ---
in_rebase() {
  [ -d "$(git rev-parse --git-path rebase-merge)" ] || \
  [ -d "$(git rev-parse --git-path rebase-apply)" ]
}

# git-ийн англи алдааг монголоор тайлбарлах
explain_error() {
  local out="$1"
  case "$out" in
    *"Could not resolve host"*|*"unable to access"*|*"Failed to connect"*|*"Connection refused"*|*"timed out"*)
      red "ИНТЕРНЭТ ХОЛБОГДОХГҮЙ БАЙНА"
      echo "GitHub руу холбогдож чадсангүй. Wi-Fi-гаа шалгаад дахин оролдоно уу." ;;
    *"Authentication failed"*|*"could not read Username"*|*"could not read Password"*|*"Permission denied"*|*"403"*)
      red "GITHUB НЭВТРЭХ АЛДАА"
      echo "GitHub чамайг танихгүй байна. Нэвтрэх эрхээ шинэчлэх хэрэгтэй."
      dim "Хамгийн хялбар: терминал дээр  gh auth login  (эсвэл GitHub Desktop-оор нэг удаа нэвтэрнэ)" ;;
    *"couldn't find remote ref"*|*"does not appear to be a git repository"*)
      red "САЛБАР ОЛДСОНГҮЙ"
      echo "GitHub дээр '$BRANCH' нэртэй салбар алга байна." ;;
    *"index.lock"*)
      red "GIT ЗАВГҮЙ БАЙНА"
      echo "Өөр нэг git үйлдэл ажиллаж байна. Хэсэг хүлээгээд дахин оролдоно уу." ;;
    *"local changes"*|*"would be overwritten"*|*"unstaged changes"*)
      red "ХАДГАЛААГҮЙ ӨӨРЧЛӨЛТ САДАА БОЛЖ БАЙНА"
      echo "Эхлээд 2) ИЛГЭЭХ сонгож өөрчлөлтөө хадгална уу." ;;
    *)
      red "АЛДАА ГАРЛАА"
      echo "Git дараах юм хэлж байна:"
      dim "$out" ;;
  esac
}

# --- Зөрчил гарсан үед ---
handle_conflict() {
  echo
  red "  ЗӨРЧИЛ ГАРЛАА (conflict)"
  echo
  echo "  Та хоёр яг НЭГ мөрийг зэрэг зассан байна."
  echo "  Git аль нь зөв болохыг өөрөө шийдэж чадахгүй тул чамаас асууж байна."
  echo
  printf "  ${B}Буцааж хуучин байдалд оруулах уу? (T/u):${N} "
  read -r ans
  case "$ans" in
    [Uu]*|[Үү]*)
      echo
      warn "  За, зөрчлийг гараар засна."
      echo "  Зөрчилтэй файлууд:"
      git diff --name-only --diff-filter=U | sed 's/^/    • /'
      echo
      echo "  Файл бүрийг нээгээд  <<<<<<<  =======  >>>>>>>  тэмдэгтүүдийг устгаж,"
      echo "  зөв кодыг үлдээ. Дараа нь терминал дээр:"
      dim "    git add -A && git rebase --continue"
      echo
      dim "  Санаа зовох юм байхгүй — бүрэн буцаах бол:  git rebase --abort"
      ;;
    *)
      if git rebase --abort >/dev/null 2>&1; then
        echo
        green "  Буцаалаа — ЮУ Ч АЛДАГДААГҮЙ."
        echo "  Чиний өөрчлөлт бүгд байрандаа байна."
        echo "  Хамтрагчтайгаа ярилцаад дахин оролдоорой."
      else
        red "  Буцааж чадсангүй. Терминал дээр  git rebase --abort  гэж бичнэ үү."
      fi
      ;;
  esac
}

# --- Илгээгээгүй commit сануулах ---
check_unpushed() {
  local ahead
  ahead="$(git rev-list --count "origin/$BRANCH..HEAD" 2>/dev/null)"
  if [ -n "$ahead" ] && [ "$ahead" -gt 0 ] 2>/dev/null; then
    echo
    warn "  Санамж: илгээгээгүй $ahead commit байна."
    echo "  Дараа нь дахин нээгээд 2) ИЛГЭЭХ сонгоорой."
  fi
}

# ============================================================
#  1) ТАТАХ
# ============================================================
do_pull() {
  echo
  info "  GitHub-аас татаж байна..."
  echo

  OLD_REMOTE="$(git rev-parse "origin/$BRANCH" 2>/dev/null)"
  BEFORE="$(git rev-parse HEAD)"

  OUT="$(git pull --rebase --autostash origin "$BRANCH" 2>&1)"
  CODE=$?

  if [ $CODE -ne 0 ]; then
    if in_rebase; then
      handle_conflict
    else
      echo
      explain_error "$OUT"
    fi
    return
  fi

  NEW_REMOTE="$(git rev-parse "origin/$BRANCH" 2>/dev/null)"
  AFTER="$(git rev-parse HEAD)"

  RANGE=""
  if [ -n "$OLD_REMOTE" ] && [ "$OLD_REMOTE" != "$NEW_REMOTE" ]; then
    RANGE="$OLD_REMOTE..$NEW_REMOTE"
  elif [ "$BEFORE" != "$AFTER" ]; then
    RANGE="$BEFORE..$AFTER"
  fi

  if [ -z "$RANGE" ]; then
    green "  ЧИ ХАМГИЙН СҮҮЛИЙН ХУВИЛБАРТАЙ."
    echo "  GitHub дээр шинэ өөрчлөлт алга."
    check_unpushed
    return
  fi

  green "  ШИНЭ ӨӨРЧЛӨЛТ ОРЖ ИРЛЭЭ:"
  echo
  git log --no-merges --reverse \
      --pretty=format:"    ${C}•${N} %s  ${D}(%an, %ad)${N}" \
      --date=format:'%m/%d %H:%M' "$RANGE"
  echo
  echo

  CHANGED="$(git diff --name-only "$RANGE" 2>/dev/null)"
  FILECOUNT="$(printf '%s\n' "$CHANGED" | grep -c . )"
  dim "    Нийт $FILECOUNT файл өөрчлөгдсөн."
  echo

  if printf '%s\n' "$CHANGED" | grep -qE '^pubspec\.(yaml|lock)$'; then
    warn "  ЗААВАЛ: pubspec өөрчлөгдсөн байна."
    echo "  Терминал дээр эхлээд:"
    dim "    flutter pub get"
    echo "  Дараа нь аппаа бүрэн дахин эхлүүл."
  else
    info "  Аппын цонхон дээр  R  дарж дахин ачаалла."
  fi

  check_unpushed
}

# ============================================================
#  2) ИЛГЭЭХ
# ============================================================
do_push() {
  echo
  DIRTY="$(git status --porcelain)"
  AHEAD="$(git rev-list --count "origin/$BRANCH..HEAD" 2>/dev/null)"
  [ -z "$AHEAD" ] && AHEAD=0

  if [ -z "$DIRTY" ] && [ "$AHEAD" -eq 0 ] 2>/dev/null; then
    green "  ИЛГЭЭХ ЮМ АЛГА."
    echo "  Чи юу ч өөрчлөөгүй байна — бүх зүйл GitHub дээр байгаа."
    return
  fi

  if [ -n "$DIRTY" ]; then
    info "  Өөрчлөгдсөн файлууд:"
    echo
    git status --porcelain | while IFS= read -r line; do
      st="${line:0:2}"
      f="${line:3}"
      case "$st" in
        "??"*)   echo "    ${G}шинэ${N}     $f" ;;
        *D*)     echo "    ${R}устсан${N}   $f" ;;
        *)       echo "    ${Y}зассан${N}   $f" ;;
      esac
    done
    echo
  fi

  if [ "$AHEAD" -gt 0 ] 2>/dev/null; then
    dim "    (өмнө нь хадгалсан, илгээгээгүй $AHEAD commit бас байна)"
    echo
  fi

  if [ -n "$DIRTY" ]; then
    printf "  ${B}Юу өөрчилсөн бэ? (Enter = огноо):${N} "
    read -r MSG
    if [ -z "$MSG" ]; then
      MSG="Шинэчлэлт $(date '+%Y-%m-%d %H:%M')"
      dim "    -> \"$MSG\""
    fi
    echo

    if ! OUT="$(git add -A 2>&1)"; then
      explain_error "$OUT"; return
    fi

    OUT="$(git commit -m "$MSG" 2>&1)"
    if [ $? -ne 0 ]; then
      case "$OUT" in
        *"nothing to commit"*) dim "    (хадгалах шинэ зүйл олдсонгүй)" ;;
        *"Please tell me who you are"*|*"user.email"*)
          red "  GIT ЧАМАЙГ ТАНИХГҮЙ БАЙНА"
          echo "  Нэг удаа терминал дээр дараах хоёрыг бичээрэй:"
          dim "    git config --global user.name \"Чиний нэр\""
          dim "    git config --global user.email \"чиний@mail.com\""
          return ;;
        *) explain_error "$OUT"; return ;;
      esac
    else
      green "  Хадгаллаа: $MSG"
    fi
    echo
  fi

  # push татгалзахаас сэргийлж эхлээд татна
  info "  Эхлээд GitHub-аас татаж байна (мөргөлдөхөөс сэргийлж)..."
  OUT="$(git pull --rebase --autostash origin "$BRANCH" 2>&1)"
  if [ $? -ne 0 ]; then
    if in_rebase; then
      handle_conflict
    else
      echo
      explain_error "$OUT"
    fi
    return
  fi

  info "  GitHub руу илгээж байна..."
  OUT="$(git push origin "$BRANCH" 2>&1)"
  if [ $? -ne 0 ]; then
    echo
    case "$OUT" in
      *"rejected"*|*"non-fast-forward"*|*"fetch first"*)
        red "  GITHUB ТАТГАЛЗЛАА"
        echo "  Хамтрагч чинь яг одоо шинэ юм илгээсэн бололтой."
        echo "  Цэс рүү буцаад эхлээд 1) ТАТАХ, дараа нь 2) ИЛГЭЭХ хий." ;;
      *) explain_error "$OUT" ;;
    esac
    return
  fi

  echo
  green "  ==============================="
  green "            БЭЛЭН!"
  green "  ==============================="
  echo
  echo "  Чиний өөрчлөлт GitHub дээр орлоо."
  echo "  Салбар: ${B}$BRANCH${N}"
  echo "  Холбоос: ${C}$REPO_URL/tree/$BRANCH${N}"
}

# ============================================================
#  3) АЖИЛЛУУЛАХ
# ============================================================
PORT=5556

do_run() {
  echo
  if ! command -v flutter >/dev/null 2>&1; then
    red "  FLUTTER ОЛДСОНГҮЙ"
    echo "  Терминал дээр  flutter --version  гэж шалгаад үзээрэй."
    dim "  Суулгах заавар: https://docs.flutter.dev/get-started/install/macos"
    return
  fi

  # --- Порт завгүй бол ---
  if lsof -nP -iTCP:$PORT -sTCP:LISTEN >/dev/null 2>&1; then
    warn "  $PORT порт дээр апп аль хэдийн ажиллаж байна."
    printf "  ${B}Түүнийг хааж шинээр эхлүүлэх үү? (T/u):${N} "
    read -r ans
    case "$ans" in
      [Uu]*|[Үү]*)
        echo; dim "  За, эхлүүлсэнгүй."
        dim "  Ажиллаж байгаа апп: http://localhost:$PORT"
        return ;;
      *)
        lsof -nP -tiTCP:$PORT -sTCP:LISTEN 2>/dev/null | xargs kill 2>/dev/null
        sleep 2
        dim "  Хуучныг хаалаа."
        echo ;;
    esac
  fi

  # --- Багцууд бэлэн эсэх (pubspec өөрчлөгдсөн бол өөрөө татна) ---
  NEED_PUB=0
  [ -f ".dart_tool/package_config.json" ] || NEED_PUB=1
  [ "pubspec.yaml" -nt ".dart_tool/package_config.json" ] && NEED_PUB=1
  [ "pubspec.lock" -nt ".dart_tool/package_config.json" ] && NEED_PUB=1

  if [ "$NEED_PUB" -eq 1 ]; then
    info "  Багцуудыг шинэчилж байна (flutter pub get)..."
    if ! flutter pub get >/dev/null 2>&1; then
      echo
      red "  БАГЦ ТАТАХАД АЛДАА ГАРЛАА"
      echo "  Терминал дээр  flutter pub get  гэж ажиллуулж алдааг нь хараарай."
      return
    fi
    green "  Багцууд бэлэн."
    echo
  fi

  info "  Аппыг Chrome дээр нээж байна..."
  dim "  (утасны хүрээтэй preview горимд — эхний удаа 1-2 минут болно)"
  echo
  echo "  ${B}Апп нээгдсэний дараа энэ цонхонд:${N}"
  echo "    ${G}r${N}  = хурдан шинэчлэх (hot reload)"
  echo "    ${G}R${N}  = бүрэн дахин ачаалах"
  echo "    ${Y}q${N}  = аппыг хааж, цэс рүү буцах"
  echo
  echo "${D}  ------------------------------------------${N}"

  flutter run -d chrome --web-port "$PORT" --dart-define=DEVICE_PREVIEW=true

  echo "${D}  ------------------------------------------${N}"
  echo
  green "  Апп хаагдлаа."
}

# ============================================================
#  ЦЭС
# ============================================================
draw_menu() {
  clear 2>/dev/null || true
  echo
  echo "${B}${C}    NIGHT OWL  <->  GITHUB${N}"
  echo "${C}    ======================${N}"
  echo
  echo "    Салбар: ${B}$BRANCH${N}"
  echo
  echo "    Юу хиймээр байна?"
  echo
  echo "      ${G}1)${N} ТАТАХ       - GitHub дээрх шинэ өөрчлөлтийг авах"
  echo "      ${Y}2)${N} ИЛГЭЭХ      - миний өөрчлөлтийг GitHub руу явуулах"
  echo "      ${C}3)${N} АЖИЛЛУУЛАХ  - аппыг Chrome дээр нээх"
  echo
  echo "      ${D}0)${N} Гарах"
  echo
}

while true; do
  draw_menu

  while true; do
    printf "    ${B}Сонголт:${N} "
    read -r CHOICE
    case "$CHOICE" in
      1) do_pull; break ;;
      2) do_push; break ;;
      3) do_run;  break ;;
      0) echo; dim "    Хаалаа."; bye 0 ;;
      "") ;;
      *) warn "    1, 2, 3 эсвэл 0 гэж бичээрэй." ;;
    esac
  done

  echo
  echo "${D}------------------------------------------${N}"
  printf "  ${B}Enter${N} = цэс рүү буцах,  ${B}0${N} = хаах:  "
  read -r AGAIN
  case "$AGAIN" in
    0|[XxQq]*) echo; dim "    Хаалаа."; echo; exit 0 ;;
  esac
done
