#!/bin/bash

ldap_config=/etc/ldapscripts/ldapscripts.conf
ldap_exec=/var/www/html/php/ldapexec.php
ldap_runtime=/usr/share/ldapscripts/runtime
gateone=/opt/gateone/server.conf
nsswitch=/etc/nsswitch.conf
content_html=/var/www/html/content.html
frame_html=/var/www/html/exp4/interaction-frame.html


    echo "Enter the IP of your system on which you want to host lab\nUse this command to find ip:\nifconfig | grep 'inet addr' | cut -d: -f2 | tail -1 | awk '{print $1}' "
    read IP
    echo "Enter the available port for gateone server" 
    read port
    echo "Enter the admin password"
    read passwd

function build_lab()nd 
{
 ########################
 #git clone https://github.com/Virtual-Labs/linux-lab-iiith.git
 #cd ~/linux-lab-iiith/
 #git checkout linux-lab-on-single-host
 ########################

 #cd ~/linux-lab-iiith/src/
 #make
 sudo rsync -ar ~/linux-lab-iiith/build/ /var/www/html #### added /html 
}

function update_ldapscripts()
{
 sed -i 's/#SERVER=.*/SERVER="ldap:\/\/localhost"/g' "$ldap_config"
 sed -i "s/#SUFFIX=.*/SUFFIX='dc=virtual-labs,dc=ac,dc=in'/g" "$ldap_config"
 sed -i "s/#GSUFFIX=.*/GSUFFIX='ou=Group'/g" "$ldap_config"
 sed -i "s/#USUFFIX=.*/USUFFIX='ou=People'/g" "$ldap_config"
 sed -i "s/#MSUFFIX=.*/MSUFFIX='ou=Computers'/g" "$ldap_config"
 sed -i "s/BINDDN=.*/BINDDN='cn=admin,dc=virtual-labs,dc=ac,dc=in'/g" "$ldap_config"
 sed -i 's/MIDSTART=.*/MIDSTART="10000"/g' "$ldap_config"
}

function create_password_file()
{
 sudo sh -c "echo -n 'password' > /etc/ldapscripts/ldapscripts.passwd"
 sudo chmod 440 /etc/ldapscripts/ldapscripts.passwd
}

function update_ldap_runtime()
{
 sed -i '0,/USER=.*/s//USER=$(whoami 2>\/dev\/null)/' $ldap_runtime
}

function add_www-data_to_root-group()
{
 usermod -a -G root www-data
}

function restart_apache2()
{
 service apache2 restart
}

#################### Gateone Server

function install_tornado_and_python-support()
{
 export http_proxy="http://proxy.iiit.ac.in:8080"
 export https_proxy="http://proxy.iiit.ac.in:8080"
 sudo apt-get install python-pip -y
 pip install tornado==2.4.1
 sudo apt-get install python-support -y
}

function download_and_install_gateone()
{
 ls ~/ | grep -qF gateone || wget https://github.com/downloads/liftoff/GateOne/gateone_1.1-1_all.deb -P ~/
 dpkg -i ~/gateone*.deb
}

function generate_server_conf()
{
 cd /opt/gateone
 ./gateone.py &
 # Get its PID
 PID=$!
 # Wait for 4 seconds
 sleep 4
 # Kill it
 kill $PID
 cd - 
}

function update_gateone_config()
{
 sed -i '0,/port =.*/s//port = '$port'/' $gateone
 ip=$IP
 sed -ie '0,/origins =.*/s//origins = "http:\/\/localhost;https:\/\/localhost;http:\/\/127.0.0.1;https:\/\/127.0.0.1;https:\/\/test;https:\/\/'$ip':'$port'"/' $gateone
}

###################################### Gateone Server END


######################################## SSH server
function install_nscd()
{
 sudo apt-get install libpam-ldap nscd -y
}

function configure_ldap()
{
 sudo dpkg-reconfigure ldap-auth-config
}

