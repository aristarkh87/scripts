#!/bin/bash

touchpad_file='/etc/X11/xorg.conf.d/20-touchpad.conf'

cat << EOF > "${touchpad_file}"
Section "InputClass"
    Identifier "touchpad"
    Driver "synaptics"
    MatchIsTouchpad "on"
        Option "TapButton1" "1"
        Option "TapButton2" "3"
        Option "TapButton3" "2"
        Option "VertEdgeScroll" "off"
        Option "VertTwoFingerScroll" "on"
        Option "VertScrollDelta" "-111"
        Option "HorizEdgeScroll" "off"
        Option "HorizTwoFingerScroll" "off"
EndSection
EOF
