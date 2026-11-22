# Git setup for the coder (one time)

The coder commits and pushes without you: its commits are signed with a **dedicated software GPG key**, never with your YubiKey, and every git network operation of the coder goes over HTTPS with the `gh` token (`with-https.sh`; your SSH remote and its YubiKey keys are not used, so no PIN is asked). The coder needs **no SSH key** on GitHub; leave the key's authentication subkey unused. The key has no passphrase by design (`unixBin/setSwGpg.sh`), so use it only for the coder, keep the revocation certificate the script writes, and revoke the key if the file ever leaks.

## Steps

1. Create the key with the coder identity (`setSwGpg.sh` reads these two variables):
   ```bash
   GIT_USER_NAME="ABK Coder Agent" GIT_USER_EMAIL=<email> ./unixBin/setSwGpg.sh
   ```
   `<email>` must be a **verified** email of the GitHub account that will hold the key (see the two choices below). Note the fingerprint it prints.
2. Add the public key to that GitHub account (Settings → SSH and GPG keys → New GPG key):
   ```bash
   gpg --armor --export <fingerprint> | pbcopy        # then paste it at https://github.com/settings/gpg/new
   ```
   Or with the CLI: `gh auth refresh -h github.com -s admin:gpg_key`, then `gh gpg-key add <public-key-file> --title "ABK Coder Agent"`.
3. Tell git who the coder is (global config; the coder reads only these):
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

## How visible is the coder on GitHub?

| | Same account as yours | Separate GitHub account for the coder |
|---|---|---|
| `<email>` | your verified noreply address | a verified address of the new account (e.g. `you+coder@gmail.com`) |
| Commits in `git log` | `ABK Coder Agent` | `ABK Coder Agent` |
| Commits and PRs in the GitHub UI | shown under **your** username | shown under the **agent's** username |
| If the key file leaks | commits can be forged as you | only as the agent account |
| Extra setup | none | account, collaborator access to the repo, a token in `CODER_GH_TOKEN` (used for the push) |

The coder skill works with both; only this setup differs. The coder never falls back to unsigned commits: without the three `coder.*` settings it stops and points here.
