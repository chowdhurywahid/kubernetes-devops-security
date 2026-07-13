#!/usr/bin/env bashset -Eeuo pipefail

K8S_MINOR="v1.30"CALICO_MANIFEST="https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/calico.yaml"

if [[ $EUID -ne 0 ]]; thenecho "Run this script as root."exit 1fi

export DEBIAN_FRONTEND=noninteractive

echo "Installing required packages..."

swapoff -ased -ri '/\sswap\s/s/^#?/#/' /etc/fstab

apt-get updateapt-get autoremove -yapt-get install -y ca-certificates curl gpg jq vim build-essential python3-pip dmidecode containerd docker.io openjdk-17-jdk maven

echo "System UUID:"dmidecode -s system-uuid || true

cat > /etc/modules-load.d/kubernetes.conf <<'EOF'overlaybr_netfilterEOF

modprobe overlaymodprobe br_netfilter

cat > /etc/sysctl.d/kubernetes.conf <<'EOF'net.bridge.bridge-nf-call-iptables = 1net.bridge.bridge-nf-call-ip6tables = 1net.ipv4.ip_forward = 1EOF

sysctl --system

echo "Configuring containerd..."

mkdir -p /etc/containerdcontainerd config default > /etc/containerd/config.tomlsed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

systemctl daemon-reloadsystemctl enable --now containerd

echo "Configuring Docker..."

mkdir -p /etc/dockercat > /etc/docker/daemon.json <<'EOF'{"exec-opts": ["native.cgroupdriver=systemd"],"log-driver": "json-file","storage-driver": "overlay2"}EOF

systemctl restart dockersystemctl enable docker

echo "Installing Kubernetes..."

mkdir -p /etc/apt/keyrings

curl -fsSL "https://pkgs.k8s.io/core:/stable:/${K8S_MINOR}/deb/Release.key" | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${K8S_MINOR}/deb/ /" 

/etc/apt/sources.list.d/kubernetes.list

apt-get updateapt-get install -y kubelet kubeadm kubectlapt-mark hold kubelet kubeadm kubectl

systemctl enable --now kubelet

echo "Resetting previous Kubernetes configuration..."

kubeadm reset -f || truerm -rf /root/.kube

echo "Initializing Kubernetes control plane..."

kubeadm init --kubernetes-version="$(kubeadm version -o short)" --skip-token-print

mkdir -p /root/.kubecp -f /etc/kubernetes/admin.conf /root/.kube/configexport KUBECONFIG=/root/.kube/config

echo "Installing Calico network plugin..."kubectl apply -f "${CALICO_MANIFEST}"

CONTROL_PLANE="$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')"

echo "Allowing workloads on the control-plane node..."kubectl taint nodes "${CONTROL_PLANE}" node-role.kubernetes.io/control-plane:NoSchedule- || true

kubectl taint nodes "${CONTROL_PLANE}" node-role.kubernetes.io/master:NoSchedule- || true

echo "Waiting for Kubernetes node readiness..."kubectl wait --for=condition=Ready "node/${CONTROL_PLANE}" --timeout=180s || truekubectl get nodes -o wide

echo "Installing Jenkins..."

curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2026.key -o /etc/apt/keyrings/jenkins-keyring.asc

echo "deb [signed-by=/etc/apt/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/" 

/etc/apt/sources.list.d/jenkins.list

apt-get updateapt-get install -y fontconfig jenkins

groupadd -f dockerusermod -aG docker jenkins

systemctl daemon-reloadsystemctl enable --now jenkinssystemctl restart jenkins

echo "========================================"echo "INSTALLATION COMPLETE"echo "Jenkins: http://<server-ip>:8080"echo "Initial Jenkins password:"cat /var/lib/jenkins/secrets/initialAdminPasswordecho "========================================"
