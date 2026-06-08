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

### Version Management
- `./unixBin/setGitAliases.sh` - Sets up all git aliases (includes versioning)
- `git rel-patch` - Trigger patch version release pipeline
- `git rel-minor` - Trigger minor version release pipeline
- `git rel-major` - Trigger major version release pipeline

### Claude Environment Setup
- `./unixBin/setClaudeEnv.sh` - Set up centralized Claude environment with git-controlled commands, configs, templates, workspaces, skills, and global CLAUDE.md
- `./unixBin/resetClaudeEnv.sh` - Reset Claude environment to original state
- **Commands**: `unixBin/env/claude/commands/` → `~/.claude/commands` (symlinked)
- **Templates**: `unixBin/env/claude/templates/` → `~/.claude/templates` (symlinked) 
- **Workspaces**: `unixBin/env/claude/workspaces/` → `~/.claude/workspaces` (symlinked)
- **Skills**: `unixBin/env/claude/skills/` → `~/.claude/skills` (symlinked)
- **Global CLAUDE.md**: `unixBin/env/claude/CLAUDE.md` → `~/.claude/CLAUDE.md` (symlinked)
- **Config**: `unixBin/env/claude/config/*.template.*` → `~/.claude/config/*.json` (generated with env vars)

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

**Version Management:**
- `VERSION` file tracks current version in semantic versioning format (major.minor.patch)
- `.github/workflows/pipeline.yml` - GitHub Actions workflow for testing and releases
- `.github/scripts/handle_release_tags.sh` - Release tag handler (used by pipeline only)
- `.github/scripts/AgentInfo.sh` - Runner information script

**Shell Environment:**
- Supports bash and zsh shells
- Modular environment configuration with linking system (`LINK_*.env` → `XXX_*.env`)
- oh-my-posh themes for terminal customization
- Comprehensive alias definitions

**Claude Environment Management:**
- `unixBin/env/claude/commands/` - Git-controlled Claude commands directory (symlinked)
- `unixBin/env/claude/templates/` - Git-controlled code templates and snippets (symlinked)
- `unixBin/env/claude/workspaces/` - Git-controlled workspace configurations (symlinked)
- `unixBin/env/claude/skills/` - Git-controlled Claude skills directory (symlinked)
- `unixBin/env/claude/CLAUDE.md` - Git-controlled user-global Claude instructions (symlinked)
- `unixBin/env/claude/config/` - Template configuration files with environment variable placeholders
- `unixBin/setClaudeEnv.sh` - Setup script for centralized environment management
- `unixBin/resetClaudeEnv.sh` - Reset script to restore original environment

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
- `VERSION` - Current version number in semantic versioning format
- `.github/scripts/` - Pipeline scripts (release handling, agent info)
- `.github/workflows/pipeline.yml` - GitHub Actions workflow for testing and releases

## Development Notes

- The system supports both macOS (homebrew) and Linux (apt) package managers
- Environment variables are defined in `unixBin/env/001_vars.env`
- Color definitions are in `unixBin/env/000_colors.env`
- The installation system uses JSON parsing with `jq` for configuration processing
- Trace logging is available with different levels (TRACE_NONE to TRACE_ALL)

## Claude Environment Setup

The repository provides comprehensive centralized management for Claude development environment through a git-controlled system:

### Extended Environment Components

**Commands** (`~/.claude/commands/`)
- Git-controlled command definitions and workflows
- Symlinked from `unixBin/env/claude/commands/`
- Preserved and merged during setup

**Templates** (`~/.claude/templates/`)
- Code templates and project scaffolding
- React components, Express routes, Docker setups, GitHub Actions
- ABK bash script templates with proper structure
- Symlinked from `unixBin/env/claude/templates/`

**Workspaces** (`~/.claude/workspaces/`)
- Multi-project configuration definitions
- Full-stack web app, microservices, DevOps stacks
- Project relationships and shared configurations
- Symlinked from `unixBin/env/claude/workspaces/`

**Skills** (`~/.claude/skills/`)
- Git-controlled skill packages (each skill is a subdirectory containing `SKILL.md`)
- Symlinked from `unixBin/env/claude/skills/`
- Preserved and merged during setup

