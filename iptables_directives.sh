#!/bin/bash

#
# iptables_directives.sh
#
# Copyright (C) 2015 frnmst (Franco Masotti) <franco.masotti@live.com>
#                                            <franco.masotti@student.unife.it>
#
# This file is part of iptables-geoport-directives.
#
# iptables-geoport-directives is free software: you can redistribute it and/or
# modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# iptables-geoport-directives is distributed in the hope that it will be
# useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with iptables-geoport-directives.  If not, see
# <http://www.gnu.org/licenses/>.
#

# New version heavily based on:
# https://wiki.archlinux.org/index.php/Simple_stateful_firewall
# https://wiki.archlinux.org/index.php/Iptables
# and a little on:
# http://www.thegeekstuff.com/2011/06 /iptables-rules-examples/
# as well as nixCraft for the bash stuff.
# See url for more info - http://www.cyberciti.biz/faq/?p=3402
# Pre author: nixCraft <www.cyberciti.biz>
# released under GPL v.2.0+

# TODO (in order of priority)
# TUNE/FINISH LOGGING,
# Get current LAN ips automatically
# DO MORE COMPACT/EFFICIENT CODE WITH LESS VARIABLES AND unsetting UNUSED ONES.
# Do better output (i.e. write [DONE] or [FAILED] at the edge right of the shell using ncurses?)
# Make this portable, also for other shells & systems

# NOT WORKING
# Not sure if logging works after iptables-save (i.e. when the rules are applied after reboot).

# Only {bash,IPv4,TCP,UDP} version
# Aim = Restrictive INPUT access

# To be run as root

# exit codes
# 0	OK
# 1	Invalid option/Too much parameters passed to program
# 2	User launching program is not root
# 3	iptables not running
# 4	Invalid port
# 5	No valid wan ip list found

# Set path.
PATH=$PATH:/usr/bin

# Exit codes.
OK=0
invalidOption=1
usrNotRoot=2
iptablesNotRunning=3
invalidPort=4
noValidIpWanListFound=5

# Get arguments from shell.
# # of elements.
argc="$#"
# strings
argv=("$@")

# Max num of elements.
maxArgsNum=3

# Some state variables set to default values.
verboseSet="false"
configFile=""
# Define an empty array for protocol type.
prot=( )
acceptedWanIps=( )
# Define an empty array used only for port numbers.
portNum=( )
# define empty array to decide between LAN or WAN.
location=( )
# Init system.
initSys=""

# Systemctl specs # TODO. see https://wiki.archlinux.org/index.php/Iptables#Configuration_file
#systemctlDirectiveDir="/etc/systemd/system/iptables.service.d"
#systemctlDirectoryFile="00-pre-network.conf"

# Function that prints help info.
function printHelp ()
{

	echo -en "\
"$0" help\n\
"$0" [-h | -i | -r | -v] -c <file-name>\n\
Options\n\
\t-c --config\t\tconfiguration file\n\
\t-h --help\t\tshow this help\n\
\t-r --reset\t\treset iptables to default values\n\
\t-v --verbose\t\tverbose at debug level\n\
Exit codes\n\
\t"$OK"\t\t\tOK\n\
\t"$invalidOption"\t\t\tInvalid option or too much parameters\n\
\t"$usrNotRoot"\t\t\tUser launching program is not root\n\
\t"$iptablesNotRunning"\t\t\tiptables not running TO BE IMPLEMENTED\n\
\t"$invalidPort"\t\t\tInvalid Port\n\
\t"$noValidIpWanListFound"\t\t\tNo valid ip WAN list found\n"

	return 0

}

function readConfigFile ()
{

	if [ -f "$configFile" ] && [ ! -z "$configFile" ]; then
		source "$configFile"
	else
		return 1
	fi

	return 0
}

# Verbose Function.
function verboseMsg ()
{

	# Get message to print
	msg="$1"

	if [ "$verboseSet" == "true" ]; then
		echo -en "$msg"
	fi

	return 0

}

# Exit error message function.
function exitWithMsg ()
{

	# get state and msg vars
	state="$1"
	msg="$2"


	echo -en "[$state]\t$msg\n"

	exit "$state"

}

# Reset iptables to default values.
function reset ()
{

	iptables -F
	iptables -X
	iptables -t nat -F
	iptables -t nat -X
	iptables -t mangle -F
	iptables -t mangle -X
	iptables -t raw -F
	iptables -t raw -X
	iptables -t security -F
	iptables -t security -X
	iptables -P INPUT ACCEPT
	iptables -P FORWARD ACCEPT
	iptables -P OUTPUT ACCEPT

	return 0

}

