#!/bin/bash

echo "🤖 GitHub Actions Runner Information"
echo "======================================"

echo "📋 Runner Details:"
echo "  - Runner OS: $RUNNER_OS"
echo "  - Runner Architecture: $RUNNER_ARCH"
echo "  - Runner Name: $RUNNER_NAME"
echo "  - Runner Workspace: $RUNNER_WORKSPACE"

echo ""
echo "🔧 System Information:"
if [[ "$RUNNER_OS" == "macOS" ]]; then
    echo "  - macOS Version: $(sw_vers -productVersion)"
    echo "  - Build Version: $(sw_vers -buildVersion)"
    echo "  - Hardware: $(uname -m)"
elif [[ "$RUNNER_OS" == "Linux" ]]; then
    echo "  - Kernel: $(uname -r)"
    echo "  - Architecture: $(uname -m)"
    echo "  - Distribution: $(lsb_release -d 2>/dev/null | cut -f2 || echo "Unknown")"
fi

echo ""
echo "🐚 Shell Information:"
echo "  - Current Shell: $SHELL"
echo "  - Available Shells:"
cat /etc/shells | sed 's/^/    /'

echo ""
echo "🛠️ Tool Versions:"
echo "  - Git: $(git --version 2>/dev/null || echo "Not installed")"
echo "  - Bash: $(bash --version | head -1 2>/dev/null || echo "Not installed")"
echo "  - Zsh: $(zsh --version 2>/dev/null || echo "Not installed")"
echo "  - jq: $(jq --version 2>/dev/null || echo "Not installed")"

echo ""
echo "💾 Disk Space:"
if [[ "$RUNNER_OS" == "macOS" ]]; then
    df -h / | tail -1 | awk '{print "  - Available: " $4 " / " $2 " (" $5 " used)"}'
else
    df -h / | tail -1 | awk '{print "  - Available: " $4 " / " $2 " (" $5 " used)"}'
fi

echo ""
echo "🧠 Memory:"
if [[ "$RUNNER_OS" == "macOS" ]]; then
    echo "  - Total: $(sysctl -n hw.memsize | awk '{print int($1/1024/1024/1024) " GB"}')"
else
    echo "  - Total: $(free -h | grep '^Mem:' | awk '{print $2}')"
    echo "  - Available: $(free -h | grep '^Mem:' | awk '{print $7}')"
fi

echo ""
echo "======================================"