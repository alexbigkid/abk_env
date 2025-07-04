# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is `abk_env` - a developer environment setup repository that provides automated installation and management of development tools, applications, and shell configurations for macOS and Linux systems. The project uses JSON configuration files to define installation packages and bash scripts for installation/uninstallation logic.

## Common Development Commands

### Installation and Testing
- `./install.sh` - Install minimal tool set (uses `tools_min.json`)
- `./install.sh tools_abk.json` - Install ABK's favorite tools
- `./install.sh tools_python.json` - Install Python development tools
- `./install.sh tools_node.json` - Install Node.js development tools
- `./install.sh tools_work.json` - Install work-specific tools
- `./install.sh tools_mobile.json` - Install mobile development tools
- `./test_install.sh` - Run installation validation tests
- `./test_install.sh tools_` - Test specific package prefix

### Uninstallation
- `./uninstall.sh` - Uninstall minimal tool set
- `./uninstall.sh tools_abk.json` - Uninstall specific package
- `./test_uninstall.sh` - Test uninstallation process

### Validation
The `test_install.sh` script validates:
- Package installation files are created in `unixPackages/`
- Shell environment configuration is added to `.bashrc`/`.zshrc`
- Symbolic links are created properly in `unixBin/env/`

## Architecture

### Core Components

**Installation System:**
- `install.sh` - Main installation script that processes JSON tool definitions
- `uninstall.sh` - Handles removal of previously installed tools
- `unixBin/abkLib.sh` - Core library with shared functions for OS detection, package management, and environment setup
- `test_install.sh` - Validation script for installation testing

**Configuration Management:**
- JSON files (`tools_*.json`) define tool installation instructions per OS
- `unixBin/env/` - Contains environment configuration files and shell themes
- `unixPackages/` - Tracks installed packages for clean uninstallation

**Shell Environment:**
- Supports bash and zsh shells
- Modular environment configuration with linking system (`LINK_*.env` → `XXX_*.env`)
- oh-my-posh themes for terminal customization
- Comprehensive alias definitions

### JSON Configuration Structure

Each `tools_*.json` file contains platform-specific installation instructions:

```json
{
  "macOS": {
    "description": "Tool description",
    "supported_versions": { "macOS": ["13", "14", "15"] },
    "update_packages": ["brew update", "brew upgrade"],
    "tools": {
      "check": { "toolname": ["command -v toolname"] },
      "install": { "toolname": ["brew install toolname"] },
      "uninstall": { "toolname": ["brew uninstall toolname"] }
    },
    "apps": { /* GUI applications */ },
    "fonts": { /* Font installations */ }
  },
  "linux": { /* Linux-specific config */ }
}
```

### Installation Flow

1. **Validation** - Check OS compatibility and prerequisites
2. **Package Manager Update** - Update brew/apt repositories
3. **Tool Installation** - Install tools, apps, and fonts based on JSON config
4. **Environment Setup** - Configure shell environment and create symlinks
5. **Tracking** - Record installed packages in `unixPackages/` for future removal

### Key Files and Directories

- `tools_*.json` - Installation package definitions
- `unixBin/abkLib.sh` - Core library functions
- `unixBin/env/` - Environment configuration files
- `unixPackages/` - Tracks installed packages
- `tests/` - Platform-specific validation files

## Development Notes

- The system supports both macOS (homebrew) and Linux (apt) package managers
- Environment variables are defined in `unixBin/env/001_vars.env`
- Color definitions are in `unixBin/env/000_colors.env`
- The installation system uses JSON parsing with `jq` for configuration processing
- Trace logging is available with different levels (TRACE_NONE to TRACE_ALL)

## Shell Integration

The system integrates with shell configuration by:
- Adding source commands to `.bashrc`/`.zshrc`
- Creating `~/bin` symlink to `unixBin/` directory
- Setting up environment variables and aliases
- Configuring oh-my-posh for terminal theming