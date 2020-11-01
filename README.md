# Cloud-in-a-Box

This is an installation of Nextcloud that borrows some of the "Mail-in-a-Box" code and standards, such as:

1. certficate creation and renewal with Let's Encrypt
1. backup and restore
1. centralisation of restorable data into /home/user-data
1. system setup, upgrade, restore and reconfiguration through a single setup script
1. encryption-at-rest
1. fail2ban
1. limiting installs to Ubuntu 18.04 and non-Dockerized

See [Mail-in-a-Box LDAP](https://github.com/downtownallday/mailinabox-ldap).

The primary purpose of this project is be able to easly deploy and maintain a cloud server (Nextcloud) for a home or small business, and together with Mail-in-a-Box LDAP, share a single user account database and similar installation and maintenance experiences. That said, both Mail-in-a-Box and Cloud-in-a-Box work just fine independently as well.


## Integration support with Mail-in-a-Box LDAP

During setup you will have an opportunity to optionally integrate Nextcloud users and groups with the companion service Mail-in-a-Box LDAP. This permits Mail-in-a-Box users access to Nextcloud without a separate password by configuring the [LDAP/Active Directory user and group backend](https://nextcloud.com/usermanagement/) for you.

`ssmtp` will be installed and configured to use Mail-in-a-Box LDAP as its mail "smart host".

Once integrated, new users can be added and removed from Nextcloud through the Mail-in-a-Box admin interface.

Note that Mail-in-a-Box LDAP is a fork of Mail-in-a-Box that supports LDAP for users and groups. This integration step works only with Mail-in-a-Box LDAP, not with Mail-in-a-Box.


## Installation

1. on a fresh Ubuntu 18.04 system, install git `apt-get install git`
2. from your home directory, clone the source code repo `git clone https://github.com/downtownallday/cloudinabox.git cloudinabox`
3. checkout the latest version `git checkout v0.2`
4. set your working directory to cloudinabox `cd cloudinabox`
5. run setup as root `sudo setup/start.sh` (or sudo ehdd/start-encrypted.sh to use encryption-at-rest)

To integrate with Mail-in-a-Box LDAP, you will also need root acess to the Mail-in-a-Box LDAP system to:

1. obtain the service account password that Nextcloud uses to perform searches for users and groups. This was created when Mail-in-a-Box LDAP was installed, and can be found in the `/home/user-data/ldap/maib_ldap.conf` file (the value of key LDAP_NEXTCLOUD_PASSWORD).
2. permit Nextcloud access the the LDAP server by adding a firewall rule for the ldaps service (port 636) (eg. on Mail-in-a-Box LDAP run `ufw allow proto tcp from <cloudinabox-ip> to any port ldaps`).
3. add an email address and alias that permits the Nextcloud host to authenticate and send mail (smart host setup).

All of these items are prompted for during setup.



## Certificate provisioning

A self-signed certificate is installed during a first-time setup. For `certbot` (the Let's Encrypt automated certificate signing program) to successfully install a valid certificate for your host, a couple of things must be in place:

1. The hostname you chose during setup MUST have a valid internet DNS entry. This can be added through your name service provider's web interface, or if you're handling your own DNS, within your own servers. If you're using Mail-in-a-Box for DNS, a custom entry can be added within the admin interface. Let's Encrypt will perform its acme challenge using this host name.

2. Timing. Cloud-in-a-Box does not have a management interface. Certificate provisioning occurs during the daily run of `management/daily_tasks.sh` (Daily Tasks) at 3:00am. To provision a Let's Encrypt certificate immediately, run `sudo management/daily_tasks.sh` manually from a shell prompt after setup has completed successfully. Note that the results of Daily Tasks is emailed to the address given during setup. Please be sure email is functioning properly (if you integrated with Mail-in-a-Box LDAP, you can test email with `echo "hi" | ssmtp me@domain.tld`).


## Upgrades

Similar to Mail-in-a-Box, upgrading Cloud-in-a-Box is simply a matter of re-running setup with the updated source code.

1. set your working directory to cloudinabox `cd cloudinabox`
1. get the latest source code `git pull`
1. checkout the new version `git checkout v0.2`
1. run setup `sudo setup/start.sh`

However, Nextcloud upgrades are handled by you using the Nextcloud user interface or directly using `occ` commands from the command line. You will find `occ` in `/usr/local/nextcloud`.


## Backup and Restore

Daily Tasks are run at 3:00am every day, which includes backing up /home/user-data with `duplicity`. This is exactly the same as Mail-in-a-Box, where backup files are encrypted and stored in /home/user-data/backup/encrypted. **Please be sure to keep a copy of the encryption key somewhere safe (off the system)**. It can be found in `/home/user-data/backup/secret_key.txt`. If your system fails restoration won't be possible without the key even if you posses the backup files.

The source code for backups (management/backup.py), was taken from the Mail-in-a-Box project and is nearly verbatim. Therefore, backups to S3 and rsync are also available, but must be configured manually due to the lack of a management interface. This is accomplished by setting backup preferences in a yaml config file located at /home/user-data/backup/custom.yaml.

Restoring from backup is simply a matter of restoring /home/user-data from duplicity backup files, then re-running setup/start.sh.

