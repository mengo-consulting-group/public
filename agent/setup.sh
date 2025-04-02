#!/usr/bin/env bash

# Check or set required input
function check_or_set_required_input() {
    if [ -f "${INSTALL_DIR}/mengo_credentials.sh" ]; then
        source "${INSTALL_DIR}/mengo_credentials.sh"
    fi
    for var_name in "$@"; do
        local var_value=$(eval echo \$$var_name)
        if [ -z "${var_value}" ]; then
            read -t 60 -p "${var_name} is not set. Please enter the ${var_name}: " var_value
            if [ -z "${var_value}" ]; then
                echo "Timeout or empty input. ${var_name} is required. Exiting."
                exit 1
            fi
            export ${var_name}=${var_value}
        fi
    done
    # Store variables in mengo_credentials.sh
    sudo rm -f ${INSTALL_DIR}/mengo_credentials.sh && touch ${INSTALL_DIR}/mengo_credentials.sh
    for var_name in "$@"; do
        local var_value=$(eval echo \$$var_name)
        echo "export ${var_name}=${var_value}" | sudo tee -a ${INSTALL_DIR}/mengo_credentials.sh > /dev/null
    done
}

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
    
    if ! command -v curl &> /dev/null || ! command -v wget &> /dev/null; then
        sudo apt update
        sudo apt-get install -y -o "Dpkg::Options::=--force-confdef" -o "Dpkg::Options::=--force-confold" curl wget
    fi

    # github
    sudo mkdir -p -m 755 /etc/apt/keyrings \
	&& wget -qO- https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null \
	&& sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
	&& echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null

    sudo apt update
    for app in ${apps}; do
        if ! dpkg -l | grep -qw ${app}; then
            sudo apt-get install -y -o "Dpkg::Options::=--force-confdef" -o "Dpkg::Options::=--force-confold" ${app}
        fi
    done

    if ! command -v pyenv &> /dev/null; then
        export PYENV_GIT_TAG=v2.5.4
        curl https://pyenv.run | bash
    fi

    # Add pyenv initialization to .bashrc if not already present
    if ! grep -q 'export PYENV_ROOT="$HOME/.pyenv"' ~/.bashrc; then
        echo 'export PYENV_ROOT="$HOME/.pyenv"' >> ~/.bashrc
        echo 'export PATH="$PYENV_ROOT/bin:$PATH"' >> ~/.bashrc
        echo 'eval "$(pyenv init --path)"' >> ~/.bashrc
        echo 'eval "$(pyenv virtualenv-init -)"' >> ~/.bashrc
    fi

    # Initialize pyenv explicitly to apply changes
    export PYENV_ROOT="$HOME/.pyenv"
    export PATH="$PYENV_ROOT/bin:$PATH"
    eval "$(pyenv init --path)"
    eval "$(pyenv virtualenv-init -)"

    if ! command -v pyenv &> /dev/null; then
        echo "Error: pyenv is not installed or not available in the PATH. Exiting."
        exit 1
    fi

    if ! pyenv versions | grep -q "ansible"; then
        LIB_PACKAGES="build-essential zlib1g-dev libffi-dev libssl-dev libbz2-dev libreadline-dev libsqlite3-dev liblzma-dev libncurses-dev tk-dev"
        sudo apt-get install -y -o "Dpkg::Options::=--force-confdef" -o "Dpkg::Options::=--force-confold" ${LIB_PACKAGES}
        pyenv install 3.11
        pyenv virtualenv 3.11 ansible
        sudo apt remove ${LIB_PACKAGES} -y
        sudo apt autoremove -y
    fi
    pyenv activate ansible
    source ~/.pyenv/versions/ansible/bin/activate
    if ! command -v ansible &> /dev/null; then
        pip install "ansible>11,<12"
    fi
}

function install_snap(){
    apps=${1}
    for app in ${apps}; do
        if ! snap list | grep -qw ${app}; then
            sudo snap install ${app}
        fi
    done
}

