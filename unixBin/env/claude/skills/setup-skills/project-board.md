# Project board

Issues of this repo are tracked on a GitHub Projects (v2) board. The `project-board` skill moves issues between its columns.

- **Project**: `<owner>` / `#<project-number>` (set `PROJECT_NUMBER=<project-number>` if an issue is on more than one board)
- **Status columns**: `🔍 Triage`, `📋 Todo`, `🛠️ Doing`, `👀 Review`, `🧪 Testing`, `✅ Done`
- **Project fields**: Priority (P0-P2), Size (XS-XL), Estimate, Start date, End date
- **Agent issue field**: account-level single select `Agent` (Triager, Coder, Reviewer, Tester), set while an agent works on an issue

Board created from the `board-template` project. Without a board, agents still do their work but do not move issues between columns.
