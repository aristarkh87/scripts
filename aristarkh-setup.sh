#!/bin/bash
#
#  Copyright 2017 Oleg Dolgikh <aristarkh@aristarkh.net>
#


softlist='ttf-mscorefonts-installer mc vim vlc geany keepassx dropbox'
gtk_softlist='network-manager-vpnc-gnome remmina-plugin-rdp'
kde_softlist='network-manager-vpnc krdc'


# Run as root
if [[ $(whoami) != root ]]
then
    sudo bash "$0" $@
    exit
fi


# Define username
define_username() {
    username=$(id -un 1000)
    while true
    do
        local opt='y'
        read -p "Your login is ${username}? (Y/n/q) " opt
        if [[ ${opt} = q ]]
        then
            echo 'Exiting...'
            exit 0
        elif [[ ${opt} != y ]]
        then
            read -p "Please, enter your login: " username
        fi

        if id -u ${username} &> /dev/null
        then
            user_id=$(id -u ${username})
            break
        else
            echo -e "Login not found\n"
        fi
    done
}


# Define type of PC
define_chassis_type() {
    chassis_type=$(dmidecode -s chassis-type)
    if [[ ${chassis_type} != Desktop ]] && [[ ${chassis_type} != Notebook ]]
    then
        clear
        local options=('Desktop' 'Laptop' 'Exit')
        local PS3='Enter the number: '
        local COLUMNS=1
        echo -e 'What type of PC you have?'
        select option in "${options[@]}"
        do
            case "${option}" in
                'Desktop')
                    chassis_type="Desktop"
                    break
                    ;;
                'Laptop')
                    chassis_type="Notebook"
                    break
                    ;;
                'Exit')
                    echo 'Exiting...'
                    exit 0
                    ;;
                *)
                    echo 'Please, enter the correct number'
                    ;;
            esac
        done
    fi
}


# Define and create directory for scripts
define_script_directory() {
    script_directory="/usr/scripts"
    if [[ ! -d "${script_directory}" ]]
    then
        mkdir -p "${script_directory}"
    fi
}


# Install software
install_software() {
    for i in $*
    do
        if ! dpkg -s "${i}" &> /dev/null
        then
            echo "Installing ${i}..."
            apt-get -y install "${i}"
        fi
    done
}


# Backup file
backup_file() {
    local filename="$1"
    if [[ ! -f "${filename}.bak" ]]
    then
        echo "Backup ${filename}..."
        cp -f "${filename}" "${filename}.bak"
    fi
}


# Main menu
main_menu() {
    local options=('Setup GRUB'
                   'Install software'
                   'Setup firewall'
                   'Setup shares'
                   'Setup Conky'
                   'Setup brightness'
                   'Setup Samba'
                   'Exit')
    local PS3='Enter the number: '
    local COLUMNS=1

    echo -e '\n\t*** Menu ***\n'
    select option in "${options[@]}"
    do
        case "${option}" in
            "${options[0]}")
                setup_grub
                main_menu
                ;;
            "${options[1]}")
                install_general_software
                main_menu
                ;;
            "${options[2]}")
                setup_firewall
                main_menu
                ;;
            "${options[3]}")
                setup_shares
                main_menu
                ;;
            "${options[4]}")
                setup_conky
                main_menu
                ;;
            "${options[5]}")
                setup_brightness
                main_menu
                ;;
            "${options[6]}")
                setup_samba
                main_menu
                ;;
            'Exit')
                echo 'Exiting...'
                exit 0
                ;;
            *)
                echo 'Please, enter the correct number'
                main_menu
                ;;
        esac
    done
}


# Setting up GRUB
setup_grub() {
    local grub_config='/etc/default/grub'
    backup_file ${grub_config}
    echo 'Enable SAVEDEFAULT...'
    sed -i '/GRUB_DEFAULT=0/i GRUB_SAVEDEFAULT=true' ${grub_config}
    sed -i 's/GRUB_DEFAULT=0/GRUB_DEFAULT=saved/' ${grub_config}
#    sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"/GRUB_CMDLINE_LINUX_DEFAULT=""/' ${grub_config}
    update-grub
}


# Installing software
install_general_software() {
    if dpkg -s kde-baseapps-bin &> /dev/null
    then
        local softlist="${softlist} ${kde_softlist}"
    else
        local softlist="${softlist} ${gtk_softlist}"
    fi

    if [[ ${chassis_type} = Notebook ]]
    then
        if add-apt-repository -y ppa:linrunner/tlp
        then
            softlist="${softlist} tlp tlp-rdw powertop xbacklight"
        fi
    fi

    echo 'Updating repositories...'
    if apt-get update &> /dev/null
    then
        install_software ${softlist}
    fi
}


