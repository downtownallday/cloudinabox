#!/bin/bash

. setup/functions.sh     || exit 1
. /etc/cloudinabox.conf  || die "Could not load /etc/cloudinabox.conf"

# this mail-in-a-box script sets up and installs nginx and php-fpm
source_miab_script "setup/web-miab.sh"

# ...remove mail-related files we don't use...
rm -f /var/lib/mailinabox/mobileconfig.xml
rm -f /var/lib/mailinabox/mozilla-autoconfig.xml
rm -f /var/lib/mailinabox/mta-sts.txt


create_main_site() {
    local server_name="$1"
    say_verbose "Creating port 80 nginx site"
    cat<<EOF > /etc/nginx/sites-available/cloudinabox
server {
    listen 80;
    listen [::]:80;
    server_name ${server_name};

	# Improve privacy: Hide version an OS information on
	# error pages and in the "Server" HTTP-Header.
	server_tokens off;

	location / {
		# Redirect using the 'return' directive and the built-in
		# variable '$request_uri' to avoid any capturing, matching
		# or evaluation of regular expressions.
		return 301 https://$server_name$request_uri;
	}

	location /.well-known/acme-challenge/ {
		# This path must be served over HTTP for ACME domain validation.
		# We map this to a special path where our TLS cert provisioning
		# tool knows to store challenge response files.
		alias $STORAGE_ROOT/ssl/lets_encrypt/webroot/.well-known/acme-challenge/;
	}
}
EOF
    [ $? -ne 0 ] && die "Unable to create nginx main site"
    
    ln -sf /etc/nginx/sites-available/cloudinabox /etc/nginx/sites-enabled/cloudinabox
    [ $? -ne 0 ] && die "Unable to enable nginx main site"
}


create_main_site "$PRIMARY_HOSTNAME"
systemctl reload nginx
