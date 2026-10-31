# WPG — Online 2.0 Agent Handoff

This package is the implementation brief for the **WPG Godot game repository**.

- Existing repository: https://github.com/ZhiH2333/WPG
- Intended branch: `dev` (verify current branch and working tree before editing)
- Engine baseline: Godot 4.6
- Language: GDScript
- Product target: WPG Online 2.0
- Backend repository: `WildBoat` (planned separate repository; do not assume it exists or has code)

## Read order

1. `CLAUDE.md`
2. `docs/prd.md`
3. `docs/tech-stack-and-architecture.md`
4. `docs/data-models-and-apis.md`
5. `docs/coding-standards-and-guidelines.md`
6. `docs/task-breakdown-and-implementation-plan.md`

## Non-negotiable boundaries

- The Godot Headless Dedicated Server is authoritative for live game simulation.
- WildBoat is authoritative for accounts, identity, social graph, parties, rooms, matchmaking, tickets, and persisted progression.
- Clients send intent/input; they do not authoritatively decide damage, AI, collision, score, or match outcomes.
- First online release: maximum 4 players per match.
- Initial deployment target: one active Dedicated Server game instance. Do not claim multiple simultaneous independent matches until multi-instance orchestration exists.
- Preserve existing solo and LAN/Host/Guest behavior during migration. Do not delete legacy networking code merely because the new path is being introduced.
- Do not invent WildBoat endpoints or assume backend implementation exists. Treat API contracts in this package as proposed contracts to be implemented in the WildBoat repository.
- Do not introduce global Autoloads casually. Inspect the current project structure before changing project-wide configuration.

## Agent operating procedure

Before coding:
1. Inspect `git status`, current branch, recent commits, `project.godot`, `roadmap.md`, and relevant networking/lobby docs.
2. Map existing code paths before editing. A previous path lookup returned 404 for some guessed files; verify paths rather than inferring missing functionality.
3. Write a short implementation plan and identify compatibility risks.
4. Implement the smallest vertical slice, with tests or reproducible manual verification.
5. Run Godot headless import/parse checks and relevant tests where available.
6. Report changed files, commands run, test results, and unresolved risks.

Never commit, push, create branches, deploy, or change repository settings unless explicitly instructed by the user.