# Function to retrieve Valid Wan Ips.
# This does not guarantuee to have a REAL valid list in the end (i.e. when
# restoring the old file or when getting a list which does not contain valid
# IPs).
function getAcceptedWanIps ()
{

        tmp=$1[@]
	lAcceptedWanCountries=("${!tmp}")
	lFile="$2"


	# Check if country file already exists.
	if [ -f "$lFile" ]; then
		verboseMsg "Saving wan ip countries list on $lFile.old\t\t"

		# if the ip country file exists, save a copy with ".old" extension, overwriting any older .old file
		mv -f "$lFile" "$lFile.old"

		verboseMsg "[DONE]\n"
	fi

	# create a new empty country file
	touch "$lFile"

	ipListProblem="false"
	# Get accepted IPs
	# O(#acceptedCountries) + 1
	for country in $lAcceptedWanCountries; do # NO double quotes here
		verboseMsg "Getting \"$country\" valid ip WAN list from $ipWanAddrRoot\t\t"

		# get url state (using only the header)
		curl --output /dev/null --silent --head --fail "$ipWanAddrRoot/$country.$ipWanAddrSuffix"
		# if the url exists
		if [ "$?" -eq 0 ]; then
			# save ips into var and write the ips into the file
			acceptedWanIps=$(curl --silent "$ipWanAddrRoot/$country.$ipWanAddrSuffix")
			echo "$acceptedWanIps" >> "$lFile"
			verboseMsg "[DONE]\n"
		# otherwise discard the content
		else
			ipListProblem="true"
			break # to fix using it as for condition...
		fi
	done

	# Since the array could contain more than one count
	# Restore old file overwriting invalid new one
	if [ "$ipListProblem" == "true" ]; then
		# if the old file exists
		if [ -f "$lFile.old" ]; then
			# restore old file
			verboseMsg "[DONE]\n"
			mv -f "$lFile.old" "$lFile"
		else
			# FATAL, no valid file found, exit
			rm "$lFile"
			verboseMsg "[FAILED]\n"
			return 1
		fi
	fi

	return 0

}

# Auto recognize protocol.
function getProtByPort ()
{

        tmp=$1[@]
	lAcceptedPorts=("${!tmp}")
        tmp=$2[@]
	lLocation=("${!tmp}")

	# iterator
	i=0
	# Get the correct protocol type based on standard port numbers
	# O(#acceptedPorts)
	for port in $lAcceptedPorts; do # No double quotes here
		verboseMsg "Evaluating port directive $port\t\t"

		# extract location: last char only
		lLocation["$i"]="${port:(-1)}"
		case "${lLocation[$i]}" in
			"l" )
				lLocation["$i"]="l"
			;;
			"w" )
				lLocation["$i"]="w"
			;;
			[0-9] )
				lLocation["$i"]="a"
			;;
			* )
				verboseMsg "[FAILED]\n"
				return 1
			;;
		esac
		verboseMsg "[DONE]\n"

		verboseMsg "Extracting port from $port\t\t"
		# extract port: all but last char
		case "${port:0:(-1)}" in
			[0-9] )
				pPort="$port"
			;;
			* )
				pPort="${port:0:(-1)}"
			;;
		esac
		verboseMsg "[DONE]\n"

		# check if port is in range
		verboseMsg "Checking port range of $pPort\t\t"
		if [ "$pPort" -le 1 ] && [ "$pPort" -ge 65535 ]; then
			verboseMsg "[FAILED]\n"
			return 1
		fi
		verboseMsg "[DONE]\n"

		verboseMsg "Evaluating port number $pPort\t\t"
		case "$pPort" in
		# Only some ports are defined
			# tcp
			21 | 22 | 80 | 443 | 631 | 3128 | 6881 | 8000 | 8080 | 8200 )
				prot["$i"]="tcp"
			;;
			# udp
			53 | 123 | 1900 )
				prot["$i"]="udp"
			;;
			# default
			* )
				verboseMsg "[FAILED]\n"
				return 1
			;;
		esac

		# Saving port number in a separate array
		portNum["$i"]="$pPort"

		verboseMsg "[DONE]\n"

		i=$(($i+1));
	done

	return 0

}

