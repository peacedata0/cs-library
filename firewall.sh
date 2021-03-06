#!/bin/bash
#
# Copyright 2011 Alexandros Iosifidis, Dimitrios Michalakos
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Lesser General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

source network.sh

FW_CHAIN='Chuck_Norris' #spaces not valid here
INTF_PUBLIC="eth0"
INTF_PRIV="eth0:1"

# Initializes iptables with basic firewall rules.
function firewall.configure {
   # Configure:
   sed -i -e 's|^\(IPTABLES_MODULES=\)\(.*\)$|\1""|' /etc/sysconfig/iptables-config #disable all modules
   sed -i -e 's|^\(IPTABLES_MODULES_UNLOAD=\)\(.*\)$|\1"no"|' /etc/sysconfig/iptables-config
   chmod u=rw,g=,o= /etc/sysconfig/iptables-config
   # Set daemon:
   # Linode kernels contain an extra policy chain, named "security", which causes iptables to fail on start-up.
   if uname -r | grep -iq "linode" ; then #kernel requires iptables patching
      cd ~
      wget http://epoxie.net/12023.txt #obtain patch
      cat 12023.txt | tr -d '\r' > /etc/init.d/iptables
      rm -f 12023.txt #collect garbage
   fi
   chmod u=rwx,g=rx,o= /etc/init.d/iptables
   chkconfig --add iptables
   chkconfig --level 35 iptables on #survive system reboot
   # Set basic rules & policies:
   iptables --flush #delete all predefined rules in "filter" table
   iptables --table nat --flush #delete all predefined rules in "nat" table
   iptables --table mangle --flush #delete all predefined rules in "mangle" table
   iptables --delete-chain #delete all user-defined chains in "filter" table
   #iptables --policy OUTPUT ACCEPT #COMMENTED OUT, REVISED: set new policy: allow traffic which originated from our system (OUTPUT)
   iptables --policy INPUT DROP
   iptables --policy OUTPUT DROP
   iptables --policy FORWARD DROP
   iptables --new-chain $FW_CHAIN #create new chain in "filter" table
   iptables --append INPUT --in-interface $INTF_PUBLIC --protocol tcp ! --syn --match state --state NEW --jump DROP
   iptables --append INPUT --in-interface $INTF_PUBLIC --protocol tcp --tcp-flags ALL ALL --jump DROP #drop malformed XMAS packets
   iptables --append INPUT --in-interface $INTF_PUBLIC --protocol tcp --tcp-flags ALL NONE --jump DROP #drop malformed NULL packets
   iptables --append INPUT --in-interface $INTF_PUBLIC --source 0.0.0.0/8 --jump DROP #Start RFC1918 antispoofing dropping
   iptables --append INPUT --in-interface $INTF_PUBLIC --destination 0.0.0.0/8 --jump DROP
   iptables --append INPUT --in-interface $INTF_PUBLIC --source 10.0.0.0/8 --jump DROP
   iptables --append INPUT --in-interface $INTF_PUBLIC --source 127.0.0.0/8 --jump DROP
   iptables --append INPUT --in-interface $INTF_PUBLIC --source 169.254.0.0/16 --jump DROP
   iptables --append INPUT --in-interface $INTF_PUBLIC --source 172.16.0.0/12 --jump DROP
   iptables --append INPUT --in-interface $INTF_PUBLIC --source 192.168.0.0/16 --jump DROP
   iptables --append INPUT --in-interface $INTF_PUBLIC --source 224.0.0.0/4 --jump DROP
   iptables --append INPUT --in-interface $INTF_PUBLIC --destination 224.0.0.0/4 --jump DROP
   iptables --append INPUT --in-interface $INTF_PUBLIC --destination 239.255.255.0/24 --jump DROP
   iptables --append INPUT --in-interface $INTF_PUBLIC --source 240.0.0.0/5 --jump DROP
   iptables --append INPUT --in-interface $INTF_PUBLIC --destination 240.0.0.0/5 --jump DROP 
   iptables --append INPUT --in-interface $INTF_PUBLIC --destination 255.255.255.255 --jump DROP #End RFC1918 antispoofing dropping
   iptables --append INPUT --in-interface $INTF_PUBLIC --protocol icmp --match icmp --icmp-type 8 --match limit --limit 1/second --jump ACCEPT #Ingress, public ICMP-ping traffic-limiting
   iptables --append INPUT --in-interface lo --jump ACCEPT
   iptables --append INPUT --jump $FW_CHAIN #handle traffic which is entering our system (INPUT)
   iptables --append FORWARD --jump $FW_CHAIN #handle traffic which is being routed between two network interfaces on our firewall (FORWARD)
   iptables --append OUTPUT --match state --state NEW,ESTABLISHED,RELATED --jump ACCEPT
   iptables --append OUTPUT --out-interface lo --jump ACCEPT
   iptables --append OUTPUT --jump $FW_CHAIN #handle traffic exiting our system (OUTPUT)
   iptables --append $FW_CHAIN --match state --state INVALID --jump DROP #drop BOGUS packets
   iptables --append $FW_CHAIN --match state --state ESTABLISHED,RELATED --jump ACCEPT #accept ONLY these TCP states
   iptables --append $FW_CHAIN --protocol tcp --tcp-flags ACK,FIN FIN --jump DROP # Start NEW TCP state malformed options filtering 
   iptables --append $FW_CHAIN --protocol tcp --tcp-flags ACK,PSH PSH --jump DROP
   iptables --append $FW_CHAIN --protocol tcp --tcp-flags ACK,URG URG --jump DROP
   iptables --append $FW_CHAIN --protocol tcp --tcp-flags FIN,RST FIN,RST --jump DROP
   iptables --append $FW_CHAIN --protocol tcp --tcp-flags SYN,FIN SYN,FIN --jump DROP
   iptables --append $FW_CHAIN --protocol tcp --tcp-flags SYN,RST SYN,RST --jump DROP
   iptables --append $FW_CHAIN --protocol tcp --tcp-flags ALL FIN,PSH,URG --jump DROP
   iptables --append $FW_CHAIN --protocol tcp --tcp-flags ALL SYN,FIN,PSH,URG --jump DROP
   iptables --append $FW_CHAIN --protocol tcp --tcp-flags ALL SYN,RST,ACK,FIN,URG --jump DROP #End NEW TCP state malformed options filtering
   iptables --append $FW_CHAIN --protocol icmp --icmp-type 255 --jump ACCEPT
   iptables --append $FW_CHAIN --jump REJECT --reject-with icmp-host-prohibited
   # Save + restart:
   service iptables save
   service iptables restart
   return 0 #done
}

