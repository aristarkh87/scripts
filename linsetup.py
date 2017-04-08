#!/usr/bin/env python3
# -*- coding: utf-8 -*-
#
# Copyright 2017 Oleg Dolgikh <aristarkh@aristarkh.net>
#

"""The script for the initial setup of a freshly installed Linux."""

import apt
import os
import os.path
import pwd
import shutil
import subprocess
from getpass import getpass


def is_root():
    """Require run the script as root."""
    if os.getuid() != 0:
        exit('You need to have root privileges to run this script.\n'
             'Please try again, this time using "sudo". Exiting. ')


class GetInfo:
    """Get login, uid and chassis type."""

    def __init__(self):
        """Init for class."""
        self.get_user()
        self.get_chassis()

    def get_user(self):
        """Get login and uid for user."""
        self.login = 'aristarkh'
        try:
            self.uid = pwd.getpwnam(self.login).pw_uid
        except KeyError:
            while True:
                self.login = input('Enter your login: ')
                try:
                    self.uid = pwd.getpwnam(self.login).pw_uid
                except KeyError:
                    print('ERROR: Login not found\n')
                else:
                    break
        return self.login, self.uid

    def get_chassis(self):
        """Get chassis type of computer."""
        self.chassis = subprocess.check_output('dmidecode -s chassis-type',
                                               shell=True,
                                               universal_newlines=True)
        self.chassis = self.chassis.split('\n')[0]

        if self.chassis != 'Desktop' and self.chassis != 'Notebook':
            menu = ('\n\t*** Chassis type ***\n',
                    '\t1. Notebook',
                    '\t2. Desktop',
                    '\t0. Exit\n')
            while True:
                for line in menu:
                    print(line)
                option = input('Select your chassis type: ')
                if option == '0':
                    exit()
                elif option == '1':
                    self.chassis = 'Notebook'
                    break
                elif option == '2':
                    self.chassis = 'Desktop'
                    break
                else:
                    print('Select the correct number!')
        return self.chassis


def apt_install(softlist):
    """Install software with apt."""
    cache = apt.Cache()
    not_found = []
    if type(softlist) == str:
        softlist = softlist.split(' ')
    for soft in softlist:
        try:
            pkg = cache[soft]
        except KeyError:
            not_found.append(soft)
            continue
        pkg.mark_install()
    if cache.install_count > 0:
        try:
            cache.update()
            cache.commit()
        except Exception as e:
            print('ERROR:', e)
    cache.close()
    if len(not_found) > 0:
        not_found = ', '.join(not_found)
        print('WARNING: Package not found:', not_found)


def setup_grub():
    """Enable savedefault option in GRUB config."""
    grub_config = '/etc/default/grub'
    bak_file = '.'.join((grub_config, 'bak'))

    if not os.path.exists(bak_file):
        shutil.copyfile(grub_config, bak_file)
    with open(grub_config, 'w') as f:
        with open(bak_file) as temp_file:
            for line in temp_file:
                line = line.replace('GRUB_DEFAULT=0',
                                    'GRUB_SAVEDEFAULT=true\n'
                                    'GRUB_DEFAULT=saved')
                f.write(line)
    subprocess.call('update-grub')
    print('Done')


def install_software():
    """Install default software."""
    softlist_common = ('ttf-mscorefonts-installer', 'mc', 'vim', 'htop',
                       'vlc', 'keepassx')
    softlist_gtk = ('network-manager-vpnc-gnome', 'remmina-plugin-rdp')
    softlist_kde = ('network-manager-vpnc', 'krdc', 'yakuake')

    cache = apt.Cache()
    if cache['plasma-desktop'].is_installed:
        softlist = softlist_common + softlist_kde
    else:
        softlist = softlist_common + softlist_gtk
    cache.close()
    if chassis == 'Notebook':
        softlist_note = ('tlp', 'tlp-rdw', 'powertop', 'xbacklight')
        softlist += softlist_note
    apt_install(softlist)
    print('Done')


def setup_firewall():
    """Install and setup netfilter-persistent."""
    script_dir = '/usr/local/scripts'
    script_iptables4 = '{0}/iptables4.sh'.format(script_dir)
    script_iptables6 = '{0}/iptables6.sh'.format(script_dir)
    localnet4 = '192.168.10.0/24'
    localnet6 = '2a02:17d0:1b0:d700::/64'

    os.makedirs(script_dir, exist_ok=True)
    apt_install('iptables-persistent')
    print('Creating script', script_iptables4)
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
        f.write(text)
    os.chmod(script_iptables4, 0o755)
    subprocess.call(script_iptables4)
    print('Done')

    print('Creating script', script_iptables6)
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
        f.write(text)
    os.chmod(script_iptables6, 0o755)
    subprocess.call(script_iptables6)
    print('Done')


