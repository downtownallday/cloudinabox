#!/bin/bash

. /etc/cloudinabox.conf  || die "Could not load /etc/cloudinabox.conf"
. setup/functions.sh     || exit 1

#apt_install php php-fpm php-cli php-curl php-dom php-gd php-mbstring php-zip php-bz2 php-intl php-mysql php-smbclient php-imap php-gmp php-imagick php-redis php-apcu || die "Unable to install php packages"

php="$REQUIRED_PHP_PACKAGE"
phpver="$REQUIRED_PHP_VERSION"

apt_install \
    $php \
    $php-fpm \
    $php-cli \
    $php-curl \
    $php-dom \
    $php-gd \
    $php-mbstring \
    $php-zip \
    $php-bz2 \
    $php-intl \
    $php-mysql \
    $php-imap \
    $php-gmp \
    $php-imagick \
    $php-bcmath \
    $php-redis \
    $php-apcu  \
    || die "Unable to install $php packages"

# php-smbclient is not currently shipping with ubuntu try to
# install, but ignore errors - it's not a required package
apt-get install -y $php-smbclient 1>/dev/null 2>&1

#
# configure php.ini
#

# php used by apache and php-fpm
# nextcloud recommeneded opcache settings
for ini in /etc/php/${phpver}/apache2/php.ini /etc/php/${phpver}/fpm/php.ini
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
tools/editconf.py /etc/php/${phpver}/cli/php.ini -c ";" \
		          "date.timezone = $TIMEZONE";
[ $? -ne 0 ] && die "Unable to modify cli/php.ini"

# this keeps the nextcloud cron job from logging
# "Memcache \\OC\\Memcache\\APCu not available for local cache"
tools/editconf.py /etc/php/${phpver}/cli/php.ini -ini-section PHP -c ";" \
                  "apc.enable_cli=1"
[ $? -ne 0 ] && die "Unable to modify cli/php.ini"


# If apc is explicitly disabled we need to enable it
if grep -q apc.enabled=0 /etc/php/${phpver}/mods-available/apcu.ini; then
	tools/editconf.py /etc/php/${phpver}/mods-available/apcu.ini -c ';' \
		              "apc.enabled=1"
    [ $? -ne 0 ] &&
        die "Unable to modify apcu.ini"
fi

restart_service php${phpver}-fpm

