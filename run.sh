#!/usr/bin/env bash

ubuntu_version=$(lsb_release -rs)
if [ "$ubuntu_version" != "22.04" ]; then
  echo "This script only supports Ubuntu 22.04. Detected version: $ubuntu_version"
  exit 1
fi

check_docker() {
  echo "Checking if Docker is installed..."
  if [ -x "$(command -v docker)" ]; then
    echo "Success! Docker is installed."
  else
    echo "Docker is not installed. Installing Docker..."
    sudo apt update
    sudo apt install -y apt-transport-https ca-certificates curl software-properties-common
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt update
    sudo apt install -y docker-ce

    if [ -x "$(command -v docker)" ]; then
      echo "Success! Docker has been installed."
      if id -nG "$USER" | grep -qw docker; then
        echo "User $USER is already in the docker group."
      else
        sudo usermod -aG docker $USER
        echo "User $USER has been added to the docker group. Please log out and log in again for this to take effect."
        exit 2
      fi
    else
      echo "Docker installation failed. Please install Docker manually."
      exit 1
    fi
  fi
}

create_ros_ws() {
  read -p "Please provide the filesystem path to your ROS workspace (ex. /home/your_username/avenic/): " -e ros_ws_path
  
  if [ ! -d $ros_ws_path ]; then
    read -p "$ros_ws_path does not exist. Would you like to create it? Enter 'y' to create the directory or 'n' to quit: " -e create_response
    if [ "$create_response" == "y" ]; then
      if mkdir -p $ros_ws_path ; then
        >&2 echo "Successfully created $ros_ws_path."
      else
        >&2 echo "Could not create $ros_ws_path."
        exit 1
      fi
    else
      exit 1
    fi
  else
    >&2 echo "Success! $ros_ws_path exists."
  fi

  echo $ros_ws_path
}

choose_ros_version() {
  read -p "Which version of ROS would you like to use? Enter '1' to select ROS1 Noetic or '2' to select ROS2 Humble (recommended): " -e ros_version_response
  if [ $ros_version_response == 1 ] || [ $ros_version_response == 2 ]; then
    >&2 echo "Setting up environment for ROS$ros_version_response."
  else
    >&2 echo "Invalid response."
    exit 1
  fi

  echo $ros_version_response
}

choose_gpu() {
  >&2 echo "Checking if Nvidia support is enabled for Docker..."
  gpu="false"
  if dpkg -s nvidia-container-toolkit &>/dev/null; then
    >&2 echo "The Nvidia container toolkit is installed, GPU support will be enabled."
    gpu="true"
  else
    >&2 echo "The Nvidia container toolkit is not installed, GPU support will be disabled."
    read -p "Would you like to install Nvidia Container Toolkit? (y/n) (do not install if your computer does not have a GPU): " -e install_nvidia
    if [ "$install_nvidia" == "y" ]; then
      curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
      curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
        sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
        sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
      sudo sed -i -e '/experimental/ s/^#//g' /etc/apt/sources.list.d/nvidia-container-toolkit.list
      sudo apt-get update
      sudo apt-get install -y nvidia-container-toolkit
      if dpkg -s nvidia-container-toolkit &>/dev/null; then
        >&2 echo "Nvidia container toolkit installed successfully, GPU support will be enabled."
        echo "Please run ./run.sh again after this."
        exit 2
      else
        >&2 echo "Failed to install Nvidia container toolkit, GPU support will be disabled."
      fi
    fi
  fi

  echo $gpu
}

create_docker() {
  echo "Cloning source code into ROS workspace directory..."
  mkdir -p "$1/src"
  git clone -b main --single-branch --recurse-submodules https://github.com/swri-robotics/sem-apc-ros-bridge "$1/src/sem-apc-ros-bridge"
  
  if [ $3 == 1 ]; then
    git clone -b ros1 --single-branch https://github.com/swri-robotics/sem-apc-carla-interface.git "$1/src/sem-apc-carla-interface"
    git clone -b ros1 --single-branch https://github.com/swri-robotics/sem-apc-example-project.git "$1/src/sem-apc-example-project"
  else
    git clone -b ros2 --single-branch https://github.com/swri-robotics/sem-apc-carla-interface.git "$1/src/sem-apc-carla-interface"
    git clone -b ros2 --single-branch https://github.com/swri-robotics/sem-apc-example-project.git "$1/src/sem-apc-example-project"
  fi

  echo "Docker build has started. This may take some time..."
  export GID=$(id -g)
  export UID=$(id -u)
  export ROS_WS="$1"

  if [ "$2" == "true" ]; then
    if [ "$3" == 1 ]; then
      docker compose --profile gpu --profile ros1 up --build -d
    else
      docker compose --profile gpu --profile ros2 up --build -d
    fi
  else
    if [ "$3" == 1 ]; then
      docker compose --profile nogpu --profile ros1 up --build -d
    else
      docker compose --profile nogpu --profile ros2 up --build -d
    fi
  fi
}

# set -e
check_docker
ros_ws_path=$(create_ros_ws)
if [ $? == 1 ]; then
  echo "Exiting script."
  exit 1
fi
selected_ros_version=$(choose_ros_version)
if [ $? == 1 ]; then
  echo "Exiting script."
  exit 1
fi
gpu=$(choose_gpu)
create_docker $ros_ws_path $gpu $selected_ros_version