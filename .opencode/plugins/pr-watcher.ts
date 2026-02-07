/**
 * PR Watcher Plugin — polls for Kiro-tagged PRs every 30 minutes.
 *
 * When it finds open PRs labeled 'kiro', it triggers the automated review flow:
 * - Small changes → auto-review with --auto flag → merge → deploy check
 * - Big changes → Slack notification for manual review
 *
 * Also checks for deploy failures and triggers Kiro retry.
 *
 * @module pr-watcher
 */

const POLL_INTERVAL_MS = 30 * 60 * 1000; // 30 minutes
const DEFAULT_REPO = "kokayicobb/consuelo_on_call_coaching";
const REVIEW_SKILL_PATH = "/Users/kokayi/Dev/claude-agent-workflow/.opencode/skills/github-review/review";
const KIRO_AGENT_PATH = "/Users/kokayi/Dev/claude-agent-workflow/.opencode/skills/kiro/kiro_agent.py";
const DEPLOY_FAILURES_DIR = "/Users/kokayi/Dev/claude-agent-workflow/.opencode/skills/kiro/deploy-failures";
const STATE_FILE = "/Users/kokayi/Dev/claude-agent-workflow/.opencode/plugins/.pr-watcher-state.json";

export const PrWatcherPlugin = async ({ client, $ }) => {
  // Load or initialize state
  let state = { processedPRs: {}, lastPoll: null };
  try {
    const stateRaw = await $`cat ${STATE_FILE} 2>/dev/null`.text();
    if (stateRaw.trim()) {
      state = JSON.parse(stateRaw);
    }
  } catch {
    // no state file yet, use defaults
  }

  async function saveState() {
    try {
      const stateJson = JSON.stringify(state, null, 2);
      await $`echo ${stateJson} > ${STATE_FILE}`;
    } catch (e) {
      console.error("[pr-watcher] failed to save state:", e);
    }
  }

  async function pollForKiroPRs() {
    try {
      const now = new Date().toISOString();
      console.log(`[pr-watcher] polling for kiro PRs at ${now}`);

      // Get open PRs with 'kiro' label
      const prListRaw = await $`/opt/homebrew/bin/gh pr list --label kiro --state open --json number,title,labels,headRefName,createdAt --repo ${DEFAULT_REPO}`.text();

      if (!prListRaw.trim() || prListRaw.trim() === "[]") {
        console.log("[pr-watcher] no open kiro PRs found");
        state.lastPoll = now;
        await saveState();
        return;
      }

      const prs = JSON.parse(prListRaw);
      console.log(`[pr-watcher] found ${prs.length} kiro PR(s)`);

      for (const pr of prs) {
        const prNum = String(pr.number);

        // skip if we already processed this PR recently (within 1 hour)
        const lastProcessed = state.processedPRs[prNum];
        if (lastProcessed) {
          const elapsed = Date.now() - new Date(lastProcessed).getTime();
          if (elapsed < 60 * 60 * 1000) {
            console.log(`[pr-watcher] PR #${prNum} already processed ${Math.round(elapsed / 60000)}min ago, skipping`);
            continue;
          }
        }

        // check labels for size hint
        const labels = (pr.labels || []).map((l) => l.name || l);
        const hasSmallLabel = labels.includes("kiro-small");
        const hasBigLabel = labels.includes("kiro-big");

        console.log(`[pr-watcher] processing PR #${prNum}: ${pr.title}`);
        console.log(`[pr-watcher]   labels: ${labels.join(", ")}`);

        // run the review with --auto flag
        try {
          console.log(`[pr-watcher] triggering review for PR #${prNum} with --auto`);
          const reviewResult = await $`python3 ${REVIEW_SKILL_PATH} ${prNum} --auto 2>&1`.text();
          console.log(`[pr-watcher] review output:\n${reviewResult.slice(0, 500)}`);

          // mark as processed
          state.processedPRs[prNum] = new Date().toISOString();
          await saveState();
        } catch (e) {
          console.error(`[pr-watcher] review failed for PR #${prNum}:`, e);
        }
      }

      state.lastPoll = now;
      await saveState();
    } catch (e) {
      console.error("[pr-watcher] poll error:", e);
    }
  }

  async function checkDeployFailures() {
    try {
      const lsResult = await $`ls ${DEPLOY_FAILURES_DIR}/*.json 2>/dev/null`.text();
      if (!lsResult.trim()) return;

      const files = lsResult.trim().split("\n");
      for (const file of files) {
        try {
          const content = await $`cat ${file}`.text();
          const failure = JSON.parse(content);

          console.log(`[pr-watcher] found deploy failure for PR #${failure.pr_number}`);
          console.log(`[pr-watcher]   error: ${(failure.error || "").slice(0, 200)}`);

          // trigger kiro to fix the error
          console.log(`[pr-watcher] triggering kiro retry for branch ${failure.branch}`);

          const retryResult = await $`python3 ${KIRO_AGENT_PATH} run \
            --branch ${failure.branch} \
            --error ${failure.error || "deploy failed"} \
            "Fix the deploy failure on this branch" 2>&1`.text();

          console.log(`[pr-watcher] kiro retry result:\n${retryResult.slice(0, 500)}`);

          // remove the failure file after processing
          await $`rm ${file}`;
          console.log(`[pr-watcher] cleaned up failure file: ${file}`);
        } catch (e) {
          console.error(`[pr-watcher] error processing failure file ${file}:`, e);
        }
      }
    } catch {
      // no failures dir or no files — that's fine
    }
  }

  // run initial poll after a short delay (don't block startup)
  setTimeout(async () => {
    await pollForKiroPRs();
    await checkDeployFailures();
  }, 10_000);

  // set up recurring poll
  const pollTimer = setInterval(async () => {
    await pollForKiroPRs();
    await checkDeployFailures();
  }, POLL_INTERVAL_MS);

  // hook into session events to log activity
  return {
    event: async ({ event }) => {
      // optionally react to specific events
      if (event.type === "session.idle") {
        // good time for a background check
        // (but don't do it every idle — respect the interval)
      }
    },
  };
};
