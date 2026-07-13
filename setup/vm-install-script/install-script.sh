#!/usr/bin/env bash
set -Eeuo pipefail

K8S_MINOR="v1.30"
CALICO_MANIFEST="https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/calico.yaml"

if [[ $EUID -ne 0 ]]; then
  echo "Run this script as root."
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

echo "Installing required packages..."

swapoff -a
sed -ri '/\sswap\s/s/^#?/#/' /etc/fstab

apt-get update
apt-get autoremove -y
apt-get install -y \
  ca-certificates \
  curl \
  gpg \
  jq \
  vim \
  build-essential \
  python3-pip \
  dmidecode \
  containerd \
  docker.io \
  openjdk-17-jdk \
  maven

echo "System UUID:"
dmidecode -s system-uuid || true

printf '%s\n' \
  'overlay' \
  'br_netfilter' \
  > /etc/modules-load.d/kubernetes.conf

modprobe overlay
modprobe br_netfilter

printf '%s\n' \
  'net.bridge.bridge-nf-call-iptables = 1' \
  'net.bridge.bridge-nf-call-ip6tables = 1' \
  'net.ipv4.ip_forward = 1' \
  > /etc/sysctl.d/kubernetes.conf

sysctl --system

echo "Configuring containerd..."

mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

systemctl daemon-reload
systemctl enable --now containerd

echo "Configuring Docker..."

mkdir -p /etc/docker
printf '%s\n' \
  '{' \
  '  "exec-opts": ["native.cgroupdriver=systemd"],' \
  '  "log-driver": "json-file",' \
  '  "storage-driver": "overlay2"' \
  '}' \
  > /etc/docker/daemon.json

systemctl restart docker
systemctl enable docker

echo "Installing Kubernetes..."

mkdir -p /etc/apt/keyrings

curl -fsSL "https://pkgs.k8s.io/core:/stable:/${K8S_MINOR}/deb/Release.key" \
  | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

printf '%s\n' \
  "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${K8S_MINOR}/deb/ /" \
  > /etc/apt/sources.list.d/kubernetes.list

apt-get update
apt-get install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl

systemctl enable --now kubelet

echo "Resetting previous Kubernetes configuration..."

kubeadm reset -f || true
rm -rf /root/.kube

echo "Initializing Kubernetes control plane..."

kubeadm init \
  --kubernetes-version="$(kubeadm version -o short)" \
  --skip-token-print

mkdir -p /root/.kube
cp -f /etc/kubernetes/admin.conf /root/.kube/config
export KUBECONFIG=/root/.kube/config

echo "Installing Calico network plugin..."
kubectl apply -f "${CALICO_MANIFEST}"

CONTROL_PLANE="$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')"

kubectl taint nodes "${CONTROL_PLANE}" \
  node-role.kubernetes.io/control-plane:NoSchedule- || true

kubectl taint nodes "${CONTROL_PLANE}" \
  node-role.kubernetes.io/master:NoSchedule- || true

echo "Waiting for Kubernetes node readiness..."
kubectl wait --for=condition=Ready "node/${CONTROL_PLANE}" --timeout=180s || true
kubectl get nodes -o wide

echo "Installing Jenkins..."

curl -fsSL \
  https://pkg.jenkins.io/debian-stable/jenkins.io-2026.key \
  -o /etc/apt/keyrings/jenkins-keyring.asc

printf '%s\n' \
  'deb [signed-by=/etc/apt/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/' \
  > /etc/apt/sources.list.d/jenkins.list

apt-get update
apt-get install -y fontconfig jenkins

groupadd -f docker
usermod -aG docker jenkins

systemctl daemon-reload
systemctl enable --now jenkins
systemctl restart jenkins

echo "========================================"
echo "INSTALLATION COMPLETE"
echo "Jenkins: http://<server-ip>:8080"
echo "Initial Jenkins password:"
cat /var/lib/jenkins/secrets/initialAdminPassword
echo "========================================"
