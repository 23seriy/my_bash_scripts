#!/bin/bash
clear

usage() { echo "Usage: $0 [-e <qa|staging|production>] [-p <project name>] [-b <branch name>] [-t <tag>] "
log "There are 3 ways to use that deployment script:\n"
log "1. When deploy to QA, do not send <tag>.\n That will ask you to insert a new tag, which will be created in git"
log "2. When deploy to QA, if you do send a <tag>, it will ask if you would like to override the QA with that tag"
log "3. When deploy to Staging / Production, you must send a <tag>, the deployment will use that tag to deploy"
1>&2; exit 1; }

while getopts ":e:p:b:t:" opt; do
	case $opt in
		e)
			env=$OPTARG
			;;
		p)
			proj=$OPTARG
			;;
		b)
			branch=$OPTARG
			;;
		t)
			tag=$OPTARG
			;;
		\?)
			echo "ERROR: Invalid option: -$OPTARG" >&2
			exit 1
			;;
		:)
			echo "ERROR: Option -$OPTARG requires an argument." >&2
			exit 1
			;;
		esac
done
shift $(( OPTIND - 1 ));

set_params() {
	# Check parameres
	SCRIPT="`readlink -e $0`"
	SCRIPTPATH="`dirname $SCRIPT`"
	log_file="${SCRIPTPATH}/logs/deploy_${proj}_${env}_`date +'%F_%T'`.log"

	project_base_path="${SCRIPTPATH}/projects/${proj}"
	project_code_base_path="/var/lib/natural-intelligence/deploy/${proj}/code"
	code_server_list_file="${project_base_path}/${proj}.${env}.code_server_list"
	db_server_file="${project_base_path}/${proj}.${env}.db_server"
	project_params_file="${project_base_path}/${proj}.params"
	project_post_deploy_file="${project_base_path}/${proj}.post_deploy"
	project_global_post_deploy_file="${project_base_path}/${proj}.global_post_deploy"
	project_pre_deploy_file="${project_base_path}/${proj}.pre_deploy"
	project_global_pre_deploy_file="${project_base_path}/${proj}.global_pre_deploy"
	project_db_commands_file="${project_base_path}/${proj}.db_commnads"
	project_global_rollback_file="${project_base_path}/${proj}.global_rollback"
	version_file="${project_code_base_path}/version"
}

log() {
	local text="$1"
	echo -e "$1" | tee -a "${log_file}"
}

send_mail() {
	subject="$1"
	messsage="$2"
	#mail_to="nadav.bilu@naturalint.com"
	mail_to="build@naturalint.com"
	echo -e "${message}" | mail -s "${subject}" -a "${log_file}" "${mail_to}"
}

checks() {

	# Check mandatory parameters
	if [ -z "${env}" ] || [ -z "${proj}" ] || [ -z "${branch}" ]; then
		usage
	fi

	if [ ${env} != "qa" ] && [ ${env} != "staging" ] && [ ${env} != "production" ]; then
		log "ERROR: Environment must be: qa / staging / production\n\nExiting script\n"
                usage
	fi

	if [ ${env} != "qa" ] && [ -z "${tag}" ]; then
		log "ERROR: When deploying to production or staging, you must send an existing tag\n\nExiting script\n"
		usage
	fi

	# Check existance of parameters file
	if [ ! -f "${project_params_file}" ]; then
		log "ERROR: Project parameters file: ${project_params_file} does not exists\nExiting script"
		exit 1
	else
		source "${project_params_file}"
		echo ${project_code_destination_path}
	fi

	# Check git url parameter exists
	if [ -z "${git_url}" ]; then
		log "ERROR: No git URL\nShould be placed in ${project_params_file} file\nExiting script"
		exit 1
	fi

	# Check project code destination path exists
        if [ -z "${project_code_destination_path}" ]; then
                log "ERROR: No code destination \nShould be placed in ${project_params_file} file\nExiting script"
                exit 1
        fi

	# Check existance of code server list file
	if [ ! -f "${code_server_list_file}" ]; then
		log "ERROR: ${code_server_list_file} does not exists\nExiting script"
		exit 1
	fi

	# Check existance of db server file
	if [ ! -f "${db_server_file}" ]; then
		log "ERROR: ${db_server_file} does not exists\nExiting script"
		exit 1
	fi
}

