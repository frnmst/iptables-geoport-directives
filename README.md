# iptables-geoport-directives
Simple shell script for GNU/Linux, built on iptables, which is able to filter incoming packets based on accepted port numbers and countries. It is aimed to SOHO users.

###WHATIS
This is a bash script suitable for GNU/Linux systems (but it might work on other *nix-like systems too) that is able to filter incoming packets from LAN and WAN based on standard port numbers and countries' IP addresses. It uses a simple stateful firewall structure. The user selects the "accepted countries" (using the ISO notation) and the "accepted ports" (which are automatically toggled to be TCP or UDP, depending on standard port numbers). It is also possible to decide the policy of filtered packets (polite or rude policy, depending respectively if you want that the sender knows that his packets have been rejected or not) and to set logging of filtered packets.
All user settings are at the top of the main script. Each setting is explained. In the future these settings will be available in a separate file.

###PACKETDEPS
- bash
- iptables active and running

###HOWTO
Download: `$ git clone https://github.com/frnmst/iptables-geoport-directives`.

Before uing this script you must have iptables active and running.
If you have systemd as init system: `sudo systemctl enable iptables && sudo systemctl start iptables`.

You also must be root to run this script: `sudo ./iptables_direcives.sh`.

###DEVELSTAT
Achieved good points. The script works, but not sure about the logging part. Important features are missing, as explaned next.

###TODO
In order of importance:

1. EXPORT VARIABLES IN EMPTY FILE TO BE PARSED BY THIS PROGRAM. FILE MUST BE NAMED $0.config

2. Get current LAN ips automatically.

3. DO MORE COMPACT/EFFICIENT CODE WITH LESS VARIABLES AND unsetting UNUSED ONES.

4. Do better output (i.e. write [DONE] or [FAILED] at the edge right of the shell using something like ncurses.

5. Make this portable, also for other shells & systems.

6. Check if iptables is running.

7. Not sure if logging works after iptables-save (i.e. when the rules are applied after reboot).

8. Clean the code.

###HELP
```
./iptables_directives.sh help
Options
	-c --config		configuration file
	-h --help		show this help
	-i --init		initialize configuration file
	-r --reset		reset iptables to default values
	-v --verbose		verbose at debug level
Exit codes
	0			OK
	1			Invalid option or too much parameters
	2			User launching program is not root
	3			iptables not running TO BE IMPLEMENTED
	4			Invalid Port
	5			No valid ip WAN list found
```
