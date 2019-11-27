#! /bin/bash



#	+>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>+
#	|													|
#	|				Projet LO14 P17						|
#	|	Codé par LALANDE Florimond et DEROUET Lucien	|
#	|													|
#	+>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>+

function init { # Initialisation du mode browse en séparant le header du body et en renvoyant la racine
	# Paramètres: $1: nom de l'archive

	if [ -e /tmp/header ]; then
		rm -f /tmp/header
	fi
	if [ -e /tmp/body ]; then
		rm -f /tmp/body
	fi

	awk 'NR==1{split($0,start,":");next}NR>=start[1]&&NR<start[2]' "${ARCHIVE_PATH}/${1}" > /tmp/header
	awk 'NR==1{split($0,start,":");next}NR>=start[2]' "${ARCHIVE_PATH}/${1}" > /tmp/body

	chmod 666 /tmp/header
	chmod 666 /tmp/body

	root=$(sed -n 's,directory \(.*\)/$,\1,p' /tmp/header) # La racine est la seule ligne du header censée se terminer par un slash
	if [ "$root" == "" ]; then
		echo "1"
		echo "-vsh: Corrupted archive: $1: Root not found"
	else
		echo "0"
		echo "$root"
	fi
}

function cleanup { # Suppression des fichiers temporaires

	rm -f /tmp/header
	rm -f /tmp/body

}

function virtual_cd { # Fonction principale du browse, lit le chemin donné et vérifie qu'il existe répertoire par répertoire
	# Paramètres: $1: nom de l'archive $2: répertoire courant $3 commande $4: chemin

	# Code d'erreur 0 ou 1 pour si le chemin existe ou non
	# VIRTUAL_PATH est le "chemin actuel virtuel", il permet de simuler (par exemple) "ls <path>" en "cd <path>; ls" sans passer par un vrai cd
	
	if [[ $4 =~ ^/ ]]; then
		VIRTUAL_PATH=$root
	else
		VIRTUAL_PATH=$2 #Current directory
	fi
	# On split le chemin à chaque slash, pour obtenir le nom de chaque répertoire succesivement
	while read dir
	do
		if [[ $dir = "" || $dir = . ]]; then # Si le nom du répertoire est vide ou est juste un point, on passe.
			continue
		elif [[ $dir = .. ]]; then # Si le nom vaut deux points, on retire le dernier répertoire
			if [[ $VIRTUAL_PATH != $root ]]; then
				VIRTUAL_PATH=$(sed "s,/$(basename "$VIRTUAL_PATH"),," <<< "$VIRTUAL_PATH")
			fi
		# Sinon, si le nom du répertoire existe dans le répetoire actuel
		elif ! awk -v pat="${VIRTUAL_PATH}/?\$" -v mat="${dir}" '$0~pat{flag=1;next}/^@$/{flag=0}flag&&$1==mat{exit 1}' /tmp/header ; then
			# On vérifie qu'il s'agit bien d'un dossier
			if ! awk -v pat="${VIRTUAL_PATH}/?\$" -v mat="${dir}" '$0~pat{flag=1;next}/^@$/{flag=0}flag&&$1==mat&&$2~/^d/{exit 1}' /tmp/header ; then
				VIRTUAL_PATH="${VIRTUAL_PATH}/${dir}"
			else
				echo "1"
				echo "-vsh: $3: $dir: Not a directory"
				return 1
			fi
		else
			echo "1"
			echo "-vsh: $3: $dir: No such file or directory"
			return 1
		fi
	done <<< "$(sed 's,/,\n,g' <<< $4)"

	return 0
}

