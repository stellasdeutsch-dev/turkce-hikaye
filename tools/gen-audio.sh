#!/bin/bash
# ---------------------------------------------------------------
#  Озвучка для сайта «Расскажи о себе по-турецки»
#
#  Тексты берутся прямо из index.html — из блоков
#  /*TR*/{...}/*END-TR*/ и /*RU*/{...}/*END-RU*/.
#  Поменял фразу в index.html — перезапусти скрипт.
#
#  Турецкий — голос Yelda (tr_TR), русский — Milena (ru_RU).
#  Запуск:  bash tools/gen-audio.sh          (только недостающие)
#           bash tools/gen-audio.sh --force  (перезаписать всё)
#
#  Хочешь живой голос — запиши mp3 с тем же именем и положи
#  в ту же папку. Сайт сначала ищет файл, потом включает
#  синтез речи браузера.
# ---------------------------------------------------------------
set -e
cd "$(dirname "$0")/.."
mkdir -p audio/tr audio/ru
[ "$1" = "--force" ] && rm -f audio/tr/*.mp3 audio/ru/*.mp3
MAN=$(mktemp); TMPD=$(mktemp -d)
trap 'rm -rf "$MAN" "$TMPD"' EXIT

python3 - "$MAN" <<'PY'
import sys, re, json
html = open('index.html', encoding='utf-8').read()
out = open(sys.argv[1], 'w', encoding='utf-8')
for tag, d, voice in (('TR', 'tr', 'Yelda'), ('RU', 'ru', 'Milena')):
    m = re.search(r'/\*' + tag + r'\*/(\{.*?\})/\*END-' + tag + r'\*/', html, re.S)
    for slug, text in json.loads(m.group(1)).items():
        out.write(f"{d}\t{voice}\t{slug}\t{text}\n")
out.close()
PY

echo "▸ Фраз в манифесте: $(wc -l < "$MAN" | tr -d ' ')"

# Последовательно: параллельный `say` конфликтует сам с собой
# и тихо роняет часть файлов. Второй проход добирает пропуски.
render_pass () {
  local made=0
  while IFS=$'\t' read -r dir voice slug text; do
    [ -z "$slug" ] && continue
    [ -s "audio/$dir/$slug.mp3" ] && continue
    rate=175; [ "$dir" = "tr" ] && rate=150
    say -v "$voice" -r $rate -o "$TMPD/x.aiff" "$text" 2>/dev/null || continue
    ffmpeg -nostdin -y -loglevel error -i "$TMPD/x.aiff" -codec:a libmp3lame -b:a 48k -ac 1 "audio/$dir/$slug.mp3" 2>/dev/null || true
    rm -f "$TMPD/x.aiff"; made=$((made+1))
  done < "$MAN"
  echo "  проход: сделано $made"
}
render_pass
render_pass

MISSING=$(while IFS=$'\t' read -r dir voice slug text; do
  [ -n "$slug" ] && [ ! -s "audio/$dir/$slug.mp3" ] && echo "$slug"; done < "$MAN" | wc -l | tr -d ' ')
echo "✔ Готово: $(ls audio/tr | wc -l | tr -d ' ') турецких, $(ls audio/ru | wc -l | tr -d ' ') русских · не хватает: $MISSING"
