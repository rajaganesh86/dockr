#!/bin/bash

set -o errexit

# Regular Colors
Black='\033[0;30m'        # Black
Red='\[\e[0;31m\]'        # Red
Green='\033[0;32m'        # Green
Yellow='\033[0;33m'       # Yellow
Blue='\033[0;34m'         # Blue
Purple='\033[0;35m'       # Purple
Cyan='\033[0;36m'         # Cyan
White='\033[0;37m'        # White
NC='\033[0m' # No Color
package_manager="apt-get" # Assume that it is Ubuntu OS
location="" # Assume that the default is local postgres

is_command_present() {
    type "$1" >/dev/null 2>&1
}

# Check whether 'wget' command exists.
has_wget() {
    has_cmd wget
}

# Check whether 'curl' command exists.
has_curl() {
    has_cmd curl
}

# Check whether the given command exists.
has_cmd() {
    command -v "$1" > /dev/null 2>&1
}

#!/bin/bash

# Define a function to capture and store environment variables in a .env file
ask_env() {

    # Check if the .env file already exists and backup it
    if [ -f .env ]; then
        mv .env .env.bak
    fi

    # Prompt the user for environment variable values
    echo "Please provide Hasura DB configuration as per your environment."

    # Prompt the user for Postgres location (local or remote)
    read -p "Is Postgres local or remote? (local/remote): " location

    if [ "$location" == "remote" ]; then

        # Set environment variables for remote PostgreSQL
        read -p "Enter POSTGRES_PASSWORD: " POSTGRES_PASSWORD
        read -p "Enter HASURA_GRAPHQL_DATABASE_URL: " HASURA_GRAPHQL_DATABASE_URL
        read -p "Enter HASURA_GRAPHQL_METADATA_DATABASE_URL: " HASURA_GRAPHQL_METADATA_DATABASE_URL
        read -p "Enter HASURA_GRAPHQL_ADMIN_SECRET: " HASURA_GRAPHQL_ADMIN_SECRET
        read -p "Enter PG_DATABASE_URL: " PG_DATABASE_URL
        #read -p "Enter HASURA_GRAPHQL_ENABLE_CONSOLE (true/false): " HASURA_GRAPHQL_ENABLE_CONSOLE

        # Create the .env file and write the variables
        echo "HASURA_GRAPHQL_DATABASE_URL=$HASURA_GRAPHQL_DATABASE_URL" >> .env
        echo "HASURA_GRAPHQL_METADATA_DATABASE_URL=$HASURA_GRAPHQL_METADATA_DATABASE_URL" >> .env
        echo "HASURA_GRAPHQL_ADMIN_SECRET=$HASURA_GRAPHQL_ADMIN_SECRET" >> .env
        echo "PG_DATABASE_URL=$PG_DATABASE_URL" >> .env
        #echo "HASURA_GRAPHQL_ENABLE_CONSOLE=$HASURA_GRAPHQL_ENABLE_CONSOLE" >> .env
        echo "POSTGRES_PASSWORD=$POSTGRES_PASSWORD" >> .env

        echo "Environment variables saved to .env file."

    else
        # If local, get postgres password and configure Hasura URLs
        read -p "Enter POSTGRES_PASSWORD: " POSTGRES_PASSWORD
        read -p "Enter HASURA_GRAPHQL_ADMIN_SECRET: " HASURA_GRAPHQL_ADMIN_SECRET
        # Create the .env file and write the variables
        echo "HASURA_GRAPHQL_DATABASE_URL=postgres://postgres:$POSTGRES_PASSWORD@postgres:5432/postgres" >> .env
        echo "HASURA_GRAPHQL_METADATA_DATABASE_URL=postgres://postgres:$POSTGRES_PASSWORD@postgres:5432/postgres" >> .env
        echo "HASURA_GRAPHQL_ADMIN_SECRET=$HASURA_GRAPHQL_ADMIN_SECRET" >> .env
        echo "PG_DATABASE_URL=postgres://postgres:$POSTGRES_PASSWORD@postgres:5432/postgres" >> .env
        #echo "HASURA_GRAPHQL_ENABLE_CONSOLE=$HASURA_GRAPHQL_ENABLE_CONSOLE" >> .env
        echo "POSTGRES_PASSWORD=$POSTGRES_PASSWORD" >> .env

        echo "Environment variables saved to .env file."
    fi

}

compose_version () {
    local compose_version
    compose_version="$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep 'tag_name' | cut -d\" -f4)"
    echo "${compose_version:-v2.18.1}"
}

