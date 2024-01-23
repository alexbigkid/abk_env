# abk_env repo
ABK MacOS, Linux, Windows environment setup

[TOC]


## What is this repository for?

* For quick automated installation of required developer tools
* Easy updates


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


## Tools installed
If you want to specify which tools are installed, please take a look at the file <code>tools.json</code>

| tool                                                          | description                                                                  |
| :------------------------------------------------------------ | :--------------------------------------------------------------------------- |
| [awscli](https://github.com/aws/aws-cli)                      | provides a unified command line interface to Amazon Web Services             |
| [direnv](https://github.com/direnv/direnv)                    | can load and unload env variables depending on the current project directory |
| [git](https://github.com/git/git)                             | Newest version of git                                                        |
| [gnuPG](https://github.com/gpg/gnupg)                         | Gnu Privacy Guard: tool to create and maintain GPG keys                      |
| [jq](https://github.com/jqlang/jq)                            | is a lightweight and flexible command-line JSON processor                    |
| [pass](https://www.passwordstore.org)                         | password manager, which works well with <code>direnv</code> tool             |
| [nodenv](https://github.com/nodenv/nodenv)                    | lets you easily switch between multiple versions of nodejs                   |
| [oh-my-posh](https://ohmyposh.dev/)                           | lets you easiliy configure your terminal prompt                              |
| [parallel](https://github.com/flesler/parallel)               | CLI tool to execute shell commands in parallel                               |
| [pyenv](https://github.com/pyenv/pyenv)                       | lets you easily switch between multiple versions of Python                   |
| [pyenv-virtualenv](https://github.com/pyenv/pyenv-virtualenv) | is a pyenv plugin, which manages virtualenvs for Python                      |
| [serverless](https://www.serverless.com/framework/docs)       | lets you deploy serverless infrastructure services to AWS                    |
| [tfenv](https://github.com/tfutils/tfenv)                     | lets you easily switch between multiple versions of Terraform                |
| [tree](https://linuxhandbook.com/tree-command/)               | lists files in tree from                                                     |
| [wget](https://linuxize.com/post/wget-command-examples/)      | utility for downloading files from the **web**                               |
| [yq](https://github.com/mikefarah/yq)                         | is a lightweight and flexible command-line YAML, JSON and XML processor      |


## Additional MacOS apps installed

| tool                                                               | description                                                             |
| :----------------------------------------------------------------- | :---------------------------------------------------------------------- |
| [balenaetcher](https://github.com/balena-io/etcher)                | Etcher is a powerful OS image flasher built with web technologies       |
| [brave-browser](https://github.com/brave/brave-browser)            | Secure, fast Web browser based on Chromium just like Chrome             |
| [docker](https://github.com/docker)                                | Docker helps developers to abstract virtual environments                |
| [flycut](https://github.com/TermiT/Flycut)                         | Flycut is a clean and simple clipboard manager for developers           |
| [iterm2](https://github.com/gnachman/iTerm2)                       | MacOS terminal app                                                      |
| [microsoft-teams](https://www.microsoft.com/en-us/microsoft-teams) | Company's online meeting app                                            |
| [mqttx](https://mqttx.app/)                                        | MQTTX makes developing and testing MQTT applications faster and easier. |
| [raspberry-pi-imager](https://github.com/raspberrypi/rpi-imager)   | Raspberry Pi Imaging Utility                                            |
| [visual-studio-code](https://github.com/microsoft/vscode)          | THe best code editor ever :)                                            |
| [vlc](https://github.com/videolan/vlc)                             | VLC is a libre and open source media player and multimedia engine       |


## Additional MacOS apps installed

Those font are useful for coding and for oh-my-posh
- font-agave-nerd-font
- font-comic-shanns-mono-nerd-font
- font-droid-sans-mono-nerd-font"
- font-cascadia-code
- font-cascadia-code-pl
- font-caskaydia-cove-nerd-font
- font-hack-nerd-font


## oh-my-posh configuration
There is a preconfigured theme located in folder <code>./unixBin/env/omp/themes</code>. If you like to configure your own theme follow: [oh-my-posh documentation](https://ohmyposh.dev/docs). There are also many other predefined themes. You can activate them in the file: <code>./unixBin/env/XXX_oh-my-posh.env</code>


## How do I get set up?
### Install
Simple execute following command in your terminal:
```shell
./install.sh
```

### Update
Simply run <code>./update.sh</code>, it will update all installed tools. This script is still WIP.
```shell
./update.sh
```

### Uninstall
If you at some point want to uninstall everything installed, simply run:
```shell
./uninstall.sh
```
