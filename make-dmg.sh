#!/bin/bash
# Пакует готовый Jiggle.app в dmg для раздачи через GitHub Releases.
#
# Это канал доставки «перетащил в Applications», в отличие от установщика,
# который собирает на месте. Тут .app уже собран, поэтому Xcode на целевой
# машине не нужен.
#
# Важное про подпись. Внутрь кладётся ровно тот .app, что собрал build-app.sh,
# со всей подписью — копируем через ditto, а не cp, чтобы подпись и xattr не
# потерялись. Если .app подписан локальным сертификатом (make-cert.sh), то
# designated requirement привязан к certificate root, а не к cdhash, и
# разрешение Accessibility на машине получателя переживает обновления —
# при условии, что все релизы подписаны ТЕМ ЖЕ сертификатом (то есть собраны
# на этой машине). Ad-hoc так не умеет: там requirement по хешу бинаря.
#
# Чего dmg НЕ делает: сертификат самоподписанный и на чужой машине не
# доверенный, поэтому Gatekeeper при первом запуске всё равно упрётся в
# карантин. Получателю один раз: System Settings → Privacy & Security →
# Open Anyway (правый клик → Open убран начиная с Sequoia), либо
#   sudo xattr -dr com.apple.quarantine /Applications/Jiggle.app
# Убрать эту возню целиком может только notarization ($99/год).

set -eu

SRC="$(cd "$(dirname "$0")" && pwd)"
APP="${JIGGLE_APP_PATH:-/Applications/Jiggle.app}"

[ -d "$APP" ] || {
    echo "Нет $APP — сначала собери: $SRC/build-app.sh" >&2
    exit 1
}

VERSION="$(defaults read "$APP/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo 1.0)"
OUT="${1:-$SRC/Jiggle-$VERSION.dmg}"

# Предупреждаем, если подпись ad-hoc: dmg соберётся, но обновления будут
# сбрасывать разрешение у всех получателей.
if codesign -d -r- "$APP" 2>&1 | grep -q 'designated => cdhash'; then
    echo "ВНИМАНИЕ: $APP подписан ad-hoc." >&2
    echo "У получателей разрешение Accessibility слетит на первом обновлении." >&2
    echo "Починить: $SRC/make-cert.sh && $SRC/build-app.sh" >&2
    echo "" >&2
fi

STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT

# ditto — единственный корректный способ копировать бандл на macOS: сохраняет
# подпись, символические ссылки и расширенные атрибуты.
ditto "$APP" "$STAGING/Jiggle.app"

# Ссылка на /Applications, чтобы окно dmg было «перетащи сюда».
ln -s /Applications "$STAGING/Applications"

rm -f "$OUT"
hdiutil create \
    -volname "Jiggle" \
    -srcfolder "$STAGING" \
    -fs HFS+ \
    -format UDZO \
    -ov \
    "$OUT" >/dev/null

echo "dmg собран: $OUT"
echo "размер: $(ls -la "$OUT" | awk '{print $5}') байт"

# Проверяем, что подпись пережила упаковку.
MNT="$(mktemp -d)"
hdiutil attach "$OUT" -nobrowse -mountpoint "$MNT" >/dev/null
if codesign -v --strict "$MNT/Jiggle.app" 2>/dev/null; then
    echo "подпись внутри dmg цела: $(codesign -dv "$MNT/Jiggle.app" 2>&1 | grep '^Authority' | head -1 | cut -d= -f2)"
else
    echo "ВНИМАНИЕ: подпись внутри dmg не проходит проверку" >&2
fi
hdiutil detach "$MNT" >/dev/null
rmdir "$MNT"