install_docker() {
    echo "++++++++++++++++++++++++"
    echo "Setting up docker repos"


    if [[ $package_manager == apt-get ]]; then
        apt_cmd="$sudo_cmd apt-get --yes --quiet"
        $apt_cmd update
        $apt_cmd install software-properties-common gnupg-agent
        curl -fsSL "https://download.docker.com/linux/ubuntu/gpg" | $sudo_cmd apt-key add -
        $sudo_cmd add-apt-repository \
            "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
        $apt_cmd update
        echo "Installing docker"
        $apt_cmd install docker-ce

     else
        send_event "installation_error_checks"
     fi
}

start_docker() {
    echo -e "🐳 Starting Docker ...\n"
    if [[ $os == "Mac" ]]; then
        open --background -a Docker && while ! docker system info > /dev/null 2>&1; do sleep 1; done
    else
        if ! $sudo_cmd systemctl is-active docker.service > /dev/null; then
            echo "Starting docker service"
            $sudo_cmd systemctl start docker.service
        fi
        # if [[ -z $sudo_cmd ]]; then
        #     docker ps > /dev/null && true
        #     if [[ $? -ne 0 ]]; then
        #         request_sudo
        #     fi
        # fi
        if [[ -z $sudo_cmd ]]; then
            if ! docker ps > /dev/null && true; then
                request_sudo
            fi
        fi
    fi
}

install_docker_compose() {
    if [[ $package_manager == "apt-get" ]]; then
        if [[ ! -f /usr/bin/docker-compose ]];then
            echo "++++++++++++++++++++++++"
            echo -e "🐳 Installing docker-compose ...\n"
            compose_url="https://github.com/docker/compose/releases/download/1.29.2/docker-compose-linux-x86_64"
            echo "Downloading docker-compose from $compose_url"
            $sudo_cmd curl -L "$compose_url" -o /usr/local/bin/docker-compose
            $sudo_cmd chmod +x /usr/local/bin/docker-compose
            $sudo_cmd ln -fs /usr/local/bin/docker-compose /usr/bin/docker-compose
            echo "docker-compose installed!"
            echo ""
        fi
    else
        send_event "docker_compose_not_found"

        echo "+++++++++++ IMPORTANT READ ++++++++++++++++++++++"
        echo "docker-compose not found! Please install docker-compose first and then continue with this installation."
        echo "Refer https://docs.docker.com/compose/install/ for installing docker-compose."
        echo "+++++++++++++++++++++++++++++++++++++++++++++++++"
        exit 1
    fi
}

wait_for_containers_start() {
    local timeout=$1

    # The while loop is important because for-loops don't work for dynamic values
    while [[ $timeout -gt 0 ]]; do
        status_code="$(curl -s -o /dev/null -w "%{http_code}" "http://localhost/" || true)"
        if [[ status_code -eq 200 ]]; then
            break
        else
            echo -ne "Waiting for all containers to start. This check will timeout in $timeout seconds ...\r\c"
        fi
        ((timeout--))
        sleep 1
    done

    echo ""
}

bye() {  # Prints a friendly good bye message and exits the script.
    if [[ "$?" -ne 0 ]]; then
        set +o errexit

        echo "🔴 The containers didn't seem to start correctly. Please run the following command to check containers that may have errored out:"
        echo ""
        echo -e "docker-compose -f ./docker-compose.yml ps -a"

        echo "++++++++++++++++++++++++++++++++++++++++"

        send_event "installation_support"


    fi
}

request_sudo() {
    if hash sudo 2>/dev/null; then
        echo -e "\n\n🙇 We will need sudo access to complete the installation."
        if (( $EUID != 0 )); then
            sudo_cmd="sudo"
            echo -e "Please enter your sudo password, if prompted."
            if ! $sudo_cmd -l | grep -e "NOPASSWD: ALL" > /dev/null && ! $sudo_cmd -v; then
                echo "Need sudo privileges to proceed with the installation."
                exit 1;
            fi

            echo -e "Got it! Thanks!! 🙏\n"
        fi
        fi
}

echo ""
echo -e "👋 Thank you for trying out Databrain! "
echo ""

sudo_cmd=""

# Check sudo permissions
if (( $EUID != 0 )); then
    echo "🟡 Running installer with non-sudo permissions."
    echo "   In case of any failure or prompt, please consider running the script with sudo privileges."
    echo ""
else
    sudo_cmd="sudo"
fi

# Run bye if failure happens
trap bye EXIT