get_code_server_list() {
	index=0
	while read line
	do
		code_server_list[$index]=${line}
		index=$(($index+1))
	done < ${code_server_list_file}

	if [ -z "${code_server_list}" ]; then
		log "ERROR: Code server list is empty.\nShould be placed in ${code_server_list_file}"
		exit 1
	fi
}

get_db_server () {
	read -r db_server < ${db_server_file}
	if [ -z "${db_server}" ]; then
		log "ERROR: Database server name is empty.\nShould be placed in ${db_server_file}"
		exit 1
	fi
}

get_version_from_code_servers() {
	IFS=$'\n' read -d '' -r -a ver_data <<< "`curl -s deployment@${code_server}/deploy/version`"
	unset IFS
	version_tag=${ver_data[1]}
	version_date=${ver_data[0]}
}

init() {
	log "++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
	log "+ Welcome to the deployment script"
	log "+ The deployment uses the following parameters:"
	log "+ Project: ${proj}"
	log "+ Environment: ${env}"
	log "+ Branch: ${branch}"
	log "+ Tag: ${tag}"
	log "+ Code severs: ${code_server_list[*]}"
	log "+ Database server: ${db_server}"
	log "+ git url: ${git_url}"
	log "++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
	for code_server in "${code_server_list[@]}"
 	do
		get_version_from_code_servers
		pre_version_tag=${version_tag}
		pre_version_date=${version_date}
	done
}

global_pre_deploy() {
	# Run one time script before pre-deploy
        log "--------------------------------"
        log "Running global pre deploy script"
        log "--------------------------------"
        if [ -f "${project_global_pre_deploy_file}" ] && [ -s "${project_global_pre_deploy_file}" ]; then
		code_global_pre_status=0
		global_pre_deploy_ret=`source ${project_global_pre_deploy_file} ${env} ${project_base_path}`
		if [ $? -ne 0 ]; then
                        log "ERROR: Global pre-deploy failed\n\nExiting script"
                        exit 1
		else
			log "Global pre deploy script ran successfully"
                fi
        else
                log "Global Pre-deploy file: ${project_global_pre_deploy_file} does not exists or empty.\nNot runnign any global Pre-deploy commands"
        fi
}

pre_deploy() {
	# pre-deploy
	# run pre-deploy commands (stop services, send mail, etc)

	log "--------------------------"
	log "Running pre deploy script"
	log "--------------------------"
	# Check existance and not empty of pre deploy sctipy
	if [ -f "${project_pre_deploy_file}" ] && [ -s "${project_pre_deploy_file}" ]; then
		code_pre_status=0
		failed_code_pre_servers=()

		for code_server in "${code_server_list[@]}"
		do
			ssh deployment@${code_server} 'bash -s' < ${project_pre_deploy_file}
			if [ $? -ne 0 ]; then
				log "ERROR: pre deploy on server: ${code_server} failed\n"
				code_pre_status=1
				failed_code_pre_servers+=("${code_server}")
			else
				log "Pre deploy on server: ${code_server} finished successfully\n"
			fi

		done

		#Check pre deploy status on all servers
		if [ ${code_pre_status} -ne 0 ]; then
			log "ERROR: not all code servers ran pre deploy script\nThe ones failed are: ${failed_code_pre_servers[*]}\nExiting script"
			exit 1
		else
			log "All code server ran pre deploy script successfully"
			log "Deploy script finished successfully"
			log "Finish: `date`"
			log "+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
		fi
	else
		log "Pre-deploy file: ${project_pre_deploy_file} does not exists or empty.\nNot runnign any Pre-deploy commands"
	fi
}

