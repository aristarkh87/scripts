#!/bin/bash

smb_config='/etc/samba/smb.conf'
apt install samba
cp -n "${smb_config}" "${smb_config}.bak"
cat << EOF >> "${smb_config}"

[Misc$]
    path = /windows/misc
    read only = no
    guest ok = yes,
[Misc]
    comment = Misc
    path = /windows/misc/Misc
    read only = yes
    guest ok = yes
EOF
service nmbd restart
service smbd restart
