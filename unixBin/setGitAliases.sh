#!/bin/bash

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
git config --global alias.dbr "!git checkout master && git branch -D $1 && git push origin --delete $1"
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
git config --global alias.sinceDate "!git log --pretty=format:'%Cred%h %Cgreen%cd%Creset | %s%C(auto)%d %Cgreen[%an]%Creset' --date=local --since=\"$1\""

git config --global alias.tmajor "!f() { \
  BRANCH=\"\$(git rev-parse --abbrev-ref HEAD)\"; \
  if [ \"\$BRANCH\" = \"main\" ]; then \
    git pull && git push && \
    git tag -f major -m 'release: major' && \
    git push -f origin major && \
    git tag -d major && \
    $HOME_BIN_DIR/alexIsAwesome.sh;
  else \
    echo \"❌ Error: Must be on 'main' branch (currently on: \$BRANCH)\"; \
  fi; \
}; f"

git config --global alias.tminor "!f() { \
  BRANCH=\"\$(git rev-parse --abbrev-ref HEAD)\"; \
  if [ \"\$BRANCH\" = \"main\" ]; then \
    git pull && git push && \
    git tag -f minor -m 'release: minor' && \
    git push -f origin minor && \
    git tag -d minor && \
    $HOME_BIN_DIR/alexIsAwesome.sh;
  else \
    echo \"❌ Error: Must be on 'main' branch (currently on: \$BRANCH)\"; \
  fi; \
}; f"

git config --global alias.tpatch "!f() { \
  BRANCH=\"\$(git rev-parse --abbrev-ref HEAD)\"; \
  if [ \"\$BRANCH\" = \"main\" ]; then \
    git pull && git push && \
    git tag -f patch -m 'release: patch' && \
    git push -f origin patch && \
    git tag -d patch && \
    $HOME_BIN_DIR/alexIsAwesome.sh;
  else \
    echo \"❌ Error: Must be on 'main' branch (currently on: \$BRANCH)\"; \
  fi; \
}; f"


if command -v diff-so-fancy &>/dev/null; then
    git config --global core.pager "diff-so-fancy | less --tabs=4 -RFX"
else
    git config --global --unset core.pager
fi

echo '----- GIT alias configuration done ------'
echo -e "${YELLOW}<- $0${NC}"
exit 0
