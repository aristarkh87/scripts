#!/usr/bin/env python3
# -*- coding: utf-8 -*-
#
# Copyright 2017 Oleg Dolgikh <aristarkh@aristarkh.net>
#

"""The script for the initial setup of a freshly installed Linux."""

import apt
import os
import os.path
import shutil
import subprocess
from pwd import getpwnam
from getpass import getpass


soft_common = [
    'ttf-mscorefonts-installer',
    'mc',
    'vim',
    'vlc',
    'keepassx',
    'dropbox'
]
soft_gtk = [
    'network-manager-vpnc-gnome',
    'remmina-plugin-rdp'
]
soft_kde = [
    'network-manager-vpnc',
    'krdc'
]
shares = [
    'public',
    'Data',
    'Multimedia'
]
brightness = 70


def is_root():
    """Require run the script as root."""
    if os.getuid() != 0:
        exit('You need to have root privileges to run this script.\n'
             'Please try again, this time using "sudo". Exiting. ')


def get_username():
    """Get login and uid for user. Return tuple (login, uid)."""
    login = 'aristarkh'
    option = input('Your login is {0}? (Y/n) '.format(login))
    while True:
        if option == 'y' or option == '':
            try:
                uid = getpwnam(login).pw_uid
            except KeyError:
                print('ERROR: Login not found\n')
                option = 'n'
            else:
                break
        else:
            login = input('Please, enter your login: ')
            option = 'y'
    return login, uid


def get_chassis():
    """Get chassis type of computer. Return string 'Notebook' or 'Desktop'."""
    chassis = subprocess.check_output(
        'dmidecode -s chassis-type',
        shell=True,
        universal_newlines=True)
    chassis = chassis.split('\n')[0]
    if chassis != 'Desktop' and chassis != 'Notebook':
        menu = '''
\t*** Chassis type ***\n
\t1. Notebook
\t2. Desktop
\t0. Exit
'''
        while True:
            print(menu)
            option = input('Choose your chassis type: ')
            if option == '0':
                exit()
            elif option == '1':
                chassis = 'Notebook'
                break
            elif option == '2':
                chassis = 'Desktop'
                break
            else:
                print('Try again!\n')
    return chassis


def apt_install(softlist):
    """Install software with apt."""
    cache = apt.Cache()
    cache.update()
    not_found = ''
    for soft in softlist:
        try:
            pkg = cache[soft]
        except KeyError:
            not_found += ' {0}'.format(soft)
            continue
        if not pkg.is_installed:
            pkg.mark_install()
    try:
        cache.commit()
    except:
        print('\nERROR: Failed to install software\n')
    cache.close()
    if len(not_found) > 0:
        print('\nWARNING: Package not found:{0}'.format(not_found))


def install_software(chassis):
    """Install default software."""
    cache = apt.Cache()
    if cache['kdelibs-bin'].is_installed:
        softlist = soft_common + soft_kde
    else:
        softlist = soft_common + soft_gtk
    cache.close()
    if chassis == 'Notebook':
        soft_note = [
            'tlp',
            'tlp-rdw',
            'powertop',
            'xbacklight'
        ]
        softlist += soft_note
    apt_install(softlist)
    print('Done')


def setup_firewall():
    """Install and setup netfilter-persistent."""
    script_dir = '/usr/local/scripts'
    os.makedirs(script_dir, exist_ok=True)
    script_iptables4 = '{0}/iptables4.sh'.format(script_dir)
    script_iptables6 = '{0}/iptables6.sh'.format(script_dir)
    localnet4 = '192.168.10.0/24'
    localnet6 = '2a02:17d0:1b0:d700::/64'
    apt_install(['iptables-persistent'])
    print('Creating script {0}...'.format(script_iptables4))
    text = '''\
#!/bin/bash

iptables=/sbin/iptables
localnet=\'{0}\'

# Flush rules
${{iptables}} -F

# Default rules
${{iptables}} -P INPUT DROP
${{iptables}} -P OUTPUT ACCEPT
${{iptables}} -P FORWARD DROP

# General input rules
${{iptables}} -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
${{iptables}} -A INPUT -i lo -j ACCEPT
${{iptables}} -A INPUT -d 127.0.0.0/8 ! -i lo -j DROP
${{iptables}} -A INPUT -p icmp -j ACCEPT
${{iptables}} -A INPUT -d 239.0.0.0/8 -j ACCEPT

# Allow INPUT for samba
${{iptables}} -A INPUT -s ${{localnet}} \
-p udp -m multiport --ports 137,138 -j ACCEPT
${{iptables}} -A INPUT -s ${{localnet}} \
-p tcp -m multiport --dports 139,445 -j ACCEPT

# Allow SSH
${{iptables}} -A INPUT -s ${{localnet}} -p tcp --dport 22 -j ACCEPT

${{iptables}}-save > /etc/iptables/rules.v4
'''.format(localnet4)
    with open(script_iptables4, 'w') as f:
        for line in text:
            f.write(line)
    os.chmod(script_iptables4, 0o755)
    subprocess.call(script_iptables4)
    print('Done')

    print('Creating script {0}...'.format(script_iptables6))
    text = '''\
#!/bin/bash

iptables6=/sbin/ip6tables
localnet=\'{0}\'

# Flush rules
${{iptables6}} -F

# Default rules
${{iptables6}} -P INPUT DROP
${{iptables6}} -P OUTPUT ACCEPT
${{iptables6}} -P FORWARD DROP

# General input rules
${{iptables6}} -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
${{iptables6}} -A INPUT -i lo -j ACCEPT
${{iptables6}} -A INPUT -d ::1/128 ! -i lo -j DROP
${{iptables6}} -A INPUT -p ipv6-icmp -j ACCEPT
${{iptables6}} -A INPUT -d ff00::/8 -j ACCEPT

# Allow samba
${{iptables6}} -A INPUT -s ${{localnet}} \
-p udp -m multiport --ports 137,138 -j ACCEPT
${{iptables6}} -A INPUT -s ${{localnet}} \
-p tcp -m multiport --dports 139,445 -j ACCEPT

${{iptables6}}-save > /etc/iptables/rules.v6
'''.format(localnet6)
    with open(script_iptables6, 'w') as f:
        for line in text:
            f.write(line)
    os.chmod(script_iptables6, 0o755)
    subprocess.call(script_iptables6)
    print('Done')


