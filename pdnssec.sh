#!/bin/bash



#####################################################################
#                                                                   #
#            pdnssec_rollover.sh                                    #
#                                                                   #          
# version 0.1                                                       #
# 25/05/2013                                                        #
# kevin@kurty.net                                                   #
# Langue :  En                                                      #
#                                                                   #
# Handle dnssec rollover with powerdns and pdnssec utility	    #
# Proof of concept mixing pdnssec and mysql to show how to used     #
# the patched database to do automatic rollover                     #
# Script are intended to be used  as a cron task  	            #
#                                                                   #
#                                                                   #
# The mysql user need to have write to update only one column       #
# All Sql Select are commited on a sqlview                          #
#                                                                   #
# Arguments      						    #
# DOMAIN        : Name of the domain to work on                     #
# ACTION        : Which feature/action to do                        #
#                                                                   #
#                                                                   #
#  valid : pdns-3.1.4 with mysql-backend patched by myself          #
#                                                                   #
# Licensing :                                                       #
# this script is free software; you can redistribute it and/or      #
# modify it under the terms of the GNU General Public License as    #
# published by the Free Software Foundation; either version 3 of    #
# the License, or (at your option) any later version.               #
#                                                                   #
#####################################################################

function usage {

	echo "usage: $0 options

		This script accept the following parameters

		OPTIONS:  ( * means mandatory )
		* -D domain name (FQDN format)  
		* -A Action 
		active_ZSK : create if needed and active a new ZSK, only if no ZSK < 10 days are available.
		all current ZSK older than 10 days are marked to be dropped
		Do nothing if a ZSK is active and has not yet 10 days old.

		destroy_ZSK : select all marked ZSK and destroy them only if on active ZSK remain, else do nothing

		mark_old_ZSK  : Mark all current ZSK that are older than 10 days to be destroy.
		-h show this message
		-d Debug : Print debug message"
}

#Récupération des arguments

#-ve -ip -hostname -pass -disk -mem -memlim -pack -login
while getopts "D:A: dh" options; do
case $options in
D) DOMAIN=$OPTARG;;
A) ACTION=$OPTARG;;
d) DEBUG=1;;
h) usage
exit 1;;
esac
done

PDNSSEC=$( which pdnssec );
if [[ -z $PDNSSEC ]]; then echo "pdnssec not available on your system"; exit 1; fi

NB_PARAM="$#"

#Fonctions qui vérifie le nombre de parametre passee en entree
if [ $NB_PARAM -lt 4 ]; then usage; exit 1; fi


# Note regarding dnssec flags : KZK=257 ZSK=256

NOW=$(  date '+%Y-%m-%d %H:%M:%S' |  date '+%s' )

TAB_ACTION="active_ZSK destroy_ZSK mark_old_ZSK"
LOGS=/tmp/pdnssec

MYSQLu=pdns_ro
MYSQLdb=pdns
MYSQLh=127.0.0.1

echo $DATE > $LOGS

#Redirecting error logs
exec 2>>$LOGS

# Just to print debug informations
function debug {
	msg=$1;
	echo "$msg" >> $LOGS
		if [[ -n "$DEBUG" ]]; then
			echo "$msg"
				fi
}

#As the name said
check_param() {
	debug  "In check_param"
# check if given DOMAIN is fqdn and exist.
		if [[ -z $DOMAIN ]]; then usage;exit 1; fi;
	if [[ -z $ACTION ]]; then usage;exit 1; fi; 
	sql_domain_id
		if [[ -z $MysqlDomainId ]]; then echo "Domain $DOMAIN doesn't exist in pdns database"; exit 1; fi
			ACTION_OK=$( echo $TAB_ACTION |grep -wi $ACTION )
				if [ $? -eq 1 ]; then echo "Action $ACTION doesn't exist, please use $TAB_ACTION"; exit 1; fi
}


#Retrieve the domain_id from the Db
function sql_domain_id {
	MYSQLtbl=domains
		MysqlDomainId=$( mysql -h $MYSQLh -D $MYSQLdb -u $MYSQLu -B -N -e "SELECT id FROM $MYSQLtbl where NAME='$DOMAIN'"; )
		debug "In sql_domain_id - MysqlId :$MysqlDomainId"
}

