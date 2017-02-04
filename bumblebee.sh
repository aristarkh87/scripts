#!/bin/bash

if lspci | egrep 'VGA|3D' | grep -q Intel && lspci | egrep 'VGA|3D' | grep -q NVIDIA
then
    opt='n'
    read -p 'Do you want to install Bumblebee? (y/N)' opt && echo
    if [[ ${opt} = y ]]
    then
        if dpkg -s nvidia-prime &> /dev/null
        then
            echo 'Removing nvidia-prime...'
            apt purge -y nvidia-prime
        fi
    apt update
    apt install -y nvidia-331 nvidia-settings bumblebee bumblebee-nvidia primus primus-libs:i386"
    fi
fi