**Configuration** (`~/.claude/config/`)
- Secure configuration with environment variable substitution
- API keys loaded from environment variables or password managers
- MCP server configurations, Claude settings, project preferences
- Generated from templates in `unixBin/env/claude/config/`

### Setup Process
1. **Run Setup**: `./unixBin/setClaudeEnv.sh`
   - **Prerequisites**: Installs required tools (`rsync`, `envsubst`)
   - **Subdirectories**: For each of `commands`, `templates`, `workspaces`, `skills`:
     - If `~/.claude/<subdir>/` is a real directory, any files not already in the git repo are merged in (git repo wins on conflicts), then the original is removed
     - A symlink is created from `~/.claude/<subdir>` → `unixBin/env/claude/<subdir>/`
   - **Global CLAUDE.md**: `~/.claude/CLAUDE.md` is symlinked to `unixBin/env/claude/CLAUDE.md`. On first setup, if a local file exists and the git copy does not, the local file is copied into the repo to preserve user content
   - **Configuration**: Processes `*.template.*` files with `envsubst` to generate secure config files in `~/.claude/config/` (no symlink — secrets stay outside the git repo)

### Reset Process
1. **Run Reset**: `./unixBin/resetClaudeEnv.sh`
   - **Cleanup Order**: Removes the CLAUDE.md, skills, workspaces, templates, and commands symlinks (reverse of setup order)
   - **Symlinks Only**: Each symlink is removed; the git-controlled files at `unixBin/env/claude/` are never touched
   - **User Data Preserved**: If `~/.claude/<subdir>/` or `~/.claude/CLAUDE.md` exists as a real file/directory (not a symlink), it is left alone
   - **Config Security**: Only files generated from `*.template.*` are removed from `~/.claude/config/`; anything you added by hand is preserved

### Replicating This Environment On A New Machine

Everything that lives in `unixBin/env/claude/` (commands, templates, workspaces, skills, global `CLAUDE.md`) follows you to any new Mac by cloning this repo and running `setClaudeEnv.sh`.

**Steps:**

