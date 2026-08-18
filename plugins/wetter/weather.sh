#!/usr/bin/env bash
#
# Wetter holen -- von Open-Meteo, ohne Schluessel und ohne Anmeldung.
#
# **Das hier ist die einzige Stelle in nbshell, die von sich aus ins Netz
# geht.** Was dabei den Rechner verlaesst: der Ortsname beim ersten Mal
# (Umrechnung in Koordinaten) und danach die Koordinaten selbst, alle paar
# Minuten. Keine Kennung, kein Konto, kein Standort vom Geraet -- der Ort steht
# in der Config und wird von Hand gesetzt.
#
#   weather.sh current <ort> [hoechstalter-in-sekunden]
#   weather.sh geo <ort>
#
# Ausgegeben wird JSON. Geht etwas schief, ist es {"ok":false,"grund":"…"} --
# die Leiste soll dann still bleiben, nicht mit Fehlern blinken.
set -uo pipefail

CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/nbshell"
GEO_API="https://geocoding-api.open-meteo.com/v1/search"
FORECAST_API="https://api.open-meteo.com/v1/forecast"

have() { command -v "$1" >/dev/null 2>&1; }

fail() {
	printf '{"ok":false,"grund":"%s"}\n' "$1"
	exit 0
}

slug() {
	printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/-$//'
}

# Ortsname -> Koordinaten. Das Ergebnis bleibt liegen: es aendert sich nicht,
# und ein zweiter Aufruf waere Hoeflichkeit gegenueber niemandem.
#
# Die Antwort geht ueber die Umgebung an python, nicht in den Text des Skripts:
# fremder JSON darf keine Anfuehrungszeichen aufbrechen koennen.
resolve() {
	local place="$1"
	local file="$CACHE/weather-geo-$(slug "$place").json"

	if [ -s "$file" ]; then
		cat "$file"
		return 0
	fi

	mkdir -p "$CACHE"
	local raw
	raw="$(curl -sS --max-time 10 --get \
		--data-urlencode "name=$place" \
		--data-urlencode "count=1" \
		--data-urlencode "language=de" \
		--data-urlencode "format=json" \
		"$GEO_API" 2>/dev/null)" || return 1

	NB_RAW="$raw" NB_FILE="$file" python3 - <<'PY' || return 1
import json, os

raw = json.loads(os.environ["NB_RAW"])
results = raw.get("results") or []
if not results:
    raise SystemExit(1)

hit = results[0]
name = hit["name"]
region = hit.get("admin1")
country = hit.get("country")
label = ", ".join(x for x in (name, region if region and region != name else None, country) if x)

out = {"lat": hit["latitude"], "lon": hit["longitude"], "name": name, "label": label}
with open(os.environ["NB_FILE"], "w") as handle:
    json.dump(out, handle)
print(json.dumps(out, ensure_ascii=False))
PY
}

field() {
	python3 -c "import json,sys; print(json.loads(sys.argv[1])[sys.argv[2]])" "$1" "$2"
}

cmd_current() {
	local place="${1:-}" max_age="${2:-900}"
	[ -n "$place" ] || place="Wien"

	have curl || fail "curl fehlt"
	have python3 || fail "python3 fehlt"

	mkdir -p "$CACHE"
	local file="$CACHE/weather-$(slug "$place").json"

	# Frisch genug? Dann gar nicht erst fragen. Das gilt auch nach einem
	# Neustart der Shell -- der Zwischenspeicher liegt auf der Platte.
	if [ -s "$file" ]; then
		local age
		age=$(( $(date +%s) - $(stat -c %Y "$file" 2>/dev/null || echo 0) ))
		if [ "$age" -lt "$max_age" ]; then
			cat "$file"
			return 0
		fi
	fi

	local geo
	if ! geo="$(resolve "$place")"; then
		# Kein Netz beim Nachschlagen: lieber der alte Stand als nichts. Wie
		# alt er ist, steht im JSON.
		[ -s "$file" ] && { cat "$file"; return 0; }
		fail "Location '$place' not found"
	fi

	local lat lon label raw
	lat="$(field "$geo" lat)"
	lon="$(field "$geo" lon)"
	label="$(field "$geo" label)"

	if ! raw="$(curl -sS --max-time 10 --get \
		--data-urlencode "latitude=$lat" \
		--data-urlencode "longitude=$lon" \
		--data-urlencode "current=temperature_2m,apparent_temperature,relative_humidity_2m,wind_speed_10m,weather_code,is_day" \
		--data-urlencode "daily=weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset,precipitation_probability_max" \
		--data-urlencode "timezone=auto" \
		--data-urlencode "forecast_days=5" \
		"$FORECAST_API" 2>/dev/null)"; then
		[ -s "$file" ] && { cat "$file"; return 0; }
		fail "no network"
	fi

	# `if !` und KEIN `|| { … }`: ein Block, der ein Here-Document umschliesst,
	# bringt bashs Parser durcheinander -- "syntax error near unexpected }".
	if NB_RAW="$raw" NB_FILE="$file" NB_LABEL="$label" python3 - <<'PY'
import json, os, time

data = json.loads(os.environ["NB_RAW"])
current = data.get("current") or {}
daily = data.get("daily") or {}

days = []
for i, day in enumerate(daily.get("time", [])):
    days.append({
        "datum": day,
        "code": daily["weather_code"][i],
        "max": daily["temperature_2m_max"][i],
        "min": daily["temperature_2m_min"][i],
        "regen": (daily.get("precipitation_probability_max") or [None] * 9)[i],
    })

out = {
    "ok": True,
    "ort": os.environ["NB_LABEL"],
    "temp": current.get("temperature_2m"),
    "gefuehlt": current.get("apparent_temperature"),
    "feuchte": current.get("relative_humidity_2m"),
    "wind": current.get("wind_speed_10m"),
    "code": current.get("weather_code"),
    "tag": bool(current.get("is_day", 1)),
    "stand": current.get("time"),
    "geholt": int(time.time()),
    "auf": (daily.get("sunrise") or [None])[0],
    "unter": (daily.get("sunset") or [None])[0],
    "tage": days,
}

with open(os.environ["NB_FILE"], "w") as handle:
    json.dump(out, handle, ensure_ascii=False)
print(json.dumps(out, ensure_ascii=False))
PY
	then
		return 0
	fi

	[ -s "$file" ] && { cat "$file"; return 0; }
	fail "Antwort unlesbar"
}

case "${1:-current}" in
current) shift && cmd_current "${1:-}" "${2:-900}" ;;
geo) shift && resolve "${1:?Ort fehlt}" ;;
*)
	echo "Aufruf: $(basename "$0") current <ort> [alter] | geo <ort>" >&2
	exit 2
	;;
esac
