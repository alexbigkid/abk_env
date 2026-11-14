# README: abk_env repo ![Tests](https://github.com/alexbigkid/abk_env/actions/workflows/pipeline.yml/badge.svg)
ABK tool environment setup for developers

[TOC]


## What is this repository for?

* Quick automated install of required developer tools, apps and fonts
* Easy updates
* Easy user friendly prompt config
* Useful aliases
* using YubiKey for setting up security (SSH/GPG)
* Private/Company wide pass manager


## Design
Check, install and uninstall instructions are configured in json files

### life cycle of installed tools
```mermaid
flowchart LR
    %% Define styles
    classDef jsonStyle fill:#e3f2fd,stroke:#2196f3,stroke-width:2,color:#0d47a1;
    classDef installStyle fill:#e8f5e9,stroke:#4caf50,stroke-width:2,color:#1b5e20;
    classDef procStyle fill:#fffde7,stroke:#fbc02d,stroke-width:2,stroke-dasharray: 5, color:#f57f17;
    classDef uninstallStyle fill:#fff3e0,stroke:#ff9800,stroke-width:2,color:#e65100;
    classDef testStyle fill:#fce4ec,stroke:#e91e63,stroke-width:2,color:#880e4f;

    %% Define nodes
    json_files("📁 <b>JSON files</b><br/>tools_abk.json<br/>tools_node.json<br/>tools_python.json<br/>tools_work.json")
    install("📦 <b>install.sh</b>")
    installed("🗂️ <b>Uninstall instructions</b><br/>for installed tools<br/>in <b>unixPackages</b> dir")
    uninstall("🧹 <b>uninstall.sh</b>")

    %% Apply styles
    class json_files jsonStyle
    class install installStyle
    class installed procStyle
    class uninstall uninstallStyle

    %% Define edges
    json_files --> install
    install --> installed
    installed --> uninstall
```


## Support for
### OS supported
- [x] MacOS
  - [ ] 11 - Big Sur - could work, not tested
  - [ ] 12 - Monterey - could work, not tested
  - [x] 13 - Ventura
  - [x] 14 - Sonoma
  - [x] 15 - Sequoia
  - [x] 26 - Tahoe
  - [x] 27 - Golden Gate
- [x] Linux / Debian distro
  - [x] 11 - bullseye
  - [x] 12 - bookworm
- [x] Linux / Ubuntu distro
  - [ ] 20.04 - support removed
  - [x] 22.04
  - [x] 24.04
  - [x] 26.04
- [x] Linux / Raspbian distro
  - [x] 11 - bullseye
  - [x] 12 - bookworm
- [ ] Windows

### Shells supported
- [x] /bin/bash
- [ ] /bin/csh
- [ ] /bin/ksh
- [ ] /bin/sh
- [ ] /bin/tcsh
- [x] /bin/zsh

### What shell are you currently using?
To determine what shell is currently used in your environment, run following command in your terminal:
```shell
echo $SHELL
```
<b>MacOS users:</b> macOS switched the default shell from <code>bash</code> to <code>zsh</code> with the release of macOS Catalina (version 10.15). If you are still using <code>bash</code>, recommendation is to switch to <code>zsh</code>, since <code>bash</code> is not being updated on MacOS. To change shell:
```shell
chsh -s /bin/zsh
```
<b>Linux users:</b> <code>zsh</code> or <code>bash</code> ... what ever floats your boat :)