# Allows incoming traffic to the specified port(s) of the supplied network protocol.
# $1 network protocol, either "tcp" or "udp". {REQUIRED}
# $+ port number(s) separated by space, positive integers ranging between 0 and 65535. {REQUIRED}
function firewall.allow {
   local protocol="$1"
   shift #ignore first parameter, which represents protocol
   # Make sure protocol is specified:
   if [ -z $protocol ] ; then
      echo "Network protocol must be specified. Availiable options: tcp, udp."
      return 1 #exit
   fi
   # Make sure protocol is valid:
   if [ $protocol != "udp" -a $protocol != "tcp" ] ; then
      echo "Invalid network protocol \"$protocol\". Availiable options: tcp, udp."
      return 1 #exit
   fi
   # Make sure at least one port is specified:
   if [ $# -eq 0 ] ; then
      echo "At least one port number must be specified."
      return 1 #exit      
   fi
   # Make sure the specified port(s) are valid:
   for port in "$@"; do
      if ! network.valid_port $port ; then
         echo "Invalid port $port. Please specify a number between 0 and 65535."
         return 1 #exit
      fi
   done
   # Append rule to iptables:
   iptables --delete $FW_CHAIN --jump REJECT --reject-with icmp-host-prohibited
   for port in "$@"; do
      iptables --append $FW_CHAIN --match state --state NEW --match $protocol --protocol $protocol --destination-port $port --jump ACCEPT
   done
   iptables --append $FW_CHAIN --jump REJECT --reject-with icmp-host-prohibited
   # Save + restart:
   service iptables save
   service iptables restart
   return 0 #done
}

# Denies incoming traffic to the specified port(s) of the supplied network protocol.
# $1 network protocol, either "tcp" or "udp". {REQUIRED}
# $+ port number(s) serarated by space, positive integers ranging between 0 and 65535. {REQUIRED}
function firewall.deny {
   local protocol="$1"
   shift #ignore first parameter, which represents protocol
   # Make sure protocol is specified:
   if [ -z $protocol ] ; then
      echo "Network protocol must be specified. Availiable options: tcp, udp."
      return 1 #exit
   fi
   # Make sure protocol is valid:
   if [ $protocol != "udp" -a $protocol != "tcp" ] ; then
      echo "Invalid network protocol \"$protocol\". Availiable options: tcp, udp."
      return 1 #exit
   fi
   # Make sure at least one port is specified:
   if [ $# -eq 0 ] ; then
      echo "At least one port number must be specified."
      return 1 #exit      
   fi
   # Make sure the specified port(s) are valid:
   for port in "$@"; do
      if ! network.valid_port $port ; then
         echo "Invalid port $port. Please specify a number between 0 and 65535."
         return 1 #exit
      fi
   done
   # Delete rule from iptables:
   iptables --delete $FW_CHAIN --match state --state NEW --match $protocol --protocol $protocol --destination-port $port --jump ACCEPT
   # Save + restart:
   service iptables save
   service iptables restart
   return 0 #done
}
