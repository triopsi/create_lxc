#/bin/bash
#---------------------------------------------------------------------
# Scriptname: create_lxc.sh
# Description: Create VM(LXC) on the host
# Date: 15.06.2020
# Version: 0.2
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
package_list="nano cron vim-nox ntp openssh-server rsyslog logrotate net-tools"

#default distrubution
default_dis="debian/10"

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
while read -r -p "Please enter the gateway address for the new LXC container: " gateway_address && [[ ! $gateway_address =~ $ip_regex ]]; do
  echo "invalid gateway address. Please try again."
done
while read -r -p "Please enter the broadcast address for the new LXC container: " broadcast_address && [[ ! $broadcast_address =~ $ip_regex ]]; do
  echo "invalid broadcast address. Please try again."
done

echo -n "List all avaible images? (y/n) :"
read -n 1 -r
echo -e "\n"    
RE='^[Yy]$'
if [[  $REPLY =~ $RE ]]; then
    lxc image list images: 'debian'
    read -r -p "Please enter the image for the new LXC container: " default_dis
fi

echo "Name of the new container: $name_container"
echo "IP of the new container: $ip_address"
echo "gateway of the new container: $gateway_address"
echo "broadcast of the new container: $broadcast_address"
echo "Image of the new container: $default_dis"
echo -n "Is this correct? (y/n) :"
read -n 1 -r
echo -e "\n"    
RE='^[Yy]$'
if [[ ! $REPLY =~ $RE ]]; then
   errorAndQuit 
fi

# create the container if it doesn't exist
if [ -e /var/lib/lxd/containers/$name_container ]; then
    echo "Container $name_container already created"
    echo -n "Remove container? (y/n) :"
    read -n 1 -r
    echo -e "\n"    
    RE='^[Yy]$'
    if [[ $REPLY =~ $RE ]]; then

        # container_run=`lxc list | grep test | tr -s ' ' | cut -d '|' -f 3`
        container_run=`lxc list | grep test | awk '{print $4;}'`
        if [ "$container_run" == "RUNNING" ];then
          echo "[H] Container stop"
          lxc stop $name_container
          wait_bar 0.5
          echo
        fi
        echo "[H] Delete Container"
        lxc delete $name_container
        wait_bar 0.5
        echo
      else
        errorAndQuit
    fi
fi

echo "[H] Container $name_container created..."
lxc launch --verbose images:$default_dis $name_container
wait_bar 0.5
echo
echo "[H] Container $name_container started"

# apply profiles
echo "[H] Add Profile"
lxc profile apply $name_container default

#Security set
echo "[H] Write security config"
lxc config set $name_container security.nesting true

#Set memory
echo "[H] Write ram config"
lxc config set $name_container limits.memory 500MB

#Autostart
echo "[H] Autoboot enabled"
lxc config set $name_container boot.autostart true

#eth0 add to the container
echo "[H] Add device"
lxc config device add $name_container eth0 nic nictype=bridged parent=br0 name=eth0

#restart container
echo "[H] Container restart..."
lxc restart $name_container
wait_bar 0.5
echo

#Network set
echo "
# This file describes the network interfaces available on your system
# and how to activate them. For more information, see interfaces(5).

# The loopback network interface
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet static
	address $ip_address/24
	gateway $gateway_address
	broadcast $broadcast_address

source /etc/network/interfaces.d/*.cfg
" > interfaces

echo "[H] Write IP Address...."
lxc exec $name_container -- sh -c "mv /etc/network/interfaces /etc/network/interfaces.backup"
lxc file push interfaces $name_container/etc/network/interfaces

echo "[H] Write nameservers...."
lxc exec $name_container -- sh -c "printf 'nameserver 8.8.8.8\nnameserver 8.8.4.4' > /etc/resolv.conf"
# lxc exec $name_container -- sh -c "nameserver 8.8.4.4 >> /etc/resolv.conf"

#restart container
echo "[H] Restart container..."
lxc restart $name_container
wait_bar 0.5
echo

#install default package 
echo "[H] Install default packages...."
echo $package_list
lxc exec $name_container -- sh -c "apt-get update 2>&1 >> /root/update.software.log && apt-get upgrade -y 2>&1 >> /root/update.software.log && apt-get dist-upgrade -y 2>&1 >> /root/update.software.log"
lxc exec $name_container -- sh -c "apt-get install -y --no-install-recommends apt-utils $package_list 2>&1 > /root/installed.software.log"

#restart
echo "[H] Restart container"
lxc restart $name_container
wait_bar 0.5
echo

#list of all container
lxc list

#finisch
echo "[H] VM setup is done"