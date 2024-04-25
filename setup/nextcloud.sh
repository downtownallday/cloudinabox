#!/bin/bash

. /etc/cloudinabox.conf  || die "Could not load /etc/cloudinabox.conf"
. setup/functions.sh     || exit 1

phpx="$REQUIRED_PHP_EXECUTABLE"


update_sql_conf() {
    local conf="$STORAGE_ROOT/sql/ciab_sql.conf"
    . "$conf" || die "Unable to load $conf"
    if [ -z "$NC_SQL_DB" ]; then
        say_verbose "Generating a new sql password for Nextcloud"
        tools/editconf.py \
            "$conf" \
            "NC_SQL_DB=nextclouddb" \
            "NC_SQL_USER=nextcloud" \
            "NC_SQL_PASSWORD=\"$(generate_password 32)\"" || die "Unable to modify $conf"
        . "$conf"
    fi
}

create_db() {
    mysql -u root --password="$SQL_ROOT_PASSWORD" 1>/dev/null 2>&1 <<EOF
use ${NC_SQL_DB};
EOF
    if [ $? -ne 0 ]; then    
        # create the necessary database
        say_verbose "Create Nextcloud database '$NC_SQL_DB'"
        mysql -u root --password="$SQL_ROOT_PASSWORD" --database=mysql <<EOF
CREATE DATABASE $NC_SQL_DB CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
CREATE USER '$NC_SQL_USER'@'localhost' IDENTIFIED BY '$NC_SQL_PASSWORD';
GRANT ALL PRIVILEGES ON $NC_SQL_DB.* TO '$NC_SQL_USER'@'localhost';
FLUSH PRIVILEGES;
EOF
        [ $? -ne 0 ] && die "Unable to create Nextcloud database"
    else
        say_verbose "Nextcloud database already exists"
    fi
}


download_nextcloud() {
    #
    # DOWNLOAD and extract Nextcloud sources
    #
    if [ -e "$NCDIR/core" ]; then
        say_verbose "Nextcloud already downloaded"
        return 0
    fi

    say_verbose "Downloading and installing Nextcloud binaries"

    # check if we're restoring from backup and only install the
    # version of Nextcloud that corresponds to the data directory. it
    # is very important that the versions correspond

    get_nc_config_value "version" ||
        die "error reading Nextcloud version from $NCSTORAGE/config/config.php or $NCSTORAGE/config.list !"

    if [ "$VALUE" == "" ]; then
        # not restoring from backup...
        say_verbose ".. installing the latest Nextcloud for this system"
        get_nc_download_url

    else
        # extract the Nextcloud version to 3 positions
        say_verbose ".. restore Nextcloud version $VALUE"
        local ver="$(awk -F. '{print $1"."$2"."$3}' <<< "$VALUE")"
        #url="https://download.nextcloud.com/server/releases/nextcloud-${ver}.tar.bz2"
        get_nc_download_url "$ver"
    fi
           
    
    download_link "$DOWNLOAD_URL" to-file use-cache "$DOWNLOAD_URL_CACHE_ID"
    
    if [ $? -ne 0 ]; then
        die "Unable to download Nextcloud ($url)"
    else
        say_verbose "Extracting: $DOWNLOAD_FILE"
        mkdir -p "$NCDIR" || die "Unable to create $NCDIR"
        (cd "$(dirname "$NCDIR")"; tar -xf "$DOWNLOAD_FILE")
        if [ $? -ne 0 ]; then
            rm -f "$DOWNLOAD_FILE"
            die "Bad download file"
        fi
    fi
    
    chown -R www-data:www-data "$NCDIR"
    if [ $? -ne 0 ]; then
        rm -rf "$NCDIR"
        die "Unable to set permissions on $NCDIR"
    fi
    return 0
}


