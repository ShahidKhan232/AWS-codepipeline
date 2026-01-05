#!/bin/bash 
# This installs the latest CodeDeploy agent on Ubuntu 24.04 (Noble)
set -e

echo "Starting CodeDeploy agent installation..."

# Update package list to get latest versions
sudo apt-get update

# Upgrade existing packages to latest versions
sudo apt-get upgrade -y

# Install latest prerequisites
sudo apt-get install -y ruby-full ruby-webrick wget curl

# Display Ruby version
echo "Ruby version:"
ruby --version

# Change to temp directory
cd /tmp

# Clean up any previous installation attempts
sudo systemctl stop codedeploy-agent 2>/dev/null || true
sudo dpkg -r codedeploy-agent 2>/dev/null || true
sudo rm -rf /opt/codedeploy-agent 2>/dev/null || true
sudo rm -rf /tmp/codedeploy-agent* 2>/dev/null || true
sudo rm -f /tmp/install 2>/dev/null || true
rm -rf codedeploy-agent* 2>/dev/null || true

# Download the latest AWS CodeDeploy installer
echo "Downloading latest CodeDeploy agent..."
wget https://aws-codedeploy-us-east-1.s3.us-east-1.amazonaws.com/latest/install
chmod +x ./install

# Install the latest version automatically
echo "Installing CodeDeploy agent..."
sudo ./install auto

# Verify installation
if [ ! -d /opt/codedeploy-agent ]; then
    echo "ERROR: CodeDeploy agent installation failed - /opt/codedeploy-agent not found"
    exit 1
fi

# Display installed version
AGENT_VERSION=$(sudo dpkg -l | grep codedeploy-agent | awk '{print $3}')
echo "CodeDeploy agent version installed: $AGENT_VERSION"

# Check if service file exists
if [ ! -f /etc/systemd/system/codedeploy-agent.service ] && [ ! -f /etc/init.d/codedeploy-agent ]; then
    echo "WARNING: Service file not found, creating it..."
    # Create init.d script for compatibility
    sudo tee /etc/init.d/codedeploy-agent > /dev/null <<'INITSCRIPT'
#!/bin/bash
### BEGIN INIT INFO
# Provides:          codedeploy-agent
# Required-Start:    $remote_fs $syslog
# Required-Stop:     $remote_fs $syslog
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: AWS CodeDeploy Agent
### END INIT INFO

AGENT_BIN="/opt/codedeploy-agent/bin/codedeploy-agent"

case "$1" in
    start)
        echo "Starting CodeDeploy agent..."
        sudo $AGENT_BIN start
        ;;
    stop)
        echo "Stopping CodeDeploy agent..."
        sudo $AGENT_BIN stop
        ;;
    status)
        sudo $AGENT_BIN status
        ;;
    restart)
        sudo $AGENT_BIN stop
        sleep 2
        sudo $AGENT_BIN start
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status}"
        exit 1
        ;;
esac
INITSCRIPT
    sudo chmod +x /etc/init.d/codedeploy-agent
    sudo update-rc.d codedeploy-agent defaults
fi

# Create configuration directory
sudo mkdir -p /etc/codedeploy-agent/conf

# Configure the agent with region and log settings
cat <<EOF | sudo tee /etc/codedeploy-agent/conf/codedeployagent.yml
---
:log_dir: /var/log/aws/codedeploy-agent
:pid_dir: /var/run/codedeploy-agent
:region: us-east-1
:verbose: false
EOF

# Create log directory with proper permissions
sudo mkdir -p /var/log/aws/codedeploy-agent
sudo mkdir -p /var/run/codedeploy-agent

# Start and enable the service
echo "Starting CodeDeploy agent service..."
sudo systemctl daemon-reload 2>/dev/null || true

# Start using init.d script
echo "Starting agent using init.d script..."
sudo /etc/init.d/codedeploy-agent start

# Wait for service to start
sleep 3

# Check status
echo "Checking CodeDeploy agent status..."
sudo /etc/init.d/codedeploy-agent status || true

# Verify agent is running by checking processes
if pgrep -f "codedeploy-agent" > /dev/null; then
    echo "✓ CodeDeploy agent process is running"
else
    echo "✗ CodeDeploy agent process not found"
    echo "Attempting to start directly..."
    sudo /opt/codedeploy-agent/bin/codedeploy-agent start
    sleep 2
fi

echo "CodeDeploy agent installation complete!"
echo ""
echo "Next steps:"
echo "1. Verify the agent is running: sudo systemctl status codedeploy-agent"
echo "2. Check logs: sudo tail -50 /var/log/aws/codedeploy-agent/codedeploy-agent.log"
echo "3. CRITICAL: Ensure this EC2 instance has an IAM role with AmazonEC2RoleforAWSCodeDeploy policy attached"
echo "4. Verify IAM role: curl -s http://169.254.169.254/latest/meta-data/iam/security-credentials/"