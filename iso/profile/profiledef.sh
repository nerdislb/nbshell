#!/usr/bin/env bash
# shellcheck disable=SC2034

# Reuse Archiso's current releng permissions and boot asset contract, then
# narrow the product to nbshell's private x86_64 UEFI preview.
source "${NBSHELL_ARCHISO_RELENG_PROFILEDEF:-/usr/share/archiso/configs/releng/profiledef.sh}"

iso_name="nbshell"
iso_label="NBSHELL_$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y%m)"
iso_publisher="nbshell project"
iso_application="nbshell private preview installer"
iso_version="$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y.%m.%d)"
install_dir="nbshell"
buildmodes=('iso')
bootmodes=('uefi.systemd-boot')
arch="x86_64"
pacman_conf="pacman.conf"
airootfs_image_type="squashfs"
airootfs_image_tool_options=('-comp' 'zstd' '-Xcompression-level' '15')
file_permissions["/usr/local/bin/nbshell-install"]="0:0:755"
file_permissions["/usr/local/lib/nbshell/installer.py"]="0:0:755"
file_permissions["/usr/local/lib/nbshell/target-setup.sh"]="0:0:755"
file_permissions["/usr/local/lib/nbshell/firstboot.sh"]="0:0:755"
