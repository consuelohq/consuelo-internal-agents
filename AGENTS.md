# AGENTS.md - Agent Workspace

this is the agent configuration directory for openengineer — a showcase of autonomous ai agent infrastructure.

## what's here

this repo contains the `.agent/` directory and supporting config extracted from a production monorepo. it's meant to be copied into your own projects to run autonomous coding agents.

## key files

| file | purpose |
|------|---------|
| `config.sh` | configuration (agent cli, branches, linear settings) |
| `run-tasks.sh` | main orchestrator — fetches issues, runs agents, creates prs |
| `webhook-receiver.py` | listens for linear webhooks, dispatches tasks |
| `linear-api.sh` | graphql helper for linear api |
| `linear-comment.sh` | post comments to linear as kiro bot |
| `init.sh` | session startup — health checks, git sync |

## how to use

see [README.md](README.md) for full setup instructions.

quick version:
1. copy `.agent/` to your project
2. set `LINEAR_API_KEY` env var
3. edit `.agent/config.sh` for your project
4. run `python3 .agent/webhook-receiver.py`
5. configure linear webhook to point to it

## related directories

- `.kiro/` — kiro agent config (skills, prompts, steering)
- `.opencode/` — opencode agent config (skills, plugins)
- `.claude/` — claude code hooks (legacy, for backward compatibility)
- `.coo/` — coo agent templates (gtm automation, not used in this showcase)