****
## Pre-requisites
### MacOS
- [x] <b>pre-installed [homebrew](https://brew.sh/) tool:</b> brew is a command line tool to install apps and tools on MacOS. To install brew, run and follow prompt requests:
```shell
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

### Linux

There are no pre-requisites for Linux. We will use <code>apt</code> tool to install packages. There is home brew for Linux, called [Linuxbrew](https://docs.brew.sh/Homebrew-on-Linux), but the installation packages are not widely available yet.


## Install

* <i><b>If you installed my previous version of ABK environment from [abkEnv](https://github.com/alexbigkid/abkEnv), please de-install it first by executing uninstall script:</b></i> <code>./uninstall.sh</code>
* For [simple minimal](https://github.com/alexbigkid/abk_env/blob/main/tools_min.json) installation: <code>./install.sh</code>
* For [python tools](https://github.com/alexbigkid/abk_env/blob/main/tools_python.json) installation: <code>./install.sh tools_python.json</code>
* For [node tools](https://github.com/alexbigkid/abk_env/blob/main/tools_node.json) installation: <code>./install.sh tools_node.json</code>
* For [my favorite tools](https://github.com/alexbigkid/abk_env/blob/main/tools_abk.json) installation: <code>./install.sh tools_abk.json</code>
* Note that you can install with several packages. E.g.: <code>./install.sh tools_node.json tools_python.json</code>. Tools which has been already installed won't be installed again.
* See table below for full list of installation sets. You can also create your own set (json files) if like. but be aware that there are 3 sections: check, install and uninstall
* The installation might require your password few times in order to install graphical apps.
* After installation script runs through, it records what tools has been installed for later clean de-installation. See files in the dir: <code>unixPackages</code>




### Available installation packages

For you convenience I prepared few installation packages listed below:

| package                                                                                | description                                                           |
| :------------------------------------------------------------------------------------- | :-------------------------------------------------------------------- |
| [tools_abk.json](https://github.com/alexbigkid/abk_env/blob/main/tools_abk.json)       | my favorite tools collection - mostly for development                 |
| [tools_max.json](https://github.com/alexbigkid/abk_env/blob/main/tools_max.json)       | maximal installation - all tools, I found useful                      |
| [tools_min.json](https://github.com/alexbigkid/abk_env/blob/main/tools_min.json)       | minimal installation - but installs brave-browser and flycut on MacOS |
| [tools_node.json](https://github.com/alexbigkid/abk_env/blob/main/tools_node.json)     | node tools installation - for node development                        |
| [tools_python.json](https://github.com/alexbigkid/abk_env/blob/main/tools_python.json) | python tools installation - for python development                    |
| [tools_work.json](https://github.com/alexbigkid/abk_env/blob/main/tools_work.json)     | work specific tools installation                                      |
| [test_001.json](https://github.com/alexbigkid/abk_env/blob/main/test_001.json)         | test 001 installation - small set of tools for testing purpose        |
| [test_002.json](https://github.com/alexbigkid/abk_env/blob/main/test_002.json)         | test 002 installation - small set of tools for testing purpose        |
| [test_003.json](https://github.com/alexbigkid/abk_env/blob/main/test_003.json)         | test 003 installation - small set of tools for testing purpose        |
| [test_004.json](https://github.com/alexbigkid/abk_env/blob/main/test_004.json)         | test 004 installation - small set of tools for testing purpose        |


### Example of tools installed

| tool                                                                            | description                                                                                                   |
| :------------------------------------------------------------------------------ | :------------------------------------------------------------------------------------------------------------ |
| [awscli](https://github.com/alexbigkid/abk_env/blob/main/tools_min.json)        | provides a unified command line interface to Amazon Web Services                                              |
| [direnv](https://github.com/direnv/direnv)                                      | can load and unload env variables depending on the current project directory                                  |
| [git](https://github.com/git/git)                                               | Newest version of git                                                                                         |
| [gnuPG](https://github.com/gpg/gnupg)                                           | Gnu Privacy Guard: tool to create and maintain GPG keys                                                       |
| [jq](https://github.com/jqlang/jq)                                              | is a lightweight and flexible command-line JSON processor                                                     |
| [nmap](https://nmap.org/)                                                       | network scanner to discover hosts and services on a computer network                                          |
| [nodenv](https://github.com/nodenv/nodenv)                                      | lets you easily switch between multiple versions of nodejs                                                    |
| [oh-my-posh](https://ohmyposh.dev/)                                             | lets you easiliy configure your terminal prompt                                                               |
| [parallel](https://github.com/flesler/parallel)                                 | CLI tool to execute shell commands in parallel                                                                |
| [pass](https://www.passwordstore.org)                                           | password manager, which works well with <code>direnv</code> tool                                              |
| [ruff](https://github.com/astral-sh/ruff)                                       | python code linter                                                                                            |
| [serverless](https://www.serverless.com/framework/docs)                         | lets you deploy serverless infrastructure services to AWS                                                     |
| [tfenv](https://github.com/tfutils/tfenv)                                       | lets you easily switch between multiple versions of Terraform                                                 |
| [tree](https://linuxhandbook.com/tree-command/)                                 | lists files in tree from                                                                                      |
| [uv](https://github.com/astral-sh/uv)                                           | Fast Python package manager. Can replace: <code>pip, pip-tools, pipx, poetry, pyenv, twine, virtualenv</code> |
| [wget](https://linuxize.com/post/wget-command-examples/)                        | utility for downloading files from the web                                                                    |
| [yq](https://github.com/mikefarah/yq)                                           | is a lightweight and flexible command-line YAML, JSON and XML processor                                       |
| [zsh-autocomplete](https://github.com/marlonrichert/zsh-autocomplete)           | Autocomplete for Zsh adds real-time type-ahead autocompletion to Zsh                                          |
| [zsh-autosuggestions](https://github.com/zsh-users/zsh-autosuggestions)         | Autosuggestions for Zsh adds autosuggestions below prompt, which can be selected                              |
| [zsh-syntax-highlighting](https://github.com/zsh-users/zsh-syntax-highlighting) | syntax highlighting for the shell zsh Zsh                                                                     |


### Example of MacOS apps installed

| tool                                                               | description                                                   |
| :----------------------------------------------------------------- | :------------------------------------------------------------ |
| [brave-browser](https://github.com/brave/brave-browser)            | Secure, fast Web browser based on Chromium just like Chrome   |
| [docker](https://github.com/docker)                                | Docker helps developers to abstract virtual environments      |
| [flycut](https://github.com/TermiT/Flycut)                         | Flycut is a clean and simple clipboard manager for developers |
| [onedrive](https://www.microsoft.com/en-us/microsoft-365/onedrive) | Company's online storage.                                     |
| [visual-studio-code](https://github.com/microsoft/vscode)          | The best code editor ever :)                                  |


### Fonts installed
Those font are useful for coding and for oh-my-posh

* font-agave-nerd-font
* font-comic-shanns-mono-nerd-font
* font-droid-sans-mono-nerd-font"
* font-cascadia-code
* font-cascadia-code-pl
* font-caskaydia-cove-nerd-font
* font-hack-nerd-font


## oh-my-posh configuration
* open terminal app
* click on Terminal / Settings (on MacOS: Press <code>&#x2318; + ,</code>)
* click in the bottom left corner on a circle with 3 dots and import
* Navigate to repo directory and then to: <code>unixBin/env/terminal/profiles</code>
* Select <code>Solarized Dark.terminal</code>
* Select the Profile just added and the click on <code>Default</code> in the bottom left corner

There is a pre-configured theme located in folder <code>./unixBin/env/omp/themes</code>. There are many other predefined themes. You can activate them in the file: <code>./unixBin/env/XXX_oh-my-posh.env</code> Default is configured for ABK customized prompt: <code>./unixBin/env/omp/themes/powerlevel10k_abk.omp.json</code>, which looks like this:
![powerlevel10k_abk](./unixBin/env/omp/themes/powerlevel10k_abk.png "pl10k_abk")

If you like to create your own theme please follow: [oh-my-posh documentation](https://ohmyposh.dev/docs).

* Note 1: if you don't see correct symbols in the prompt, please use font which is capable to display glyphs (symbols) in your terminal app settings. A good font example: Hack Nerd Font
* Note 2: The default oh-my-posh theme is based on dark background terminal app profile. It might not look great if you use theme with bright background.


## Aliases
Don't forget to check out many aliases configured in <code>./unixBin/env/002_aliases.env</code> and <code>./unixBin/env/002_abk_aliases.env</code>. YOu can put your own aliases into <code>./unixBin/env/aliases_user.env</code> Here are few good examples:

| alias                          | description                                                   |
| :----------------------------- | :------------------------------------------------------------ |
| <code>epoch</code>             | copies current epoch time into clipboard                      |
| <code>getAwsAccount</code>     | copies currently configured AWS account number into clipboard |
| <code>glrt</code>              | Git List Remote Tags                                          |
| <code>dpps</code>              | Display Python Package Size                                   |
| <code>ncpu</code>              | Number of CPUs                                                |
| <code>ppp</code>               | Pretty Print PATH                                             |
| <code>pppp</code>              | Pretty Print PYTHONPATH                                       |
| <code>prg</code>               | git push - Push it Real Good - when deploying new release     |
| <code>snp</code>               | git push - Salt 'N Pepper version                             |
| <code>brew_update</code>       | MacOS users: updates all tools managed by brew                |
| <code>brew_update_casks</code> | MacOS users: updates all graphical apps managed by brew       |
| <code>brew_update_all</code>   | MacOS users: updates tools and apps managed by brew           |
| <code>apt_update</code>        | Linux users: updates all tools managed by apt                 |


## Update
To update your tools you could use the alias:
* <code>brew_update</code>> - (MacOS) to update all brew installed tools
* <code>brew_update_casks</code>> - (MacOS) to update all brew installed graphical apps
* <code>brew_update_all</code> - (MacOS) update both tools and graphical apps
* <code>apt_update</code> - (Linux) updates all tools managed by apt


## Uninstall
If at some point you'd like to uninstall installed packages, you can run <code>./uninstall.sh</code>. Here few examples:
* <code>./uninstall.sh tools_node.json</code> - will uninstall all node packages. Since it was recorded what tools have been installed only the packages which has been previously installed with <code>tools_node.json</code> will be uninstalled.
* <code>./uninstall.sh tools_min.json</code> - uninstalls packages previously has installed with <code>tools_min.json</code>
* <code>./uninstall.sh tools_min.json tools_node.json</code> - uninstalls packages previously has installed with <code>tools_min.json</code> and <code>tools_node.json</code>


## Software GPG key
Run <code>./unixBin/setSwGpg.sh</code> to create a GPG key stored on this computer only (no YubiKey). Requires <code>gpg</code>, <code>gpg-agent</code> and <code>expect</code>.

* Master key: Ed25519, certify-only. Subkeys: sign, encrypt, auth (usable for SSH). All expire in 2 years.
* Name and email come from <code>GIT_USER_NAME</code>/<code>GIT_USER_EMAIL</code>, or from your git config.
* Backups go to <code>~/.gnupg-backup/</code>: master secret and public key, subkeys, revocation certificate and a <code>README-IMPORTANT-&lt;fingerprint&gt;.txt</code> with recovery and rotation steps.
* <b>The keys have no passphrase.</b> Anyone who gets these files can use the key.
* The new key is found by its exact fingerprint, so existing keys with the same email are left alone.
* It does not set up git signing, gpg-agent or SSH to use the key.

<b>The master key is not removed by the script.</b> Once the backups are safe, do it manually (the script prints these commands with your fingerprint):
```shell
ls -laR ~/.gnupg-backup/                                   # 1. verify backups
# 2. copy ~/.gnupg-backup to offline media (USB drive, paper)
gpg --delete-secret-keys <FP>                              # 3. removes master + subkeys
gpg --import ~/.gnupg-backup/subkeys/<FP>-subkeys.asc      # 4. re-import subkeys only
gpg --list-secret-keys <FP>                                # 5. master must show as 'sec#'
rm -P ~/.gnupg-backup/master-key/<FP>-master-key.asc       # 6. remove master from disk (Linux: shred -u)
```


## Git aliases
Run <code>./unixBin/setGitAliases.sh</code> to put the same git aliases on every machine. It writes them to your global git config (<code>~/.gitconfig</code>), overwriting aliases with the same names, and is safe to re-run. List them with <code>git alias</code>.

| alias                                                       | description                                                        |
| :---------------------------------------------------------- | :----------------------------------------------------------------- |
| <code>st</code>, <code>co</code>, <code>ci</code>, <code>br</code>, <code>cob</code> | status, checkout, commit, branch, checkout -b             |
| <code>hist</code>, <code>logg</code>, <code>last</code>     | compact graph logs, last commit                                    |
| <code>today</code>, <code>yesterday</code>, <code>sinceYesterday</code> | commits in that time window                            |
| <code>sinceDate "2026-11-01"</code>                         | commits since the given date                                       |
| <code>dbr &lt;branch&gt;</code>                             | switch to main, delete the branch locally and on origin            |
| <code>staged</code>, <code>unstaged</code>, <code>untracked</code>, <code>ignored</code> | list files in that state                  |
| <code>unstage</code>, <code>rtl</code>                      | unstage files, hard reset to HEAD                                  |
| <code>adt</code>/<code>rdt</code>, <code>aqt</code>/<code>rqt</code>, <code>art</code>/<code>rrt</code> | add/remove the dev, qa, release tag (local + origin) |
| <code>rel-patch</code>, <code>rel-minor</code>, <code>rel-major</code> | trigger a release (see [Releases](#releases))           |

It also sets <code>diff-so-fancy</code> as the git pager when it is installed.

### Releases
On <code>main</code>, run <code>git rel-patch</code>, <code>git rel-minor</code> or <code>git rel-major</code>. The alias pulls, pushes and pushes a temporary <code>rel-*</code> tag. GitHub Actions then runs the install/uninstall tests on macOS and Ubuntu; if they pass, it bumps <code>VERSION</code>, commits it and creates the <code>vX.Y.Z</code> tag. If they fail, no release is made.


## Claude Code environment
Centralized Claude Code configuration for all your computers. The settings live in this repo under <code>unixBin/env/claude/</code> and are linked into <code>~/.claude</code> on each machine.

* <code>./unixBin/setClaudeEnv.sh</code> - sets up <code>~/.claude</code> on this machine from the repo
* <code>./unixBin/resetClaudeEnv.sh</code> - undoes the setup (removes symlinks and generated config only)
* Run both from the repo root - paths are built from the current directory.
* Requires <code>claude</code> to be installed, e.g. with <code>./install.sh tools_ai.json</code>

What gets set up:

| in <code>~/.claude</code>                                | how                                                               |
| :------------------------------------------------------- | :---------------------------------------------------------------- |
| <code>commands</code>, <code>templates</code>, <code>workspaces</code>, <code>skills</code> | symlinked to <code>unixBin/env/claude/&lt;dir&gt;</code> |
| <code>CLAUDE.md</code>                                   | symlinked to <code>unixBin/env/claude/CLAUDE.md</code>            |
| <code>config/*.json</code>                               | generated from <code>config/*.template.*</code> with your env vars (mode 600) |

Things to know:
* Symlinks, not copies: edits made on any machine change the repo. Commit and pull to sync them to your other machines.
* On first run, existing local files are merged into the repo (repo wins on conflicts), so they may end up committed.
* Secrets stay on each machine: config files are built from local environment variables (e.g. <code>ANTHROPIC_API_KEY</code>, <code>GITHUB_TOKEN</code>) and never stored in git.
* Not covered: <code>~/.claude/settings.json</code>, plugins, MCP auth and history - set those up per machine.
* Reset does not bring back the original local files - they were merged into the repo during setup and are still there.

More details: see the "Claude Environment Setup" section in [CLAUDE.md](CLAUDE.md).


## Git branch rename from master to main
```shell
git branch -m master main
git fetch origin
git branch -u origin/main main
git remote set-head origin -a
```
