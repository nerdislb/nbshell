#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
python3 -m unittest -v test_installer.py
bash -n ../airootfs/usr/local/lib/nbshell/target-setup.sh
bash -n ../airootfs/usr/local/lib/nbshell/firstboot.sh
bash test_scripts.sh
