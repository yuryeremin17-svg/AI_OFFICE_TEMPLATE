#!/bin/bash
# weekly_check.sh — еженедельная диагностика проекта
# Запуск: bash weekly_check.sh
# Рекомендуется: каждый понедельник в начале сессии

set -uo pipefail

OFFICE_DIR="$(cd "$(dirname "$0")" && pwd)"
WARNINGS=0
ERRORS=0
TODAY=$(date +%Y-%m-%d)

# Цвета
RED='\033[0;31m'
YELLOW='\033[0;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

ok()   { printf "${GREEN}✓${NC} %s\n" "$1"; }
warn() { printf "${YELLOW}⚠${NC} %s\n" "$1"; WARNINGS=$((WARNINGS + 1)); }
fail() { printf "${RED}✗${NC} %s\n" "$1"; ERRORS=$((ERRORS + 1)); }
info() { printf "${CYAN}ℹ${NC} %s\n" "$1"; }

echo "=== Еженедельная проверка ($TODAY) ==="
echo ""

# --- 1. ERRORS.md — количество записей ---
if [ -f "$OFFICE_DIR/ERRORS.md" ]; then
    ERROR_COUNT=$(grep -c '^### ' "$OFFICE_DIR/ERRORS.md" 2>/dev/null || echo 0)
    ERRORS_LINES=$(wc -l < "$OFFICE_DIR/ERRORS.md" | tr -d ' ')
    if [ "$ERROR_COUNT" -gt 8 ]; then
        warn "ERRORS.md: ${ERROR_COUNT} записей — возможно есть устаревшие"
    else
        ok "ERRORS.md: ${ERROR_COUNT} записей (${ERRORS_LINES} строк)"
    fi
else
    fail "ERRORS.md не найден!"
fi

# --- 2. HANDOFF.md — дата актуальности ---
if [ -f "$OFFICE_DIR/HANDOFF.md" ]; then
    HANDOFF_DATE=$(sed -n 's/.*Дата:\*\* \([0-9]* [^ ]* [0-9]*\).*/\1/p' "$OFFICE_DIR/HANDOFF.md" | head -1)
    if [ -n "$HANDOFF_DATE" ]; then
        DAY=$(echo "$HANDOFF_DATE" | awk '{print $1}')
        MONTH_RU=$(echo "$HANDOFF_DATE" | awk '{print $2}')
        YEAR=$(echo "$HANDOFF_DATE" | awk '{print $3}')

        case "$MONTH_RU" in
            январ*)  MONTH=01 ;; феврал*) MONTH=02 ;; март*)   MONTH=03 ;;
            апрел*)  MONTH=04 ;; ма[яй]*)    MONTH=05 ;; июн*)    MONTH=06 ;;
            июл*)    MONTH=07 ;; август*) MONTH=08 ;; сентябр*) MONTH=09 ;;
            октябр*) MONTH=10 ;; ноябр*)  MONTH=11 ;; декабр*) MONTH=12 ;;
            *) MONTH="" ;;
        esac

        if [ -n "$MONTH" ]; then
            HANDOFF_TS=$(date -j -f "%Y-%m-%d" "$YEAR-$MONTH-$(printf '%02d' "$DAY")" "+%s" 2>/dev/null || echo 0)
            NOW_TS=$(date "+%s")
            DIFF_DAYS=$(( (NOW_TS - HANDOFF_TS) / 86400 ))

            if [ "$DIFF_DAYS" -gt 7 ]; then
                warn "HANDOFF.md: последнее обновление $DIFF_DAYS дней назад"
            else
                ok "HANDOFF.md актуален ($HANDOFF_DATE, ${DIFF_DAYS}д назад)"
            fi
        else
            warn "HANDOFF.md: не удалось распознать месяц '$MONTH_RU'"
        fi
    else
        warn "HANDOFF.md: дата не найдена"
    fi
else
    fail "HANDOFF.md не найден!"
fi

