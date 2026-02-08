# Kiro Pipeline Observations

Updated by the orchestrator after every kiro session. Tracks bugs, inefficiencies, and suggestions for improving the workflow.

---

## 2026-02-08 — First Live Run (DEV-505: icon fix)

### Bugs Found
- **Stale label ID in config.sh** — the kiro label was moved from team-level to workspace-level in linear, giving it a new ID. config.sh had the old ID, so specs-watcher found 0 tasks for weeks. Fixed by switching `linear_get_kiro_issues()` to filter by label name instead of ID.
- **Self-approval blocked** — PR created as `kokayicobb`, review posted as `kokayicobb`. GitHub blocks self-approval. The auto-merge flow fails silently (posts COMMENTED instead of APPROVED, then merges anyway on manual retry). Need a bot account or disable required approvals for kiro-small PRs.
- **Railway deploy check fails** — review skill runs `railway` CLI but no project is linked in this environment. Deploy check always fails with "No linked project found." Either `railway link` on the machine or skip deploy check in review skill.

### Token Waste
- **Spawned kiro read the entire App.tsx** (~2000+ lines) searching for an "eye icon on the dock." The task description said "mercury on the docks" but no file matched "dock" or "mercury" — kiro had to brute-force search. Better task descriptions with file hints would save tokens.
- **Orchestrator read all skill files** to understand the pipeline. First-run cost — won't repeat.
- **Two kiro sessions running** — this chat (orchestrator) + spawned kiro coder. Both burn tokens. When the autonomous pipeline works (specs-watcher → kiro → pr-watcher), there's only one session per task.

### Suggestions
1. **Fix self-approval** — either create a `consuelo-bot` GitHub account for PR creation, or disable branch protection requiring approvals for kiro-small PRs. This is blocking the full auto-merge flow.
2. **Fix or skip railway deploy check** — the review skill should gracefully skip deploy verification if `railway` isn't linked, instead of writing a deploy-failure file that triggers a kiro retry loop.
3. **Add file hints to linear specs** — when creating kiro tasks, include likely file paths. "Change icon in `src/components/FileManager.tsx`" saves kiro from reading 20 files to find it.
4. **Cap file reads** — kiro should not read files over 500 lines in full. Add a rule to the kiro prompt: "If a file is very large, read only the relevant section using grep or line ranges."
5. **pr-watcher state not persisting** — `processedPRs` was empty even after processing PR 793. The state save might be failing silently. Investigate.
6. **specs-watcher should log which label ID it's using** — would have caught the stale ID issue immediately instead of silently returning empty results.

## 2026-02-08 — Cron Debug + Monitoring

### Bugs Found
- **GH_TOKEN missing from cron environment** — `gh` auth is stored in the macos keyring, which cron can't access. Every `gh api` call returned 404 (actually an auth failure). Fixed by adding `GH_TOKEN` to `pipeline-env.sh`. Note: current token is `gho_` (oauth, may expire). Should create a proper PAT.
- **`md5` command not found in cron** — cron's PATH is minimal (`/usr/bin:/bin`). `md5` lives in `/sbin`. Fixed by adding full PATH to `pipeline-env.sh`.
- **specs-watcher tried all 11 tasks every run** — no `MAX_TASKS_PER_RUN` limit was set, so it attempted all 11 and failed all 11 every 30 minutes. Changed cron to every 4 hours. Should set `MAX_TASKS_PER_RUN=1` initially.
- **DEV-505 already has a PR (#793)** — but specs-watcher doesn't check for existing branches/PRs before trying to create a new one. It will keep trying to process DEV-505 on every run. Need a "processed tasks" state file or check Linear status.

### Suggestions
1. **Create a GitHub PAT** — the `gho_` oauth token from `gh auth login` can expire. Create a fine-grained PAT with repo scope and use that in `pipeline-env.sh` instead.
2. **Set MAX_TASKS_PER_RUN=1** — until the pipeline is proven reliable, process one task per cron run. Avoids burning 11 kiro sessions on failures.
3. **Skip already-processed tasks** — specs-watcher should check if a branch or PR already exists for a task before trying to create one. Or maintain a state file of processed task IDs.
4. **Remove DEV-505 from queue** — it already has PR #793 merged. Update its Linear status to "Done" so specs-watcher stops picking it up.
