#!/usr/bin/env bash
#
# Copyright (c) 2017 Oleg Dolgikh
#

softlist_common='mc sudo htop vlc'
softlist_gtk='vpnc networkmanager-vpnc network-manager-vpnc-gnome freerdp remmina remmina-plugin-rdp'
softlist_kde='vpnc networkmanager-vpnc network-manager-vpnc krdc yakuake'
softlist_note='tlp tlp-rdw powertop'


generate_softlist() {
    if [[ KDE = ${DE} ]]; then
        local softlist="${softlist_common} ${softlist_kde}"
    else
        local softlist="${softlist_common} ${softlist_gtk}"
    fi
    if [[ ${chassis_type} = Notebook ]]; then
        local softlist="${softlist} ${softlist_note}"
    fi
    install_software ${softlist}
    echo 'Done'
}


setup_firewall() {
    local iptables_script="/etc/iptables/iptables.sh"
    local localnet4='192.168.10.0/24'
    local localnet6='2a02:17d0:1b0:d700::/64'

    case "${pm}" in
        'pm_apt')
            local iptables_file=/etc/iptables/rules.v4
            local ip6tables_file=/etc/iptables/rules.v6
            install_software iptables-persistent
            ;;
        'pm_pacman')
            local iptables_file=/etc/iptables/iptables.rules
            local ip6tables_file=/etc/iptables/ip6tables.rules
            systemctl enable iptables
            systemctl enable ip6tables
            ;;
        *)
            local iptables_file=/etc/iptables/rules.v4
            local ip6tables_file=/etc/iptables/rules.v6
            ;;
    esac

    echo "Creating script ${iptables_script}..."
    mkdir /etc/iptables
    cat << EOF > "${iptables_script}"
#!/bin/bash

iptables=/sbin/iptables
ip6tables=/sbin/ip6tables
localnet4=${localnet4}
localnet6=${localnet6}

# Flush rules
\${iptables} -F
\${ip6tables} -F

# Default rules
\${iptables} -P INPUT DROP
\${iptables} -P OUTPUT ACCEPT
\${iptables} -P FORWARD DROP
\${ip6tables} -P INPUT DROP
\${ip6tables} -P OUTPUT ACCEPT
\${ip6tables} -P FORWARD DROP

# General input rules
\${iptables} -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
\${ip6tables} -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
\${iptables} -A INPUT -i lo -j ACCEPT
\${ip6tables} -A INPUT -i lo -j ACCEPT
\${iptables} -A INPUT -p icmp -j ACCEPT
\${ip6tables} -A INPUT -p ipv6-icmp -j ACCEPT

# Allow multicast
\${iptables} -A INPUT -d 239.0.0.0/8 -j ACCEPT
\${ip6tables} -A INPUT -d ff00::/8 -j ACCEPT

# Allow INPUT for samba
\${iptables} -A INPUT -s \${localnet4} -p udp -m multiport --ports 137,138 -j ACCEPT
\${ip6tables} -A INPUT -s \${localnet6} -p udp -m multiport --ports 137,138 -j ACCEPT
\${iptables} -A INPUT -s \${localnet4} -p tcp -m multiport --dports 139,445 -j ACCEPT
\${ip6tables} -A INPUT -s \${localnet6} -p tcp -m multiport --dports 139,445 -j ACCEPT

# Allow SSH
\${iptables} -A INPUT -s \${localnet4} -p tcp --dport 22 -j ACCEPT
\${ip6tables} -A INPUT -s \${localnet6} -p tcp --dport 22 -j ACCEPT

# Save rules
\${iptables}-save > ${iptables_file}
\${ip6tables}-save > ${ip6tables_file}
EOF
    chmod +x "${iptables_script}"
    "${iptables_script}"
    echo 'Done'
}


