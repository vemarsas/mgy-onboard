#!/bin/bash

set +e

# This assumes that the user
# OnBoard/Margay will run-as
# already exists in the system and can sudo,
# and the current software project
# is copied / placed in the relevant directory with proper
# ownership/permissions.
# This script takes control from there.
# Another script has been implemented for that very initial
# bootstrap: it is located at top-level dir of this project
# and it is named setup.sh as well (at the time of writing this note).

# echo $* # DEBUG

PROJECT_ROOT=${1:-`pwd`}
APP_USER=${2:-'onboard'}

SCRIPTDIR=$PROJECT_ROOT/etc/scripts

export DEBIAN_FRONTEND=noninteractive

install_conffiles() {
    # See README file in doc/sysadm/examples/ .
    install -bvC -m 644 doc/sysadm/examples/etc/dnsmasq.conf            /etc/
    install -bvC -m 644 doc/sysadm/examples/etc/sysctl.conf             /etc/

    install -bvC -m 644 doc/sysadm/examples/etc/usb_modeswitch.conf     /etc/
    install -bvC -m 644 doc/sysadm/examples/etc/usb_modeswitch.d/*:*    /etc/usb_modeswitch.d/
}

disable_dhcpcd_master() {
    # Even if no interface is configured with dhcp in /etc/network/interfaces,
    # dhcpcd is a system(d) service, that starts as just "dhcpcd" (master mode)
    # which is incompatible with onboard detection and control.
    if (systemctl list-units --all -t service | grep dhcpcd); then
        systemctl stop dhcpcd
        systemctl disable dhcpcd
    fi
}

setup_nginx() {
    apt-get -y remove lighttpd
    apt-get -y install nginx-light ssl-cert
    rm -fv /etc/nginx/sites-enabled/default  # just a symlink
    install -bvC -m 644 doc/sysadm/examples/etc/nginx/sites-available/margay /etc/nginx/sites-available/
    ln -svf ../sites-available/margay /etc/nginx/sites-enabled/
    systemctl reload nginx
}

cd $PROJECT_ROOT

apt-get update
apt-get -y upgrade

apt-get -y install ruby ruby-dev ruby-rack ruby-rack-protection ruby-locale sudo iproute2 iptables bridge-utils pciutils usbutils usb-modeswitch dhcpcd5 dnsmasq resolvconf locales ifrename build-essential ca-certificates libssl-dev ntp psmisc

install_conffiles

# Let's not use the old Debian one...
gem install -v '~> 2' bundler

su - $APP_USER -c "
    cd $PROJECT_ROOT
    # Module names are also Gemfile groups
    set -x
    bundle install
"

modprobe nf_conntrack
service procps restart

disable_app_modules

disable_dhcpcd_master

# Circumvent this bug:
# http://debian.2.n7.nabble.com/Bug-732920-procps-sysctl-system-fails-to-load-etc-sysctl-conf-td3133311.html
sysctl --load=/etc/sysctl.conf
sysctl --load=$PROJECT_ROOT/doc/sysadm/examples/etc/sysctl.conf

# Disable the legacy persist service: we rely on /etc now...
if ( systemctl list-units --all | grep margay-persist.service ); then
    systemctl disable margay-persist.service
fi

cat > /etc/systemd/system/margay.service <<EOF
[Unit]
Description=Margay Service
After=network.target

[Service]
Type=simple
User=$APP_USER
WorkingDirectory=$PROJECT_ROOT
Environment="APP_ENV=production"
ExecStart=/usr/bin/env ruby onboard.rb
SyslogIdentifier=margay
Restart=on-failure
# Other Restart options: always, on-abort, on-failure etc

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload

systemctl enable margay
systemctl start margay

cd $PROJECT_ROOT  # Apparently needed...

setup_nginx

# Remove packages conflicting with our DHCP management
if (dpkg -l | egrep '^i.\s+wicd-daemon')
then
    apt-get -y remove wicd-daemon
fi

. $SCRIPTDIR/_restore_dns.sh

