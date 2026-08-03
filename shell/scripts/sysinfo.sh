#!/usr/bin/env bash
#
# Alles, was das Popout der Leistungsanzeige zeigt -- Temperaturen, Luefter,
# Kerne, Speicher, Platte, Laufzeit.
#
# Die Zelle in der Leiste kommt ohne das aus: sie liest /proc/stat und
# /proc/meminfo direkt in QML. Hier steht nur, was mehr Arbeit macht als eine
# Zeile lesen -- und was deshalb nur laeuft, solange jemand hinsieht.
#
# **`nvidia-smi` weckt die Grafikkarte.** Auf einem Optimus-Notebook haelt ein
# Aufruf alle zwei Sekunden die dedizierte Karte wach und kostet Laufzeit.
# Deshalb wird sie nur gefragt, wenn es ausdruecklich verlangt wird -- das
# Popout tut das, die Leiste nie.
#
#   sysinfo.sh detail [gpu]
set -uo pipefail

have() { command -v "$1" >/dev/null 2>&1; }

# Zwei Messungen von /proc/stat im Abstand von 200 ms: aus der Differenz
# ergibt sich die Last je Kern. Ein einzelner Blick zeigt nur die Summe seit
# dem Start -- also praktisch immer dieselbe Zahl.
cpu_cores() {
	python3 - <<'PY'
import json, time

def snapshot():
    out = {}
    with open("/proc/stat") as handle:
        for line in handle:
            if not line.startswith("cpu"):
                break
            parts = line.split()
            if parts[0] == "cpu":
                continue
            values = [int(x) for x in parts[1:]]
            out[parts[0]] = (sum(values), values[3] + (values[4] if len(values) > 4 else 0))
    return out

first = snapshot()
time.sleep(0.2)
second = snapshot()

cores = []
for name in sorted(first, key=lambda n: int(n[3:])):
    total0, idle0 = first[name]
    total1, idle1 = second.get(name, (total0, idle0))
    dt, di = total1 - total0, idle1 - idle0
    cores.append(round(100 * (dt - di) / dt) if dt > 0 else 0)

print(json.dumps(cores))
PY
}

# Temperaturen und Luefter aus /sys/class/hwmon.
#
# Gefiltert, nicht gesammelt: der Rechner meldet hier zwei Dutzend Werte, von
# denen die meisten Dubletten sind. `dell_smm` etwa liefert acht unbeschriftete
# Temperaturen, die als CPU, Chipsatz und Gehaeuse schon dabei sind -- seine
# LUEFTER sind aber die einzige Quelle, also faellt nur der Temperaturteil weg.
sensors_json() {
	python3 - <<'PY'
import glob, json, os

def read(path):
    try:
        with open(path) as handle:
            return handle.read().strip()
    except OSError:
        return None

temps, fans, cores = [], [], []
for hwmon in sorted(glob.glob("/sys/class/hwmon/hwmon*")):
    chip = read(os.path.join(hwmon, "name")) or "?"

    for path in sorted(glob.glob(os.path.join(hwmon, "temp*_input"))):
        raw = read(path)
        if raw is None:
            continue
        try:
            value = int(raw) / 1000
        except ValueError:
            continue
        if value <= 0 or value > 150:
            continue
        label = read(path.replace("_input", "_label")) or ""

        if chip.startswith(("coretemp", "k10temp")):
            # "Package id 0" ist die Zahl, die man meint, wenn man
            # "CPU-Temperatur" sagt. Die einzelnen Kerne wandern in eine
            # eigene Liste -- als Zeile taugt davon nur der hoechste.
            if label.startswith("Package") or label.startswith("Tctl"):
                temps.append({"name": "CPU", "wert": round(value, 1)})
            else:
                cores.append(round(value, 1))
        elif chip.startswith("nvme"):
            if label in ("", "Composite"):
                temps.append({"name": "SSD", "wert": round(value, 1)})
        elif chip.startswith("acpitz"):
            temps.append({"name": "Gehaeuse", "wert": round(value, 1)})
        elif chip.startswith("pch_"):
            temps.append({"name": "Chipsatz", "wert": round(value, 1)})
        elif chip.startswith("iwlwifi"):
            temps.append({"name": "WLAN", "wert": round(value, 1)})
        elif chip.startswith("amdgpu"):
            temps.append({"name": "GPU", "wert": round(value, 1)})

    for path in sorted(glob.glob(os.path.join(hwmon, "fan*_input"))):
        raw = read(path)
        if raw is None:
            continue
        label = read(path.replace("_input", "_label")) or ""
        fans.append({
            "name": label or ("Luefter " + os.path.basename(path)[3]),
            "wert": int(raw),
        })

if cores:
    temps.append({"name": "CPU-Kern (max)", "wert": max(cores)})

# CPU zuerst, der Rest in der Reihenfolge, in der er gefunden wurde.
temps.sort(key=lambda t: 0 if t["name"] == "CPU" else 1)

print(json.dumps({"temps": temps, "fans": fans}, ensure_ascii=False))
PY
}

