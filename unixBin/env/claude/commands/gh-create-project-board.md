# gh create project board slash command

## Usage
`/gh-create-project-board`

## Description
Creates the standard GitHub project board (Triage, Todo, Doing, Review, Testing, Done) for the GitHub repo the current directory belongs to. The board is a copy of the `board-template` project (Status columns, Priority, Size, Estimate, Iteration, 8 views), named after the repo and linked to it. Items are not copied.

## Instructions

### 1. Resolve repo and template
Run from inside the repo. Use the explicit owner login, `gh project link` rejects `@me`.
```bash
REPO=$(gh repo view --json name -q .name)
OWNER=$(gh repo view --json owner -q .owner.login)
TEMPLATE=$(gh project list --owner "$OWNER" --format json -q '.projects[] | select(.title=="board-template") | .number')
```
- If `TEMPLATE` is empty, stop and tell the user the `board-template` project was not found under `$OWNER` (see "Rebuilding the template" below).
- If a project titled `$REPO` already exists for `$OWNER`, stop and tell the user instead of creating a duplicate.

### 2. Copy the template and link it
```bash
NUM=$(gh project copy "$TEMPLATE" --source-owner "$OWNER" --target-owner "$OWNER" --title "$REPO" --format json -q .number)
gh project link "$NUM" --owner "$OWNER" --repo "$OWNER/$REPO"
```

### 3. Report
Give the user the project URL: `https://github.com/users/$OWNER/projects/$NUM` (use `/orgs/` instead of `/users/` for an organisation owner).
Remind them that `gh` does not copy workflows (auto-add, close -> Done): check Settings -> Workflows on the new project.

## Notes
- Requires `gh` with the `project` scope (`gh auth refresh -s project`).
- The template must exist under the same owner as the repo. For an organisation, copy `board-template` there once (`gh project copy <n> --source-owner <user> --target-owner <org> --title board-template`).
- The board is private, same as the template.

## Rebuilding the template
The GitHub API cannot create project views, so the template cannot be generated from code. If `board-template` is lost, copy any existing board made from it (`gh project copy <n> --source-owner <owner> --target-owner <owner> --title board-template`) and optionally enable "Make template" in its settings.
