#!/bin/bash



#	+>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>+
#	|													|
#	|				Projet LO14 P17						|
#	|	Codé par LALANDE Florimond et DEROUET Lucien	|
#	|													|
#	+>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>+


#	>>>>>>>>      IP serveur 176.179.34.51      <<<<<<<<<<<<<<<<<<


#chaner id port
#nettoyer

# Informations de connexion au serveur
ID=""
PORT=""
IP=""

ARCHIVE_PATH="~/Projet"
SERVER_SCRIPT="browse_server_v7.sh"


function test_nb_parametre {

	if [[ ! $1 -eq $2 ]]; then
		echo "Too many arguments"
		exit
	fi
}

function test_port { # Test si la saisie correspond à un port

	if [[ $(echo $1 | sed -e 's/[0-9]//g' | wc -c ) -eq 1 ]]; then
		if [[ $1 -le 65535 && $1 -ge 0 ]]; then
			PORT=$1
			return 0
		else
			echo "Port should be a number between 0 and 65 535"
			exit
		fi
	else
		echo " Bad port"
		exit
	fi
}

function test_saisie_IP {  # Test si la saisie correspond à une adresse IP

	if [[ !	$( echo $1 | grep -E ^\([0-9]\{1,3\}\.\)\{3\}[0-9]\{1,3\}$ | wc -w ) -eq 1 ]]; then
		echo "$1 is not a valid IP adress"
		exit
		else
			IP=$1
			test_port $2  # Si oui, test du port
			if [[ $? -eq 0 ]]; then
				return 0
			fi
	fi
}

function test_ssh_id {   # Test du mot de passe et de l'identifiant saisi

	ssh -q -o ConnectTimeout=10 -p ${2} ${ID}@${1} 'exit'

	if [[ ! $? -eq 0 ]]; then
		echo "Connection failed: Timeout"
		exit
	else
		create_keys $1 $2  # Si la connexion est valide, création de clés SSH pour ne plus saisir de mot de passe
	fi
}

function create_keys {  # Création d'une paire de clés RSA

	ssh-keygen -q -t rsa -f ~/.ssh/projet_lo14
	echo "Key generated, enter password (last time)"
	ssh -i ~/.ssh/projet_lo14 -q -p ${2} ${ID}@${1} 'cat >> ~/.ssh/authorized_keys ' < ~/.ssh/projet_lo14.pub # Copie de la clé publique sur le serveur 

}

function check_keys {  # Test l'existence d'une paire de clés RSA

	echo -n "Enter server login : "
	read ID

	if [[ ! -e ~/.ssh/projet_lo14 ]]; then  # S'il n'y a pas de clés, test du mdp/Id
		test_ssh_id $1 $2
	else
		ssh -i ~/.ssh/projet_lo14 -o ConnectTimeout=10 -p $2 ${ID}@${1} 'exit' # Si des clés existent, test de la connexion
		if [[ $? -eq 0 ]]; then
			return 0
		else
			echo "Bad connection information"
			rm ~/.ssh/projet_lo14*
			exit
		fi
	fi
}

function remove_keys { # Fonction de supression des clés

	ssh -i ~/.ssh/projet_lo14 -q -p ${2} ${ID}@${1} "cat ~/.ssh/authorized_keys | grep ${USER}@${HOSTNAME} > ~/.ssh/authorized_keys " 
	# Suppression sur serveur de la clé autorisée 
	rm ~/.ssh/projet_lo14* 
	# Suppression de la paire de clés
	echo "Keys have been deleted."
}

function list {
	
	echo "Archives list from ${ID}'s directory :"
	ssh -i ~/.ssh/projet_lo14 -q -p ${2} ${ID}@${1} "ls ${ARCHIVE_PATH} | grep \.arch$"  # Recherche et affichage des fichiers en .arch
}

function test_nom_archive { # Test de l'existence de l'archive demandée sur le serveur

	retour=$( ssh -i ~/.ssh/projet_lo14 -q -p ${2} ${ID}@${1} "if [ ! -r ${ARCHIVE_PATH}/${3} ]; then echo "1"; fi")
	if [[ ${retour} -eq 1 ]]; then
		echo "Archive ${3} not found"
		exit
	else
		return 0
	fi
}

function get_permission { # Fonction récupérer les permissions d'un fihcier en octal à partir de sa valeur en caractères
	# Paramètres: $1: le string représentant les permissions ("drwxrwxrwx")

	local tab_permission=(0 0 0)
	local count=0
	while read char
	do
		idx=$((count / 3))
		tab_permission[idx]=$((${tab_permission[idx]} + $char * 2 ** ( ( 8 - count ) % 3 ) ))
		((count++))
	done  <<< "$(sed -e 's/^.//g' -e 's/-/0/g' -e 's/[^0]/1/g' -e 's/\(.\)/\1\n/g' <<< $1)"
	tr -d ' ' <<< ${tab_permission[*]}
}

