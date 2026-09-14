#!/bin/sh
# One-time rename of the old app's on-disk state. Existing Omamail state
# always wins: combining two stores without understanding their contents could
# overwrite a newer account or cache.
set -eu

move_once() {
  old=$1
  new=$2
  if [ -d "$old" ] && [ ! -L "$old" ] && [ ! -e "$new" ] && [ ! -L "$new" ]; then
    mv -T -- "$old" "$new"
  fi
}

config_home=${XDG_CONFIG_HOME:-$HOME/.config}
cache_home=${XDG_CACHE_HOME:-$HOME/.cache}

move_once "$config_home/omarchy-gmail" "$config_home/omamail"
move_once "$cache_home/omarchy-gmail" "$cache_home/omamail"
