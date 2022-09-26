#!/bin/bash

sleep 5

# add nodes
ldapadd -x -H ldapi:/// -D cn=admin,dc=example,dc=org -w admin -f /setup/basedn.ldif

# enable memberOf
ldapadd -Q -Y EXTERNAL -H ldapi:/// -f /setup/memberof.ldif
#ldapmodify -Q -Y EXTERNAL -H ldapi:/// -f /setup/refint1.if
ldapadd -Q -Y EXTERNAL -H ldapi:/// -f /setup/refint2.ldif

# add a user
ldapadd -x -H ldapi:/// -D cn=admin,dc=example,dc=org -w admin -f /setup/add_user.ldif

# add a group
ldapadd -x -H ldapi:/// -D cn=admin,dc=example,dc=org -w admin -f /setup/add_group.ldif

# search user
ldapsearch -x -H ldapi:/// -D cn=admin,dc=example,dc=org -w admin -b ou=people,dc=example,dc=org uid=john memberOf

tail -f /dev/null