git_pull() {
	# deploy
	# git pull to deploy server
	# Check if branch exists on deploy server
	log "-----------------------------------------"
	log "Pulling code from git url: ${git_url}"
	log "-----------------------------------------"
	log "Start: `date`"
	git_pull_status=0
	if [ -d "${project_code_base_path}" ]; then
		log "Branch already exists, running git pull ${branch}"
		cd "${project_code_base_path}"
		git reset --hard origin/${branch}
		git pull -q origin "${branch}"
		if [ $? -ne 0 ]; then
			log "ERROR: could not pull code from git, branch: ${branch}\n\nExiting script"
			exit 1
		fi
	else
		log "Repository does not exists on deploy server.\nCreating one by git clone to ${project_code_base_path}"
		git clone -q -b "${branch}" "${git_url}" "${project_code_base_path}"
		if [ $? -ne 0 ]; then
			log "ERROR: could not clone code from git, branch: ${branch}\n\nExiting script"
			exit 1
		fi
		cd "${project_code_base_path}"
	fi


	# If QA, use project and branch and CREATE tag in git
	# If Staging / Production use the created tag to pull
	latest_git_version=`git describe --tags \`git rev-list --tags --max-count=1\``
	if [ "${env}" == "qa" ] && [ -z "${tag}" ]; then
		log "Environment is QA and no tag is given, so creating a new tag"
		log "Latest tag in git is: ${latest_git_version}"
		while [ -z "${tag}" ]
		do
			echo -n "Enter new tag: "
			read tag
		done
		# check if tag exists before creating
		cd "${project_code_base_path}"
		tag_exists=`git tag -l | grep "${tag}"`
		if [ "${tag_exists}" == "${tag}" ]; then
			log "Tag: ${tag} already exists in git"
			log "Do you want to continue yn \?"
			read answer
			if [ "${answer}" != "y" ]; then
				log "Exiting without any changes"
				exit 0
			fi
		fi
		echo "`date`" > "${version_file}"
		echo "${tag}" >> "${version_file}"
		git add "${version_file}"
		git commit -m"`date` ${tag}"

		git tag -a "${tag}" -m"Created tag ${tag} from deployment script"
		git push origin "${tag}"
		if [ $? -ne 0 ]; then
			log "ERROR: could not push code to git, tag: ${tag}\n\nExiting script"
			exit 1
		fi
	# If env is QA and tag is given, overide QA with tag
	elif  [ "${env}" == "qa" ] && [ -n "${tag}" ]; then
		log "Environment is QA and tag is given, so using that tag"
		log "You are about to override the current release in QA with ${tag}"
		log "Do you want to continue yn \?"
		read answer
		if [ "${answer}" != "y" ]; then
			log "Exiting without any changes"
			exit 0
		fi
		cd "${project_code_base_path}"
		git checkout -q tags/"${tag}"
		if [ $? -ne 0 ]; then
			log "ERROR: could not checkout code from git, tag: ${tag}\n\nExiting script"
			exit 1
		fi
	elif [ "${env}" != "qa" ] && [ -n "${tag}" ]; then
		# if env is any and tag is given, deploy the tag
		log "Environment is ${env}, so checking out tag ${tag}"
		git checkout -q tags/"${tag}"
		if [ $? -ne 0 ]; then
			log "ERROR: could not checkout code from git, tag: ${tag}\n\nExiting script"
			exit 1
		fi

	else
		log "ERROR: not pulling from git\nExiting script"
		exit 1

	fi
	log "End: `date`"
	log "-----------------------------------------"
}

rsync_code() {
	log "-----------------------"
	log "Compressing project into zip"
	log "-----------------------"
	cd ${project_code_base_path}/
	tar -zcvf /tmp/${tag}.tar.gz . --exclude=.git

	# rsync from deploy server to all servers need the code to a new $tag folder in releases folder
	# get confirmation all rsync to all server end successfully
	log "------------------------"
	log "Code sync to code server"
	log "------------------------"
	log "Start: `date`\n"

	failed_code_servers=()
	code_deploy_status=0
	for code_server in "${code_server_list[@]}"
	do
		# Copy code, exclude the git folder to the code server into $tag folder.
		log "Start sync code to ${code_server}\n"
		#rsync -arvvq --delete --exclude .git/ "${project_code_base_path}/" "deployment@${code_server}:${project_code_destination_path}/releases/${tag}"
		ssh deployment@${code_server} "mkdir -p ${project_code_destination_path}/releases/${tag}"
		scp /tmp/${tag}.tar.gz deployment@${code_server}:${project_code_destination_path}/releases/${tag}/${tag}.tar.gz
		if [ $? -ne 0 ]; then
			log "ERROR: sync code to server: ${code_server} failed\n"
			code_deploy_status=1
			failed_code_servers+=("${code_server}")
		else
			log "Sync code to server: ${code_server} finished successfully\n"
			log "Now decomprssing code into destination directory"
			ssh deployment@${code_server} "cd ${project_code_destination_path}/releases/${tag}/ && tar -zxvf ${tag}.tar.gz && rm ${tag}.tar.gz"
		fi
	done

	if [ ${code_deploy_status} -ne 0 ]; then
		log "ERROR: Not all servers synced the code\nThe ones failed: ${failed_code_servers[*]}\nExiting script"
		exit 1
	else
		rm ${tag}.tar.gz
		log "All servers successfully code synced"
	fi

	log "End: `date`\n"
	log "------------------------"
}