gpu_json() {
	have nvidia-smi || { echo 'null'; return 0; }
	nvidia-smi --query-gpu=name,temperature.gpu,utilization.gpu,memory.used,memory.total \
		--format=csv,noheader,nounits 2>/dev/null |
		python3 -c "
import json, sys

line = sys.stdin.readline().strip()
if not line:
    print('null')
    raise SystemExit(0)

name, temp, util, used, total = [x.strip() for x in line.split(',')]
print(json.dumps({
    'name': name,
    'temp': float(temp),
    'last': float(util),
    'benutzt': float(used),
    'gesamt': float(total),
}, ensure_ascii=False))
"
}

cmd_detail() {
	local want_gpu="${1:-}"
	have python3 || {
		printf '{"ok":false,"grund":"python3 fehlt"}\n'
		return 0
	}

	local cores sensors gpu
	cores="$(cpu_cores)"
	sensors="$(sensors_json)"
	gpu='null'
	[ "$want_gpu" = "gpu" ] && gpu="$(gpu_json)"

	NB_CORES="$cores" NB_SENSORS="$sensors" NB_GPU="$gpu" python3 - <<'PY'
import json, os, shutil, subprocess

def read(path):
    try:
        with open(path) as handle:
            return handle.read()
    except OSError:
        return ""

cores = json.loads(os.environ["NB_CORES"])
sensors = json.loads(os.environ["NB_SENSORS"])
gpu = json.loads(os.environ["NB_GPU"])

model = ""
mhz = []
for line in read("/proc/cpuinfo").splitlines():
    if line.startswith("model name") and not model:
        model = line.split(":", 1)[1].strip()
    elif line.startswith("cpu MHz"):
        mhz.append(float(line.split(":", 1)[1]))

mem = {}
for line in read("/proc/meminfo").splitlines():
    key, _, rest = line.partition(":")
    parts = rest.split()
    if parts:
        mem[key] = int(parts[0])

load = read("/proc/loadavg").split()
uptime = float((read("/proc/uptime") or "0").split()[0])

total, avail = mem.get("MemTotal", 0), mem.get("MemAvailable", 0)
swap_total, swap_free = mem.get("SwapTotal", 0), mem.get("SwapFree", 0)

disk = None
usage = shutil.disk_usage("/")
disk = {
    "gesamt": round(usage.total / 2**30, 1),
    "benutzt": round(usage.used / 2**30, 1),
    "prozent": round(100 * usage.used / usage.total),
}

print(json.dumps({
    "ok": True,
    "modell": model,
    "kerne": cores,
    "mhz": round(sum(mhz) / len(mhz)) if mhz else None,
    "last": [float(x) for x in load[:3]] if len(load) >= 3 else [],
    "laufzeit": int(uptime),
    "speicher": {
        "gesamt": round(total / 2**20, 1),
        "benutzt": round((total - avail) / 2**20, 1),
        "cache": round(mem.get("Cached", 0) / 2**20, 1),
        "swap_gesamt": round(swap_total / 2**20, 1),
        "swap_benutzt": round((swap_total - swap_free) / 2**20, 1),
    },
    "platte": disk,
    "temps": sensors["temps"],
    "luefter": sensors["fans"],
    "gpu": gpu,
}, ensure_ascii=False))
PY
}

case "${1:-detail}" in
detail) shift && cmd_detail "${1:-}" ;;
*)
	echo "Aufruf: $(basename "$0") detail [gpu]" >&2
	exit 2
	;;
esac