setup_autofs() {
    local shares='Multimedia Data public'
    local softlist='autofs cifs-utils'
    local nas_name='a-nas'
    local nas_domain='aristarkh.net'
    local nas_fqdn="${nas_name}.${nas_domain}"
    local secret_file="/home/${user_name}/.${nas_name}"
    local mount_directory="/storage"

    echo "Setting up ${nas_name} mounts..."
    read -p "Please, enter your login for ${nas_fqdn} [${user_name}]: " username
    if [[ ! ${username} ]]; then
        username=${user_name}
    fi
    read -sp "Please, enter the password to ${nas_name}: " password && echo
    echo -e "username=${username}\npassword=${password}" > "${secret_file}"
    chown "${user_name}": "${secret_file}"
    chmod 600 "${secret_file}"
    install_software ${softlist}
    if [[ ! -d "${mount_directory}" ]]; then
        echo "Creating directory ${mount_directory}..."
        mkdir -p "${mount_directory}"
    fi
    case "${pm}" in
        'pm_apt')
            local autofs_dir='/etc'
            ;;
        'pm_pacman')
            local autofs_dir='/etc/autofs'
            ;;
        *)
            local autofs_dir='/etc'
            ;;
    esac
    if [[ ! -d "${autofs_dir}/auto.master.d" ]]; then
        echo "Creating directory ${autofs_dir}/auto.master.d..."
        mkdir "${autofs_dir}/auto.master.d"
    fi
    echo "Creating config file ${autofs_dir}/auto.master.d/${nas_name}.autofs"
    echo "${mount_directory} ${autofs_dir}/auto.storage --timeout=30 --ghost" > "${autofs_dir}/auto.master.d/${nas_name}.autofs"
    if [[ -f "${autofs_dir}/auto.storage" ]]; then
        rm "${autofs_dir}/auto.storage"
    fi
    for share in ${shares}; do
        echo "${share} -fstype=cifs,rw,_netdev,vers=3.0,credentials=${secret_file},uid=${user_name},gid=${user_name},file_mode=0644,dir_mode=0755,iocharset=utf8 ://${nas_fqdn}/${share}" >> "${autofs_dir}/auto.storage"
    done
    chmod 600 "${autofs_dir}/auto.storage"
    ln -fs "${mount_directory}" "/home/${user_name}"
    chown "${user_name}":"${user_name}" "/home/${user_name}"
    systemctl enable autofs
    systemctl restart autofs
    echo 'Done'
}


# Deprecated
setup_automount() {
    local nas_name='a-nas'
    local nas_domain='aristarkh.net'
    local shares='public Data Multimedia'
    local nas_fqdn="${nas_name}.${nas_domain}"
    local secret_file="/home/${user_name}/.${nas_name}"
    local mount_directory="/storage"

    echo "Setting up ${nas_name} mounts..."
    read -p "Please, enter your login for ${nas_fqdn} [${user_name}]: " username
    if [[ ! ${username} ]]; then
        username=${user_name}
    fi
    read -sp "Please, enter the password to ${nas_name}: " password && echo
    echo -e "username=${username}\npassword=${password}" > "${secret_file}"
    chown "${user_name}": "${secret_file}"
    chmod 600 "${secret_file}"
    install_software cifs-utils
    echo "Creating directory ${mount_directory}..."
    mkdir "${mount_directory}"
    for share in ${shares}; do
        mkdir "${mount_directory}/${share}"
        unit_mount="/etc/systemd/system/$(basename ${mount_directory})-${share}.mount"
        unit_automount="/etc/systemd/system/$(basename ${mount_directory})-${share}.automount"
        cat << EOF > "${unit_mount}"
[Unit]
Description=${share} Folder
After=remote-fs.target

[Mount]
What=//${nas_fqdn}/${share}
Where=${mount_directory}/${share}
Type=cifs
Options=_netdev,vers=3.0,credentials=${secret_file},uid=${user_name},iocharset=utf8
EOF
        cat << EOF > "${unit_automount}"
[Unit]
Description=Automount ${share} Folder
After=remote-fs.target

[Automount]
Where=${mount_directory}/${share}
TimeoutIdleSec=30

[Install]
WantedBy=remote-fs.target
EOF
        systemctl daemon-reload
        systemctl start $(basename ${unit_automount})
        systemctl enable $(basename ${unit_automount})
    done
    sudo -u ${user_name} ln -s "${mount_directory}" "/home/${user_name}"
    echo 'Done'
}