# Setting up firewall
setup_firewall() {
    local iptables_script="${script_directory}/iptables4.sh"
    local ip6tables_script="${script_directory}/iptables6.sh"

    install_software iptables-persistent
    echo "Creating script ${iptables_script}..."
    cat << EOF > "${iptables_script}"
#!/bin/bash

iptables=/sbin/iptables
localnet=192.168.10.0/24

# Flush rules
\${iptables} -F

# Default rules
\${iptables} -P INPUT DROP
\${iptables} -P OUTPUT ACCEPT
\${iptables} -P FORWARD DROP

# General input rules
\${iptables} -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
\${iptables} -A INPUT -i lo -j ACCEPT
\${iptables} -A INPUT -d 127.0.0.0/8 ! -i lo -j DROP
\${iptables} -A INPUT -p icmp -j ACCEPT
\${iptables} -A INPUT -d 239.0.0.0/8 -j ACCEPT

# Allow INPUT for samba
\${iptables} -A INPUT -s \${localnet} -p udp -m multiport --ports 137,138 -j ACCEPT
\${iptables} -A INPUT -s \${localnet} -p tcp -m multiport --dports 139,445 -j ACCEPT

# Allow SSH
#\${iptables} -A INPUT -s \${localnet} -p tcp --dport 22 -j ACCEPT

\${iptables}-save > /etc/iptables/rules.v4
EOF
    echo "Creating script ${ip6tables_script}..."
    cat << EOF > "${ip6tables_script}"
#!/bin/bash

ip6tables=/sbin/ip6tables
localnet=2a02:17d0:1b0:d700::/64

# Flush rules
\${ip6tables} -F

# Default rules
\${ip6tables} -P INPUT DROP
\${ip6tables} -P OUTPUT ACCEPT
\${ip6tables} -P FORWARD DROP

# General input rules
\${ip6tables} -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
\${ip6tables} -A INPUT -i lo -j ACCEPT
\${ip6tables} -A INPUT -d ::1/128 ! -i lo -j DROP
\${ip6tables} -A INPUT -p ipv6-icmp -j ACCEPT
\${ip6tables} -A INPUT -d ff00::/8 -j ACCEPT

# Allow samba
\${ip6tables} -A INPUT -s \${localnet} -p udp -m multiport --ports 137,138 -j ACCEPT
\${ip6tables} -A INPUT -s \${localnet} -p tcp -m multiport --dports 139,445 -j ACCEPT

# Allow SSH
#\${ip6tables} -A INPUT -s \${localnet} -p tcp --dport 22 -j ACCEPT

\${ip6tables}-save > /etc/iptables/rules.v6
EOF
    chmod +x "${iptables_script}"
    chmod +x "${ip6tables_script}"
    "${iptables_script}"
    "${ip6tables_script}"
}


# Setting up shares
setup_shares() {
    local softlist='autofs cifs-utils'
    local nas_name='a-nas'
    local nas_domain='aristarkh.net'
    local nas_fqdn="${nas_name}.${nas_domain}"
    local shares_directory="/${nas_name}"
    local shares[0]='public'
    local shares[1]='Data'
    local shares[2]='Multimedia'
    local secret_file="/home/${username}/.${nas_name}"

    echo "Setting up ${nas_name} mounts..."
    read -sp "Please, enter the password to ${nas_name}: " my_password && echo
    echo -e "username=${username}\npassword=${my_password}" > "${secret_file}"
    chown "${username}": "${secret_file}"
    chmod 600 "${secret_file}"
    install_software ${softlist}
    if [[ ! -d "${shares_directory}" ]]
    then
        echo "Creating directory ${shares_directory}..."
        mkdir "${shares_directory}"
    fi
    if [[ ! -d "/home/${username}/${nas_name}" ]]
    then
        echo "Creating directory /home/${username}/${nas_name}..."
        sudo -u "${username}" mkdir "/home/${username}/${nas_name}"
    fi
    if [[ ! -f /etc/auto.${nas_name} ]]
    then
        rm /etc/auto.${nas_name}
    fi
    for share in ${shares[@]}
    do
        echo "${share} -fstype=cifs,rw,credentials=${secret_file},uid=${user_id},iocharset=utf8 ://${nas_fqdn}/${share}" >> /etc/auto.${nas_name}
        ln -s "${shares_directory}/${share}/" "/home/${username}/${nas_name}"
    done
    echo >> /etc/auto.${nas_name}
    chmod 600 /etc/auto.${nas_name}
    if [[ ! -d /etc/auto.master.d ]]
    then
        echo "Creating directory /etc/auto.master.d..."
        mkdir /etc/auto.master.d
    else
        echo > /etc/auto.master.d/${nas_name}.autofs
    fi
    echo "Creating config file /etc/auto.master.d/${nas_name}.autofs"
    echo "$shares_directory /etc/auto.${nas_name} --timeout=30 --ghost" > /etc/auto.master.d/${nas_name}.autofs
    sleep 1
    service autofs restart
}

