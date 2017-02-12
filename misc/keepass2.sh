#!/bin/bash

if apt-add-repository -y ppa:dlech/keepass2-plugins
then
    apt update
    apt install -y keepass2 mono-complete xdotool keepass2-plugin-application-indicator
fi
