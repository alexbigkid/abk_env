# Git setup for the coder (one time per user and machine)

The coder works as **your own GitHub account** (your `gh` login) in whatever repository you run it in. Nothing is tied to one account or repository: the repo comes from the git remote, and every person who sets up this Claude environment creates their own coder key and settings below.

Its commits are signed with a **dedicated software GPG key**, never with your YubiKey or other hardware key, and every git network operation of the coder goes over HTTPS with your `gh` token (`with-https.sh`; your SSH remote and its keys are not used, so no PIN is asked). The coder needs **no SSH key** on GitHub; leave the key's authentication subkey unused. The key has no passphrase by design (`unixBin/setSwGpg.sh`): use it only for the coder, keep the revocation certificate the script writes, and revoke the key if the file ever leaks. How far the agents' credentials should be restricted is tracked in the "Agent credentials hardening" issue.

## Steps

1. Create the key with the coder identity (`setSwGpg.sh` reads these two variables):
   ```bash
   GIT_USER_NAME="ABK Coder Agent" GIT_USER_EMAIL=<email> ./unixBin/setSwGpg.sh
   ```
   `<email>` must be a **verified** email of your GitHub account; your GitHub noreply address always is. Note the fingerprint it prints.
2. Add the public key to your GitHub account (Settings → SSH and GPG keys → New GPG key):
   ```bash
   gpg --armor --export <fingerprint> | pbcopy        # then paste it at https://github.com/settings/gpg/new
   ```
   Or with the CLI: `gh auth refresh -h github.com -s admin:gpg_key`, then `gh gpg-key add <public-key-file> --title "ABK Coder Agent"`.
3. Tell git who the coder is (global config; the coder reads only these three):
   ```bash
   git config --global coder.signingkey <fingerprint>
   git config --global coder.name "ABK Coder Agent"
   git config --global coder.email <email>
   ```
4. Check that GitHub knows the key (public list, no token scope needed; the signing subkey id must appear):
   ```bash
   gh api users/<your-login>/gpg_keys -q '.[] | .key_id, (.subkeys[].key_id)'
   ```
5. After the coder's first push, the commit shows **Verified** on GitHub.

## What you see on GitHub

The commits show under **your** username, with the Verified badge. The name "ABK Coder Agent" is the author and committer in `git log` and in the commit details. A separate GitHub account for the agents would show them as their own user; that is not part of this setup (see the hardening issue).

## Platforms

The scripts are bash: they are meant for macOS and Linux (WSL included). They were run on macOS only (bash 3.2, bash and zsh). Native Windows (PowerShell, cmd) is out of scope; it would need its own scripts.
