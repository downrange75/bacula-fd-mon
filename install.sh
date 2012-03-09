#!/bin/bash
##################################################################################
# Copyright (C) 2011  Chris Rutledge <rutledge.chris@gmail.com>
#
# http://code.google.com/p/bacula-fd-mon/
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
##################################################################################

if [ "$(id -u)" != "0" ]; then
   echo "This script must be run as root" 1>&2
   exit 1
fi

if [ ! -d "/etc/bacula" ]
then
   echo "Creating directory /etc/bacula"
   mkdir -p /etc/bacula
fi

if [ -z "$(which bconsole)" ]
then
   echo "WARNING: Could not find bconsole"
   echo "         Please install Bacula Console"
fi

if [ -z "$(which expect)" ]
then
   echo "WARNING: Could not find expect"
   echo "         Please install expect"
fi

if [ ! -f "/etc/bacula/bacula-fd-mon.cfg" ]
then
   echo "Installing bacula-fd-mon.cfg ..."
   cp bacula-fd-mon.cfg /etc/bacula 
else
   echo "Installing bacula-fd-mon.cfg as bacula-fd-mon.cfg.new ..."
   cp bacula-fd-mon.cfg /etc/bacula/bacula-fd-mon.cfg.new
fi
   
echo "Installing bacula-fd-mon.pl and bacula-runjob.exp ..."
cp bacula-fd-mon.pl bacula-runjob.exp /usr/bin

echo "Installing bacula-fd-mon init script ..."
cp bacula-fd-mon /etc/init.d

echo "Running chkconfig on bacula-fd-mon ..."
chkconfig --add bacula-fd-mon

chmod +x /usr/bin/bacula-fd-mon.pl /usr/bin/bacula-runjob.exp
