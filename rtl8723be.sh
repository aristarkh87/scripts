#! /bin/bash

echo "options rtl8723be ips=0 fwlps=0 swlps=0" | sudo tee /etc/modprobe.d/rtl8723be.conf
