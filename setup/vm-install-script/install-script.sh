#!/bin/bash

echo ".........----------------#################._.-.-INSTALL-.-._.#################----------------........."
PS1='\[\e[01;36m\]\u\[\e[01;37m\]@\[\e[01;33m\]\H\[\e[01;37m\]:\[\e[01;32m\]\w\[\e[01;37m\]\$\[\033[0;37m\] '
echo "PS1='\[\e[01;36m\]\u\[\e[01;37m\]@\[\e[01;33m\]\H\[\e[01;37m\]:\[\e[01;32m\]\w\[\e[01;37m\]\$\[\033[0;37m\] '" >> ~/.bashrc
sed -i '1s/^/force_color_prompt=yes\n/' ~/.bashrc
# Note: sourcing from a non-interactive script won't change your current terminal window's prompt instantly, but it will work on next login.

apt-get autoremove -y  # removes the packages that are no longer needed
apt-get update
systemctl daemon-reload

# --- MODERN KUBERNETES SETUP (v1.30) ---
mkdir -p /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /' | tee /etc/apt/sources.list.d/kubernetes.list

apt-get update
# Note: Modern pkgs.k8s.io builds bundles dependencies accurately. We install the stable v1.30 native packages.
apt-get install -y docker.io vim build-essential jq python3-pip kubelet kubectl kubeadm
pip3 install jc

### UUID of VM 
### comment below line if this Script is not executed on Cloud based VMs
jc dmidecode | jq .[1].values.uuid -r

cat > /etc/docker/daemon.json <<EOF
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "storage-driver": "overlay2"
}
EOF
mkdir -p /etc/systemd/system/docker.service.d

systemctl daemon-reload
systemctl restart docker
systemctl enable docker
systemctl enable kubelet
systemctl start kubelet

echo ".........----------------#################._.-.-KUBERNETES-.-._.#################----------------........."
rm -f /root/.kube/config
kubeadm reset -f

# Initialize using the modern configuration
kubeadm init --kubernetes-version=1.30.0 --skip-token-print

mkdir -p ~/.kube
cp -i /etc/kubernetes/admin.conf ~/.kube/config
chown $(id -u):$(id -g) ~/.kube/config

# Deploying alternative stable pod network configuration (Weave is deprecated, using Calico standard for modern cluster architectures)
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/calico.yaml

sleep 60

echo "untaint controlplane node"
# Updated target taints to align with modern Kubernetes versions (master label changed entirely to control-plane)
kubectl taints node $(kubectl get nodes -o=jsonpath='{.items[].metadata.name}') node.kubernetes.io/not-ready:NoSchedule- || true
kubectl taints node $(kubectl get nodes -o=jsonpath='{.items[].metadata.name}') node-role.kubernetes.io/master:NoSchedule- || true
kubectl taints node $(kubectl get nodes -o=jsonpath='{.items[].metadata.name}') node-role.kubernetes.io/control-plane:NoSchedule- || true
kubectl get node -o wide

echo ".........----------------#################._.-.-Java and MAVEN-.-._.#################----------------........."
apt install openjdk-11-jdk -y
java -version
apt install -y maven
mvn -v

echo ".........----------------#################._.-.-JENKINS-.-._.#################----------------........."
# Using modern secure directory standard for Jenkins keys instead of apt-key
mkdir -p /usr/share/keyrings
curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key | tee /usr/share/keyrings/jenkins-keyring.asc > /dev/null

echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/" | tee /etc/apt/sources.list.d/jenkins.list

apt update
apt install -y jenkins
systemctl daemon-reload
systemctl enable jenkins
systemctl start jenkins

# Ensure docker group exists before adding Jenkins to it
groupadd -f docker
usermod -a -G docker jenkins
echo "jenkins ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

echo ".........----------------#################._.-.-COMPLETED-.-._.#################----------------........."
