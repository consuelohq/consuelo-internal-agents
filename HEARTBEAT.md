# Heartbeat Tasks - Checked Every Hour

## Check Calendar
Look for events in next 2-4 hours. If something is coming up soon, send slack notification.

## Check Email (if configured)
Look for urgent unread messages. Flag anything that seems time-sensitive.

## System Health Check
Just verify things are running smoothly. No need to report unless there's an issue.

## Reminders/Task Check
Check if there are any pending tasks or reminders you asked me to track.

---

**Note:** All findings should be sent to slack channel #suelo only if actionable.
If nothing needs attention, send "HEARTBEAT_OK" (which may be discarded).

**Schedule:** Every hour during waking hours (10 AM - 2 AM)
