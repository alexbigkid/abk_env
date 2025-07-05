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

### 2. Write a descriptive Commit Message
A good commit message should:
- Use Arlo Commit Notation (ACN): https://github.com/arlobelshee/ArlosCommitNotation
  1. Risk Level Notation
     - . : Addresses all known and unknown risks / Intended Change, Known Invariants, Unknown Invariants
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
- `. b Fix Dropdown menu positioning issue`
- `. r Update API endpoint for user profiles`
- `. r Remove deprecated helper methods`
- `^ r Refactor database connection logic`
- `. d Update documentation / README.md`
- `! f validate user feature complete, but missing unit test coverage`
- `@ f WIP: validate user feature complete, but failing tests`
- `. e set usb_mode Environment to true`
- `. t Implement unit tests for user validation feature`
- `. a Auto format using: ruff format`

#### Examples of Bad Commit Messages
- `stuff`
- `fixed it`
- `changes`
- `updates and fixes`

### 3. Submit Commit
The command will:
1. Review your staged changes
2. Create a commit with your message
3. Note: that git commit sometimes requires a PIN from yubikey
   1. This is because all commits are verified by a GPG key stored on yubikey
   2. The PIN is required only sometimes because there is a timeout for how long the PIN is valid
   3. So if the commit is pending for longer than 5 seconds, continue with next task, user will eventually key in PIN for the commit to be successful
4. Never push commits to remote repo. This is always done by user, using different command
5. After submitting commit execute following command: say "Commit_Message without ACN"
   1. This should play commit message without the Arlo Commit Notation
   2. Example if the complete commit message was: ". r Extracted functions to increase code readability", it should say "Extracted functions to increase code readability"

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
- Run linting tool, here are a few examples:
  - Python: uv run ruff check --fix
  - TypeScript: eslint . --ext .ts --fix
  - Kotlin: ktlint -F
  - Bash: shellcheck <bash-shell-script.sh>
- Similarly, run auto formatting tool
  - Python: uv run ruff format
- Use meaningful commit messages that help other developers understand the change
- Keep commits atomic - if you need to revert, you can revert the entire feature/fix
