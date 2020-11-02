#!/bin/bash

. /etc/cloudinabox.conf  || die "Could not load /etc/cloudinabox.conf"
. setup/functions.sh     || exit 1

php="$REQUIRED_PHP_PACKAGE"
phpver="$REQUIRED_PHP_VERSION"

# this mail-in-a-box script sets up and installs nginx and php-fpm
# however to support our desired version of php, we must modify it
# first
echo "# GENERATED FILE - DO NOT EDIT - GENERATED FROM setup/web-miab.sh" > setup/web-miab-mods.sh \
    || die "Could not create setup/web-miab-mods.sh"

cat setup/web-miab.sh >> setup/web-miab-mods.sh \
    || die "Could not copy setup/web-miab.sh"

# change php module names, eg: php-cli => php7.4-cli
errmsg="Could not edit setup/web-miab.sh"
sed -i "s/php-/$php-/g" setup/web-miab-mods.sh || die "$errmsg"

# change hardcoded php version
sed -i "s/7\\.2/$phpver/g" setup/web-miab-mods.sh || die "$errmsg"

# run the modified script
source_miab_script "setup/web-miab-mods.sh"

# ... then, remove mail-related files we don't use...
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
