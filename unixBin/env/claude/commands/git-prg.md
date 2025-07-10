# git prg slash command

## Usage
`/git-prg [release-type]`

## Description
This command pushes commits to remote repo, with the intention to push a major accomplishment with an intention to create a release

## Instructions

### Push all local commits to remote repo
Feature implementation should be pushed with: prg
```bash
# git-prg with patch
prg
git rel-patch
# git-prg with minor
prg
git rel-minor
# git-prg with major
prg
git rel-major
# git-prg without [release-type] - for release type use your best judgement
prg
git rel-[major|minor|patch]
```

### prg explanation
When pushing a feature complete commit, please use an alias `prg` - which stands for: Push it Real Good
- it will push the commit(s)
- display `Alex is Awesome!` art
- play longer version of `Push it Real Good!` from Salt 'n Pepper band
- this way user can see and hear that major feature commit has been pushed

### Usage Examples:
```
/git-prg patch
/git-prg minor
/git-prg major
/git-prg
```

## Best Practices
After pushing commits to remote repo, we should create a release
- `prg` alias command will push changes to remote repo
- `git rel-patch` git alias for creating tag named rel-patch, which will create a patch release on CI/CD pipeline
- `git rel-minor` git alias for creating tag named rel-minor, which will create a minor release on CI/CD pipeline
- `git rel-major` git alias for creating tag named rel-major, which will create a major release on CI/CD pipeline
- when `git-prg` is used without parameter, use your best judgement to pick the correct release type
