#!/bin/bash

if apt install x11vnc
then
    sudo x11vnc -storepasswd /etc/.vnc_passwd
    cat << EOF > /lib/systemd/system/x11vnc.service
[Unit]
Description=Start x11vnc at startup
After=multi-user.target

[Service]
Type=simple
ExecStart=/usr/bin/x11vnc -auth guess -dontdisconnect -forever -loop -shared -repeat -noxdamage -noxfixes -rfbauth /etc/.vnc_passwd -rfbport 5900 -o /var/log/x11vnc.log

[Install]
WantedBy=multi-user.target
EOF
    sudo systemctl daemon-reload
    sudo systemctl enable x11vnc.service
    sudo systemctl start x11vnc.service
fi

exit 0
