#!/bin/bash
# Собирает самораспаковывающийся установщик jiggle-installer.sh — один файл,
# внутри которого лежат все исходники джигглера в виде base64.
#
# Запускать после любой правки jiggle.sh / jiggle-launcher.applescript / иконки.
# Результат: jiggle-installer.sh рядом со скриптом — его и везём на новый ноут
# либо прикладываем к GitHub Release. В git он не коммитится (см. .gitignore).
#
# Путь для результата можно задать первым аргументом.

set -eu

SRC="$(cd "$(dirname "$0")" && pwd)"
OUT="${1:-$SRC/jiggle-installer.sh}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

FILES="jiggle.sh jiggle-launcher.applescript jiggle-icon.png build-jiggle-app.sh"

for f in $FILES; do
    [ -f "$SRC/$f" ] || { echo "нет файла: $SRC/$f" >&2; exit 1; }
done

# base64 вместо сырого tar: файл остаётся текстовым и переживает пересылку
# через мессенджеры и почту, которые бинарь могут покорёжить.
tar czf "$TMP/payload.tar.gz" -C "$SRC" $FILES
base64 -i "$TMP/payload.tar.gz" -o "$TMP/payload.b64"

cat > "$OUT" <<'INSTALLER_HEADER'
#!/bin/bash
# Jiggle — установщик. Всё нужное упаковано внутрь этого файла.
#
# Запуск:
#   bash jiggle-installer.sh
#
# Переменные (задать, чтобы не спрашивал):
#   JIGGLE_DEST=путь      готовый путь для исходников, вопрос не задаётся
#   JIGGLE_BASE=путь      папка, внутри которой создать jiggle/
#   JIGGLE_SKIP_DOCK=1    не трогать Dock

set -eu

APP="$HOME/Applications/Jiggle.app"

[ "$(uname -s)" = "Darwin" ] || { echo "Это только для macOS." >&2; exit 1; }

echo "=== Jiggle installer ==="
echo ""

# --- Куда распаковывать -------------------------------------------------------
# Спрашиваем, только если путь не задан переменной и есть терминал: установщик
# должен так же работать при запуске из скрипта или по ssh без интерактива.
if [ -n "${JIGGLE_DEST:-}" ]; then
    DEST="$JIGGLE_DEST"
elif [ -n "${JIGGLE_BASE:-}" ]; then
    DEST="$JIGGLE_BASE/jiggle"
elif [ -t 0 ]; then
    DEFAULT_BASE="$HOME"
    printf 'В какой папке создать jiggle/ ? [Enter = %s]\n> ' "$DEFAULT_BASE"
    read -r BASE || BASE=""
    [ -n "$BASE" ] || BASE="$DEFAULT_BASE"
    case "$BASE" in
        "~")   BASE="$HOME" ;;
        "~/"*) BASE="$HOME/${BASE#~/}" ;;
    esac
    DEST="$BASE/jiggle"
    echo ""
else
    DEST="$HOME/jiggle"
fi

PARENT="$(dirname "$DEST")"
if [ ! -d "$PARENT" ]; then
    echo "Папки $PARENT не существует." >&2
    exit 1
fi

# --- Распаковка ---------------------------------------------------------------
LINE=$(awk '/^__PAYLOAD_BELOW__$/ { print NR + 1; exit 0 }' "$0")
[ -n "${LINE:-}" ] || { echo "payload не найден — файл повреждён." >&2; exit 1; }

mkdir -p "$DEST"
tail -n +"$LINE" "$0" | base64 -d | tar xzf - -C "$DEST"
chmod +x "$DEST"/*.sh
echo "[1/4] исходники распакованы в $DEST"

# --- cliclick -----------------------------------------------------------------
if command -v cliclick >/dev/null 2>&1; then
    echo "[2/4] cliclick уже стоит"
elif command -v brew >/dev/null 2>&1; then
    echo "[2/4] ставлю cliclick через brew..."
    brew install cliclick || { echo "  brew install не удался, поставь вручную" >&2; }
else
    echo "[2/4] ВНИМАНИЕ: нет ни cliclick, ни brew."
    echo "      Поставь Homebrew (brew.sh), затем: brew install cliclick"
fi

# --- Сборка приложения --------------------------------------------------------
if [ -d "/Applications/iTerm.app" ] || [ -d "$HOME/Applications/iTerm.app" ]; then
    :
else
    echo "      ВНИМАНИЕ: iTerm не найден — иконка запустится, но окно не откроется."
fi

"$DEST/build-jiggle-app.sh" >/dev/null
echo "[3/4] приложение собрано: $APP"

# --- Dock ---------------------------------------------------------------------
if [ "${JIGGLE_SKIP_DOCK:-0}" = "1" ]; then
    echo "[4/4] Dock пропущен (JIGGLE_SKIP_DOCK=1)"
elif defaults read com.apple.dock persistent-apps 2>/dev/null | grep -q "Jiggle.app"; then
    echo "[4/4] иконка уже в Dock"
else
    defaults write com.apple.dock persistent-apps -array-add "<dict><key>tile-data</key><dict><key>file-data</key><dict><key>_CFURLString</key><string>${APP}</string><key>_CFURLStringType</key><integer>0</integer></dict></dict></dict>"
    killall Dock 2>/dev/null || true
    echo "[4/4] иконка добавлена в Dock"
fi

cat <<'MANUAL'

Осталось два разрешения, оба одноразовые и только руками:

  1. System Settings → Privacy & Security → Accessibility
     включить галочку для iTerm (без этого курсор двигаться не будет)

  2. при первом клике по иконке всплывёт
     «Jiggle» хочет управлять «iTerm» → OK

MANUAL

echo "Исходники:  $DEST"
echo "Приложение: $APP"
echo "Проверить без иконки:  $DEST/jiggle.sh"
echo ""
exit 0

__PAYLOAD_BELOW__
INSTALLER_HEADER

cat "$TMP/payload.b64" >> "$OUT"
chmod +x "$OUT"

echo "установщик собран: $OUT"
echo "размер: $(ls -la "$OUT" | awk '{print $5}') байт"
echo "внутри: $FILES"