1. **Install Homebrew** (Apple's prerequisite for everything else):
   ```bash
   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
   ```

2. **Clone this repo** to its expected location:
   ```bash
   mkdir -p ~/dev/git && cd ~/dev/git
   git clone <your-abk_env-remote-url> abk_env
   cd abk_env
   ```

3. **Install Claude and the AI tool set** (also installs `cline`, `kilocode`, Claude Desktop, Wispr Flow):
   ```bash
   ./install.sh tools_ai.json
   ```

4. **Export the environment variables that the config templates expect**, in your `~/.zshrc` or via a password manager such as `pass`:
   ```bash
   export ANTHROPIC_API_KEY=...
   export OPENAI_API_KEY=...          # optional
   export GITHUB_TOKEN=...
   export POSTGRES_CONNECTION_STRING=...  # optional, for MCP postgres
   export BRAVE_API_KEY=...               # optional, for MCP brave search
   export TESTING_FRAMEWORK=...           # optional, populates claude-settings.json
   export FRONTEND_FRAMEWORK=...          # optional
   export BACKEND_FRAMEWORK=...           # optional
   export DATABASE_TYPE=...               # optional
   export GIT_BRANCH_PATTERN=...          # optional
   export DEV_ENVIRONMENT=...             # optional
   ```
   Missing variables become empty strings in the generated config — not a fatal error.

5. **Wire up the symlinks**:
   ```bash
   ./unixBin/setClaudeEnv.sh
   ```
   This creates the five symlinks (`commands`, `templates`, `workspaces`, `skills`, `CLAUDE.md` → git repo) and generates `~/.claude/config/*.json` from templates with mode `600`.

After step 5: all your git-tracked slash commands, code templates, workspace defs, skills, and global Claude instructions are live on the new machine.

**What does NOT transfer (not in this repo):**

| Item | Why | What to do |
|---|---|---|
| `~/.claude/settings.json` | Per-machine harness config | Copy from old Mac, or let `/config` recreate |
| `~/.claude/plugins/` | Installed via `/plugins` | Reinstall via `/plugins` on new machine |
| `~/.claude/projects/`, `sessions/`, `history.jsonl` | Per-machine conversation/history state | Skip — fresh start is fine |
| `~/.claude/backups/`, `cache/`, `file-history/`, `paste-cache/`, `shell-snapshots/` | Caches | Skip — regenerated on demand |
| `mcp-needs-auth-cache.json` and MCP OAuth tokens | Per-machine auth state | Re-authenticate each MCP server |

### Security Model
- **Templates Only in Git**: Only `.template.*` files are version controlled
- **Environment Variables**: Secrets loaded from `$ANTHROPIC_API_KEY`, `$(pass dev/api/key)`, etc.
- **Generated Configs**: Local config files have restrictive permissions (600)
- **No Secrets in Git**: API keys and secrets never committed to repository

### Configuration Templates

**API Configuration** (`api-config.template.json`)
```json
{
  "anthropic": {
    "apiKey": "${ANTHROPIC_API_KEY}",
    "endpoint": "https://api.anthropic.com/v1"
  },
  "github": {
    "token": "${GITHUB_TOKEN}"
  }
}
```

**MCP Servers** (`mcp-servers.template.json`)
```json
{
  "mcpServers": {
    "filesystem": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-filesystem", "/tmp"]
    },
    "postgres": {
      "env": {
        "POSTGRES_CONNECTION_STRING": "${POSTGRES_CONNECTION_STRING}"
      }
    }
  }
}
```

### Available Templates

**Code Templates**:
- `react-component.tsx` - TypeScript React component with props interface
- `express-route.js` - Express.js API endpoint with error handling
- `abk-script.sh` - ABK-style bash script with proper structure
- `package-json.template` - Node.js package.json with common dependencies
- `github-actions-node.yml` - CI/CD workflow for Node.js projects

**Infrastructure Templates**:
- `docker-setup/` - Dockerfile and docker-compose configurations
- Docker security best practices with non-root users

**Workspace Configurations**:
- `webapp-stack.json` - Full-stack web application (frontend/backend/database)
- `microservices.json` - Microservices architecture with API gateway
- `devops-stack.json` - DevOps tools (Terraform, Kubernetes, Ansible, monitoring)

### Benefits
- **Version Control**: All development patterns and configurations in git
- **Security**: Secrets managed through environment variables and password managers
- **Consistency**: Standardized project structures and configurations across machines
- **Non-Destructive**: Existing Claude setup preserved and merged
- **Reversible**: Complete restoration to original state
- **Cross-Machine**: Easy replication of entire development environment
- **Team Sharing**: Git-controlled templates and workspaces for team consistency

## Shell Integration

The system integrates with shell configuration by:
- Adding source commands to `.bashrc`/`.zshrc`
- Creating `~/bin` symlink to `unixBin/` directory
- Setting up environment variables and aliases
- Configuring oh-my-posh for terminal theming

## Version Management Workflow

The repository uses semantic versioning (major.minor.patch) with automated release management:

1. **Trigger Release**: Use `git rel-patch`, `git rel-minor`, or `git rel-major`
2. **Automated Pipeline Process**:
   - Git aliases push temporary tag (`rel-patch`, `rel-minor`, `rel-major`)
   - GitHub Actions detects tag and triggers testing pipeline
   - **Runs installation tests** on macOS (13, 14, 15) and Ubuntu (22.04, 24.04)
   - Tests both bash and zsh shells with install/uninstall validation
   - **If tests pass**: `handle_release_tags.sh` bumps version, updates `VERSION` file
   - Commits version change to main branch
   - Creates final version tag (e.g., `v1.0.1`)
   - Cleans up temporary trigger tag
   - **If tests fail**: No release is created, temporary tags are cleaned up
3. **Setup**: Run `./unixBin/setGitAliases.sh` to configure git aliases

**Release Types:**
- **Patch** (x.y.Z): Bug fixes, minor improvements
- **Minor** (x.Y.0): New features, backward-compatible changes
- **Major** (X.0.0): Breaking changes, major features
