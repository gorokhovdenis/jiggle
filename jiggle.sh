#!/bin/bash
# Mouse Jiggler
# Случайно шевелит курсор, чтобы система видела активность и не уходила в idle.
#
# Зависимость: brew install cliclick
# Права: System Settings → Privacy & Security → Accessibility → включить терминал
#
# Настройки через переменные окружения:
#   JIGGLE_MIN=30     минимальная пауза между шевелениями, сек
#   JIGGLE_MAX=90     максимальная пауза, сек
#   JIGGLE_DELTA=150  максимальный сдвиг курсора, пикселей
#   JIGGLE_EASE=300   плавность хода: 0 = мгновенный скачок, больше = медленнее
#                     и человекоподобнее (300 на 400px ≈ 0.8с)
#   JIGGLE_SMART=1    1 = пропускать такт, если мышь двигали руками (0 = всегда)
#
# Примеры:
#   ./jiggle.sh
#   JIGGLE_MIN=10 JIGGLE_MAX=20 ./jiggle.sh          # часто, для проверки
#   JIGGLE_DELTA=400 JIGGLE_EASE=500 ./jiggle.sh     # размашисто и медленно
#   JIGGLE_DELTA=4 JIGGLE_EASE=0 ./jiggle.sh         # незаметно (старое поведение)
#   JIGGLE_SMART=0 ./jiggle.sh                       # дёргать всегда

set -u

MIN=${JIGGLE_MIN:-30}
MAX=${JIGGLE_MAX:-90}
DELTA=${JIGGLE_DELTA:-150}
EASE=${JIGGLE_EASE:-300}
SMART=${JIGGLE_SMART:-1}

command -v cliclick >/dev/null 2>&1 || {
    echo "Не найден cliclick. Поставь: brew install cliclick" >&2
    exit 1
}

# Текущая позиция курсора в виде "X,Y". Предупреждения cliclick уходят в stderr.
pos() { cliclick p 2>/dev/null; }

# Случайное целое в диапазоне [$1, $2] включительно, работает с отрицательными.
# Результат в $RND, а не в stdout: $RANDOM внутри $( ) берётся из копии сида
# родителя и сид родителя не двигает — все вызовы вернули бы одно число.
rnd() { RND=$(( RANDOM % ( ($2) - ($1) + 1 ) + ($1) )); }

# Относительный сдвиг рывком: cliclick требует явный знак, отсюда %+d.
nudge() { cliclick "m:$(printf '%+d,%+d' "$1" "$2")" >/dev/null 2>&1; }

# Абсолютный переход в точку "X,Y". Отрицательные координаты cliclick принял бы
# за относительные, им нужен префикс "=". Отрицательные тут реальны: за границей
# экрана клампится только видимый курсор, логическая координата уходит в минус
# (проверено: уезд на -150 от края даёт "-150,400"), плюс второй монитор слева.
abs_move() {
    local x="${1%%,*}" y="${1##*,}"
    [ "${x#-}" != "$x" ] && x="=$x"
    [ "${y#-}" != "$y" ] && y="=$y"
    printf 'm:%s,%s' "$x" "$y"
}

# Плавно уехать на dx,dy и так же плавно вернуться в исходную точку $3.
# Возврат абсолютный: зеркальный относительный тоже даёт точную позицию, но
# абсолютный не накапливает ошибку, если какой-то из шагов не выполнится.
glide() {
    cliclick -e "$EASE" "m:$(printf '%+d,%+d' "$1" "$2")" >/dev/null 2>&1
    cliclick -e "$EASE" "$(abs_move "$3")" >/dev/null 2>&1
}

# --- Проверка, что права выданы и курсор реально двигается -------------------
probe_before=$(pos)
nudge 3 3
sleep 0.1
probe_after=$(pos)
nudge -3 -3

if [ "$probe_before" = "$probe_after" ]; then
    cat >&2 <<'EOF'
ОШИБКА: курсор не сдвинулся — скорее всего нет прав Accessibility.

  System Settings → Privacy & Security → Accessibility
  и включить галочку для терминала, из которого запускаешь (Terminal / iTerm).
  После выдачи прав терминал надо перезапустить.
EOF
    exit 1
fi

# --- Основной цикл ----------------------------------------------------------
count=0
last=$(pos)

trap 'printf "\nОстановлено. Шевелений за сессию: %d\n" "$count"; exit 0' INT TERM

echo "jiggle: пауза ${MIN}-${MAX}с, сдвиг ±${DELTA}px, плавность ${EASE}, smart=${SMART}. Ctrl-C — выход."

while :; do
    rnd "$MIN" "$MAX"
    sleep "$RND"

    now=$(pos)

    # Курсор не там, где мы его оставили, — значит за ноутом кто-то есть.
    if [ "$SMART" = "1" ] && [ "$now" != "$last" ]; then
        printf '[%s] пропуск — мышь двигали руками\n' "$(date +%H:%M:%S)"
        last=$now
        continue
    fi

    rnd "-$DELTA" "$DELTA"; dx=$RND
    rnd "-$DELTA" "$DELTA"; dy=$RND
    [ "$dx" -eq 0 ] && [ "$dy" -eq 0 ] && dx=1   # нулевой сдвиг события не породит

    glide "$dx" "$dy" "$now"                     # уехать и вернуться на место

    last=$(pos)
    count=$((count + 1))
    printf '[%s] jiggle %+d,%+d (всего: %d)\n' "$(date +%H:%M:%S)" "$dx" "$dy" "$count"
done
