#!/bin/bash

# Ensure script is run as root
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root" 
    exit 1
fi

# Get username to configure
read -p "Enter username to configure with admin privileges: " USERNAME

if ! id "$USERNAME" &>/dev/null; then
    echo "User $USERNAME does not exist!"
    exit 1
fi

echo "========================================================"
echo "Debian 12 Post-Installation Setup Script"
echo "========================================================"
echo "Setting up system for user: $USERNAME"

# Get user home directory
USER_HOME=$(eval echo ~$USERNAME)

# Create a directory for admin scripts
mkdir -p /usr/local/admin-scripts
mkdir -p $USER_HOME/scripts

# Enable non-free and non-free-firmware repositories
echo "Enabling non-free repositories..."
sed -i 's/main/main contrib non-free non-free-firmware/g' /etc/apt/sources.list
apt update

#Install required packages
echo "Installing base packages..."
apt install -y sudo curl wget git build-essential apt-transport-https ca-certificates \
    gnupg lsb-release unzip fontconfig \
    fastfetch ncdu tmux net-tools dnsutils tree zip \
    iotop nload iftop fail2ban openssh-server \
    ripgrep fd-find bat fzf jq python3-pip python3-venv \
    ranger vim emacs nfs-common rpcbind\
    golang-go btop \
    ethtool smartmontools lm-sensors \
    acl attr mc rdiff-backup logrotate molly-guard needrestart pwgen \
    apt-listchanges unattended-upgrades plocate debsums nvtop

# Configure unattended-upgrades
cat > /etc/apt/apt.conf.d/50unattended-upgrades << EOF
Unattended-Upgrade::Allowed-Origins {
    "\${distro_id}:\${distro_codename}";
    "\${distro_id}:${distro_codename}-security";
};
Unattended-Upgrade::Automatic-Reboot "true";
EOF
systemctl enable --now unattended-upgrades.service

# Install Docker
echo "Installing Docker..."
for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do apt remove $pkg; done
# Add Docker's official GPG key:
apt update
apt install ca-certificates curl
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

# Add the repository to Apt sources:
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null
apt update
#curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.asc
#sudo chmod a+r /etc/apt/keyrings/docker.asc
#echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
#apt update
apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin docker-buildx-plugin

# Create a dedicated Docker user
adduser --system --home "" --no-create-home --no-login docker
# Add docker user to docker group
usermod -aG docker docker

# Add user to sudo and other groups
echo "Adding $USERNAME to necessary groups..."
usermod -aG sudo,adm,docker,dialout,plugdev,netdev,audio,video,media "$USERNAME"

# Configure sudo with insults
echo "Configuring sudo with insults..."
echo 'Defaults insults' > /etc/sudoers.d/insults
echo 'Defaults timestamp_timeout=30' >> /etc/sudoers.d/insults
chmod 440 /etc/sudoers.d/insults

# Setup fail2ban for SSH
echo "Configuring fail2ban for SSH..."
systemctl enable fail2ban
systemctl start fail2ban
cat > /etc/fail2ban/jail.local << EOF
[sshd]
enabled = true
port = ssh
filter = sshd
logpath = %(sshd_log)s
maxretry = 3
bantime = 600
EOF

# User HOME directory
USER_HOME=$(eval echo ~$USERNAME)

cat >> /$USER_HOME/.bashrc << EOF

# Useful aliases
alias update='sudo apt update && sudo apt upgrade -y'
alias install='sudo apt install -y'
alias remove='sudo apt remove'
alias ports='ss -tuln'
alias myip='curl http://ipecho.net/plain; echo'
alias df='df -h'
alias du='du -h'
alias free='free -h'
alias grep='grep --color=auto'
alias mkdir='mkdir -p'
alias dc='docker-compose'
alias dps='docker ps'
alias dimg='docker images'
alias lzd='docker run --rm -it -v /var/run/docker.sock:/var/run/docker.sock -v /yourpath/config:/.config/jesseduffield/lazydocker lazyteam/lazydocker'

# Enable terminal colors
export TERM=xterm-256color
EOF

# Set proper permissions for user's home directory
chown -R $USERNAME:$USERNAME $USER_HOME

# Enable and start services
echo "Enabling and starting services..."
systemctl enable docker
systemctl start docker

# Clean up
echo "Cleaning up..."
rm -rf /tmp/fonts
# Restart SSH for X11 forwarding to take effect
echo "Restarting SSH service..."
systemctl restart ssh

# Final update & cleanup
echo "Running final update and cleanup..."
apt update
apt upgrade -y
apt autoremove -y
apt autoclean

echo "========================================================"
echo "Installation complete!"
echo "========================================================"
echo "You can log in to Tailscale by running: sudo tailscale up"
echo "You may need to log out and log back in for all changes to take effect."
echo "Reboot is recommended."

echo "Script completed successfully!"