db_deploy() {
	# DB
	log "------------------------"
	log "run the DB deploy script"
	log "------------------------"
	log "Start: `date`\n"
	# Check existance and not empty of db commands file
	db_deploy_status=0
	if [ -f "${project_db_commands_file}" ] && [ -s "${project_db_commands_file}" ]; then
		ssh deployment@${db_server} 'bash -s' < ${project_db_commands_file}
		if [ $? -ne 0 ]; then
			log "ERROR: db commands on server: ${db_server} failed\n"
			db_deploy_status=1
		else
			log "DB commnads on server: ${code_server} finished successfully\n"
		fi
	else
		log "DB commands file: ${db_commands_file} does not exists or empty.\nNot runnign any DB commands"
	fi


	# Check DB deploy status
	if [ ${db_deploy_status} -ne 0 ]; then
		log "ERROR: DB deployment to server: ${db_server} failed\nExiting script"
		exit 1
	else
		log "DB deployment to server: ${db_server} finished successfully\n"
	fi
	log "End: `date`\n"
	log "------------------------"
}

post_deploy() {
	# post-deploy
	# run and post install scripts

	# Check existance and not empty of post deploy sctipy
	if [ -f "${project_post_deploy_file}" ] && [ -s "${project_post_deploy_file}" ]; then
		code_post_status=0
		failed_code_post_servers=()

		log "--------------------------"
		log "Running post deploy script"
		log "--------------------------"
		for code_server in "${code_server_list[@]}"
		do
			ssh deployment@${code_server} ARG1="${tag}" ARG2=${global_pre_deploy_ret} 'bash -s' < ${project_post_deploy_file}
			if [ $? -ne 0 ]; then
				log "ERROR: post deploy on server: ${code_server} failed\n"
				code_post_status=1
				failed_code_post_servers+=("${code_server}")
			else
				log "Post deploy on server: ${code_server} finished successfully\n"
			fi

		done

		#Check post deploy status on all servers
		if [ ${code_post_status} -ne 0 ]; then
			log "ERROR: not all code servers ran post deploy script\nThe ones failed are: ${failed_code_post_servers[*]}\nExiting Script"
			exit 1
		else
			log "All code server ran post deploy script successfully"
		fi
	else
                log "Post-deploy file: ${project_post_deploy_file} does not exists or empty.\nNot runnign any Post-deploy commands"
	fi
}

global_post_deploy() {
	# Run one time script after post deploy
        log "---------------------------------"
        log "Running global post deploy script"
        log "---------------------------------"
        if [ -f "${project_global_post_deploy_file}" ] && [ -s "${project_global_post_deploy_file}" ]; then
		code_global_post_status=0
		sh ${project_global_post_deploy_file} ${env} ${project_base_path} ${global_pre_deploy_ret} ${code_server_list[0]} ${tag}
		if [ $? -ne 0 ]; then
                        log "ERROR: Global post-deploy failed\n\nExiting script"
                        exit 1
		else
			log "Global post deploy script ran successfully"
                fi
        else
                log "Global post-deploy file: ${project_global_post_deploy_file} does not exists or empty.\nNot runnign any global post-deploy commands"
        fi
}

