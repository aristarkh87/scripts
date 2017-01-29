#!/bin/bash

if lspci | egrep 'VGA|3D' | grep -q Intel && lspci | egrep 'VGA|3D' | grep -q NVIDIA
then
local opt='n'
read -p 'Do you want to install Bumblebee? (y/N)' opt && echo
    if [[ ${opt} = y ]]
    then
        if dpkg -s nvidia-prime &> /dev/null
        then
            echo 'Removing nvidia-prime...'
            apt-get -y purge nvidia-prime
        fi
    apt install -y nvidia-331 nvidia-settings bumblebee bumblebee-nvidia primus primus-libs:i386"
    fi
fi
