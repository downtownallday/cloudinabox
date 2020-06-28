#!/bin/bash

. setup/functions.sh     || exit 1
. /etc/cloudinabox.conf  || die "Could not load /etc/cloudinabox.conf"

apt_install php php-fpm php-cli php-curl php-dom php-gd php-mbstring php-zip php-bz2 php-intl php-mysql php-smbclient php-imap php-gmp php-imagick php-redis php-apcu || die "Unable to install php packages"

#
# configure php.ini
#

# php used by apache and php-fpm
# nextcloud recommeneded opcache settings
for ini in /etc/php/7.2/apache2/php.ini /etc/php/7.2/fpm/php.ini
do
    [ ! -e "$ini" ] && continue
    tools/editconf.py $ini -c ";" \
		      "memory_limit = 512M" \
		      "upload_max_filesize = 3G" \
		      "max_execution_time = 360" \
              "output_buffering = 16384" \
		      "post_max_size = 3G" \
              "short_open_tag = On" \
	          "opcache.enable=1" \
	          "opcache.interned_strings_buffer=8" \
	          "opcache.max_accelerated_files=10000" \
	          "opcache.memory_consumption=128" \
	          "opcache.save_comments=1" \
	          "opcache.revalidate_freq=1" \
		      "date.timezone = $TIMEZONE"
    [ $? -ne 0 ] &&
        die "Unable to modify $ini"
done

# php used from the command line (Nextcloud cron jobs):
tools/editconf.py /etc/php/7.2/cli/php.ini -c ";" \
		          "date.timezone = $TIMEZONE";
[ $? -ne 0 ] && die "Unable to modify cli/php.ini"

# this keeps the nextcloud cron job from logging
# "Memcache \\OC\\Memcache\\APCu not available for local cache"
tools/editconf.py /etc/php/7.2/cli/php.ini -ini-section PHP -c ";" \
                  "apc.enable_cli=1"
[ $? -ne 0 ] && die "Unable to modify cli/php.ini"


# If apc is explicitly disabled we need to enable it
if grep -q apc.enabled=0 /etc/php/7.2/mods-available/apcu.ini; then
	tools/editconf.py /etc/php/7.2/mods-available/apcu.ini -c ';' \
		              "apc.enabled=1"
    [ $? -ne 0 ] &&
        die "Unable to modify apcu.ini"
fi

restart_service php7.2-fpm

