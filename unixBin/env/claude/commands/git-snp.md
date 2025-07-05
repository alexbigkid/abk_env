# Git Commit Slash command

## Usage
`/git-commit [message]`

## Description
This command helps you create well structured git commits with descriptive messages and submit them to the repo

## Instructions

### 1. Stage Your Changes
Before using this command, make sure you have staged the files you want to commit:
```bash
# stage all modified files
git add .
# or stage specific files
git add path/to/file.txt
```

### 2. Write a dDescriptive Commit Message
A good commit message should:
- Use Arlo Commit Notation (ACN): https://github.com/arlobelshee/ArlosCommitNotation
  1. Risk Level Notation
     - . : Addresses all known and unknown risks / ntended Change, Known Invariants, Unknown Invariants
     - ^ : Addresses all known risks / Intended Change, Known Invariants
     - ! : Some known risks remain unverified / Intended Change
     - @ : No risk attestation
  2. Core Intention
     - f : Feature / Change or extend one aspect of program behavior without altering others
     - b : Bugfix / Repair one existing, undesirable program behavior without altering any others
     - r : Refactoring / Change implementation without changing program behavior
     - d : Documentation / Change something which communicates to team members and does not impact program behavior
     - e : Environment / Environment (non-code) changes (for development)
     - t : Tests / Only test code changed
     - a : Automated / automated formatting
  3. Commit message
- For commit message use imperative mood ("Add feature" not "Added feature")
- Be concise, but descriptive (50 characters or less for the first line)
- Explain what the change does, not how it does it
- Use present tense

#### Examples of Good Commit Message
- `. f Add user authentication system`
- `. b fix Dropdown menu positioning issue`
- `. r Update API endpoint for user profiles`
- `. r Remove deprecated helper methods`
- `^ r Refactor database connection logic`
- `. d Update documentation / README.md`
- `! F validate user feature complete, but missing unit test coverage`
- `@ F WIP: validate user feature complete, but failing tests`
- `. e set usb_mode Environment to true`
- `. t implement unit tests for user validation feature`
- `. a auto format using: ruff format`

#### Examples of Bad Commit Messages
- `stuff`
- `fixed it`
- `changes`
- `updates and fixes`

### 3. Submit Commit
The command will:
1. Review your staged changes
2. Create a commit with your message
3. Optionally push to the remote repo (if specified)
4. Note: that git commit sometimes requires a PIN from yubikey
   4.1. This because all commits a verified by a GPG key stored on yubikey
   4.2. The PIN is required only sometimes because there is a timeout for how long the PIN is valid
   4.3. So if the commit is pending for longer then 5 seconds, continue with next task, user will eventually key in PIN for the commit to be successful
5. When pushing to the remote repo, please use an alias `snp` - which stands for: Salt 'n Pepper.
   5.1. it will push the commit(s)
   5.2. Display `Ahh, Push it!` art
   5.3. and play short version of `Push it!` from Salt 'n Pepper band
   5.4. This way user can see and hear that commit has been pushed
6. When pushing a feature complete commit, please use an alias `prg` - which stands for: Push it Real Good
   6.1. it will push the commit(s)
   6.2. Display `Alex is Awesome!` art
   6.3. and play longer version of `Push it Real Good!` from Salt 'n Pepper band
   6.4. This way user can see and hear that major feature commit has been pushed

### Usage Examples:
```
/git-commit
/git-commit . f Add new payment processing feature
/git-commit . b Fix responsive layout on mobile devices
/git-commit . r Extracted functions to increase code readability
/git-commit . r Use observer design pattern to improve performance with clean code design
```

## Best Practices
- Commit often with small, focused changes
- Each commit should represent a single logical change
- Test your implementation changes before committing
- If possible, create unit tests for implemented feature
- Run unit tests before committing
- Run linting tool, here few examples:
  - Python: uv run ruff check --fix
  - TypeScript: eslint . --ext .ts --fix
  - Kotlin: ktlint -F
  - Bash: shellcheck <bash-shell-script.sh>
- Similarly run auto formatting tool
  - Python: uv run ruff format
- Use meaningful commit messages that help other developers understand the change
- Keep commits atomic - if you need to revert, you can revert the entire feature/fix