function extract { # Fonction d'exctration d'une archive dans le répertoire courant
	# Paramètres: $1: nom de l'archive
	
	# On commence par récupérer le header et le body via SSH
	header_start=$(	ssh -i ~/.ssh/projet_lo14 -q -p ${PORT} ${ID}@${IP} "head -n1 ${ARCHIVE_PATH}/${1} | cut -d':' -f1")
	body_start=$(($(ssh -i ~/.ssh/projet_lo14 -q -p ${PORT} ${ID}@${IP} "head -n1 "${ARCHIVE_PATH}/${1}" |  cut -d':' -f2") - 1))
	
	ssh -i ~/.ssh/projet_lo14 -q -p ${PORT} ${ID}@${IP} "cat ${ARCHIVE_PATH}/${1}" | sed -n ''"$header_start"','"$body_start"'p' > /tmp/header
	ssh -i ~/.ssh/projet_lo14 -q -p ${PORT} ${ID}@${IP} "cat ${ARCHIVE_PATH}/${1}" | sed '1,'"$body_start"'d' > /tmp/body
	
	root=$(sed -n 's,directory \(.*\)/$,\1,p' /tmp/header)
	
	while grep -q '^@$' /tmp/header
	do
		current_dir="."
		
		sed -e '/^@$/q' /tmp/header | head -n-1 | while read line
		do
			set $line
			if [[ $line =~ ^directory ]];then
				current_dir="."$(sed -e 's,'"$root"',,' -e 's,/$,,' <<< "$2")
			else
				permission=$(get_permission $2)
				filename=${current_dir}"/"${1}
				if [[ $2 =~ ^d ]];then
					mkdir -p $filename
				elif [ $3 -eq 0 ]; then
					touch $filename  #mettre dans le repertoire
				else
					file_end=$(($4 + $5 - 1))
					sed -n ''"$4"','"$file_end"'p' /tmp/body > $filename
				fi
				chmod $permission $filename
			fi
		done
		sed -i '1,/^@$/ d' /tmp/header
	done
	rm -f /tmp/header
  	rm -f /tmp/body
}

function walk { # Fonction récursive pour parcourir l'arborescence des dossiers à archiver
	# Paramètres: $1: chemin du répertoire $2: slash optionnel

	echo "directory $(sed 's,'"$(pwd)"/',,' <<< "$1$2")" >> /tmp/header

	# On parcourt une première fois tous les fichiers du répertoire
	ls "$1" | while read file
	do
		if [[ $(stat -c "%A" "$1/$file") =~ [d-][rwx-]{9} ]];then
			# Si c'est un dossier, dans un premier temps on ajoute juste sa ligne
			if [ -d "$1/$file" ];then
				echo "$file $(stat -c "%A %s" "$1/$file")" >> /tmp/header
			elif [ -r "$1/$file" ];then
				# Si c'est un fichier, on récupère sa ligne de départ dans le body et sa longeur
				# On ajoute sa ligne dans le header et son contenu dans le body
				start_in_body=$(($(wc -l < /tmp/body) + 1))
				file_lenght=$(wc -l < "$1/$file")
				echo "$file $(stat -c "%A %s" "$1/$file") $start_in_body $file_lenght" >> /tmp/header
				cat "$1/$file" >> /tmp/body
			else
				echo "Warn: $file"": Read permission denied, file ignored"
			fi
		else
			echo "Warn: $file"": Not a regular file or directory, file ignored"
		fi
	done

	echo "@" >> /tmp/header

	# On parcourt une seconde fois les fichiers du répertoire pour effectuer "walk" sur les dossiers
	# On ne l'a pas fait dans le premier parcourt pour respecter l'ordre de l'archive.
	ls "$1" | while read file
	do
		if [[ $(stat -c "%A" "$1/$file") =~ d[rwx-]{9} ]];then
			walk "$1/$file"
		fi
	done
}

function archive { # Fonction de création d'archive, elle lance le parcours de l'arborescence ("walk") et crée le fichier .rch
	# Paramètres: $1: nom de l'archive

	if [ -d "$1" ]; then
		touch /tmp/header
		touch /tmp/body
		start_pwd=$(pwd)
		cd "$1"



		root_name=$(basename "$(pwd)")
		cd ..

		walk "$(pwd)/${root_name}" "/"

		cd "$start_pwd"
		body_start=$(($(wc -l < /tmp/header) + 3))
		echo "3:$body_start" > "/tmp/${root_name}.arch"
		echo "" >> "/tmp/${root_name}.arch"
		cat /tmp/header >> "/tmp/${root_name}.arch"
		cat /tmp/body >> "/tmp/${root_name}.arch"

		scp -P ${PORT} /tmp/${root_name}.arch ${ID}@${IP}:${ARCHIVE_PATH}/
		rm /tmp/${root_name}.arch
		rm /tmp/header
  		rm /tmp/body
	else 
		echo "archive: $1: Not a directory"
	fi
}