# Core function which sets iptables directives/rules
# It creates user defined chains and sets first basic rules on how to handle packets
function iptablesSet ()
{

	# get argument
	lInvalidPacketPolicy="$1"
	lLoggingEnabled="$2"


	verboseMsg "Setting basic rules\t\t"

	# call function to reset ip tables
	reset

	# USING FILTER TABLE AS DEFAULT
	# Output traffic is NOT filtered
	iptables -P OUTPUT ACCEPT

	# Create two user defined chains that will define tcp an udp protocol rules later
	iptables -N TCP
	iptables -N UDP

	# From Arch wiki:
	# The first rule added to the INPUT chain will allow traffic that
	# belongs to established connections, or new valid traffic that is
	# related to these connections such as ICMP errors, or echo replies
	iptables -A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT

	# loopback interface INPUT traffic enabled for ping and debugging stuff
	iptables -A INPUT -i lo -j ACCEPT

	# Drop all invalid INPUT (i.e. damaged) packets. To do this connection must be tracked (conntrack) and connection state (cstate) is set to INVALID
	iptables -A INPUT -m conntrack --ctstate INVALID -j DROP

	# Allow icmp type 8 (i.e. ping) to all interfaces
	iptables -A INPUT -p icmp --icmp-type 8 -m conntrack --ctstate NEW -j ACCEPT

	# TCP snd UDP chains are connected to INPUT chains. These two user-defined chains will manage the ports
	iptables -A INPUT -p tcp --syn -m conntrack --ctstate NEW -j TCP # remember that tcp uses SYN to initialize a connection, unlike UDP
	iptables -A INPUT -p udp -m conntrack --ctstate NEW -j UDP

	# DROP / REJECT rules
	if [ "$loggingEnabled" == "yes" ]; then
	# log
		# create a new chain called logdrop
		iptables -N LOGGING
		# attach it to INPUT chain
		iptables -A INPUT -j LOGGING

		iptables -A LOGGING -m limit --limit 2/hour --limit-burst 10 -j LOG
		if [ "$lInvalidPacketPolicy" == "rude" ]; then
			# Drop everything
			iptables -A LOGGING -j DROP
		else
			iptables -A LOGGING -p tcp -j REJECT --reject-with tcp-rst
			iptables -A LOGGING -p udp -j REJECT --reject-with icmp-port-unreachable

			# other protocols are usually not used, so REJECT those packets with icmp-proto-unreachable
			iptables -A LOGGING -j REJECT --reject-with icmp-proto-unreachable
		fi
	else
	# no log
		if [ "$lInvalidpacketPolicy" == "rude" ]; then
			# Drop everything
			iptables -A INPUT -j DROP
		else
		# RFC compilant
			iptables -A INPUT -p tcp -j REJECT --reject-with tcp-rst
			iptables -A INPUT -p udp -j REJECT --reject-with icmp-port-unreachable

			# other protocols are usually not used, so REJECT those packets with icmp-proto-unreachable
			iptables -A INPUT -j REJECT --reject-with icmp-proto-unreachable
		fi
	fi

	verboseMsg "[DONE]\n"

	return 0

}

# Another set of core rules.
# Inside this function TCP and UDP user defined chain rules are set.
function iptablesApply ()
{

#        tmp=$1[@]
#	lPortNum=("${!tmp}")
        tmp=$1[@]
	lAcceptedLanIps=("${!tmp}")
        tmp=$2[@]
	lAcceptedWanIps=("${!tmp}")
        tmp=$3[@]
	lLocation=("${!tmp}")

	verboseMsg "Setting port rules\t\t"

	# Apply iptable rules
	# Doing it in this nested way, it will save iterations
	# O (#portNum * #acceptedLanIps * #acceptedWanIps)
	i=0
	#for port in "${lPortNum[@]}"
	for port in "${portNum[@]}"; do
		for lan in $lAcceptedLanIps; do
			if [ "${lLocation[$i]}" == "l" ] || [ "${lLocation[$i]}" == "a" ]
			then
				if [ "${prot[$i]}" == "tcp" ]
				then
					iptables -A TCP -p "${prot[$i]}" --dport "$port" -s "$lan" -j ACCEPT
				else
					iptables -A UDP -p "${prot[$i]}" --dport "$port" -s "$lan" -j ACCEPT
				fi
			fi
		done

		for wan in $lAcceptedWanIps; do
			if [ "${lLocation[$i]}" == "w" ] || [ "${lLocation[$i]}" == "a" ]
			then
				if [ "${prot[$i]}" == "tcp" ]; then
					iptables -A TCP -p "${prot[$i]}" --dport "$port" -s "$wan" -j ACCEPT
				else
					iptables -A UDP -p "${prot[$i]}" --dport "$port" -s "$wan" -j ACCEPT
				fi
			fi
		done

		i=$(($i+1))
	done

	# drop every other packet as default policy (for unset rules). In this
	# way we are certain that the firewall works as expected.
	iptables -P INPUT DROP

	verboseMsg "[DONE]\n"

	return 0

}

