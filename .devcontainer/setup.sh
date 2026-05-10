#!/bin/bash
set -e  # Exit on any error

# Parse command line arguments
INSTALL_CLAUDE=false

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  --claude    Install Claude with MCP support (includes Node.js, uvx, Serena, and AWS MCP servers)"
    echo "  -h, --help  Show this help message"
    exit 1
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --claude)
            INSTALL_CLAUDE=true
            shift
            ;;
        -h|--help)
            show_usage
            ;;
        *)
            echo "Unknown option: $1"
            show_usage
            ;;
    esac
done

echo "🚀 Starting devcontainer setup..."
if [ "$INSTALL_CLAUDE" = true ]; then
    echo "🤖 Claude MCP support will be installed"
else
    echo "⏭️  Skipping Claude MCP installation (use --claude to enable)"
fi

# STEP 1: Check if we're on NRCAN network and install certificates FIRST (before any downloads)
if [ "$(curl -k -o /dev/null -s -w "%{http_code}" "https://intranet.nrcan.gc.ca/")" -ge 200 ] && [ "$(curl -o /dev/null -s -w "%{http_code}" "https://intranet.nrcan.gc.ca/")" -lt 400 ]; then
    echo "🔐 NRCAN network detected - installing certificates..."
    git clone https://github.com/canmet-energy/linux_nrcan_certs.git >/dev/null 2>&1
    cd linux_nrcan_certs
    git checkout ruby_3.2
    git pull
    ./install_nrcan_certs.sh >/dev/null 2>&1
    cd ..
    rm -fr linux_nrcan_certs
    echo 'export NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-certificates.crt' >> /home/vscode/.bashrc
    echo 'export SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt' >> /home/vscode/.bashrc
    echo 'export REQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt' >> /home/vscode/.bashrc
    echo 'export AWS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt' >> /home/vscode/.bashrc
    export NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-certificates.crt
    
    # IMPORTANT: Reload certificate store and update environment
    sudo update-ca-certificates >/dev/null 2>&1
    export SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
    export REQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt
    export AWS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt
    
    echo "✅ NRCAN certificates installed and environment updated"
    NRCAN_NETWORK=true
else
    echo "🌐 Standard network detected - using default certificates"
    NRCAN_NETWORK=false
    
    # Set SSL environment variables for systems that have certificates installed
    if [ -f "/etc/ssl/certs/ca-certificates.crt" ]; then
        echo "🔐 SSL certificates detected - configuring environment..."
        echo 'export SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt' >> /home/vscode/.bashrc
        echo 'export REQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt' >> /home/vscode/.bashrc
        echo 'export NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-certificates.crt' >> /home/vscode/.bashrc
        echo 'export AWS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt' >> /home/vscode/.bashrc
        export SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
        export REQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt
        export NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-certificates.crt
        export AWS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt
        echo "✅ SSL environment variables configured"
    fi
fi

# STEP 2: Install Node.js and related tools AFTER certificates are set up (only if Claude is requested)
if [ "$INSTALL_CLAUDE" = true ]; then
    echo "📦 Installing Node.js and tools..."
    # Now use proper SSL verification since certificates are installed
    if [ "$NRCAN_NETWORK" = true ]; then
        curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash - >/dev/null 2>&1
    else
        curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash - >/dev/null 2>&1
    fi
    sudo apt-get install -y nodejs python3-pip >/dev/null 2>&1
    
    # Ensure pip/uv is available for the current user
    if command -v pip3 >/dev/null 2>&1; then
        pip3 install uv >/dev/null 2>&1
    elif command -v pip >/dev/null 2>&1; then
        pip install uv >/dev/null 2>&1
    else
        echo "⚠️  No pip found, trying python -m pip to install uv..."
        python3 -m pip install uv >/dev/null 2>&1 || python -m pip install uv >/dev/null 2>&1
    fi
    
    sudo apt-get update >/dev/null 2>&1
    echo "✅ Node.js and tools installed"
fi

# Set up Python virtual environment (check for various Python installations)
PYTHON_CMD=""
PYTHON_VENV_CREATED=false
if [ -f "/venv/bin/python" ]; then
    PYTHON_CMD="/venv/bin/python"
elif command -v python3 >/dev/null 2>&1; then
    PYTHON_CMD="python3"
elif command -v python >/dev/null 2>&1; then
    PYTHON_CMD="python"
fi

if [ -n "$PYTHON_CMD" ]; then
    echo "🐍 Setting up Python virtual environment using $PYTHON_CMD..."
    $PYTHON_CMD -m venv ./.venv
    PYTHON_VENV_CREATED=true
    echo "   ✅ Python virtual environment created"
    
    # Install Python packages from requirements.txt if it exists
    if [ -f "requirements.txt" ]; then
        echo "   📦 Installing Python packages from requirements.txt..."
        
        # Check for pip in the virtual environment first, then fall back to system pip
        PIP_CMD=""
        if [ -f "./.venv/bin/pip" ]; then
            PIP_CMD="./.venv/bin/pip"
        elif [ -f "./.venv/bin/pip3" ]; then
            PIP_CMD="./.venv/bin/pip3"
        elif command -v pip3 >/dev/null 2>&1; then
            PIP_CMD="pip3"
        elif command -v pip >/dev/null 2>&1; then
            PIP_CMD="pip"
        else
            echo "   ⚠️  No pip found, trying to install packages with python -m pip..."
            PIP_CMD="$PYTHON_CMD -m pip"
        fi
        
        echo "   📍 Using pip command: $PIP_CMD"
        $PIP_CMD install -r requirements.txt
        echo "   ✅ Python packages installed"
    else
        echo "   ℹ️  No requirements.txt found, skipping Python package installation"
    fi
else
    echo "⚠️  No Python installation found, skipping Python virtual environment setup"
fi

# Set up Ruby bundle (only if Ruby and Gemfile.lock exist)
RUBY_BUNDLE_INSTALLED=false
if command -v ruby >/dev/null 2>&1; then
    if [ -f "Gemfile.lock.$OPENSTUDIO_VERSION" ]; then
        echo "💎 Setting up Ruby bundle..."
        cp Gemfile.lock.$OPENSTUDIO_VERSION Gemfile.lock
        bundle config set path "./vendor/bundle" >/dev/null 2>&1
        bundle install >/dev/null 2>&1
        RUBY_BUNDLE_INSTALLED=true
        echo "   ✅ Ruby bundle installed"
    else
        echo "   ⚠️  Gemfile.lock.$OPENSTUDIO_VERSION not found, skipping Ruby bundle setup"
    fi
else
    echo "⚠️  Ruby not found, skipping Ruby bundle setup"
fi

echo "🔑 Setting up AWS credentials..."
AWS_MOUNTED=false

# Check if AWS credentials were mounted into the container
if [ -d "/home/vscode/.aws" ] && [ "$(ls -A /home/vscode/.aws 2>/dev/null)" ]; then
    echo "✅ AWS credentials found and mounted from host"
    AWS_MOUNTED=true
    
    # Test if AWS credentials actually work
    if aws sts get-caller-identity >/dev/null 2>&1; then
        echo "   ✅ AWS credentials are valid and working"
        AWS_ACCOUNT=$(aws sts get-caller-identity --query 'Account' --output text 2>/dev/null)
        AWS_USER=$(aws sts get-caller-identity --query 'Arn' --output text 2>/dev/null | rev | cut -d'/' -f1 | rev)
        AWS_REGION=$(aws configure get region 2>/dev/null || echo "not-set")
        if [ -n "$AWS_ACCOUNT" ]; then
            echo "   📍 Connected to AWS Account: $AWS_ACCOUNT"
            echo "   👤 User: $AWS_USER"
            echo "   🌍 Region: $AWS_REGION"
        fi
    else
        echo "   ⚠️  AWS credentials found but not working - check your configuration, perhaps you need to refresh your aws credentials on your host machine?"
        AWS_MOUNTED=false
    fi
else
    echo "⚠️  No AWS credentials found. AWS credentials should be available at ~/.aws on the host system. If you are not using aws ignore this message."
fi

# Set up standalone MCP servers that both Claude and VS Code can use
echo "🔧 Setting up standalone MCP servers..."

# Create .vscode directory if it doesn't exist
mkdir -p .vscode

# Create VS Code MCP configuration
echo "   📝 Creating VS Code MCP configuration..."
cat > .vscode/mcp.json << 'EOF'
{
  "servers": {
    "serena": {
      "type": "stdio",
      "command": "uv",
      "args": ["tool", "run", "--python", "3.12", "--from", "git+https://github.com/oraios/serena", "serena", "start-mcp-server", "--context", "ide-assistant", "--project", "."]
    }
  }
}
EOF

# Install Claude if requested and configure it to use the same MCP servers
if [ "$INSTALL_CLAUDE" = true ]; then
    echo "   🤖 Installing Claude Code..."
    if curl -fsSL https://claude.ai/install.sh | bash; then
        echo "   ✅ Claude Code installed successfully"
    else
        echo "   ⚠️  Claude Code installation failed - you may need to install it manually"
    fi
    
    echo "   🔗 Configuring Claude to use standalone MCP servers..."
    # Configure Claude to use the same Serena MCP server (ignore if already exists)
    if claude mcp add serena -- uv tool run --python 3.12 --from git+https://github.com/oraios/serena serena start-mcp-server --context ide-assistant --project "$(pwd)" 2>/dev/null; then
        echo "   ✅ Serena MCP server added to Claude"
    else
        echo "   ℹ️  Serena MCP server already exists in Claude configuration"
    fi
    echo "   ✅ Claude and standalone MCP servers configured"
fi

# Add AWS MCP server to both VS Code and Claude if AWS credentials are available
if [ "$AWS_MOUNTED" = true ]; then
    echo "☁️ Setting up AWS MCP server..."
    
    # Add AWS server to VS Code configuration
    echo "   📝 Adding AWS MCP server to VS Code configuration..."
    # Update the VS Code mcp.json to include AWS server
    cat > .vscode/mcp.json << 'EOF'
{
  "servers": {
    "serena": {
      "type": "stdio",
      "command": "uv",
      "args": ["tool", "run", "--python", "3.12", "--from", "git+https://github.com/oraios/serena", "serena", "start-mcp-server", "--context", "ide-assistant", "--project", "."]
    },
    "awslabs-ccapi-mcp-server": {
      "type": "stdio",
      "command": "uv",
      "args": ["tool", "run", "--python", "3.12", "--from", "awslabs.ccapi-mcp-server@latest", "awslabs.ccapi-mcp-server", "--readonly"],
      "env": {
        "DEFAULT_TAGS": "enabled",
        "SECURITY_SCANNING": "enabled",
        "FASTMCP_LOG_LEVEL": "ERROR"
      }
    }
  }
}
EOF
    echo "   ✅ AWS MCP server added to VS Code configuration"
    
    # Add AWS server to Claude if Claude is installed
    if [ "$INSTALL_CLAUDE" = true ]; then
        echo "   🔗 Adding AWS MCP server to Claude configuration..."
        if claude mcp add awslabs-ccapi-mcp-server \
          -e DEFAULT_TAGS=enabled \
          -e SECURITY_SCANNING=enabled \
          -e FASTMCP_LOG_LEVEL=ERROR \
          -- uv tool run --python 3.12 --from awslabs.ccapi-mcp-server@latest awslabs.ccapi-mcp-server --readonly 2>/dev/null; then
            echo "   ✅ AWS MCP server added to Claude configuration"
        else
            echo "   ℹ️  AWS MCP server already exists in Claude configuration"
        fi
    fi
    
    echo "   🎯 AWS MCP server configured for both VS Code and Claude"
else
    echo "ℹ️  AWS credentials not found, skipping AWS MCP server setup"
fi

echo "🎉 Devcontainer setup complete!"

echo "📝 You can now use:"
echo "   - VS Code with standalone MCP servers (Serena for code analysis)"
if [ "$AWS_MOUNTED" = true ]; then
    echo "   - VS Code with AWS MCP server for AWS resource management"
fi
echo "   - GitHub Copilot for code completion"
if [ "$PYTHON_VENV_CREATED" = true ]; then
    echo "   - Python virtual environment at ./.venv"
fi
if [ "$RUBY_BUNDLE_INSTALLED" = true ]; then
    echo "   - Ruby gems in ./vendor/bundle"
fi
echo ""
echo "🔧 MCP Configuration:"
echo "   - VS Code MCP config: .vscode/mcp.json"
if [ "$INSTALL_CLAUDE" = true ]; then
    echo "   - Claude Desktop/Code with the same MCP servers"
    echo "   - Both VS Code and Claude use the same MCP servers independently"
    echo "   - No need to keep Claude open for MCP servers to work in VS Code"
else
    echo "   - MCP servers work independently in VS Code"
    echo "   - Run with --claude to also add Claude Desktop support"
fi