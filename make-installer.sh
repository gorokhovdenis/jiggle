#!/bin/bash
# Собирает самораспаковывающийся установщик jiggle-installer.sh — один файл,
# внутри которого лежат все исходники в виде base64.
#
# Запускать после правки исходников. Результат — jiggle-installer.sh рядом со
# скриптом; в git он не коммитится (см. .gitignore), место ему в GitHub Release.
#
# Путь для результата можно задать первым аргументом.

set -eu

SRC="$(cd "$(dirname "$0")" && pwd)"
OUT="${1:-$SRC/jiggle-installer.sh}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

FILES="jiggle.sh build-app.sh make-cert.sh jiggle-icon.png app"

for f in $FILES; do
    [ -e "$SRC/$f" ] || { echo "нет: $SRC/$f" >&2; exit 1; }
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
#   JIGGLE_DEST=путь    готовый путь для исходников, вопрос не задаётся
#   JIGGLE_BASE=путь    папка, внутри которой создать jiggle/

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
[ -d "$PARENT" ] || { echo "Папки $PARENT не существует." >&2; exit 1; }

# --- Распаковка ---------------------------------------------------------------
LINE=$(awk '/^__PAYLOAD_BELOW__$/ { print NR + 1; exit 0 }' "$0")
[ -n "${LINE:-}" ] || { echo "payload не найден — файл повреждён." >&2; exit 1; }

mkdir -p "$DEST"
tail -n +"$LINE" "$0" | base64 -d | tar xzf - -C "$DEST"
chmod +x "$DEST"/*.sh
echo "[1/2] исходники распакованы в $DEST"

# --- Сборка -------------------------------------------------------------------
if ! command -v swiftc >/dev/null 2>&1; then
    echo "" >&2
    echo "Нет swiftc — нужны Xcode Command Line Tools:" >&2
    echo "  xcode-select --install" >&2
    echo "После установки запусти: $DEST/make-cert.sh && $DEST/build-app.sh" >&2
    exit 1
fi

# Сертификат до сборки, иначе бандл уйдёт подписанным ad-hoc и разрешение в
# Accessibility будет слетать при каждой пересборке — молча.
"$DEST/make-cert.sh" >/dev/null || {
    echo "[2/3] сертификат создать не удалось — соберу с ad-hoc подписью."
    echo "      Разрешение Accessibility придётся переоформлять после каждой"
    echo "      пересборки. Починить: $DEST/make-cert.sh"
}
echo "[2/3] подпись готова"

"$DEST/build-app.sh" >/dev/null
echo "[3/3] приложение собрано: $APP"

cat <<MANUAL

Готово. Запустить:

  open "$APP"

Иконка появится в строке меню (в доке её нет — это menu bar приложение).

При первом запуске macOS попросит Accessibility: без него курсор двигаться не
будет. Разрешать надо в диалоге самого приложения — добавление через «+» в
System Settings выглядит тем же самым, но такая запись теряется при
перезапуске приложения.

Чтобы стартовало при входе в систему:
  System Settings → General → Login Items → добавить Jiggle.

Лог, если что-то не так: ~/Library/Logs/jiggle.log

Консольная версия (нужен Homebrew и cliclick):
  brew install cliclick
  $DEST/jiggle.sh

MANUAL
exit 0

__PAYLOAD_BELOW__
INSTALLER_HEADER

cat "$TMP/payload.b64" >> "$OUT"
chmod +x "$OUT"

echo "установщик собран: $OUT"
echo "размер: $(ls -la "$OUT" | awk '{print $5}') байт"
echo "внутри: $FILES"