move_config_to_user_data() {
    if [ ! -e "$STORAGE_ROOT/nextcloud/config" ]; then
        mv "$NCDIR/config" "$STORAGE_ROOT/nextcloud" \
            || die "Could not move $NCDIR/config to $STORAGE_ROOT/nextcloud"
    fi

    rm -rf "$NCDIR/config"
    
    ln -sf "$STORAGE_ROOT/nextcloud/config" "$NCDIR/config" \
        || die "Could not link $NCDIR/config -> $STORAGE_ROOT/nextcloud/config"
}


install_nextcloud() {
    mkdir -p "$NCDATA" || die "Could not create $NCDATA"
    chown www-data:www-data "$NCDATA"
    chmod 770 "$NCDATA"

    local installed=1
    local errors=()

    # relocate nextcloud/config to user-data/nextcloud/config
    move_config_to_user_data
    
    if [ ! -e "$NCDIR/config/config.php" ]; then
        installed=0
    else
        # get installed state
        get_nc_config_value installed 0
        installed=$VALUE
    fi

    if [ $installed -eq 0 ]; then
        say_verbose "Running Nextcloud installation"
        local occargs=""
        is_verbose && occargs="-vvv"
        sudo -E -u www-data $phpx $NCDIR/occ  maintenance:install $occargs --database "mysql" --database-name "$NC_SQL_DB"  --database-user "$NC_SQL_USER" --database-pass "$NC_SQL_PASSWORD" --admin-user "admin" --admin-pass "$SQL_ROOT_PASSWORD" --data-dir "$NCDATA"
        if [ $? -ne 0 ]; then
            die "Nextcloud occ maintenance:install failed"
        fi

        cat >"$CIAB_NEXTCLOUD_CONF" <<EOF
NC_ADMIN_USER=admin
NC_ADMIN_PASSWORD='$SQL_ROOT_PASSWORD'
EOF
        chmod 600 "$CIAB_NEXTCLOUD_CONF"    

        # additional occ commands
        sudo -E -u www-data $phpx $NCDIR/occ maintenance:update:htaccess -q
        [ $? -ne 0 ] && errors+=("occ maintenance:update:htaccess failed")
        sudo -E -u www-data $phpx $NCDIR/occ app:disable survey_client -q
        [ $? -ne 0 ] && errors+=("occ app:disable survey_client failed")
        sudo -E -u www-data $phpx $NCDIR/occ app:enable admin_audit -q
        [ $? -ne 0 ] && errors+=("occ app:enable admin_audit failed")
        sudo -E -u www-data $phpx $NCDIR/occ db:convert-filecache-bigint -q --no-interaction
        [ $? -ne 0 ] && errors+=("occ db:convert-filecache-bigint failed")
        sudo -E -u www-data $phpx $NCDIR/occ app:list > $STORAGE_ROOT/nextcloud/app.list
        [ $? -ne 0 ] && errors+=("occ app:list failed")

    else
        # maintenance / recovery commands
        sudo -E -u www-data $phpx $NCDIR/occ maintenance:mode --off
        [ $? -ne 0 ] && errors+=("occ maintenance:mode --off failed")
        sudo -E -u www-data $phpx $NCDIR/occ maintenance:repair -q
        #[ $? -ne 0 ] && errors+=("occ maintenance:repair failed")
        sudo -E -u www-data $phpx $NCDIR/occ db:add-missing-indices -q
        [ $? -ne 0 ] && errors+=("occ db:add-missing-indices failed")
        sudo -E -u www-data $phpx $NCDIR/occ files:scan --all
        #[ $? -ne 0 ] && errors+=("occ files:scan --all failed")
    fi


    if [ ${#errors[@]} -gt 0 ]; then
        die "${errors[*]}"
    fi

    source "$CIAB_NEXTCLOUD_CONF"
    
    return 0
}

    
update_nextcloud_config() {
    local dot_local="$(hostname | awk -F. '{print $1}').local"
    local trusted_domains=("$PRIMARY_HOSTNAME" "$dot_local")
    if [ "$(hostname)" != "$PRIMARY_HOSTNAME" ]; then
        trusted_domains+=($(hostname))
    fi
    
    local addr
    for addr in $(ip --brief address | awk '{print $3; print $NF}' | awk -F/ '{print $1}' | sort -u); do
        trusted_domains+=("$addr")
    done

    local idx
    let idx=0
    while [ $idx -lt ${#trusted_domains[*]} ]; do
        trusted_domains[$idx]="$idx=>'${trusted_domains[$idx]}',"
        let idx+=1
    done
    
    sudo -u www-data $phpx tools/editconf.php "$NCDIR/config/config.php" \
         "CONFIG" \
         'trusted_domains' "array(${trusted_domains[*]})" \
         'overwrite.cli.url' "https://$PRIMARY_HOSTNAME/" \
         'htaccess.RewriteBase' '/' \
         'forcessl' 'true' \
         'auth.bruteforce.protection.enabled' 'true' \
         'memcache.local' '\OC\Memcache\APCu' \
         'memcache.distributed' '\OC\Memcache\Redis' \
         'memcache.locking' '\OC\Memcache\Redis' \
         'redis' "array(
                 'host' => '/var/run/redis/redis-server.sock',
                 'port' => 0)" \
         '+enable_previews' 'true' \
         '+enabledPreviewProviders' "array(
                 0 => 'OC\\Preview\\PNG',
                 1 => 'OC\\Preview\\JPEG',
                 2 => 'OC\\Preview\\GIF',
                 3 => 'OC\\Preview\\HEIC',
                 4 => 'OC\\Preview\\BMP',
                 5 => 'OC\\Preview\\XBitmap',
                 6 => 'OC\\Preview\\Movie',
                 7 => 'OC\\Preview\\MP3',
                 8 => 'OC\\Preview\\TXT',
                 9 => 'OC\\Preview\\MarkDown')" \
         '+preview_max_x' 1440 \
         '+preview_max_y' 1080 \
         '+preview_max_scale_factor' 1 \
         'filesystem_check_changes' 0 \
         'log_type' 'file' \
         'logfile' '/var/log/nextcloud/nextcloud.log' \
         '+loglevel' 2 \
         'logtimezone'  "$TIMEZONE" \
         'log_rotate_size' 0 \
         'activity_expire_days' 30 \
         'mysql.utf8mb4' 'true'
    [ $? -ne 0 ] && die "Unable to change $NCDIR/config/config.php"
    #                 9 => 'OC\\Preview\\PDF')" 

    chmod o-rwx "$NCDIR/config/config.php"
    
    mkdir -p /var/log/nextcloud
    chown www-data:syslog /var/log/nextcloud
    chmod 775 /var/log/nextcloud
    
    return 0
}


update_crontab() {
    cat >/etc/cron.d/cloudinabox-nextcloud <<EOF
# Generated file do not edit
*/5 * * * *	root	sudo -u www-data $phpx -f $NCDIR/cron.php
0 1 * * *	root	sudo -u www-data $phpx $NCDIR/occ app:list > "$NCSTORAGE/app.list"
1 1 * * *	root	sudo -u www-data $phpx $NCDIR/occ config:list > "$NCSTORAGE/config.list"
30 2 * * *	root	/usr/bin/mysqldump --defaults-extra-file=$HOME/.my.cnf --single-transaction --routines --triggers --databases $NC_SQL_DB | /usr/bin/xz > "$STORAGE_ROOT/sql/data_backup/$NC_SQL_DB.sql.xz"; chmod 600 "$STORAGE_ROOT/sql/data_backup/$NC_SQL_DB.sql.xz"
EOF
    [ $? -ne 0 ] && die "Error installing crontab"    

    sudo -E -u www-data $phpx $NCDIR/occ background:cron -q
    [ $? -ne 0 ] && die "Could not run occ backgrond:cron"
    return 0
}

restore_apps() {
    local listfile="$STORAGE_ROOT/nextcloud/app.list"
    [ ! -e "$listfile" ] && return 0

    local actual desired
    actual=( $(sudo -u www-data $phpx $NCDIR/occ app:list | awk 'BEGIN { S=0 } /^Enabled:/ {S=1; next; } /^Disabled:/ {S=2; next; } S==1 {print substr($2,1,length($2)-1)}') )
    [ $? -ne 0 ] && die "Unable to list apps with occ app:list"

    desired=( $(cat "$listfile" | awk 'BEGIN { S=0 } /^Enabled:/ {S=1; next; } /^Disabled:/ {S=2; next; } S==1 {print substr($2,1,length($2)-1)}') )
    [ $? -ne 0 ] && die "Problem reading $listfile"
    
    local app
    for app in "${desired[@]}"; do
        if ! array_contains "$app" ${actual[@]}; then
            say_verbose "Install missing app: $app"
            sudo -E -u www-data $phpx $NCDIR/occ app:install "$app" -q --no-interaction
            [ $? -ne 0 ] && say "Could not install Nextcloud app $app"
        fi
    done
}



create_nextcloud_site() {
    # SEE: https://docs.nextcloud.com/server/16/admin_manual/installation/nginx.html
    local server_name="$1"
    local cert="$2"
    say_verbose "Creating Nextcloud nginx site"


    local mixins=""
    local local_mods_dir="${LOCAL_MODS_DIR:-local}"
    if [ -e "$local_mods_dir/nginx.mixins" ]; then
        mixins="$(cat $local_mods_dir/nginx.mixins)"
        [ $? -ne 0 ] && die "Could not read $local_mods_dir/nginx.mixins"
    fi
         
    cat<<EOF > /etc/nginx/sites-available/cloudinabox-nextcloud
upstream php-handler {
   server unix:/var/run/php/php${REQUIRED_PHP_VERSION}-fpm.sock;
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name ${server_name};
    server_tokens off;

    ssl_certificate $cert;
    ssl_certificate_key $STORAGE_ROOT/ssl/ssl_private_key.pem;

    add_header Strict-Transport-Security "max-age=15768000; includeSubDomains;";
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    add_header X-Robots-Tag noindex,nofollow;
    add_header X-Download-Options noopen;
    add_header X-Permitted-Cross-Domain-Policies none;
    add_header X-Frame-Options SAMEORIGIN;
    add_header Referrer-Policy no-referrer;

    # Remove X-Powered-By, which is an information leak
    fastcgi_hide_header X-Powered-By;

    root /usr/local/nextcloud;

    location = /robots.txt {
      log_not_found off;
      access_log off;
    }
    location = /favicon.ico {
      log_not_found off;
      access_log off;
    }

    location = /.well-known/carddav {
      return 301 \$scheme://\$host:\$server_port/remote.php/dav;
    }
    location = /.well-known/caldav {
      return 301 \$scheme://\$host:\$server_port/remote.php/dav;
    }

    location = /.well-known/webfinger {
      return 301 /index.php\$uri;
    }

    location = /.well-known/nodeinfo {
      return 301 /index.php\$uri;
    }

    # set max upload size
    client_max_body_size 512M;
    fastcgi_buffers 64 4K;

    # Enable gzip but do not remove ETag headers
    gzip on;
    gzip_vary on;
    gzip_comp_level 4;
    gzip_min_length 256;
    gzip_proxied expired no-cache no-store private no_last_modified no_etag auth;
    gzip_types application/atom+xml application/javascript application/json application/ld+json application/manifest+json application/rss+xml application/vnd.geo+json application/vnd.ms-fontobject application/x-font-ttf application/x-web-app-manifest+json application/xhtml+xml application/xml font/opentype image/bmp image/svg+xml image/x-icon text/cache-manifest text/css text/plain text/vcard text/vnd.rim.location.xloc text/vtt text/x-component text/x-cross-domain-policy;

     location / {
        rewrite ^ /index.php;
     }

     location ~ ^\/(?:build|tests|config|lib|3rdparty|templates|data)\/ {
        deny all;
     }
     location ~ ^\/(?:\.|autotest|occ|issue|indie|db_|console) {
        deny all;
     }

     # local/nginx.mixins
     ${mixins:-# -- none --}

     # local pages
     location = /site {
       return 302 /site/;
     }

     location ^~ /site/ {
       index index.html index.htm;
       disable_symlinks on;
       alias /home/user-data/www/default/;
     }

     location ~ ^\/(?:index|remote|public|cron|core\/ajax\/update|status|ocs\/v[12]|updater\/.+|oc[ms]-provider\/.+)\.php(?:\$|\/) {
        fastcgi_split_path_info ^(.+?\.php)(\/.*|)\$;
        set \$path_info \$fastcgi_path_info;
        try_files \$fastcgi_script_name =404;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param PATH_INFO \$path_info;
        fastcgi_param HTTPS on;
        # Avoid sending the security headers twice
        fastcgi_param modHeadersAvailable true;
        # Enable pretty urls
        fastcgi_param front_controller_active true;
        fastcgi_pass php-handler;
        fastcgi_intercept_errors on;
        fastcgi_request_buffering off;
     }

     location ~ ^\/(?:updater|oc[ms]-provider)(?:\$|\/) {
        try_files \$uri/ =404;
        index index.php;
     }

     # Adding the cache control header for js, css and map files
     # Make sure it is BELOW the PHP block
     location ~ \.(?:css|js|mjs|woff2?|svg|gif|map)\$ {
        try_files \$uri /index.php\$request_uri;
        add_header Cache-Control "public, max-age=15778463";
        # Add headers to serve security related headers (It is intended to
        # have those duplicated to the ones above)
        # Before enabling Strict-Transport-Security headers please read into
        # this topic first.
        add_header Strict-Transport-Security "max-age=15768000; includeSubDomains;";
        #
        # WARNING: Only add the preload option once you read about
        # the consequences in https://hstspreload.org/. This option
        # will add the domain to a hardcoded list that is shipped
        # in all major browsers and getting removed from this list
        # could take several months.
        add_header X-Content-Type-Options nosniff;
        add_header X-XSS-Protection "1; mode=block";
        add_header X-Robots-Tag none;
        add_header X-Download-Options noopen;
        add_header X-Permitted-Cross-Domain-Policies none;
        add_header Referrer-Policy no-referrer;

        # Optional: Don't log access to assets
        access_log off;
     }

     location ~ \.(?:png|html|ttf|ico|jpg|jpeg|bcmap)\$ {
        try_files \$uri /index.php\$request_uri;
        # Optional: Don't log access to other assets
        access_log off;
     }
}   
EOF
    [ $? -ne 0 ] && die "Unable to create nginx Nextcloud site"
    
    ln -sf /etc/nginx/sites-available/cloudinabox-nextcloud /etc/nginx/sites-enabled/cloudinabox-nextcloud
    [ $? -ne 0 ] && die "Unable to enable nginx Nextcloud site"
    return 0
}


say "Installing Nextcloud"

# install additional packages (now needed for NC21)
apt_install imagemagick

# update ciab_sql.conf to include nextcloud variables (and loads it)
update_sql_conf

# create the nextcloud sql database
create_db

# download sources
download_nextcloud

# allow nextcloud access to local redis-server.sock
usermod -a -G redis www-data

# run the nextcloud occ maintenance:install step
install_nextcloud

# apply local config changes
update_nextcloud_config

# Run nextcloud background jobs via cron:
update_crontab

# Restore missing apps
restore_apps

# Create site in nginx
create_nextcloud_site "$PRIMARY_HOSTNAME" "$STORAGE_ROOT/ssl/ssl_certificate.pem"

# rotate the logs
cat > /etc/logrotate.d/nextcloud <<EOF
/var/log/nextcloud/nextcloud.log {
	weekly
	missingok
	rotate 52
	compress
	delaycompress
	notifempty
	create 660 www-data syslog
}
EOF

systemctl reload nginx || die "NGINX failed to start, see /var/log/syslog !!"
systemctl restart php${REQUIRED_PHP_VERSION}-fpm