# --- 3. Размер ключевых файлов ---
echo ""
printf "${CYAN}--- Размер файлов документации ---${NC}\n"
for docfile in \
    "$OFFICE_DIR/CLAUDE.md" \
    "$OFFICE_DIR/HANDOFF.md" \
    "$OFFICE_DIR/ERRORS.md" \
    "$OFFICE_DIR/COMPANY.md" \
    "$OFFICE_DIR/PROFILE.md" \
    "$OFFICE_DIR/DEV.md"; do
    [ ! -f "$docfile" ] && continue
    LINES=$(wc -l < "$docfile" | tr -d ' ')
    NAME=$(basename "$docfile")
    if [ "$LINES" -gt 300 ]; then
        warn "$NAME: ${LINES} строк (>300) — возможно раздулся"
    else
        ok "$NAME: ${LINES} строк"
    fi
done
echo ""

# --- 4. Bash синтаксис ---
SH_ERRORS=0
for shfile in "$OFFICE_DIR"/*.sh; do
    [ ! -f "$shfile" ] && continue
    if ! bash -n "$shfile" 2>/dev/null; then
        fail "Bash ошибка: $(basename "$shfile")"
        SH_ERRORS=$((SH_ERRORS + 1))
    fi
done
if [ "$SH_ERRORS" -eq 0 ]; then
    ok "Bash синтаксис: все .sh файлы валидны"
fi

# --- 5. Python синтаксис (если есть .py файлы) ---
PY_FILES=$(find "$OFFICE_DIR" -maxdepth 2 -name "*.py" -type f 2>/dev/null)
if [ -n "$PY_FILES" ]; then
    PY_ERRORS=0
    PYTHON_BIN="python3"
    [ -x "$OFFICE_DIR/.venv/bin/python3" ] && PYTHON_BIN="$OFFICE_DIR/.venv/bin/python3"

    while IFS= read -r pyfile; do
        if ! "$PYTHON_BIN" -m py_compile "$pyfile" 2>/dev/null; then
            fail "Python ошибка: $(basename "$pyfile")"
            PY_ERRORS=$((PY_ERRORS + 1))
        fi
    done <<< "$PY_FILES"

    if [ "$PY_ERRORS" -eq 0 ]; then
        ok "Python синтаксис: все .py файлы валидны"
    fi
fi

# --- 6. reports/ — пустые или подозрительные отчёты ---
if [ -d "$OFFICE_DIR/reports" ]; then
    EMPTY_REPORTS=0
    TOTAL_REPORTS=$(find "$OFFICE_DIR/reports" -name "*.md" -type f 2>/dev/null | wc -l | tr -d ' ')

    while IFS= read -r report; do
        [ -z "$report" ] && continue
        SIZE=$(wc -c < "$report" 2>/dev/null || echo 0)
        if [ "$SIZE" -lt 100 ]; then
            EMPTY_REPORTS=$((EMPTY_REPORTS + 1))
        fi
    done <<< "$(find "$OFFICE_DIR/reports" -name "*.md" -type f 2>/dev/null)"

    if [ "$EMPTY_REPORTS" -gt 0 ]; then
        warn "reports/: $EMPTY_REPORTS из $TOTAL_REPORTS отчётов подозрительно малы (<100 байт)"
    elif [ "$TOTAL_REPORTS" -gt 0 ]; then
        ok "reports/: $TOTAL_REPORTS отчётов, все корректного размера"
    else
        info "reports/: пусто"
    fi
else
    info "Директория reports/ не найдена"
fi

# --- 7. archive/ — существует ли ---
if [ ! -d "$OFFICE_DIR/archive" ]; then
    warn "archive/ не найден — создайте для архивирования устаревших файлов"
fi

# --- Итог ---
echo ""
echo "========================================="
echo "=== Итого: $ERRORS ошибок, $WARNINGS предупреждений ==="
echo "========================================="

if [ "$ERRORS" -gt 0 ]; then
    printf "\n${RED}Есть критические проблемы — исправить до следующего push.${NC}\n"
elif [ "$WARNINGS" -gt 0 ]; then
    printf "\n${YELLOW}Есть замечания — рекомендуется разобрать.${NC}\n"
else
    printf "\n${GREEN}Всё чисто! Проект в хорошей форме.${NC}\n"
fi

exit 0
