#!/bin/bash

username=$(id -un 1000)
if apt install -y wireshark
then
    dpkg-reconfigure wireshark-common
    usermod -aG wireshark ${username}
    if [ -f /usr/bin/dumpcap ]
    then
        chmod +x /usr/bin/dumpcap
    fi
fi
