Tools to validate that Block Producers and Standby Block Producers have set up their public configuration in a usable fashion.

The validator has multiple parts which need to be installed:
- rabbitmq
- mariadb
- webui
- dispatch
- probe

All parts can be installed on the same server, or each on its own server. Adjust usernames and passwords listed in the instructions to suit.

Installation Instructions (for ubuntu/debian):

rabbitmq:
- run: apt install rabbitmq-server
- run: rabbitmq-plugins enable rabbitmq_management
- run: rabbitmq-plugins enable rabbitmq_stomp
- run: rabbitmqctl add_vhost bpvalidate
- run: rabbitmqctl add_user bpvalidate bpvalidate
- run: rabbitmqctl set_permissions -p bpvalidate bpvalidate '.*' '.*' '.*'

mariadb:
- run: apt install mariadb-server
- mysql: create database bpvalidate
- mysql: create user user bpvalidate identified by 'bpvalidate'
- mysql: grant all privileges on bpvalidate.* to 'bpvalidate'@'%'

webui:
- install libraries from https://github.com/EOS-Nation/perl-lib
- get png-small icons from https://github.com/EOS-Nation/chain-icons and put in /var/www/chains
- download fontawesome and place in /var/www/fontawesome (or edit res/template.html and replace fontawesome references to the fontawesome CDN)
- run: apt install apache2
- create /etc/apache/sites-enabled/bpvalidate.conf to point at html directory
```
<VirtualHost *:80>
  ...
  AddDefaultCharset UTF-8
  ErrorDocument 403 /errors/403.html
  ErrorDocument 404 /errors/404.html
  DocumentRoot /var/www/bpvalidate
  <Directory /var/www/bpvalidate>
    Options +MultiViews -Indexes
    AddLanguage en .en
    AddLanguage zh .zh
    AddLanguage ko .ko
    LanguagePriority en zh ko
  </Directory>
</VirtualHost>
```

dispatch:
- install libraries from https://github.com/EOS-Nation/perl-lib
- run: apt install libtext-csv-perl libjson-perl libdbd-mysql-perl libdata-validate-perl liblocale-codes-perl libnet-stomp-perl
- mkdir /run/bpvalidate

probe:
- install libraries from https://github.com/EOS-Nation/perl-lib
- install p2ptest from https://github.com/EOS-Nation/eosio-protocol
- run: apt install libjson-validator-perl libdbd-sqlite3-perl libnet-stomp-perl libdata-validate-ip-perl libjson-perl liblwpx-paranoidagent-perl libnet-whois-ip-perl libtext-diff-perl libipc-run-perl libxml-libxml-perl nmap