setup_nano() {
    nano_config="/home/${user_name}/.nanorc"
    install_software nano
    sed -i '/include "\/usr\/share\/nano\/\*\.nanorc"/s/# //' /etc/nanorc
    cat << EOF > "${nano_config}"
set tabsize 4
set tabstospaces
EOF
    chown ${user_name}: "${nano_config}"
    echo 'Done'
}


setup_vim() {
    vim_config="/home/${user_name}/.vimrc"
    install_software vim
    cat << EOF > "${vim_config}"
syntax on

set nocompatible
set encoding=utf-8
set termencoding=utf-8
set fileencodings=utf-8,cp1251,koi8-r,cp866

set title
set laststatus=2
set statusline=%t\ %h%w%m%r[%{&ff},%{strlen(&fenc)?&fenc:'none'}]%y%=%-14.(%c,%l/%L%)\ %P
set wildmenu
set showcmd

set wrap
set linebreak
set showmatch
set incsearch
set autoread
set listchars=eol:$,tab:>-,trail:.

set shiftwidth=4
set softtabstop=4
set tabstop=4
set expandtab
set autoindent
set smartindent
set pastetoggle=<F2>
EOF
    chown ${user_name}: "${vim_config}"
    echo 'Done'
}


setup_grub() {
    local grub_config='/etc/default/grub'
    cp -n "${grub_config}" "${grub_config}.bak"
    echo 'Enable SAVEDEFAULT...'
    if grep -q GRUB_SAVEDEFAULT ${grub_config}; then
        sed -i 's/^.*GRUB_SAVEDEFAULT.*$/GRUB_SAVEDEFAULT=true/' ${grub_config}
    else
        echo 'GRUB_SAVEDEFAULT=true' >> ${grub_config}
    fi
    sed -i 's/^.*GRUB_DEFAULT=.*$/GRUB_DEFAULT=saved/' ${grub_config}
    sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT=.*$/GRUB_CMDLINE_LINUX_DEFAULT=""/' ${grub_config}
    grub-mkconfig -o /boot/grub/grub.cfg
    echo 'Done'
}


setup_backlight() {
    local brightness=70
    case ${pm} in
    'pm_apt')
        local backlight_file='/etc/X11/Xsession.d/99backlight'
        install_software xbacklight
        ;;
    'pm_pacman')
        local backlight_file='/etc/X11/xinit/xinitrc.d/99backlight'
        echo '#!/bin/sh' > "${backlight_file}"
        chmod +x "${backlight_file}"
        install_software xorg-xbacklight
        ;;
    *)
        echo 'ERROR Unknown packet manager.'
        return
        ;;
    esac
    echo "xbacklight -set ${brightness}" >> "${backlight_file}"
    bash "${backlight_file}"
    echo "Startup brightness is set to ${brightness}"
    echo 'Done'
}


setup_conky() {
    local conky_config="/home/${user_name}/.conkyrc"
    install_software conky
    local net_ifaces=($(ls -1 /sys/class/net | grep -v 'lo'))
    while [[ ${#net_ifaces[@]} -lt 2 ]]; do
        net_ifaces+=(none)
    done
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
\${font Noto Sans [monotype]:bold:size=12}\${color0}Network\${font}\${color}\${if_gw}\${if_up ${net_ifaces[0]}}
${net_ifaces[0]}: \${alignr}\${addr ${net_ifaces[0]}}
Upspeed: \${alignr}\${upspeed ${net_ifaces[0]}}
Downspeed: \${alignr}\${downspeed ${net_ifaces[0]}}\${endif}\${if_up ${net_ifaces[1]}}
${net_ifaces[1]}: \${alignr}\${addr ${net_ifaces[1]}}
Upspeed: \${alignr}\${upspeed ${net_ifaces[1]}}
Downspeed: \${alignr}\${downspeed ${net_ifaces[1]}}\${endif}\${else}
None\${endif}
\${hr}
\${font Noto Sans [monotype]:bold:size=12}\${color0}Time and date\${font}\${color}
Date: \${alignr}\${time %d.%m.%Y}
Local: \${alignr}\${time %H:%M}
Moscow: \${alignr}\${tztime Europe/Moscow %H:%M}
EOF
    if [[ ${chassis_type} = Notebook ]]; then
        cat << EOF >> "${conky_config}"
\${hr}
\${font Noto Sans [monotype]:bold:size=12}\${color0}Battery\${font}\${color}
Power Rate: \${alignr}\${execi 5 cat /sys/class/power_supply/BAT0/power_now | awk '{a=\$1/1000000; print a}'} W
Charge: \${alignr}\${battery}
Time left: \${alignr}\${battery_time}
EOF
    fi
    echo ']];' >> "${conky_config}"
    chown ${user_name}: "${conky_config}"
    echo 'Done'
}


install_software() {
    case ${pm} in
    'pm_apt')
        for i in $*; do
            apt-get install ${i}
        done
        ;;
    'pm_pacman')
        pacman -Syu
        for i in $*; do
            pacman -S ${i} --needed
        done
        ;;
    *)
        echo 'ERROR Unknown OS. Unable to install software.'
        ;;
    esac
}