def setup_mounts(user):
    """Install autofs and setup mounts."""
    softlist = ['autofs', 'cifs-utils']
    nas_name = 'a-nas'
    nas_domain = 'aristarkh.net'
    nas_fqdn = '{0}.{1}'.format(nas_name, nas_domain)
    mount_directory = '/{0}'.format(nas_name)
    mount_directory_home = '/home/{0}/{1}'.format(user[0], nas_name)
    secret_file = '/home/{0}/.{1}'.format(user[0], nas_name)
    print('Setting up {0} mounts...'.format(nas_name))
    password = getpass(prompt='Enter the password to {0}: '.format(nas_name))
    text = (
        'username={0}\n'.format(user[0]),
        'password={0}'.format(password)
    )
    with open(secret_file, 'w') as f:
        for line in text:
            f.write(line)
    os.chown(secret_file, user[1], user[1])
    os.chmod(secret_file, 0o600)
    apt_install(softlist)
    os.makedirs(mount_directory, exist_ok=True)
    os.makedirs(mount_directory_home, exist_ok=True)
    os.chown(mount_directory_home, user[1], user[1])
    if os.path.exists('/etc/auto.{0}'.format(nas_name)):
        os.remove('/etc/auto.{0}'.format(nas_name))
    for share in shares:
        mount_opts = '{0} '\
                     '-fstype=cifs,'\
                     'rw,'\
                     'credentials={1},'\
                     'uid={2},'\
                     'iocharset=utf8 '\
                     '://{3}/{0}\n'
        mount_opts = mount_opts.format(
            share, secret_file, user[1], nas_fqdn)
        with open('/etc/auto.{0}'.format(nas_name), 'a') as f:
            f.write(mount_opts)
            if not os.path.exists(
                '{0}/{1}'.format(mount_directory_home, share)
            ):
                os.symlink(
                    '{0}/{1}'.format(mount_directory, share),
                    '{0}/{1}'.format(mount_directory_home, share)
                )
    os.chmod('/etc/auto.{0}'.format(nas_name), 0o600)
    os.makedirs('/etc/auto.master.d', exist_ok=True)
    if os.path.exists('/etc/auto.master.d/{0}.autofs'.format(nas_name)):
        os.remove('/etc/auto.master.d/{0}.autofs'.format(nas_name))
    print('Creating config file '
          '/etc/auto.master.d/{0}.autofs...'.format(nas_name))
    nas_mount = '{0} /etc/auto.{1} --timeout=30 --ghost'
    nas_mount = nas_mount.format(mount_directory, nas_name)
    with open('/etc/auto.master.d/{0}.autofs'.format(nas_name), 'w') as f:
        f.write(nas_mount)
    subprocess.call('service autofs restart', shell=True)
    print('Done')


def setup_grub():
    """Enable savedefault option in GRUB config."""
    grub_config = '/etc/default/grub'
    bak_file = '{0}.bak'.format(grub_config)
    if not os.path.exists(bak_file):
        shutil.copyfile(grub_config, bak_file)
    with open(grub_config, 'w') as f:
        with open(bak_file) as temp_file:
            for line in temp_file:
                line = line.replace(
                    'GRUB_DEFAULT=0',
                    'GRUB_SAVEDEFAULT=true\n'
                    'GRUB_DEFAULT=saved'
                )
                f.write(line)
    subprocess.call('update-grub')
    print('Done')


