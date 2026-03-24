#!/bin/bash
set -e
echo "🚀 Preparing VM for Lab deployment..."
echo "====================================="

echo "=== Step 0/5: Setup Disks ==="
dnf install -y cloud-utils-growpart
growpart /dev/sda 3 2>/dev/null || true
pvresize /dev/sda3 2>/dev/null || true
lvextend -l +100%FREE /dev/mapper/rl_linux1-root 2>/dev/null || true
xfs_growfs / 2>/dev/null || true
if ! mountpoint -q /data; then
 echo -e "n\np\n1\n\n\nw" | fdisk /dev/sdb 2>/dev/null || true
 mkfs.xfs /dev/sdb1 2>/dev/null || true
 mkdir -p /data
 mount /dev/sdb1 /data 2>/dev/null || true
 grep -q '/dev/sdb1' /etc/fstab || echo '/dev/sdb1 /data xfs defaults 0 0' >> /etc/fstab
fi
timedatectl set-timezone Asia/Bangkok
echo "✅ Disks ready, Timezone: Asia/Bangkok"

echo "=== Step 1/5: Install Docker CE ==="
dnf remove -y podman podman-docker containers-common 2>/dev/null || true
dnf config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo
dnf install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
mkdir -p /data/docker /etc/docker
printf '{"data-root":"/data/docker"}' > /etc/docker/daemon.json
systemctl enable --now docker
docker --version && echo "✅ Docker ready"

echo "=== Step 2/5: Install GitHub CLI ==="
dnf config-manager --add-repo https://cli.github.com/packages/rpm/gh-cli.repo
dnf install -y gh
gh --version && echo "✅ gh CLI ready"

echo "=== Step 3/5: Login GitHub CLI ==="
gh auth login --scopes "repo,workflow"

echo "=== Step 4/5: Install Self-hosted Runner ==="
useradd -m -s /bin/bash github-runner 2>/dev/null || true
mkdir -p /data/github-runner
RUNNER_VER=\$(curl -s https://api.github.com/repos/actions/runner/releases/latest | python3 -c 'import sys,json; print(json.load(sys.stdin)["tag_name"].lstrip("v"))')
curl -o /data/github-runner/runner.tar.gz -L "https://github.com/actions/runner/releases/download/v\${RUNNER_VER}/actions-runner-linux-x64-\${RUNNER_VER}.tar.gz"
cd /data/github-runner && tar xzf runner.tar.gz
./bin/installdependencies.sh
chown -R github-runner:github-runner /data/github-runner
echo ""
echo "ดึง Token จาก: github.com/chaladshop/lab-infrastructure"
echo "→ Settings → Actions → Runners → New self-hosted runner"
read -p "Runner Token: " RUNNER_TOKEN
read -p "Runner Name (default: lab-runner): " RUNNER_NAME
RUNNER_NAME=\${RUNNER_NAME:-lab-runner}
su - github-runner -c "cd /data/github-runner && ./config.sh --url https://github.com/chaladshop/lab-infrastructure --token \${RUNNER_TOKEN} --name \${RUNNER_NAME} --unattended"
cd /data/github-runner
./svc.sh install github-runner
chcon -R -t bin_t /data/github-runner/
chmod -R 755 /data/github-runner
./svc.sh start
sleep 5 && ./svc.sh status | grep Active
echo "✅ Step 4/5 done"

echo "=== Step 5/5: Clone Lab Repo ==="
gh repo clone chaladshop/lab-infrastructure /data/lab-infrastructure
echo "✅ Step 5/5 done"

echo "====================================="
echo "✅ VM preparation complete!"
echo "ขั้นตอนต่อไป: รัน Deploy Workflow บน GitHub Actions"
echo "github.com/chaladshop/lab-infrastructure/actions"
