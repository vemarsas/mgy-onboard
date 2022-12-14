#!/bin/bash

PROJECT_ROOT=${1:-`dirname $0`/../../../../../..}
APP_USER=${2:-'onboard'}

SCRIPTDIR=$PROJECT_ROOT/etc/scripts

enable_onboard_modules() {
	cd $PROJECT_ROOT/modules/
	rm -f ap/.disable
	touch ap/.enable
}

apt-get -yq install hostapd

# The system(d) service is "masked" by default, which is okay for us ;)

enable_onboard_modules

systemctl stop margay
systemctl start margay

. $SCRIPTDIR/_restore_dns.sh

