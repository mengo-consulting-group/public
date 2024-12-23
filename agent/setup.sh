#!/usr/bin/env bash

# Ensure infrastructure apps are available
function add_apt_repos(){
  repos=${1}
  sudo apt-add-repository ${repos} -y
}

# Ensure application list is available
function install_apt(){
    apps=${1}
    export NEEDRESTART_MODE=a
    export DEBIAN_FRONTEND=noninteractive
    
    sudo apt update
    sudo apt-get install -y -o "Dpkg::Options::=--force-confdef" -o "Dpkg::Options::=--force-confold" curl wget

    # ansible
    add_apt_repos "ppa:ansible/ansible"

    # github
    sudo mkdir -p -m 755 /etc/apt/keyrings \
	&& wget -qO- https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null \
	&& sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
	&& echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null

    sudo apt update
    sudo apt-get install -y -o "Dpkg::Options::=--force-confdef" -o "Dpkg::Options::=--force-confold" ${apps}
}

function install_snap(){
    apps=${1}
    sudo snap install ${apps}
}

function get_hcp_vault_secrets(){
    # TODO: check mengo_credentials.sh file exist, and validate them
    # TODO: load this credentials when work with ansible collections
    source mengo_credentials.sh

    export HCP_API_TOKEN=$(curl --silent --location "https://auth.idp.hashicorp.com/oauth2/token" \
    --header "Content-Type: application/x-www-form-urlencoded" \
    --data-urlencode "client_id=$HCP_CLIENT_ID" \
    --data-urlencode "client_secret=$HCP_CLIENT_SECRET" \
    --data-urlencode "grant_type=client_credentials" \
    --data-urlencode "audience=https://api.hashicorp.cloud" | jq -r .access_token)

    # Generate providers json file
    curl --silent \
    --location ${HCP_VAULT_GLOBAL_DATA} \
    --request GET \
    --header "Authorization: Bearer ${HCP_API_TOKEN}" | \
    jq -r '.secrets[] | select(.name == "providers") | .version.value' | sudo tee ${INSTALL_DIR}/.vault_providers.json
}

# Create environment file if does not exist
function mengo_app_agent_configure_git(){
    cat ${INSTALL_DIR}/.vault_providers.json | jq -r '.github.github_token' | sudo tee ${INSTALL_DIR}/.gh_token

    gh auth login --with-token < ${INSTALL_DIR}/.gh_token

    gh auth setup-git
}

# Function to check if SSH key exists in authorized_keys
function ssh_public_key_exists() {
  grep -q "$(cat ${INSTALL_DIR}/.ssh_public_key)" ~/.ssh/authorized_keys
}

# Function to add the key to authorized_keys if it doesn't exist
function add_ssh_public_key() {
  if ! ssh_public_key_exists "$(cat ${INSTALL_DIR}/.ssh_public_key)"; then
    echo "$(cat ${INSTALL_DIR}/.ssh_public_key)" >> ~/.ssh/authorized_keys
  fi
}

# Create environment file if does not exist
function mengo_app_agent_ssh_private_key(){
    cat ${INSTALL_DIR}/.vault_providers.json | jq -r '.ssh.private_key' | sudo tee ${INSTALL_DIR}/.ssh_private_key
    cat ${INSTALL_DIR}/.vault_providers.json | jq -r '.ssh.public_key' | sudo tee ${INSTALL_DIR}/.ssh_public_key

    sudo chmod 0400 ${INSTALL_DIR}/.ssh_private_key
    me=$(whoami)
    sudo chown ${me}:${me} ${INSTALL_DIR}/.ssh_private_key
    
    add_ssh_public_key
}

# Agent customization
function mengo_app_agent_installation(){

    # Get HCP Vault required secrets
    get_hcp_vault_secrets

    # Configure git agent
    mengo_app_agent_configure_git

    # Install mengo ansible collection
    ansible-galaxy collection install ${MENGO_ANSIBLE_COLLECTION_URL} --force

    # Obtain environment definition[s]
    # TODO: use stick flag to make group to any file/dir created by the user who is installing
    me=$(whoami)
    sudo mkdir -p ${INSTALL_DIR}/inventory && sudo chown ${me}:${me} ${INSTALL_DIR}/inventory
    if [ -z "$( ls -A ${INSTALL_DIR}/inventory )" ]; then
        git clone ${MENGO_AGENT_ENVIRONMENT_GIT_URL} ${INSTALL_DIR}/inventory
    else
        cd ${INSTALL_DIR}/inventory
        git pull
        cd -
    fi

    # Set up SSH private SSH key
    mengo_app_agent_ssh_private_key
}

# Agent commands info
function agent_info(){

    # Share information
    echo ""
    echo "**** Mengo Agent installed ****"
    echo "Mengo ansible collection version:"
    echo "$(ansible-galaxy collection list local.mengo)"
    echo ""
    echo "Mengo agent environments"
    echo ""
    echo "$(ls ${INSTALL_DIR}/inventory/mengo/${MENGO_AGENT_ID})"
    echo ""
    echo "*********************************"
    echo ""
}

# Agent start
function agent_start_and_register(){
    echo ""

    # TODO: Create a shell script that periodically pull the secrets from HCP Vault.
    # Then, we will be able to rotate any value like github key, ms teams, ssh keys

    # # Start service
    # echo ""
    # echo "**** Mengo Agent schedule ****"
    # cd ${INSTALL_DIR}
    # echo "*********************************"
    # echo ""
}

# Global variables
INSTALL_DIR=/opt/mengo/agent

HCP_VAULT_GLOBAL_DATA="https://api.cloud.hashicorp.com/secrets/2023-06-13/organizations/536b4122-6313-42a7-87a7-fa42d1e65362/projects/d6d602d6-faba-4baf-aaa6-8bf86588b39d/apps/mengo/open"
MENGO_ANSIBLE_COLLECTION_URL="git+https://github.com/mengo-consulting-group/ansible.git#/ansible_collections/local/mengo,main"
MENGO_AGENT_ENVIRONMENT_GIT_URL='-b main https://github.com/mengo-consulting-group/mengo-agent-environments.git'

# Required packages installation
install_apt "ansible git gh"
install_snap "yq jq"

# Agent installation
sudo mkdir -p ${INSTALL_DIR}
mengo_app_agent_installation

# Agent info
agent_info

# Agent start & register
# agent_start_and_register /opt/mengo/agent