#_______________Fonction browse________________

function browse {
	# Paramètres: $1: nom de l'archive

	trap 'ssh -i ~/.ssh/projet_lo14 -q -p ${PORT} ${ID}@${IP} "bash" < ${SERVER_SCRIPT}' EXIT

	if [[ ! -r "${SERVER_SCRIPT}" ]]; then
		echo "-vsh: Server-side script \"${SERVER_SCRIPT}\" not found"
		exit
	else

		SERVER_RETURN=$(ssh -i ~/.ssh/projet_lo14 -q -p ${PORT} ${ID}@${IP} "bash -s ${1}" < ${SERVER_SCRIPT})	#initialisation	
		if [[ $(echo ${SERVER_RETURN} | cut -c1) -eq 0 ]]; then
			root=$(echo ${SERVER_RETURN} | cut -c3-)
		else
			echo ${SERVER_RETURN} | cut -c3-
			exit
		fi

		CURRENT_PATH=${root}
		while [[ 1 ]]; do

			echo -n "vsh>:$(sed "s,$root/*,/," <<< ${CURRENT_PATH})$ "

			read cmd args

			if [[ $(echo ${args} | awk '{print NF}') -gt 1 ]]; then
				echo "-vsh: ${cmd}: ${args}: Too many arguments"
			elif [ ! "$cmd" == "" ]; then
				case ${cmd} in
					cd)
						SERVER_RETURN=$(ssh -i ~/.ssh/projet_lo14 -q -p ${PORT} ${ID}@${IP} "bash -s ${1} ${CURRENT_PATH} ${cmd} \"${args}\"" < ${SERVER_SCRIPT})
						if [[ $(echo ${SERVER_RETURN} | cut -c1) -eq 0 ]]; then
							CURRENT_PATH=$(sed -n '2p' <<< "$SERVER_RETURN")
						else
							sed '1d' <<< "$SERVER_RETURN"
						fi;;
					ls)
						SERVER_RETURN=$(ssh -i ~/.ssh/projet_lo14 -q -p ${PORT} ${ID}@${IP} "bash -s ${1} ${CURRENT_PATH} ${cmd} \"${args}\"" < ${SERVER_SCRIPT})
						sed '1d' <<< "$SERVER_RETURN";;
					cat)
    					SERVER_RETURN=$(ssh -i ~/.ssh/projet_lo14 -q -p ${PORT} ${ID}@${IP} "bash -s ${1} ${CURRENT_PATH} ${cmd} \"${args}\"" < ${SERVER_SCRIPT})
    					sed '1d' <<< "$SERVER_RETURN";;
					rm)
						SERVER_RETURN=$(ssh -i ~/.ssh/projet_lo14 -q -p ${PORT} ${ID}@${IP} "bash -s ${1} ${CURRENT_PATH} ${cmd} \"${args}\"" < ${SERVER_SCRIPT})
						sed '1d' <<< "$SERVER_RETURN";;
					pwd)

						cat <<< "$SERVER_RETURN"

						echo $(sed "s,$root/*,/," <<< ${CURRENT_PATH});;
					exit)
						break;;
					*)
						echo "-vsh: $cmd: Command not found"
				esac
			fi
		done
	fi
}


#_____________Menu___________________________

case $1 in 		# $1: mode choisi  $2: IP, $3: port, $4: nom archive 
	-list)
		test_nb_parametre 3 $#
		test_saisie_IP $2 $3
		check_keys $2 $3
		list $2 $3;;
	-browse) 
		test_nb_parametre 4 $#
		test_saisie_IP $2 $3 
		check_keys $2 $3
		test_nom_archive $2 $3 $4
		browse $4;;
	-extract)
		test_nb_parametre 4 $#
		test_saisie_IP $2 $3 
		check_keys $2 $3
		test_nom_archive $2 $3 $4
		extract $4;;
	-remove_keys)
		test_nb_parametre 3 $#
		test_saisie_IP $2 $3
		check_keys $2 $3
		remove_keys $2 $3 ;;
	-archive)
		test_nb_parametre 4 $#
		test_saisie_IP $2 $3 
		check_keys $2 $3
		archive $4;;
	*)
		echo "${1}: Invalid mode"; exit;;
esac	