def setup_brightness():
    """Setup startup brightness for laptop."""
    rclocal = '/etc/rc.local'
    softlist = ['xbacklight']
    command = 'xbacklight -set {0}'.format(brightness)
    apt_install(softlist)
    with open(rclocal, 'r+') as f:
        text = []
        insert_needed = True
        for line in f:
            if line.startswith('xbacklight'):
                text += [command + '\n']
                insert_needed = False
            else:
                text += [line]
        if insert_needed is True:
                text.insert(-1, command + '\n')
        f.seek(0)
        for line in text:
            f.write(line)
    print('Done')


def setup_conky(user, chassis):
    """Install and setup conky."""
    conky_config = '/home/{0}/.conkyrc'.format(user[0])
    apt_install(['conky'])
    if os.path.exists(conky_config):
        shutil.copyfile(conky_config, conky_config + '.bak')
    network_devices = os.listdir('/sys/class/net')
    network_devices.remove('lo')
    if len(network_devices) < 2:
        if len(network_devices) == 0:
            network_devices = ['eth0', 'wlan0']
        elif len(network_devices) == 1:
            network_devices.append('wlan0')
    text = '''\
conky.config = {{
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
}};

conky.text = [[
${{font Noto Sans [monotype]:bold:size=12}}${{color0}}General\
${{font}}${{color}}
Kernel: ${{alignr}}${{kernel}}
Frequency: ${{alignr}}${{freq}} MHz
Load Average: ${{alignr}}${{loadavg 1 5 15}}
CPU: ${{alignr}}${{cpu cpu1}}% ${{cpubar cpu1 10,75}}
RAM: ${{alignr}}${{memperc}}% ${{membar 10,75}}
SWAP: ${{alignr}}${{swapperc}}% ${{swapbar 10,75}}
Uptime: ${{alignr}}${{uptime}}
${{hr}}
${{font Noto Sans [monotype]:bold:size=12}}${{color0}}Disks${{font}}${{color}}
System (/): ${{alignr}}${{fs_used /}}/${{fs_size /}}
${{alignr}}${{fs_used_perc /}}% ${{fs_bar 10,75 /}}${{if_mounted /home}}
/home: ${{alignr}}${{fs_used /home}}/${{fs_size /home}}
${{alignr}}${{fs_used_perc /home}}% ${{fs_bar 10,75 /home}}${{endif}}
${{hr}}
${{font Noto Sans [monotype]:bold:size=12}}${{color0}}Network\
${{font}}${{color}}${{if_gw}}${{if_up {0}}}
{0}: ${{alignr}}${{addr {0}}}
Upspeed: ${{alignr}}${{upspeed {0}}}
Downspeed: ${{alignr}}${{downspeed {0}}}${{endif}}${{if_up {1}}}
{1}: ${{alignr}}${{addr {1}}}
Upspeed: ${{alignr}}${{upspeed {1}}}
Downspeed: ${{alignr}}${{downspeed {1}}}${{endif}}${{else}}
None${{endif}}
${{hr}}
${{font Noto Sans [monotype]:bold:size=12}}${{color0}}Time and date\
${{font}}${{color}}
Date: ${{alignr}}${{time %d.%m.%Y}}
Local: ${{alignr}}${{time %H:%M}}
Moscow: ${{alignr}}${{tztime Europe/Moscow %H:%M}}
'''.format(*network_devices)
    with open(conky_config, 'w') as f:
        for line in text:
            f.write(line)
    if chassis == 'Notebook':
        text = '''\
${hr}
${font Noto Sans [monotype]:bold:size=12}${color0}Battery${font}${color}
Power Rate: ${alignr}\
${execi 5 cat /sys/class/power_supply/BAT0/power_now | \
awk '{a=$1/1000000; print a}'} W
Charge: ${alignr}${battery}
Time left: ${alignr}${battery_time}
'''
        with open(conky_config, 'a') as f:
            for line in text:
                f.write(line)
    with open(conky_config, 'a') as f:
        f.write(']];\n')
    os.chown(conky_config, user[1], user[1])
    print('Done')


def main_menu(user, chassis):
    """Main menu."""
    menu = '''
\t*** Main menu ***\n
\t1. Install software
\t2. Setup firewall
\t3. Setup mounts
\t4. Setup GRUB
\t5. Setup brightness
\t6. Setup Conky
\t0. Exit
'''
    while True:
        print(menu)
        option = input('Choose action: ')
        if option == '0':
            exit()
        elif option == '1':
            install_software(chassis)
        elif option == '2':
            setup_firewall()
        elif option == '3':
            setup_mounts(user)
        elif option == '4':
            setup_grub()
        elif option == '5':
            setup_brightness()
        elif option == '6':
            setup_conky(user, chassis)


def main():
    """Main function."""
    is_root()
    user = get_username()
    chassis = get_chassis()
    main_menu(user, chassis)


if __name__ == '__main__':
    main()
