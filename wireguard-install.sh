#!/bin/bash
#
# https://github.com/Fruxlabs/wireguard-roadwarrior
#
# Copyright (c) 2018 eshanaswar. Released under the MIT License.

# Detect Debian users running the script with "sh" instead of bash
if readlink /proc/$$/exe | grep -q "dash"; then
echo "This script needs to be run with bash, not sh"
exit
fi

if [[ "$EUID" -ne 0 ]]; then
echo "Sorry, you need to run this as root"
exit
fi

#Detect running Operating System
if [[ -e /etc/debian_version ]]; then
OS=debian
else
echo "Looks like you aren't running this installer on Debian"
exit
fi

newclient () {
# Client Key generation
rm -rf /etc/wireguard/$1
mkdir -p /etc/wireguard/$1
cd /etc/wireguard/$1
client_priv=$(wg genkey)
client_pub=$(echo $client_priv | wg pubkey)
echo $client_priv | tee private.key
echo $client_pub | tee public.key
client_ip=$(all="$(wg show wg0 allowed-ips)"; for ((i=2; i<=254; i++)); do ip="10.0.0.$i"; [[ $all != *$ip/32* ]] && echo $ip && break; done)
wg set wg0 peer $client_pub allowed-ips $client_ip/32

#Generate Client Config File
(umask 077 && printf "[Interface]\nPrivateKey = $client_priv\nAddress = $client_ip/32\nDNS = 8.8.8.8\n\n[Peer]\nPublicKey = $server_public_key\nEndpoint = $PUBLICIP:$(echo $PORT | awk '{$1=$1};1')\nAllowedIPs = 0.0.0.0/0" | sudo tee /root/$client_ip.conf)

echo
echo "Finished!"
echo
echo "Your client configuration is available at: /root/$client_ip.conf"
echo
while true; do
read -p "Do you want to generate a QR code for this configuration? " yn
case $yn in
[Yy]* ) qrencode -t ansiutf8 < /root/$client_ip.conf; break;;
[Nn]* ) exit;;
* ) echo "Please answer yes or no. ";;
esac
done
echo
}

if [[ -e /etc/wireguard/wg0.conf ]]; then
while :
do
clear
echo "Looks like Wireguard is already installed."
echo
echo "What do you want to do?"
echo "   1) Add a new user"
echo "   2) Remove User"
echo "   3) Remove Wireguard"
echo "   4) Exit"
read -p "Select an option [1-4]: " option
case $option in

1) 
echo
echo "Tell me a name for the client configuration."
echo "Please, use one word only, no special characters."
read -p "Client name: " -e CLIENT
echo
echo "Enter your Public IP address."
read -p "Public IP address: " -e PUBLICIP
server_public_key=$(cat /etc/wireguard/publickey)
PORT=$(wg | grep port | cut -d':' -f2)
newclient "$CLIENT"
echo
exit
;;

2)
echo "This is under development"
ClientNumber=$(find /etc/wireguard/* -type f -name '*.key' | sed -r 's|/[^/]+$||' | uniq | wc -l)
ClientLocation=$(find /etc/wireguard/* -type f -name '*.key' | sed -r 's|/[^/]+$||' | uniq | cut -d"/" -f4)
ClientList=($(echo $ClientLocation))
if [[ "$ClientNumber" = '0' ]]; then
echo "You have no existing clients!"
exit
else
echo
echo "Select the existing client you want to revoke:"
# Client Removal Program
PS3="Client: "
select option in $ClientLocation
do
echo $option
echo
for ((i = 0; i < ${#ClientList}; i++)); do
if [[ ${ClientList[$i]} = $option ]]; then
echo
read -p "Do you really want to revoke access for client $option? [y/N]: " -e REVOKE
if [[ "$REVOKE" = 'y' || "$REVOKE" = 'Y' ]]; then
sudo wg set wg0 peer $(cat /etc/wireguard/$option/public.key) remove
rm -rf /etc/wireguard/$option
exit
else
echo
echo "Revocation of client $option aborted!"
fi
exit
fi
done
if ((i == ${#ClientList})); then
echo "Incorrect Option Selected"
echo "Run the script again"
fi
done
fi
exit
;;
3) 
echo
read -p "Do you really want to remove Wireguard? [y/N]: " -e REMOVE
if [[ "$REMOVE"='y' || "$REMOVE"='Y' ]]; then
echo
wg-quick down wg0
apt remove wireguard qrencode -y
apt-get autoremove -y
rm -rf /etc/wireguard
rm -rf /etc/qrencode
rm -rf /etc/sysctl.d/wireguard.conf
sysctl -p
else
echo
echo "Removal aborted!"
fi
exit
;;

4) exit;;
esac
done

else

clear
echo 'Welcome to this WireGuard "road warrior" installer!'
echo
# Wireguard setup and first user creation
echo "I need to ask you a few questions before starting the setup."
echo "You can leave the default options and just press enter if you are ok with them."
echo
echo "First, Provide the IPv4 address of the network interface you want Wireguard"
echo "listening to."
read -p "Public IP address / hostname: " -e PUBLICIP
fi
echo
echo "What port do you want Wireguard listening to?"
read -p "Port: " -e -i 5100 PORT
echo
echo "Finally, tell me a name for the client configuration."
echo "Please, use one word only, no special characters."
read -p "Client name: " -e -i client CLIENT
echo
echo "Okay, that was all I needed. We are ready to set up your Wireguard VPN server now."
read -n1 -r -p "Press any key to continue..."
INTERFACE=$(ip -o link show | sed -rn '/^[0-9]+: en/{s/.: ([^:]*):.*/\1/p}')
if [[ "$OS"='debian' ]]; then
echo "deb http://deb.debian.org/debian/ unstable main" > /etc/apt/sources.list.d/unstable.list
printf 'Package: *\nPin: release a=unstable\nPin-Priority: 150\n' > /etc/apt/preferences.d/limit-unstable
apt update
apt install wireguard qrencode -y
fi

(umask 077 && printf "[Interface]\nPrivateKey = " | sudo tee /etc/wireguard/wg0.conf)
server_private_key=$(wg genkey)
server_public_key=$(echo $server_private_key | wg pubkey)
echo $server_private_key | sudo tee -a /etc/wireguard/wg0.conf 
echo $server_public_key | sudo tee /etc/wireguard/publickey
(printf "ListenPort = " | sudo tee -a /etc/wireguard/wg0.conf)
echo $PORT | tee -a /etc/wireguard/wg0.conf
(printf "SaveConfig = false\nAddress = 10.0.0.1/24\nPostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o $INTERFACE -j MASQUERADE;\nPostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o $INTERFACE -j MASQUERADE\n" | sudo tee -a /etc/wireguard/wg0.conf > /dev/null)
wg-quick up wg0
systemctl enable wg-quick@wg0

#Packet Forwarding
(printf "net.ipv4.ip_forward=1\nnet.ipv6.conf.all.forwarding=1\n" | sudo tee /etc/sysctl.d/wireguard.conf)
sysctl -p /etc/sysctl.d/wireguard.conf

#First Client Creation
newclient $CLIENT

echo "If you want to add more clients, you simply need to run this script again!"
fi