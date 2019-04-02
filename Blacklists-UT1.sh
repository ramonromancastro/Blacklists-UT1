#!/bin/bash

# Blacklists-UT1.sh is a bash function to download Blacklists UT1 lists
# (http://dsi.ut-capitole.fr/blacklists/index_en.php) and modify them
# to use in conjuntion with Squid or squidGuard.
#
# Copyright (C) 2018 Ramon Roman Castro <ramonromancastro@gmail.com>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

#
# Default configuration variables (You can modify them)
#

UT1_Blacklist=
UT1_Whitelist=
UT1_Squid_Integration=false
squid_user=squid
squid_group=squid

squidGuard_dbhome=/var/squidGuard/blacklists
squidGuard_logdir=/var/log/squidGuard
squidGuard_Config=/etc/squid/squidGuard.conf
squidGuard_redirect=https://dsi.ut-capitole.fr/blacklists/index_en.php

Smtp_Integration=false
Smtp_Smtp=
Smtp_From=
Smtp_Username=
Smtp_Password=
Smtp_To=
Smtp_Command=

#
# Constants
#

UT1_Version=1.2.2
UT1_Uri=http://dsi.ut-capitole.fr/blacklists/download/blacklists.tar.gz
UT1_Config=Blacklists-UT1.conf

#
# Functions
#

email(){
	if [[ $Smtp_Integration =~ true ]]; then
		echo -e "An error occurred while running Blacklists-UT1.sh (`hostname -f`):\n\n$1" | $smtp_Command > /dev/null 2>&1
	fi
}

msg(){
	echo -e $1
}

error(){
	ERROR_COLOR="\033[91m"
	DEFAULT_COLOR="\033[39m"
	echo -en $ERROR_COLOR
	msg "$1"
	echo -en $DEFAULT_COLOR
	email "$1"
	exit 1
}

inArray () {
  local e match="$1"
  shift
  for e; do [[ "$e" == "$match" ]] && return 0; done
  return 1
}

#
# Main code
#

msg "Blacklists-UT1 v$UT1_Version\nCopyright (c) 2018 Ramón Román Castro <ramonromancastro@gmail.com>\n"

# Enable case insensitive regex in bash
shopt -s nocasematch

# Verifying configuration file
if [ -f $UT1_Config ]; then
	msg "Loading $UT1_Config ..."
	. $UT1_Config
else
	error "$UT1_Config not found!"
fi

# Calculate automatica variables

squidGuard_dbtop="$(dirname "$squidGuard_dbhome")"

# Detect squid installation

squid -v > /dev/null 2>1 || error "squid not found!"

# Detect squidGuard installation

squidGuard -v > /dev/null 2>1 || error "squidGuard not found!"

# Verifying destination directory

if [ ! -d $squidGuard_dbtop ]; then
	msg "Creating $squidGuard_dbtop directory ..."
	mkdir -p $squidGuard_dbtop || error "Error creating $squidGuard_dbtop directory"
fi

# Downloading Blacklists UT1

UT1_Uri_File=`basename $UT1_Uri`
pushd $squidGuard_dbtop > /dev/null
msg "Downloading $UT1_Uri ..."
wget --no-check-certificate -q -O $UT1_Uri_File $UT1_Uri || error "Error downloading $UT1_Uri"
msg "Extracting $UT1_Uri ..."
tar xzf $UT1_Uri_File || error "Error extracting $UT1_Uri_File"
rm -f $UT1_Uri_File
popd > /dev/null

# Creating squidGuard config header

msg "Creating $squidGuard_Config header ..."
echo "# Blacklists UT1 (L'Université Toulouse 1 Capitole)" > $squidGuard_Config
echo "# Generated automatically by Blacklists-UT1.sh" >> $squidGuard_Config
echo "# IMPORTANT: DO NOT EDIT MANUALLY!" >> $squidGuard_Config
echo "# Date: `date`" >> $squidGuard_Config
echo >> $squidGuard_Config
echo dbhome $squidGuard_dbhome >> $squidGuard_Config
echo logdir $squidGuard_logdir >> $squidGuard_Config
echo >> $squidGuard_Config

for dir in $(find -P $squidGuard_dbhome -mindepth 1 -maxdepth 1 -type d | sort); do
	dest=`basename $dir`
	dest_block=skip
	if [ -f ${dir}/usage ] && [ "${UT1_Blacklist[@]}" == "" ] && awk '/^\s*[^#]/{ print $0 }' ${dir}/usage |  grep "black" > /dev/null; then dest_block=black; fi
	if [ -f ${dir}/usage ] && inArray "$dest" "${UT1_Blacklist[@]}"; then dest_block=black; fi
	if inArray "$dest" "${UT1_Whitelist[@]}"; then dest_block=white; fi
	if [ $dest_block != "skip" ]; then
		if [ $dest_block == "black" ]; then Blacklist="$Blacklist!${dest} "; msg "Blacklist [$dest]"; fi
		if [ $dest_block == "white" ]; then msg "Whitelist [$dest]"; fi
		echo "dest ${dest} {" >> $squidGuard_Config
		[ -s ${dir}/domains ]     && echo "	domainlist ${dest}/domains" >> $squidGuard_Config
		[ -s ${dir}/urls ]        && echo "	urllist ${dest}/urls" >> $squidGuard_Config
		[ -s ${dir}/expressions ] && echo "	expressionlist ${dest}/expressions" >> $squidGuard_Config
		echo "	log ${dest}.log" >> $squidGuard_Config
		echo "}" >> $squidGuard_Config
	else
		msg "Skip [$dest] list"
	fi
done

# Creating squidGuard config footer

msg "Creating $squidGuard_Config footer ..."
echo >> $squidGuard_Config
echo "acl {" >> $squidGuard_Config
echo "	default {" >> $squidGuard_Config
echo "		pass ${UT1_Whitelist[@]} $Blacklist all" >> $squidGuard_Config
echo "		redirect $squidGuard_redirect" >> $squidGuard_Config
echo "	}" >> $squidGuard_Config
echo "}" >> $squidGuard_Config

# Compiling squidGuard lists

msg "Compiling squidGuard lists ..."
squidGuard -C all -c $squidGuard_Config -d || error "Error compiling squidGuard lists"

# Setting permissions and SELinux

msg "Regenerating permissions ..."
chmod 640 $squidGuard_Config
chown $squid_user:$squid_group $squidGuard_dbtop -R

msg "Regenerating SELinux ..."
getenforce > /dev/null && restorecon -R $squidGuard_dbtop

# Reloading Squid

if [[ $UT1_Squid_Integration =~ true ]]; then
	msg "Reloading squid ..."
	if ps 1 | grep "systemd" > /dev/null 2>&1; then
		systemctl reload squid > /dev/null 2>&1 || error "Error reloading squid"
	else
		service squid reload > /dev/null 2>&1 || error "Error reloading squid"
	fi
fi