function modify_nsswitch_conf()
{
 sed -i '0,/passwd:.*/s//passwd:         ldap compat/' $nsswitch
 sed -i '0,/group:.*/s//group:          ldap compat/' $nsswitch
 sed -i '0,/shadow:.*/s//shadow:         ldap compat/' $nsswitch
 sed -i '0,/hosts:.*/s//hosts:          files dns ldap/' $nsswitch
}

function edit_common_session()
{
  LINE='session required pam_mkhomedir.so skel=/etc/skel umask=0022'
  FILE=/etc/pam.d/common-session
  grep -qF "$LINE" "$FILE" || echo "$LINE" >> "$FILE"
}

function restart_nscd()
{
 /etc/init.d/nscd restart
}
######################################## SSH server END


######################################## LDAP server configuration
function install_ldap()
{
 sudo apt-get install slapd ldap-utils -y
}

function configure_slapd()
{
 dpkg-reconfigure slapd
}
function create_organizational_units()
{
 touch ~/units.ldif ~/group.ldif ~/testuser1.ldif
 echo "dn: ou=People,dc=virtual-labs,dc=ac,dc=in
ou: People
objectClass: organizationalUnit

dn: ou=Group,dc=virtual-labs,dc=ac,dc=in
ou: Group
objectClass: organizationalUnit" > ~/units.ldif

 echo "dn: cn=vlusers,ou=Group,dc=virtual-labs,dc=ac,dc=in
cn: vlusers
gidNumber: 20000
objectClass: top
objectClass: posixGroup" > ~/group.ldif

 echo "dn: uid=testuser1,ou=People,dc=virtual-labs,dc=ac,dc=in
uid: testuser1
uidNumber: 20000
gidNumber: 20000
cn: Test User 1
sn: User
objectClass: top
objectClass: person
objectClass: posixAccount
objectClass: shadowAccount
loginShell: /bin/bash
homeDirectory: /home/testuser1" > ~/testuser1.ldif

ldapadd -x -D 'cn=admin,dc=virtual-labs,dc=ac,dc=in' -W -f ~/units.ldif
ldapadd -x -D 'cn=admin,dc=virtual-labs,dc=ac,dc=in' -W -f ~/group.ldif
ldapadd -x -D 'cn=admin,dc=virtual-labs,dc=ac,dc=in' -W -f ~/testuser1.ldif

}

function create_ldap_log_file()
{
 touch /var/log/ldapscripts.log
 chmod o-r /var/log/ldapscripts.log
 chown www-data:www-data /var/log/ldapscripts.log
}
 
function update_ldapexec_file()
{
 ldap_ip=$IP
 sed -i '0,/$ldap_host =.*/s//$ldap_host = \"'$ldap_ip'\";/' $ldap_exec
 ldap_password=$passwd
 ldap_confirm_password=$passwd
 if [ $ldap_password != $ldap_confirm_password ]
 then
    echo "password does not match"
 else
    sed -i '0,/$ldap_admin_pass =.*/s//$ldap_admin_pass = \"'$ldap_password'\";/' $ldap_exec
 fi
}

######################################## ldap 


############################################ Final Setup

function final_setup()
{
 gateone_ip=$IP
 gateone_port=$port
 sed -ie '0,/.*accessed <a href="http.*/s//                accessed <a href="https:\/\/'$gateone_ip':'$gateone_port'">here<\/a>./' $content_html
 sed -ie '0,/    <frame src="http.*/s//    <frame src="https:\/\/'$gateone_ip':'$gateone_port'" \/>/' $frame_html

 cd /opt/gateone
 ./gateone.py > /dev/null &
 cd -
 sudo service apache2 restart
}

######################################## FINAL setup


#######################################

build_lab
update_ldapscripts
create_password_file
update_ldap_runtime
add_www-data_to_root-group
restart_apache2

########### gateone
install_tornado_and_python-support
download_and_install_gateone
generate_server_conf
update_gateone_config
###################

###### ldap
install_ldap
configure_slapd
create_organizational_units
create_ldap_log_file
update_ldapexec_file
##########

########### ssh
install_nscd
configure_ldap
modify_nsswitch_conf
edit_common_session
restart_nscd
###############

final_setup
