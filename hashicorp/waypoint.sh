#!/bin/bash

# BUG: https://github.com/kubernetes/minikube/issues/7511 - gave me lots of issues
# https://www.waypointproject.io/docs/server/install#nomad-platform
# https://www.waypointproject.io/docs/getting-started
# https://learn.hashicorp.com/tutorials/waypoint/get-started-nomad?in=waypoint/get-started-nomad

function waypoint-install() {
  arch=$(lscpu | grep "Architecture" | awk '{print $NF}')
  if [[ $arch == x86_64* ]]; then
      ARCH="amd64"
  elif  [[ $arch == aarch64 ]]; then
      ARCH="arm"
  fi
  echo -e '\e[38;5;198m'"CPU is $ARCH"

  sudo DEBIAN_FRONTEND=noninteractive apt-get --assume-yes install curl unzip jq
  yes | sudo docker system prune -a
  yes | sudo docker system prune --volumes

  echo -e '\e[38;5;198m'"Waypoint Install"
  # check if waypoint is installed, start and exit
  if [ -f /usr/local/bin/waypoint ]; then
    echo -e '\e[38;5;198m'"++++ Waypoint already installed at /usr/local/bin/waypoint"
    echo -e '\e[38;5;198m'"++++ `/usr/local/bin/waypoint version`"
  else
  # if waypoint is not installed, download and install
    echo -e '\e[38;5;198m'"++++ Waypoint not installed, installing.."
    LATEST_URL=$(curl -sL https://releases.hashicorp.com/waypoint/index.json | jq -r '.versions[].builds[].url' | sort -t. -k 1,1n -k 2,2n -k 3,3n -k 4,4n | egrep -v 'rc|beta' | egrep "linux.*$ARCH" | sort -V | tail -n 1)
    wget -q $LATEST_URL -O /tmp/waypoint.zip
    mkdir -p /usr/local/bin
    (cd /usr/local/bin && unzip /tmp/waypoint.zip)
    echo -e '\e[38;5;198m'"++++ Installed `/usr/local/bin/waypoint version`"
  fi
}

function waypoint-kubernetes-minikube() {
  echo -e '\e[38;5;198m'"++++ Ensure Minikube is running"
  sudo bash /vagrant/minikube/minikube.sh

  echo -e '\e[38;5;198m'"++++ Waypoint Delete and Cleanup"
  sudo --preserve-env=PATH -u vagrant kubectl config get-contexts
  sudo --preserve-env=PATH -u vagrant kubectl delete statefulset waypoint-server
  sudo --preserve-env=PATH -u vagrant kubectl delete pvc data-waypoint-server-0
  sudo --preserve-env=PATH -u vagrant kubectl delete svc waypoint
  sudo --preserve-env=PATH -u vagrant kubectl delete deployments waypoint-runner
  echo -e '\e[38;5;198m'"++++ Waypoint Context Clear"
  sudo --preserve-env=PATH -u vagrant waypoint context clear
  sudo --preserve-env=PATH -u vagrant waypoint context delete minikube
  sudo --preserve-env=PATH -u vagrant waypoint context list

  # https://www.waypointproject.io/docs/troubleshooting#waypoint-server-in-kubernetes
  echo -e '\e[38;5;198m'"++++ Waypoint Install on Platform Kubernetes (Minikube)"
  sudo --preserve-env=PATH -u vagrant waypoint install -platform=kubernetes -k8s-context=minikube -context-create=minikube -k8s-storageclassname=standard -k8s-helm-version=v0.1.8 -accept-tos
  sudo --preserve-env=PATH -u vagrant kubectl get all
  eval $(sudo --preserve-env=PATH -u vagrant minikube docker-env)
  sleep 120;
  sudo --preserve-env=PATH -u vagrant kubectl port-forward -n default service/waypoint-server 19702:9702 --address="0.0.0.0" > /dev/null 2>&1 &
  
  echo -e '\e[38;5;198m'"++++ Set Waypoint Context Kubernetes (Minikube)"
  export WAYPOINT_TOKEN_MINIKUBE=$(sudo --preserve-env=PATH -u vagrant waypoint user token)
  # TODO: the waypoint contexts keeps getting overwritten between kubernetes and nomad 
  # sudo --preserve-env=PATH -u vagrant waypoint context create \
  #   -server-addr=localhost:19702 \
  #   -server-auth-token=$WAYPOINT_TOKEN_MINIKUBE \
  #   -server-tls=false \
  #   -server-platform=kubernetes \
  #   -set-default minikube
  echo -e '\e[38;5;198m'"++++ Waypoint Context"
  sudo --preserve-env=PATH -u vagrant waypoint context list
  sudo --preserve-env=PATH -u vagrant waypoint context verify
  echo -e '\e[38;5;198m'"++++ Waypoint Init and Up T-Rex Nodejs Example"
  echo -e '\e[38;5;198m'"++++ Found here /vagrant/hashicorp/waypoint/custom-examples/kubernetes-trex-nodejs"
  cd /vagrant/hashicorp/waypoint/custom-examples/kubernetes-trex-nodejs
  echo -e '\e[38;5;198m'"++++ Write /vagrant/hashicorp/waypoint/custom-examples/kubernetes-trex-nodejs/waypoint.hcl"
  rm -rf /vagrant/hashicorp/waypoint/custom-examples/kubernetes-trex-nodejs/waypoint.hcl
  cat <<EOF | sudo tee /vagrant/hashicorp/waypoint/custom-examples/kubernetes-trex-nodejs/waypoint.hcl
project = "kubernetes-trex-nodejs"

app "kubernetes-trex-nodejs" {
  labels = {
    "service" = "kubernetes-trex-nodejs",
    "env"     = "dev"
  }

  build {
    use "docker" {}
    registry {
      use "docker" {
        image = "10.9.99.10:5001/trex-nodejs" # See minikube docker registry
        tag   = "0.0.2"
        local = false
        #encoded_auth = filebase64("/etc/docker/auth.json") # https://www.waypointproject.io/docs/lifecycle/build#private-registries
      }
    }
  }

  deploy {
    use "kubernetes" {
      probe_path   = "/"
      replicas     = 1
      service_port = 6001
      probe {
        initial_delay = 4
      }
      labels = {
        env = "local"
      }
      annotations = {
        demo = "yes"
      }
    }
  }

  release {
    use "kubernetes" {
      load_balancer = true
      port          = 6001
    }
  }
}
EOF
  echo -e '\e[38;5;198m'"++++ Waypoint Init"
  sudo --preserve-env=PATH -u vagrant waypoint init
  echo -e '\e[38;5;198m'"++++ Waypoint Up"
  sudo --preserve-env=PATH -u vagrant waypoint up
  echo -e '\e[38;5;198m'"++++ Waypoint Deploy"
  sudo --preserve-env=PATH -u vagrant waypoint deploy
  echo -e '\e[38;5;198m'"++++ Waypoint Server https://localhost:19702 and enter the following Token displayed below"
  echo $WAYPOINT_TOKEN_MINIKUBE
}

function waypoint-nomad() {
  echo -e '\e[38;5;198m'"++++ Ensure Nomad is running"
  sudo bash /vagrant/hashicorp/nomad.sh
  echo -e '\e[38;5;198m'"++++ Docker pull Waypoint Server container"
  docker pull hashicorp/waypoint:latest
  docker stop waypoint-server
  docker rm waypoint-server
  echo -e '\e[38;5;198m'"++++ Waypoint Job stop"
  for i in $(nomad job status | grep -e trex -e waypoint | tr -s " " | cut -d " " -f1); do nomad job stop $i; done
  echo -e '\e[38;5;198m'"++++ Waypoint Job Status"
  nomad job status
  echo -e '\e[38;5;198m'"++++ Nomad System GC"
  nomad system gc
  echo -e '\e[38;5;198m'"++++ Waypoint Context Clear"
  sudo --preserve-env=PATH -u vagrant waypoint context list
  sudo --preserve-env=PATH -u vagrant waypoint context clear
  # remove the previous waypoint db so that new context can be created
  sudo rm -rf /opt/nomad/data/volume/waypoint/*
  echo -e '\e[38;5;198m'"++++ Waypoint Install on Platform Hashicorp Nomad"
  export NOMAD_ADDR='http://localhost:4646'
  sudo --preserve-env=PATH -u vagrant waypoint install -platform=nomad -nomad-dc=dc1 -accept-tos -nomad-host-volume=waypoint -context-create=nomad -runner=false
  sleep 60;
  nomad job status
  nomad status
  echo -e '\e[38;5;198m'"++++ Set Waypoint Context Nomad"
  sudo --preserve-env=PATH -u vagrant waypoint context use nomad
  export WAYPOINT_TOKEN_NOMAD=$(sudo --preserve-env=PATH -u vagrant waypoint user token)
  echo -e '\e[38;5;198m'"++++ Waypoint Context"
  sudo --preserve-env=PATH -u vagrant waypoint context list
  sudo --preserve-env=PATH -u vagrant waypoint context verify
  echo -e '\e[38;5;198m'"++++ Waypoint Init and Up T-Rex Nodejs Example"
  echo -e '\e[38;5;198m'"++++ Found here /vagrant/hashicorp/waypoint/custom-examples/nomad-trex-nodejs"
  cd /vagrant/hashicorp/waypoint/custom-examples/nomad-trex-nodejs
  echo -e '\e[38;5;198m'"++++ Write /vagrant/hashicorp/waypoint/custom-examples/nomad-trex-nodejs/waypoint.hcl"
  rm -rf /vagrant/hashicorp/waypoint/custom-examples/nomad-trex-nodejs/waypoint.hcl
  cat <<EOF | sudo tee /vagrant/hashicorp/waypoint/custom-examples/nomad-trex-nodejs/waypoint.hcl
project = "nomad-trex-nodejs"

app "nomad-trex-nodejs" {
  labels = {
    "service" = "nomad-trex-nodejs",
    "env"     = "dev"
  }

  build {
    use "docker" {}
    registry {
      use "docker" {
        image = "trex-nodejs" # See docker registry in docker/docker.sh
        tag   = "0.0.2"
        local = true
        #encoded_auth = filebase64("/etc/docker/auth.json") # https://www.waypointproject.io/docs/lifecycle/build#private-registries
      }
    }
  }

  deploy {
    use "nomad" {
      datacenter = "dc1"
    }
  }

}
EOF
  echo -e '\e[38;5;198m'"++++ Waypoint Init"
  sudo --preserve-env=PATH -u vagrant waypoint init
  echo -e '\e[38;5;198m'"++++ Waypoint Up"
  sudo --preserve-env=PATH -u vagrant waypoint up
  echo -e '\e[38;5;198m'"++++ Waypoint Deploy"
  sudo --preserve-env=PATH -u vagrant waypoint deploy
  echo -e '\e[38;5;198m'"++++ Waypoint Server https://localhost:9702 and enter the following Token displayed below"
  echo $WAYPOINT_TOKEN_NOMAD
  echo -e '\e[38;5;198m'"++++ Waypoint Documentation http://localhost:3333/#/hashicorp/README?id=waypoint"
  echo -e '\e[38;5;198m'"++++ Nomad http://localhost:4646"
}

waypoint-install
$1