# Setting up Conky
setup_conky() {
    local conky_config="/home/${username}/.conkyrc"

    install_software conky
    local network_interfaces=$(ip link | grep 'UP' | awk '{print $2}' | tr -cs [:alnum:] ' ' | sed 's/.$//')
    read -p "Please, enter the Ethernet interface that you want to monitor (${network_interfaces}) [default: eth0]: " if_eth
    read -p "Please, enter the WLAN interface that you want to monitor (${network_interfaces}) [default: wlan0]: " if_wlan && echo
    if [[ ! ${if_eth} ]]
    then
        local if_eth='eth0'
    fi
    if [[ ! ${if_wlan} ]]
    then
        local if_wlan='wlan0'
    fi
    echo "Creating conky config file ${conky_config}..."
    backup_file "${conky_config}"
    cat << EOF > "${conky_config}"
conky.config = {
    use_xft = true,
    font = 'Noto Sans [monotype]:size=10',
    override_utf8_locale = true,
    background = true,
    update_interval = 1,
    total_run_times = 0,
    double_buffer = true,
    no_buffers = true,
    net_avg_samples = 2,
    text_buffer_size = 1024,
    if_up_strictness = 'address',
    short_units = true,
    own_window = true,
    own_window_transparent = true,
    own_window_type = 'desktop',
    own_window_hints = 'undecorated,below,sticky,skip_taskbar,skip_pager',
    draw_borders = false,
    draw_shades = true,
    default_color = 'white',
    color0 = 'orange',
    minimum_height = 700,
    gap_x = 10,
    gap_y = 40,
    alignment = 'top_right',
};

conky.text = [[
\${font Noto Sans [monotype]:bold:size=12}\${color0}General\${font}\${color}
Kernel: \${alignr}\${kernel}
Frequency: \${alignr}\${freq} MHz
Load Average: \${alignr}\${loadavg 1 5 15}
CPU: \${alignr}\${cpu cpu1}% \${cpubar cpu1 10,75}
RAM: \${alignr}\${memperc}% \${membar 10,75}
SWAP: \${alignr}\${swapperc}% \${swapbar 10,75}
Uptime: \${alignr}\${uptime}
\${hr}
\${font Noto Sans [monotype]:bold:size=12}\${color0}Disks\${font}\${color}
System (/): \${alignr}\${fs_used /}/\${fs_size /}
\${alignr}\${fs_used_perc /}% \${fs_bar 10,75 /}\${if_mounted /home}
/home: \${alignr}\${fs_used /home}/\${fs_size /home}
\${alignr}\${fs_used_perc /home}% \${fs_bar 10,75 /home}\${endif}
\${hr}
\${font Noto Sans [monotype]:bold:size=12}\${color0}Network\${font}\${color}\${if_gw}\${if_up ${if_eth}}
Ethernet: \${alignr}\${addr ${if_eth}}
Upspeed: \${alignr}\${upspeed ${if_eth}}
Downspeed: \${alignr}\${downspeed ${if_eth}}\${endif}\${if_up ${if_wlan}}
WLAN: \${alignr}\${addr ${if_wlan}}
Upspeed: \${alignr}\${upspeed ${if_wlan}}
Downspeed: \${alignr}\${downspeed ${if_wlan}}\${endif}\${else}
None\${endif}
\${hr}
\${font Noto Sans [monotype]:bold:size=12}\${color0}Time and date\${font}\${color}
Date: \${alignr}\${time %d.%m.%Y}
Local: \${alignr}\${time %H:%M}
Moscow: \${alignr}\${tztime Europe/Moscow %H:%M}
EOF
    if [[ ${chassis_type} = Notebook ]]
    then
        cat << EOF >> "${conky_config}"
\${hr}
\${font Noto Sans [monotype]:bold:size=12}\${color0}Battery\${font}\${color}
Power Rate: \${alignr}\${execi 5 cat /sys/class/power_supply/BAT0/power_now | awk '{a=\$1/1000000; print a}'} W
Charge: \${alignr}\${battery}
Time left: \${alignr}\${battery_time}
EOF
    fi
    echo ']];' >> "${conky_config}"
    chown ${username}: "${conky_config}"
}


# Setting up brightness
setup_brightness() {
    while true
    do
        read -p "Please, enter startup brightness (30-100): " brightness
        if [[ $brightness -ge 30 ]] && [[ $brightness -le 100 ]]
        then
            break
        else
            echo -e "Wrong value! Please, enter value between 30 and 100\n"
        fi
    done

    install_software xbacklight
    xbacklight -set ${brightness}
    if grep -q 'xbacklight' /etc/rc.local
    then
        sed -i "s/.*xbacklight.*/xbacklight -set ${brightness}/" /etc/rc.local
    else
        sed -i "\$i\xbacklight -set ${brightness}\n" /etc/rc.local
    fi
    echo "Startup brightness is set to ${brightness}"
}


# Setting up Samba
setup_samba() {
    local smb_config='/etc/samba/smb.conf'
    install_software samba
    backup_file ${smb_config}
    egrep -v '(^#|^;)' "${smb_config}.bak" | uniq > "${smb_config}"
    echo 'Setting up samba...'
    echo -e '[Misc$]\n   path = /windows/misc\n   read only = no\n   guest ok = yes\n' >> "${smb_config}"
    echo -e '[Misc]\n   comment = Misc\n   path = /windows/misc/Misc\n   read only = yes\n   guest ok = yes\n' >> "${smb_config}"
    service nmbd restart
    service smbd restart
}


# Begin
define_username
define_chassis_type
define_script_directory
main_menu

exit 0
