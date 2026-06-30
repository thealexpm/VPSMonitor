# Roadmap Issues

Copy these into GitHub Issues when remote GitHub actions are available.

Suggested labels already exist in the repository: `enhancement`,
`documentation`, `help wanted`, `good first issue`.

## Quick create commands

Run these from the repository root if you want to create all roadmap issues with
GitHub CLI:

```bash
gh issue create --title "Add Homebrew Cask distribution" --body-file docs/roadmap-issue-bodies/homebrew-cask.md --label enhancement --label "help wanted"
gh issue create --title "Add Telegram, Slack and Discord alert integrations" --body-file docs/roadmap-issue-bodies/alert-integrations.md --label enhancement
gh issue create --title "Add signed/notarized release channel and auto-update flow" --body-file docs/roadmap-issue-bodies/signed-release-channel.md --label enhancement
gh issue create --title "Export incident snapshots and metric reports" --body-file docs/roadmap-issue-bodies/export-reports.md --label enhancement
gh issue create --title "Add server groups and tags" --body-file docs/roadmap-issue-bodies/server-groups-tags.md --label enhancement --label "good first issue"
gh issue create --title "Add custom health rules" --body-file docs/roadmap-issue-bodies/custom-health-rules.md --label enhancement
gh issue create --title "Add public demo video/GIF to README" --body-file docs/roadmap-issue-bodies/demo-video.md --label documentation --label "help wanted"
```

## 1. Add Homebrew Cask distribution

Labels: `enhancement`, `help wanted`

```text
Publish VPSMonitor as a Homebrew Cask so macOS users can install and update it with brew.

Acceptance criteria:
- Cask installs the latest unsigned or signed release DMG/ZIP.
- README includes a brew install command.
- Release process documents how to update the cask.

This would improve discovery for macOS users and make installation easier.
```

## 2. Add Telegram, Slack and Discord alert integrations

Labels: `enhancement`

```text
Add optional external alert integrations for server down/recovered events and stopped services.

Acceptance criteria:
- User can configure Telegram, Slack or Discord webhook destinations.
- Alerts include server name, status, stopped services and suggested manual checks.
- Integrations are optional and disabled by default.
- No metric data is sent unless the user explicitly enables an integration.
```

## 3. Add signed/notarized release channel and auto-update flow

Labels: `enhancement`

```text
Improve the official distribution flow for non-technical macOS users.

Acceptance criteria:
- Release process produces a signed and notarized DMG.
- README explains the difference between source build, unsigned package and official signed build.
- Update banner points users to the latest GitHub release.
- Future auto-update support has a clear technical path.
```

## 4. Export incident snapshots and metric reports

Labels: `enhancement`

```text
Allow users to export incident summaries and historical metric reports.

Acceptance criteria:
- Export current incident snapshot as Markdown.
- Export metric history for a server as CSV.
- Export includes server name, checked time, resource metrics, baseline values and suggested commands.
- Export stays local; no cloud service is required.
```

## 5. Add server groups and tags

Labels: `enhancement`, `good first issue`

```text
Allow users to organize VPS entries into groups or tags such as Production, Staging, Bots, VPN, Client projects.

Acceptance criteria:
- Server configuration supports optional tags/groups.
- Sidebar can show group labels or filter by group.
- Menu bar view remains compact.
- Existing configurations migrate without data loss.
```

## 6. Add custom health rules

Labels: `enhancement`

```text
Allow users to define simple per-server health rules instead of relying only on default thresholds.

Examples:
- CPU warning above 80%.
- Disk warning above 85%.
- Latency warning above 2000 ms.
- Specific systemd service must be running.

Acceptance criteria:
- Rules are configured locally.
- Incident analysis explains which rule triggered.
- Defaults still work for users who do not configure custom rules.
```

## 7. Add public demo video/GIF to README

Labels: `documentation`, `help wanted`

```text
Add a short demo GIF or video to the README showing the core flow:

1. Add VPS.
2. View live metrics.
3. Inspect discovered projects.
4. Copy incident snapshot/manual check command.
5. Open the menu bar dropdown.

This should help first-time visitors understand the app in under 30 seconds.
```