function remove { # Fonction récursive pour la suppression des fichiers
	# Paramètres: $1: chemin du répertoire actel $2: nom de l'élément à supprimer

	local dir=$1
	local base=$2
	# Si la base est un dossier:
	if ! awk -v pat="${dir}/?\$" -v mat="${base}" '$0~pat{flag=1;next}/^@$/{flag=0}flag&&$1==mat&&$2~/^d/{exit 1}' "${ARCHIVE_NAME}" ; then
		# On parcourt ce dossier
		awk -v pat="${dir}/${base}/?\$" '$0~pat{flag=1;next}/^@$/{flag=0}flag{print $1}' "${ARCHIVE_NAME}" | while read file
		do
			# On effectue "remove" chacun de ses fichiers et répertoires
			remove "${dir}/${base}" "${file}"
		done
		# Enfin on supprime ce répertoire:
		# On décale le début du header, on supprime sa ligne dans son répertoire, on supprime la ligne "directory <nom>" et le "@" correspondant
		awk -v pat="${dir}" -v mat="${base}" 'NR==1{split($0,start,":");print start[1]":"start[2]-3;next}
										$0~pat"/?$"{flagA=1}flagA&&$1==mat{flagA=0;next}
										$0~pat"/"mat"/?$"{flagB=1;next}
										flagB&&/^@$/{flagB=0;next}
										{print}' "${ARCHIVE_NAME}" > /tmp/archive_rm
										
	# Si c'est un fichier, on décale le début du header, on supprime sa ligne dans son répertoire,
	else
		awk -v pat="${dir}/?\$" -v mat="${base}" 'NR==1{split($0,start,":");print start[1]":"start[2]-1;next}
											$0~pat{flagA=1}
											flagA&&$1==mat{file_start=$4;len=$5;flagA=0;flagB=1;next}
											flagB&&NR>=start[2]{flagB=0;flagC=1}
											flagB&&$4!=""{$4=$4-len}
											!(flagC&&NR>=(start[2]-1+file_start)&&NR<=(start[2]-1+file_start+len-1)){print}' "${ARCHIVE_NAME}" > /tmp/archive_rm
	fi
	mv /tmp/archive_rm "${ARCHIVE_NAME}"
}

#

ARCHIVE_PATH="$HOME/Projet"

if [[ $# -eq 1 ]]; then
	# Si 1 seul paramètre, il s'agit de la fonction d'initialisation
	init $1
elif [[ $# -eq 0 ]]; then
	# Si aucun paramètre, il s'agit de l'appelle de fin de programme
	cleanup
else
	root=$(sed -n 's,directory \(.*\)/$,\1,p' /tmp/header)
	case $3 in
		cd)
			if virtual_cd $1 $2 $3 $4; then
				echo "0"
				echo "$VIRTUAL_PATH"
			fi;;
		ls)
			if virtual_cd $1 $2 $3 $4; then
				echo "0"
				awk -v pat="${VIRTUAL_PATH}/?\$" '$0~pat{flag=1;next}
												/^@$/{flag=0}
												flag{if(match($2, /^d/)) print $1"/"; else if(match($2, /^...x/)) print $1"*"; else print $1}' /tmp/header | paste -sd " " -
			fi;;
		cat)
			if [ "$4" == "" ]; then
				echo "1"
				echo "Usage: cat <file>"
			else
				dir=$(dirname $4)
				file=$(basename $4)
				if virtual_cd $1 $2 $3 "${dir}"; then
					if [[ $file =~ ^\.\.?$ ]]; then
						echo "1"
						echo "-vsh: cat: $file: Is a directory"
					else
						if ! awk -v pat="${VIRTUAL_PATH}/?\$" -v mat="${file}" '$0~pat{flag=1;next}/^@$/{flag=0}flag&&$1==mat{exit 1}' /tmp/header ; then
							if ! awk -v pat="${VIRTUAL_PATH}/?\$" -v mat="${file}" '$0~pat{flag=1;next}/^@$/{flag=0}flag&&$1==mat&&$2~/^-/{exit 1}' /tmp/header ; then
								echo "0"
								awk -v pat="${VIRTUAL_PATH}/?\$" -v mat="${file}" 'NR==1{split($0,start,":")}
																				$0~pat{flag=1}
																				flag&&$1==mat{file_start=$4-1;len=$5-1}
																				flag&&NR>=(start[2]+file_start)&&NR<=(start[2]+file_start+len){print}' "${ARCHIVE_PATH}/${1}"
							else
								echo "1"
								echo "-vsh: cat: $file: Is a directory"
							fi
						else
							echo "1"
							echo "-vsh: cat: $file: No such file or directory"
						fi
					fi
				fi
			fi;;
		rm)
			if [ "$4" == "" ]; then
				echo "1"
				echo "Usage: rm <file>"
			else
				dir=$(dirname $4)
				file=$(basename $4)
				if [[ $file =~ ^\.\.?$ ]]; then
					echo "1"
					echo "-vsh: rm: refusing to remove '.' or '..' directory"
				else
					if virtual_cd $1 $2 $3 "${dir}"; then
						if ! awk -v pat="${VIRTUAL_PATH}/?\$" -v mat="${file}" '$0~pat{flag=1;next}/^@$/{flag=0}flag&&$1==mat{exit 1}' /tmp/header ; then
							ARCHIVE_NAME="${ARCHIVE_PATH}/${1}"
							remove "${VIRTUAL_PATH}" "${file}"
							init $1
						else
							echo "1"
							echo "-vsh: rm: $file: No such file or directory"
						fi
					fi
				fi
			fi;;
	esac

fi