send_event() {
    error=""

    case "$1" in
        'install_started')
            event="Installation Started"
            ;;
        'os_not_supported')
            event="Installation Error"
            error="OS Not Supported"
            ;;
        'docker_not_installed')
            event="Installation Error"
            error="Docker not installed"
            ;;
        'docker_compose_not_found')
            event="Installation Error"
            event="Docker Compose not found"
            ;;
        'port_not_available')
            event="Installation Error"
            error="port not available"
            ;;
        'installation_error_checks')
            event="Installation Error - Checks"
            error="Containers not started"
            others='"data": "some_checks",'
            ;;
        'installation_support')
            event="Installation Support"
            others='"email": "'"$email"'",'
            ;;
        'installation_success')
            event="Installation Success"
            ;;
        'identify_successful_installation')
            event="Identify Successful Installation"
            others='"email": "'"$email"'",'
            ;;
        *)
            print_error "unknown event type: $1"
            exit 1
            ;;
    esac

    if [[ "$error" != "" ]]; then
        error='"error": "'"$error"'", '
    fi

}
download_composefile() {

        # Construct the Gist raw URL
        if [ "$location" == "remote" ]; then
                GIST_RAW_URL="https://gist.githubusercontent.com/rajaganesh86/bed9ad676d3edc15c8a062092e1f13f6/raw/bab75be4a9d51efdc8bdd8411995bbf9cbe33dd9/docker-compose-no-postgres.yml"
        else
                GIST_RAW_URL="https://gist.githubusercontent.com/rajaganesh86/d815d6bc63eb94f30f3be5c21c663ba9/raw/4b0b69e9eda47724d0ed6902d934906a395a7946/docker-compose.yml"
        fi

        echo "Downloading docker-compose.yml file..."
        curl -o docker-compose.yml -L "$GIST_RAW_URL" 2>/dev/null

        # Check if the download was successful
        if [ $? -eq 0 ]; then
            echo "docker-compose.yml file downloaded successfully."
        else
            echo "docker-compose.yml file download failed."
        fi
}
send_event "install_started"

if [[ $desired_os -eq 0 ]]; then
    send_event "os_not_supported"
fi

# check_ports_occupied

# Check is Docker daemon is installed and available. If not, the install & start Docker for Linux machines. We cannot automatically install Docker Desktop on Mac OS
if ! is_command_present docker; then

    if [[ $package_manager == "apt-get" ]]; then
        request_sudo
        install_docker
        start_docker
        # enable docker without sudo from next reboot
        sudo usermod -aG docker "${USER}"
    else
        echo ""
        echo "+++++++++++ IMPORTANT READ ++++++++++++++++++++++"
        echo "Docker must be installed manually on your machine to proceed. Docker can only be installed automatically on Ubuntu OS"
        echo "https://docs.docker.com/get-docker/"
        echo "++++++++++++++++++++++++++++++++++++++++++++++++"

        send_event "docker_not_installed"
        exit 1
    fi
fi

# Install docker-compose
if ! is_command_present docker-compose; then
    request_sudo
    install_docker_compose
fi

start_docker
ask_env
download_composefile

echo ""
echo -e "\n🟡 Pulling the latest container images for Databrain.\n"
docker-compose -f ./docker-compose.yml pull
#docker-compose pull

echo ""
echo "🟡 Starting the Databrain containers. It may take a few minutes ..."
echo
# The docker-compose command does some nasty stuff for the `--detach` functionality. So we add a `|| true` so that the
# script doesn't exit because this command looks like it failed to do it's thing.
docker-compose -f ./docker-compose.yml up --detach --remove-orphans || true

wait_for_containers_start 60
echo ""

if [[ $status_code -ne 200 ]]; then
    echo "+++++++++++ ERROR ++++++++++++++++++++++"
    echo "🔴 The containers didn't seem to start correctly. Please run the following command to check containers that may have errored out:"
    echo ""

    echo -e "docker-compose -f ./docker-compose.yml ps -a"

    echo "++++++++++++++++++++++++++++++++++++++++"

    send_event "installation_error_checks"
    exit 1

else
    send_event "installation_success"

    echo "++++++++++++++++++ SUCCESS ++++++++++++++++++++++"
    echo ""
    echo "🟢 Your installation is complete!"
    echo ""
    echo -e "🟢 Your frontend is running on http://localhost"
    echo ""

    echo "ℹ️  To bring down Databrain and clean volumes : docker-compose -f ./docker-compose.yml down -v"

    echo ""
    echo "+++++++++++++++++++++++++++++++++++++++++++++++++"
    echo ""
    echo "👉 Need help in Getting Started?"
    echo -e "Join us on Slack <URL>"
    echo ""

    send_event "identify_successful_installation"
    # Clean up temporary files
    #rm $temp_compose_file

fi

echo -e "\n🙏 Thank you!\n"