change_current_link() {
	# If DB script and rsync ended successfully, switch the "current" link to the new tag.
	log "-----------------------------------------------------"
	log "Changing current link to new code in all code servers"
	log "-----------------------------------------------------"

	# Only if post deploy status on all servers is OK, continue to post deploy
	if [ ${code_post_status} -eq 0 ]; then
		code_change_link_status=0
		failed_code_change_servers=()
		for code_server in "${code_server_list[@]}"
		do
			ssh deployment@${code_server} "
				cd ${project_code_destination_path}
				rm -f current
				ln -s releases/${tag} current
			"
			if [ $? -ne 0 ]; then
				log "ERROR: change code link on server: ${code_server} failed\n"
				code_change_link_status=1
				failed_code_change_servers+=("${code_server}")
			else
				log "Change code link on server: ${code_server} finished successfully\n"
			fi
		done
	fi

	# Check code change link status
	if [ ${code_change_link_status} -ne 0 ]; then
		log "ERROR: not all code servers changed the link\nThe ones failed are: ${failed_code_change_servers[*]}\nExiting script"
		exit 1
	else
		log "All code servers changed link to ${tag} successfully"
	fi
}

rollback() {

	log "\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!"
	log "\!\!\!\! ROLLING BACK TO PREVIOUS VERSION \!\!\!\!"
	log "\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\n\n"
	log "-----------------------------------------------------------------------------"
	log "Changing current link to PREVIOUS version: ${pre_version_tag} in all code servers"
	log "-----------------------------------------------------------------------------"

	rollback_status=0
        if [ -f "${project_global_rollback_file}" ] && [ -s "${project_global_rollback_file}" ]; then
		sh ${project_global_rollback_file} ${env} ${project_base_path} ${global_pre_deploy_ret}
		if [ $? -ne 0 ]; then
                        log "ERROR: Global rollback failed\n\nExiting script"
                        exit 1
		else
			log "Global rollback script ran successfully"
                fi
        else
                log "Global rollback file: ${project_global_rollback_file} does not exists or empty.\nNot runnign any global post-deploy commands"
        fi
	#changing $tag to previous version for switch back the current link
	tag=${pre_version_tag}
	change_current_link
	rollback_status=${code_change_link_status}
	# Check status
	if [ ${rollback_status} -ne 0 ]; then
		log "ERROR: not all code servers changed the link\nThe ones failed are: ${failed_code_change_servers[*]}\nExiting script"
		exit 1
	else
		log "All code servers changed link back to ${pre_version_tag} successfully"
        	log "\n\n\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!"
	        log "\!\!\!\! ROLLING BACK TO COMPLETED SUCCESSFULLY \!\!\!\!"
	        log "\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\n\n"

	fi


}

final_checks() {
	log "--------------------------------"
	log "Checking new version through API"
	log "--------------------------------"
	if [ ${code_post_status} -eq 0 ] && [ ${code_change_link_status} -eq 0 ]; then
		version_status=0
		failed_version_servers=()
		for code_server in "${code_server_list[@]}"
		do
			get_version_from_code_servers ${code_server}
			current_version_tag=${version_tag}
			current_version_date=${version_date}
			log "${code_server} version: ${current_version_tag}"
			if [ "${current_version_tag}" != "${tag}" ]; then
				version_status=1
				failed_version_servers+=("${code_server}")
			fi
		done

		if [ ${version_status} -eq 0 ]; then
			log "\n\n+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
			log "All servers are deployed with ${tag} version"
			log "Deploy script finished successfully"
			log "Finish: `date`"
			log "+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
			subject="${proj} ${tag} deployed to ${env} successfully"
			message="Date: `date`\n\nEnvironment: ${env}\n\nCode server list: ${code_server_list[*]}\n\nDatabase server: ${db_server}\n\nSee attached log"
			send_mail "${subject}" "${message}"
		else
			log "ERROR: not all code servers switched to ${tag} version\nThe ones failed are: ${failed_version_servers[*]}\nExiting script\n\n"
			rollback
			subject="ERROR: ${proj} ${tag} failed to deploy to ${env}, Rolled back to ${pre_version_tag}"
			message="Date: `date`\n\nEnvironment: ${env}\n\nFull code server list: ${code_server_list[*]}\n\nDatabase server: ${db_server}\n\nFailed servers list:${failed_version_servers[*]}\n\nSee attached log"
			send_mail "${subject}" "${message}"


		fi
	fi
}
### main starts here ###
set_params
checks
get_code_server_list
get_db_server
init
global_pre_deploy
pre_deploy
git_pull
rsync_code
db_deploy
post_deploy
global_post_deploy
change_current_link
final_checks