# Parsing function for bash arguments
function parseArgs ()
{

	# arguments treated as positional values
	lArgc=$1
	# array passed by reference
	tmp=$2[@]
	lArgv=("${!tmp}")
	lMaxArgsNum=$3


	# check # of elements. it works slightly different from C
	if [ "$lArgc" -gt "$lMaxArgsNum" ]; then
		return 1
	fi

	i=0
	# less equal
	loop="true"
	while [ "$i" -lt "$lArgc" ] && [ "$loop" == "true" ]; do
		case "${lArgv[$i]}" in
			"-c" | "--config")
				# check config file if -c or --config switch is selected
				# argv[1+x] may be a path
				configFile="${lArgv[$i+1]}"
				loop="false"
			;;
			"-h" | "--help" )
				printHelp
				loop="false"
				exit "$OK" # UGLY BUT WORKS
			;;
			"-r" | "--reset" )
				reset
				loop="false"
				exit "$OK" # UGLY BUT WORKS
			;;
			"-v" | "--verbose" )
				verboseSet="true"
			;;
			# No arg
			"" )
				loop="false"
			;;
			# Invalid option or previous is -c
			* )
				# if previous is -c or --config
				case "${lArgv[$(($i-1))]}" in
					"-c" | "--config" )
					;;
					* )
					#invalid option
						return 1
					;;
				esac
			;;
		esac

		i=$(($i+1))
	done

	return 0

}

# Check if user root is launching program
if [ "$UID" -ne 0 ]; then
	exitWithMsg "$usrNotRoot" "You must be root user (uid = 0) \
to launch the program"
fi

# TODO
#detectInitSys

# check if iptables is running
# TODO
#checkIptablesStatus
#if [ "$?" -eq 1 ]; then
#	exitWithMsg "$iptablesNotRunning" "Iptables not running"
#fi

# Call parsing function
parseArgs "$argc" argv "$maxArgsNum" # argv passed by reference
if [ "$?" -eq 1 ]; then
	exitWithMsg "$invalidOption" "Invalid option, filename or too much parameters"
fi

# Check config file switch to read config file
readConfigFile
if [ "$?" -eq 1 ]; then
	exitWithMsg "$invalidOption" "Invalid option, filename or too much parameters"
fi

# Get a shorter variable for file name
file="$acceptedWanIpsPath/.$acceptedWanIpsFileName"

# call the function to get accepted wan ip list
getAcceptedWanIps acceptedWanCountries "$file"
if [ "$?" -eq 1 ]; then
	exitWithMsg "$noValidIpWanListFound" "Invalid option, filename or too much parameters"
fi

# Call function to auto recognize transport level protocol based on standard port numbers
getProtByPort acceptedPorts location

if [ "$?" -eq 1 ]; then
	exitWithMsg "$invalidPort" "Port number invalid or out of range"
fi

# Apply first set of rules
iptablesSet "$invalidPacketPolicy" "$loggingEnabled"
if [ "$?" -eq 1 ]; then
	exitWithMsg "$invalidPort" "Port number invalid or out of range"
fi

iptablesApply acceptedLanIps acceptedWanIps lLocation
if [ "$?" -eq 1 ]; then
	exitWithMsg "$invalidPort" "Port number invalid or out of range"
fi

# Save iptables into files; this works for Arch Linux, don't know about otrher distros
verboseMsg "Saving directives to ** VAR TO BE CHANGED **\t\t"
iptables-save > /etc/iptables/iptables.rules
verboseMsg "[DONE]\n"

exit "$OK"


# Detect init system type
# Don't use grep but use portable built-in matching
# TODO
#function detectInitSys ()
#{
#	if [ "$(/sbin/init --version)" == "upstart" ]; then
#		initSys="upstart"
#	elif [ "$(systemctl | grep -c \".mount\")" -ge 1 ]; then
#		initSys="systemd"
#	elif [ -f "/etc/init.d/cron" ] && [ ! -h "/etc/init.d/cron" ]; then
#		initSys="sysv-init"
#	else
#		initSys="NULL"
#	fi
#
#	return 0
#
#}
#
#function checkIptablesStatus ()
#{
#
#	ret=""
#
#	case "$initSys" in
#		"systemd" )
#			## NOT WORKING LIKE THIS. TODO BETTER
#			ret="$(systemctl status iptables.service)"
#			if [ "$?" -ne 0 ]; then
#				return 1
#			fi
#		;;
#	esac
#}