get_chassis() {
    chassis_type=$(dmidecode -s chassis-type 2> /dev/null)
    if [[ ${chassis_type} != Desktop ]] && [[ ${chassis_type} != Notebook ]]; then
        local options=('Desktop' 'Laptop' 'Exit')
        local PS3='Select your chassis type: '
        local COLUMNS=1
        echo -e 'What type of PC you have?'
        select option in "${options[@]}"; do
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
                    echo 'Please, enter the correct number!'
                    ;;
            esac
        done
    fi
}


get_pm(){
    os_name=$(grep '^NAME=' /etc/os-release | awk -F '"' '{print $2}')
    case "${os_name}" in
        'Ubuntu'|'Linux Mint'|'KDE Neon' )
            pm='pm_apt'
            ;;
        'Arch Linux'|'Manjaro Linux')
            pm='pm_pacman'
            ;;
        *)
            pm='unknown'
            ;;
    esac
}


get_de() {
    case "$XDG_CURRENT_DESKTOP" in
        'KDE')
            DE='KDE'
            ;;
        'GNOME'|'XFCE'|'MATE'|'X-Cinnamon')
            DE='GTK'
            ;;
        *)
            echo "WARNING: Unable to define your Desktop: $XDG_CURRENT_DESKTOP."
            DE='unknown'
            ;;
    esac
}


main_menu() {
    local options=('Install software'
                   'Setup firewall'
                   'Setup automount'
                   'Setup Nano'
                   'Setup Vim'
                   'Setup GRUB'
                   'Setup backlight'
                   'Setup Conky'
                   'Exit')
    local PS3='Enter the number: '
    local COLUMNS=1

    echo -e '\n\t*** Menu ***\n'
    select option in "${options[@]}"; do
        case "${option}" in
            "${options[0]}")
                generate_softlist
                main_menu
                ;;
            "${options[1]}")
                setup_firewall
                main_menu
                ;;
            "${options[2]}")
                setup_autofs
                main_menu
                ;;
            "${options[3]}")
                setup_nano
                main_menu
                ;;
            "${options[4]}")
                setup_vim
                main_menu
                ;;
            "${options[5]}")
                setup_grub
                main_menu
                ;;
            "${options[6]}")
                setup_backlight
                main_menu
                ;;
            "${options[7]}")
                setup_conky
                main_menu
                ;;
            'Exit')
                echo 'Exiting...'
                exit 0
                ;;
            *)
                echo 'Please, select the correct number!'
                main_menu
                ;;
        esac
    done
}


main() {
    if [[ $(whoami) != root ]]; then
        sudo -E bash "$0" $(whoami) "$@"
        exit
    else
        if [[ '' != $1 ]] && id $1 &> /dev/null; then
            user_name=$1
            shift
        else
            read -p 'Enter you login: ' user_name
        fi
    fi
    get_chassis
    get_pm
    get_de
    main_menu
}

main "$@"
