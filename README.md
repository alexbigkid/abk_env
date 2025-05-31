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


## Support for
### OS supported
- [x] MacOS
- [x] Linux / Debian distro
- [x] Linux / Ubuntu distro
- [x] Linux / Raspbian distro
- [ ] Windows

### Shells supported
- [x] /bin/bash
- [ ] /bin/csh
- [ ] /bin/ksh453945
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
| [pyenv](https://github.com/pyenv/pyenv)                                         | lets you easily switch between multiple versions of Python                                                    |
| [pyenv-virtualenv](https://github.com/pyenv/pyenv-virtualenv)                   | is a pyenv plugin, which manages virtualenvs for Python                                                       |
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

| tool                                                               | description                                                             |
| :----------------------------------------------------------------- | :---------------------------------------------------------------------- |
| [brave-browser](https://github.com/brave/brave-browser)            | Secure, fast Web browser based on Chromium just like Chrome             |
| [docker](https://github.com/docker)                                | Docker helps developers to abstract virtual environments                |
| [flycut](https://github.com/TermiT/Flycut)                         | Flycut is a clean and simple clipboard manager for developers           |
| [onedrive](https://www.microsoft.com/en-us/microsoft-365/onedrive) | Company's online storage.                                               |
| [visual-studio-code](https://github.com/microsoft/vscode)          | The best code editor ever :)                                            |


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
There is a pre-configured theme located in folder <code>./unixBin/env/omp/themes</code>. There are many other predefined themes. You can activate them in the file: <code>./unixBin/env/XXX_oh-my-posh.env</code> Default is configured for ABK customized prompt: <code>./unixBin/env/omp/themes/powerlevel10k_abk.omp.json</code>, which looks like this:
![powerlevel10k_abk](./unixBin/env/omp/themes/powerlevel10k_abk.png "pl10k_abk")

If you like to create your own theme please follow: [oh-my-posh documentation](https://ohmyposh.dev/docs).

* Note 1: if you don't see correct symbols in the prompt, please use font which is capable to display glyphs (symbols) in your terminal app settings. A good font example: Hack Nerd Font
* Note 2: The default oh-my-posh theme is based on dark background terminal app profile. If you like to use my profile please import it from <code>./unixBin/env/terminal/profiles/Solarized Dark.terminal</code>


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
* <code>./uninstall.sh tools_node.json</code> - will uninstall all node packages. SInce it was recorded what tools have been installed only the packages which has been previously installed with <code>tools_node.json</code> will be removed.
* <code>./uninstall.sh tools_min.json</code> - uninstalls packages previously has installed with <code>tools_min.json</code>
* <code>./uninstall.sh tools_min.json tools_node.json</code> - uninstalls packages previously has installed with <code>tools_min.json</code> and <code>tools_node.json</code>
