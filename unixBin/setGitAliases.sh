#!/bin/bash

#------------------------------------------------------------------------------
# setGitAliases.sh - consistent git aliases on all machines
#
# Writes ABK's git aliases into your GLOBAL git config (~/.gitconfig), so
# every computer gets the same shortcuts. Safe to re-run any time.
#
# What it sets:
#   - Everyday shortcuts: st, co, ci, br, cob, last, hist, logg, unstage, ...
#   - Log views: today, yesterday, sinceYesterday, sinceDate
#   - File lists: staged, unstaged, untracked, ignored
#   - Env tags: adt/rdt (dev), aqt/rqt (qa), art/rrt (release) - add/remove
#     the tag locally and on origin
#   - Releases: rel-patch, rel-minor, rel-major run unixBin/gitRelease.sh, which
#     pushes the temporary tag rel-<type> on main. The pipeline runs the tests once;
#     when they pass, its release job bumps VERSION through a pull request, merges
#     it and creates the tag vX.Y.Z.
#   - core.pager: diff-so-fancy if installed, otherwise the pager is unset
#
# Notes:
#   - Overwrites existing global aliases with the same names.
#   - $HOME_BIN_DIR (from unixBin/env/001_vars.env) is expanded when THIS
#     script runs and baked into the rel-* aliases. Run it from a shell where
#     the ABK env is loaded.
#   - Colors load only when run from unixBin/ (relative path to
#     env/000_colors.env); output is just uncolored otherwise.
#   - List all aliases with: git alias
#------------------------------------------------------------------------------

ABK_COLOR_FILE="env/000_colors.env"
[ -f $ABK_COLOR_FILE ] && . $ABK_COLOR_FILE

echo -e "${YELLOW}-> $0${NC}"
echo '----- GIT alias configuration start ------'

git config --global alias.alias "config --get-regexp ^alias\."
git config --global alias.lcnf 'config --list --show-origin'
git config --global alias.br branch
git config --global alias.brr "!git fetch -p && git branch -r"
git config --global alias.ci commit
git config --global alias.co checkout
git config --global alias.dbr '!f() { git checkout main && git branch -D "$1" && git push origin --delete "$1"; }; f'
git config --global alias.adt "!git tag dev && git push origin dev"
git config --global alias.rdt "!git tag --delete dev && git push --delete origin dev"
git config --global alias.aqt "!git tag qa && git push origin qa"
git config --global alias.rqt "!git tag --delete qa && git push --delete origin qa"
git config --global alias.art "!git tag release && git push origin release"
git config --global alias.rrt "!git tag --delete release && git push --delete origin release"
git config --global alias.cob "checkout -b"
git config --global alias.hist "log --pretty=format:'%h %ad | %s%d [%an]' --graph --date=short"
git config --global alias.last "log -1 HEAD"
git config --global alias.logg 'log --pretty=format:"%h %s" --graph'
git config --global alias.rtl "reset --hard HEAD"
git config --global alias.sinceYesterday "log --pretty=format:'%Cred%h %Cgreen%cd%Creset | %s%C(auto)%d %Cgreen[%an]%Creset' --date=local --since=yesterday.midnight"
git config --global alias.st status
git config --global alias.today "log --pretty=format:'%Cred%h %Cgreen%cd%Creset | %s%C(auto)%d %Cgreen[%an]%Creset' --date=local --since=midnight"
git config --global alias.unstage "reset HEAD --"
git config --global alias.yesterday "log --pretty=format:'%Cred%h %Cgreen%cd%Creset | %s%C(auto)%d %Cgreen[%an]%Creset' --date=local --since=yesterday.midnight --until=midnight"
git config --global alias.unstaged 'diff --name-only'
git config --global alias.staged 'diff --name-only --cached'
git config --global alias.untracked 'ls-files --exclude-standard --others'
git config --global alias.ignored 'ls-files --exclude-standard --others --ignored'

git config --global alias.stash-staged '!bash -c "git stash --keep-index; git stash push -m "staged" --keep-index; git stash pop stash@{1}"'
git config --global alias.move-staged '!bash -c "git stash-staged;git commit -m "temp"; git stash; git reset --hard HEAD^; git stash pop"'
git config --global alias.sinceDate '!f() { git log --pretty=format:"%Cred%h %Cgreen%cd%Creset | %s%C(auto)%d %Cgreen[%an]%Creset" --date=local --since="$1"; }; f'

# Releases: push the temporary tag rel-<type> on main (starts the pipeline)
git config --global alias.rel-major "!$HOME_BIN_DIR/gitRelease.sh major"
git config --global alias.rel-minor "!$HOME_BIN_DIR/gitRelease.sh minor"
git config --global alias.rel-patch "!$HOME_BIN_DIR/gitRelease.sh patch"


if command -v diff-so-fancy &>/dev/null; then
    git config --global core.pager "diff-so-fancy | less --tabs=4 -RFX"
else
    git config --global --unset core.pager
fi

echo '----- GIT alias configuration done ------'
echo -e "${YELLOW}<- $0${NC}"
exit 0