#Retrieve an array of zsk_active key id
function zsk_active {
	ZSK_active=$( pdnssec show-zone $DOMAIN|grep "Active: 1"|grep ZSK|awk {'print $3'} )
		debug "In zsk_active - ZSK_active : $ZSK_active"
		i=0
		while read line; do
			tab_zsk_active[i++]=$line
				done < <(echo "$ZSK_active" )

				n=${#tab_zsk_active[@]}
	for ((i=0; i < n; i++)); do
		debug "tab_zsk_active[$i]=${tab_zsk_active[$i]}"  
			done

}

#Retrieve an array of ksk_active key id
function ksk_active {
	KSK_active=$( pdnssec show-zone $DOMAIN|grep "Active: 1"|grep KSK|awk {'print $3'} )
		debug "In ksk_active - KSK_active : $KSK_active"
		i=0
		while read line; do
			tab_ksk_active[i++]=$line
				done < <(echo "$KSK_active" )

				n=${#tab_ksk_active[@]}
	for ((i=0; i < n; i++)); do
		debug "In ksk_active : tab_ksk_active[$i]=${tab_ksk_active[$i]}"  
			done
}

#Retrieve an array of zsk_inactive key id
function zsk_inactive {
	tab_zsk_inactive=()
		ZSK_inactive=$( pdnssec show-zone $DOMAIN|grep "Active: 0"|grep ZSK|awk {'print $3'} )
		debug "In zsk_inactive - ZSK_inactive : $ZSK_inactive"
		if [[ -n $ZSK_inactive ]]; then
			i=0
				while read line; do
					tab_zsk_inactive[$i]=$line
						i=$(($i + 1))
						done < <(echo "$ZSK_inactive" )

						n=${#tab_zsk_inactive[@]}
	for ((i=0; i < n; i++)); do
		debug "In zsk_inactive :tab_zsk_inactive[$i]=${tab_zsk_inactive[$i]}"  
			done
		else
			unset ${tab_zsk_inactive}
	fi
}
#Retrieve an array of ksk_inactive key id
function ksk_inactive {
	KSK_inactive=$( pdnssec show-zone $DOMAIN|grep "Active: 0"|grep KSK|awk {'print $3'} )
		debug "In key_search - KSK_inactive : $KSK_inactive"
		i=0
		while read line; do
			tab_ksk_inactive[i++]=$line
				done < <(echo "$KSK_inactive" )

				n=${#tab_ksk_inactive[@]}
	for ((i=0; i < n; i++)); do
		debug "In ksk_inactive : tab_ksk_inactive[$i]=${tab_ksk_inactive[$i]}"  
#printf '%2d) %s\n' "$i" "${tab_ksk_inactive[i]}"
			done
}

#Use pdnssec tools to generate a new zsk key
function generate_new_zsk {
	debug "In generate_new_zsk"
		unset ID_to_active
		ZSK_new=$( pdnssec add-zone-key $DOMAIN zsk rsasha256 )
		if [ $? -ne "0" ]; then
			debug "In generate_new_zsk : generation failed, exit"
				exit 1
				fi
				echo "A new ZSK key has been generated"
}

#Select the first inactive zsk key id
function select_zsk_inactive_key {
	unset Nb_key

		zsk_inactive
		Nb_key=${#tab_zsk_inactive[*]}


	debug "In select_zsk_inactive_key : Nb_key = $Nb_key"
		if [ $Nb_key -ge "1" ]; then
			ID_to_active=${tab_zsk_inactive[0]}
	debug " In select_zsk_inactive_key ID_to_active : $ID_to_active"
		else
			debug "In select_zsk_inactive_key : Generation d'une nouvelle cle � faire"
				fi
}


#Use pdnssec tools to remove a zsk from a zone, refer to mysql database values on key eraseable since 10 days
function destroy_ZSK {
	debug "In destroy_ZSK"
		MYSQLtbl=v_crypto
		SqlQuery=$( mysql -h $MYSQLh -D $MYSQLdb -u $MYSQLu -B -N -e "SELECT key_id FROM $MYSQLtbl where activated < NOW() - INTERVAL 10 DAY and eraseable <> '0000-00-00 00:00:00' and domain_id='$MysqlDomainId'; " )
		if [ $? -ne "0" ]; then echo " Select in Db failed, exit"; exit; fi
			if [[ -n $SqlQuery ]]; then
				debug "In destroy_ZSK : SqlQuery=$SqlQuery"
					i=0
					for keyid in $( echo $SqlQuery ); do
						MYSQLtbl=v_crypto
							if [[ -n $keyid ]]; then
								debug "In destroy_ZSK - keyid : $keyid"
									$( pdnssec remove-zone-key $DOMAIN $keyid )
									if [ $? -ne "0" ]; then
										debug "In destroy_ZSK : destroy failed, exit"
											exit 1
											fi
											echo " Key $keyid has been destroyed with pdnssec command "
											i=$(($i + 1))
											fi
											done;
									else echo "No key to destroy, try action mark_old_key and try again later"; exit 0; fi
}

# Mark all keys older than 10 days to be deleted
function mark_old_ZSK {
	debug "In mark_old_ZSK"
		MYSQLtbl=v_crypto
		zsk_active
		Nb_key=${#tab_zsk_active[@]}
	for ((i=0; i < Nb_key; i++)); do
		SqlQuery=$(  mysql -h $MYSQLh -D $MYSQLdb -u $MYSQLu -B -N -e  "SELECT key_id from $MYSQLtbl where key_id='${tab_zsk_active[$i]}' and eraseable='0000-00-00 00:00:00' and activated < NOW() - INTERVAL 10 DAY and domain_id='$MysqlDomainId'; ")
			if [[ -z $SqlQuery ]]; then echo "No key to mark as old"; else 
				MYSQLtbl=cryptotime
#SqlQuery=$( mysql -h $MYSQLh -D $MYSQLdb -u $MYSQLu -B -N -e "UPDATE $MYSQLtbl set eraseable=NOW() where key_id='${tab_zsk_active[$i]}' and eraseable='0000-00-00 00:00:00' and activated < NOW() - INTERVAL 10 DAY and domain_id='$MysqlDomainId'; " )
					SqlQuery=$( mysql -h $MYSQLh -D $MYSQLdb -u $MYSQLu -B -N -e "UPDATE $MYSQLtbl set eraseable=NOW() where key_id='${tab_zsk_active[$i]}' and eraseable='0000-00-00 00:00:00' and activated < NOW() - INTERVAL 10 DAY; " )
					if [ $? -ne "0" ]; then debug "In mark_old_ZSK : Update in Db failed, go to next step"; fi
						fi
							done
							debug "Out mark_old_ZSK"
}


#Return the number of active zsk key
function check_nb_active_zsk {
	MYSQLtbl=v_crypto
		MysqlZSKid=$( mysql -h $MYSQLh -D $MYSQLdb -u $MYSQLu -B -N -e "SELECT key_id FROM $MYSQLtbl where domain_id='$MysqlDomainId' and active=1 and flags='256'"; )
		debug "In check_nb_active_zsk : MysqlZSKid=$MysqlZSKid"
		i=0
		for keyid in $( echo $MysqlZSKid ); do
			MysqlZSKidOk[$i]=$( mysql -h $MYSQLh -D $MYSQLdb -u $MYSQLu -B -N -e "SELECT key_id FROM $MYSQLtbl where key_id=$keyid and activated BETWEEN NOW() - INTERVAL 10 DAY AND NOW()"; )
				if [[ -n ${MysqlZSKidOk["$i"]} ]]; then
					debug "In check_nb_active_zsk - MysqlZSKidOk[$i] : ${MysqlZSKidOk["$i"]};"
						i=$(($i + 1))
						fi
						done;
	return $i
		debug "In check_nb_active_zsk : i=$i"
}

#Active a existing or new generated zsk key
function active_ZSK {
#On verifie que la creation d'une cle soit utile, pas de cle creer a moins de 10j
	check_nb_active_zsk
		if [[ $? -eq 1 ]]; then echo "At least one key not 10 days older, try again in few days"; exit 0; fi
#on marque la cle active comme a detruire dans 10j
			mark_old_ZSK
#On trouve une nouvelle cle a activer
				select_zsk_inactive_key
				if [[ -z $ID_to_active ]]; then 
					debug "In active_ZSK :  No key to activate !" 
						generate_new_zsk
						select_zsk_inactive_key
						if [[ -z $ID_to_active ]]; then
							debug "Probleme de creation de cle, je sort"
								exit 1
								fi
								fi
								OPE=$( pdnssec activate-zone-key $DOMAIN $ID_to_active )
								if [ $? -ne "0" ]
									then
										debug "Activation sur $DOMAIN clé ZSK ID $ID_to_active failed"
										exit 0
										fi
										echo "Activation sur $DOMAIN clé ZSK ID $ID_to_active"
}


#Main

check_param

#Really bad way, but fast:
if [ $ACTION = "active_ZSK" ]; then active_ZSK; exit 0; fi
if [ $ACTION = "destroy_ZSK" ]; then destroy_ZSK; exit 0; fi
if [ $ACTION = "mark_old_ZSK" ]; then mark_old_ZSK; exit 0; fi
exit 1