function get_hcp_vault_secrets(){
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

# Clone or pull git repo
function clone_or_pull_git_repo(){
    me=$(whoami)
    sudo mkdir -p ${INSTALL_DIR}/environments && sudo chown ${me}:${me} ${INSTALL_DIR}/environments

    if [ -z "$( ls -A ${INSTALL_DIR}/environments )" ]; then
        git clone ${MENGO_AGENT_ENVIRONMENT_GIT_URL} ${INSTALL_DIR}/environments
    else
        cd ${INSTALL_DIR}/environments
        git fetch --all
        git reset --hard origin/main
        cd -
    fi
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
    clone_or_pull_git_repo

    # Set up SSH private SSH key
    mengo_app_agent_ssh_private_key

    # Add current user to the syslog group
    sudo usermod -aG syslog $(whoami)
    sudo mkdir -p /var/log/ansible/hosts
    sudo chown -R root:syslog /var/log/ansible
    sudo chmod -R 775 /var/log/ansible

    # Copy this script under ${INSTALL_DIR}/setup.sh to be used by cronjob
    if [ "$0" != "${INSTALL_DIR}/setup.sh" ]; then
        sudo cp $0 ${INSTALL_DIR}/setup.sh
    fi
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
    echo "$(ls ${INSTALL_DIR}/environments/mengo/${MENGO_AGENT_ID})"
    echo ""
    echo "*********************************"
    echo ""
}

# Agent start
function agent_start_and_register(){
    # Ensure SHELL=/bin/bash is the first line of crontab entries
    (crontab -l 2>/dev/null | grep -v "^SHELL=/bin/bash"; echo "SHELL=/bin/bash") | crontab -
    # Add cronjob to refresh mengo agent setup file every hour
    (crontab -l 2>/dev/null | grep -v "Mengo Agent setup download"; echo "0 */1 * * * curl -L -s https://raw.githubusercontent.com/mengo-consulting-group/public/refs/heads/main/agent/setup.sh | sudo tee ${INSTALL_DIR}/setup.sh # Mengo Agent setup download") | crontab -
    # Add cronjob to refresh mengo agent setup every hour
    (crontab -l 2>/dev/null | grep -v "Mengo Agent setup execution"; echo "0 */1 * * * ${INSTALL_DIR}/setup.sh # Mengo Agent setup execution") | crontab -
    # Add cronjob to run ansible playbooks every 2 hours
    (crontab -l 2>/dev/null | grep -v "Mengo Agent entrypoint"; echo "0 */2 * * * (source ~/.pyenv/versions/ansible/bin/activate && ${INSTALL_DIR}/environments/mengo/${MENGO_AGENT_ID}/entrypoint.sh) > /var/log/mengo_agent.log 2>&1 # Mengo Agent entrypoint") | crontab -
}

# Global variables
INSTALL_DIR=/opt/mengo/agent

HCP_VAULT_GLOBAL_DATA="https://api.cloud.hashicorp.com/secrets/2023-06-13/organizations/536b4122-6313-42a7-87a7-fa42d1e65362/projects/d6d602d6-faba-4baf-aaa6-8bf86588b39d/apps/mengo/open"
MENGO_ANSIBLE_COLLECTION_URL="git+https://github.com/mengo-consulting-group/ansible.git#/ansible_collections/local/mengo,v1.1.0"
MENGO_AGENT_ENVIRONMENT_GIT_URL='-b main https://github.com/mengo-consulting-group/mengo-agent-environments.git'

sudo mkdir -p ${INSTALL_DIR} && sudo chown $(whoami):$(whoami) ${INSTALL_DIR}

# Required inputs
check_or_set_required_input "MENGO_AGENT_ID" "HCP_CLIENT_ID" "HCP_CLIENT_SECRET"

# Required packages installation
install_apt "virtualenv rsyslog git gh"
install_snap "yq jq"

# Agent installation
mengo_app_agent_installation

# Agent info
agent_info

# Agent start & register
agent_start_and_register
