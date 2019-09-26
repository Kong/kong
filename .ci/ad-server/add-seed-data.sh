#!bin/bash

# If you wish to add more users/groups, modify the script below
set -e

orgUnits=(mathematicians scientists)
for i in "${orgUnits[@]}"
do
    samba-tool ou create "OU=$i"
done

for i in $( seq 1 5 )
do
   samba-tool group add "test-group-$i"
done

samba-tool user create "John Nash" --uid john.nash --surname John --mail-address jnash@beautifulmind.com --userou OU=mathematicians --uid-number 88887 --uid-number 99998 --unix-home home passw2rd1111A$
samba-tool user create euclid --uid euclid --surname euclid --userou OU=mathematicians passw2rd1111A$
samba-tool user create "Nikola Tesla" --uid tesla --surname Tesla --mail-address tesla@ldap.forumsys.com --userou OU=mathematicians --uid-number 88888 --uid-number 99999 --unix-home home passw2rd1111A$
samba-tool user create einstein --surname einstein --uid einstein --userou OU=scientists passw2rd1111A$
samba-tool user create "Andrei Sakharov" --surname Andrei --uid andrei.sakharov --userou OU=scientists --mail-address asakharov@ras.ru --uid-number 88287 --gid-number 99999 --unix-home home passw2rd1111A$

users=(User1 User2 Ophelia Desdemona Katherina Hamlet Othello Petruchio MacBeth)
for i in "${users[@]}"
do
    samba-tool user create $i passw2rd1111A$
done

samba-tool group addmembers test-group-1 User1,User2,MacBeth
samba-tool group addmembers test-group-2 Ophelia,Desdemona,Katherina
samba-tool group addmembers test-group-3 Hamlet,Othello,Petruchio,MacBeth,Desdemona
samba-tool group addmembers test-group-4 euclid,"Nikola Tesla",einstein,"Andrei Sakharov","John Nash"
