# Git SNP Slash command

## Usage
`/git-snp`

## Description
This command pushes commits to remote repo, with the intention to push more often smaller steps

## Instructions

### Push all local commits to remote repo
Smaller commits should be pushed more often to remote repo using alias: snp
```bash
snp
```

### snp explanation
snp stands for Salt 'n Pepper
The command will:
1. will push the commit(s)
2. display `Ahh, Push it!` art
3. play short version of `Push it!` from Salt 'n Pepper band
This way user can see and hear that commit has been pushed
Note: that `snp` which executes `git push` sometimes requires a PIN from yubikey
- This is because all git commits and pushes are verified by a GPG key stored on yubikey
- The PIN is required only sometimes because there is a timeout for how long the PIN is valid
- If the push is pending for longer than 5 seconds, continue with next task, user will eventually key in PIN for the push to be successful

### Usage Examples:
```
/git-snp
```

## Best Practices
After pushing commits to remote repo, we should improve further the quality of the changes just committed by following steps below:
- think hard, analyze the code for possible improvements
- search for common patterns, for possibility to extract those patterns into a modular functions
- if some methods are too long, try to shorten them by extracting logical part into methods.
- Analyze committed code. For Kotlin you could use `detekt` tool for code quality analysis
- think hard: is there a possibility for improvement by introducing a design patterns like: strategy or observer pattern. There are more design patterns available on https://refactoring.guru/design-patterns
  - Creational Design Patterns: https://refactoring.guru/design-patterns/creational-patterns
  - Structural Design Patterns: https://refactoring.guru/design-patterns/structural-patterns
  - Behavioral Design Patterns: https://refactoring.guru/design-patterns/behavioral-patterns
- For observer pattern could use well established library:
  - Python: reactivex (RxPy): https://rxpy.readthedocs.io/en/latest/
  - JavaScript/TypeScript: RxJS: https://rxjs.dev/guide/overview
- think hard: can the performance be improved? Can some code be used asynchronously, in parallel?
- after analyzing possible improvements, create a plan and present it to the user.