def setup_autofs():
    """Install autofs and setup mounts."""
    shares = ('public', 'Data', 'Multimedia')
    softlist = ('autofs', 'cifs-utils')
    nas_name = 'a-nas'
    nas_domain = 'aristarkh.net'
    nas_fqdn = '.'.join((nas_name, nas_domain))
    mount_directory = '/{0}'.format(nas_name)
    mount_directory_home = '/home/{0}/{1}'.format(login, nas_name)
    secret_file = '/home/{0}/.{1}'.format(login, nas_name)

    print('Setting up {0} mounts'.format(nas_name))
    username = input(
        'Please, enter your login for {0} [{1}]: '.format(nas_name, login))
    if username == '':
        username = login
    password = getpass(prompt='Enter the password for {0}: '.format(nas_name))
    text = ('username={0}\n'.format(username),
            'password={0}\n'.format(password))
    with open(secret_file, 'w') as f:
        f.writelines(text)
    os.chown(secret_file, uid, uid)
    os.chmod(secret_file, 0o600)
    apt_install(softlist)
    os.makedirs(mount_directory, exist_ok=True)
    os.makedirs(mount_directory_home, exist_ok=True)
    os.chown(mount_directory_home, uid, uid)
    if os.path.exists('/etc/auto.{0}'.format(nas_name)):
        os.remove('/etc/auto.{0}'.format(nas_name))
    for share in shares:
        mount_opts = '{0} -fstype=cifs,rw,credentials={1},uid={2},'\
                     'iocharset=utf8 ://{3}/{0}\n'
        mount_opts = mount_opts.format(share, secret_file, uid, nas_fqdn)
        with open('/etc/auto.{0}'.format(nas_name), 'a') as f:
            f.write(mount_opts)
            if not os.path.exists(
                    '{0}/{1}'.format(mount_directory_home, share)):
                os.symlink('{0}/{1}'.format(mount_directory, share),
                           '{0}/{1}'.format(mount_directory_home, share))
    os.chmod('/etc/auto.{0}'.format(nas_name), 0o600)
    os.makedirs('/etc/auto.master.d', exist_ok=True)
    if os.path.exists('/etc/auto.master.d/{0}.autofs'.format(nas_name)):
        os.remove('/etc/auto.master.d/{0}.autofs'.format(nas_name))
    print('Creating config file '
          '/etc/auto.master.d/{0}.autofs'.format(nas_name))
    nas_mount = '{0} /etc/auto.{1} --timeout=30 --ghost'
    nas_mount = nas_mount.format(mount_directory, nas_name)
    with open('/etc/auto.master.d/{0}.autofs'.format(nas_name), 'w') as f:
        f.write(nas_mount)
    subprocess.call('service autofs restart', shell=True)
    print('Done')


def setup_vim():
    """Install and setup VIM."""
    vim_config = '/home/{0}/.vimrc'.format(login)
    apt_install('vim')
    if os.path.exists(vim_config):
        bak_file = '.'.join((vim_config, 'bak'))
        shutil.copyfile(vim_config, bak_file)
        os.chown(bak_file, uid, uid)
    text = '''\
syntax on

set nocompatible
set encoding=utf-8
set termencoding=utf-8
set fileencodings=utf-8,cp1251,koi8-r,cp866

set title
set laststatus=2
set statusline=%t\ %h%w%m%r[%{&ff},%{strlen(&fenc)?&fenc:'none'}]%y%=\
%-14.(%c,%l/%L%)\ %P
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
'''
    with open(vim_config, 'w') as f:
        f.write(text)
    os.chown(vim_config, uid, uid)
    subprocess.call('update-alternatives --set editor /usr/bin/vim.basic',
                    shell=True)
    print('Done')


def setup_brightness():
    """Setup startup brightness for laptop."""
    brightness = 70
    brightness_file = '/etc/X11/Xsession.d/98brightness'
    command = '/usr/bin/xbacklight -set {0}\n'.format(brightness)

    apt_install('xbacklight')
    with open(brightness_file, 'w') as f:
        f.write(command)
    print('Done')


def setup_conky():
    """Install and setup conky."""
    conky_config = '/home/{0}/.conkyrc'.format(login)

    apt_install('conky')
    if os.path.exists(conky_config):
        bak_file = '.'.join((conky_config, 'bak'))
        shutil.copyfile(conky_config, bak_file)
        os.chown(bak_file, uid, uid)
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
    if chassis == 'Notebook':
        text += '''\
${hr}
${font Noto Sans [monotype]:bold:size=12}${color0}Battery${font}${color}
Power Rate: ${alignr}\
${execi 5 cat /sys/class/power_supply/BAT0/power_now | \
awk '{a=$1/1000000; print a}'} W
Charge: ${alignr}${battery}
Time left: ${alignr}${battery_time}
'''
    text += ']];\n'
    with open(conky_config, 'w') as f:
        f.write(text)
    os.chown(conky_config, uid, uid)
    print('Done')


def main_menu():
    """Main menu."""
    menu = ('\n\t*** Main menu ***\n',
            '\t1. Setup GRUB',
            '\t2. Install software',
            '\t3. Setup firewall',
            '\t4. Setup automount',
            '\t5. Setup VIM',
            '\t6. Setup brightness',
            '\t7. Setup Conky',
            '\t0. Exit\n')
    while True:
        for line in menu:
            print(line)
        option = input('Select an action: ')
        if option == '0':
            exit()
        elif option == '1':
            setup_grub()
        elif option == '2':
            install_software()
        elif option == '3':
            setup_firewall()
        elif option == '4':
            setup_autofs()
        elif option == '5':
            setup_vim()
        elif option == '6':
            setup_brightness()
        elif option == '7':
            setup_conky()
        else:
            print('Select the correct number!')


def main():
    """Main function."""
    is_root()
    get_info = GetInfo()
    global login
    global uid
    global chassis
    login = get_info.login
    uid = get_info.uid
    chassis = get_info.chassis
    main_menu()


if __name__ == '__main__':
    main()
