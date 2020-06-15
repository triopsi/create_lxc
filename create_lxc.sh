#/bin/bash
#---------------------------------------------------------------------
# Scriptname: create_lxc.sh
# Description: Create VM(LXC) on the host
# Date: 15.06.2020
# Version: 0.1
#---------------------------------------------------------------------
echo "
  _     __   _______ 
 | |    \ \ / / ____|
 | |     \ V / |     
 | |      > <| |     
 | |____ / . \ |____ 
 |______/_/ \_\_____|
                    
"

APWD=$(pwd);

function errorAndQuit {
    echo "Exit now!"
    exit 1
}

function wait_bar () {
  for i in {1..10}
  do
    printf '= %.0s' {1..$i}
    sleep $1s
  done
}

#default package list
package_list="nano cron vim-nox ntp openssh openssh-server rsyslog"

#default distrubution
default_dis = "debian/10"

# ------------------------------------------------------------------------------------------
# Logging
#-------------------------------------------------------------------------------------------
#Those lines are for logging purposes
exec > >(tee -i ${APWD}/create_lxc.log)
exec 2>&1
echo 
echo "Welcome to the setup for a new lxc container"
echo "========================================="
echo "Setup started..."
echo "========================================="


# Check if user is root
if [[ $(id -u) -ne 0 ]]; then # $EUID
	echo "Error: This script must be run as root, please run this script again with the root user or sudo."
	errorAndQuit
fi

# Check if on Linux
if ! echo "$OSTYPE" | grep -iq "linux"; then
	echo "Error: This script must be run on Linux."
	errorAndQuit
fi

lxc list

read -r -p "Please enter the hostname for the new LXC container: " name_container
ip_regex='^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$'
while read -r -p "Please enter the ip address for the new LXC container: " ip_address && [[ ! $ip_address =~ $ip_regex ]]; do
  echo "invalid ip address. Please try again."
done

echo "Name of the new container: $name_container"
echo "IP of the new container: $ip_address"
echo -n "Is this correct? (y/n) :"
read -n 1 -r
echo -e "\n"    
RE='^[Yy]$'
if [[ ! $REPLY =~ $RE ]]; then
   errorAndQuit 
fi

# create the container if it doesn't exist
if [ ! -e /var/lib/lxd/containers/$name_container ]
  then
    lxc launch --verbose images:$default_dis $name_container
    wait_bar 0.5
    echo container $name_container started
  else
    echo container $name_container already created
fi

# apply profiles
lxc profile apply $name_container default

#Security set
lxc config set $name_container security.nesting true

#Set memory
lxc config set $name_container limits.memory 500MB

#Autostart
lxc config set $name_container boot.autostart true

#eth0 add to the container
lxc config device add $name_container eth0 nic nictype=bridged parent=br0 name=eth0

#restart container
lxc restart $name_container

#wait
wait_bar 5

#Network set
echo "
# This file describes the network interfaces available on your system
# and how to activate them. For more information, see interfaces(5).

# The loopback network interface
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet static
	address $ip_address
	gateway 91.210.226.1
	broadcast 91.210.226.255
	dns-nameservers 8.8.8.8 8.8.4.4

source /etc/network/interfaces.d/*.cfg
" >> interfaces

lxc exec $name_container "mv /etc/network/interfaces /etc/network/interfaces.backup"
lxc file push interfaces $name_container/etc/network/interfaces

lxc exec $name_container "nameserver 8.8.8.8 >> /etc/resolv.conf"
lxc exec $name_container "nameserver 8.8.4.4 >> /etc/resolv.conf"

#restart container
lxc restart $name_container

#wait
wait_bar 0.5

#install default package 
lxc exec $name_container "apt-update && apt-get upgrade -y && apt-get dist-upgrade -y"
lxc exec $name_container "apt-get install -y $package_list"

#restart
lxc restart $name_container

#wait
wait_bar 0.5

#list of all container
lxc list

#finisch
echo "VM setup is done"