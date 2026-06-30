# VPSMonitor Launch Plan

This file keeps practical, copy-ready material for free distribution channels.
The goal is to grow from near-zero GitHub traffic to a steady flow of relevant
Mac, self-hosting, sysadmin and DevOps users.

## Positioning

Short description:

> Native macOS menu bar app for monitoring Linux VPS over SSH. No agent, no cloud, local-first.

One-liner:

> VPSMonitor gives Mac users a native menu bar dashboard for Linux VPS metrics,
> services and incident hints over plain SSH, without installing anything on the
> server.

## Where to post first

Use these channels in this order. Do not post everywhere in one hour; spread the
launch over 7-10 days and adjust wording after each response.

1. Hacker News: https://news.ycombinator.com/submit
   Title: `Show HN: VPSMonitor - native macOS monitoring for Linux VPS over SSH`
   Best angle: technical, no marketing fluff, explain SSH/no-agent/local-first.

2. Reddit r/selfhosted: https://www.reddit.com/r/selfhosted/submit
   Best angle: no cloud, no agent, local-first, compare honestly with Uptime Kuma.

3. Reddit r/macapps: https://www.reddit.com/r/macapps/submit
   Best angle: native macOS menu bar app, screenshots, multilingual UI.

4. Reddit r/devops: https://www.reddit.com/r/devops/submit
   Best angle: lightweight personal/server-side ops helper, not enterprise APM.

5. Reddit r/sysadmin: https://www.reddit.com/r/sysadmin/submit
   Best angle: "small VPS fleet visibility from a Mac"; be careful not to overclaim.

6. Product Hunt: https://www.producthunt.com/
   Best angle: polished screenshots, concise launch copy, "no agent, no cloud".

7. Indie Hackers: https://www.indiehackers.com/
   Best angle: building a local-first open-source macOS utility in public.

8. Dev.to: https://dev.to/new
   Best angle: technical build story: SwiftUI + SSH + local-first monitoring.

9. Swift Forums: https://forums.swift.org/
   Best angle: SwiftUI/macOS implementation notes, not just product promotion.

10. Lobsters: https://lobste.rs/
    Best angle: submit only if you have an account/invite; keep it technical.

## Show HN draft

Title:

```text
Show HN: VPSMonitor - native macOS monitoring for Linux VPS over SSH
```

Body:

```text
I built VPSMonitor, a native macOS menu bar app for monitoring Linux VPS hosts over SSH.

The idea is simple: no agent on the server, no cloud account, no extra open port.
The app connects over SSH, runs a small read-only bash script, parses CPU/RAM/disk/uptime/systemd/process data locally, and shows everything in a SwiftUI dashboard.

It also tries to map discovered project folders like /opt, /var/www, /srv, /app and /home/* to systemd services and live processes, so it is easier to see what is actually running on a small VPS fleet.

Current features:
- native macOS menu bar app
- SSH key or password auth via Keychain
- per-server CPU, RAM, disk, latency and uptime
- per-service CPU/RAM
- project discovery
- local metric history
- incident summary with copyable manual check commands
- country flags by IP with manual override
- UI languages: English, Russian, Spanish, Chinese

Repo: https://github.com/thealexpm/VPSMonitor
```

## Reddit draft

Title:

```text
I built a native macOS menu bar app to monitor Linux VPS over SSH, no agent or cloud
```

Body:

```text
I built VPSMonitor because I wanted a small local-first way to watch my own VPS hosts from a Mac without installing a monitoring agent or running a separate monitoring server.

It connects over SSH, runs a read-only bash script, and shows CPU/RAM/disk/uptime/latency, systemd services, live processes and discovered project folders in a native SwiftUI dashboard.

It is not meant to replace Uptime Kuma, Netdata or a hosted observability stack. It is more like a menu bar companion for a small VPS fleet:

- no server-side agent
- no cloud account
- SSH key or password via macOS Keychain
- local metric history
- project discovery from /opt, /var/www, /srv, /app, /home/*
- incident summary and copyable manual check commands

Open source repo:
https://github.com/thealexpm/VPSMonitor

Feedback from self-hosting/Mac/Linux users would be useful.
```

## Product Hunt draft

Tagline:

```text
Native macOS monitoring for Linux VPS over SSH
```

Description:

```text
VPSMonitor is a local-first macOS menu bar app for monitoring Linux VPS hosts.
It connects over SSH, requires no server-side agent, and shows live metrics,
services, discovered projects, local history and incident hints in a native
SwiftUI dashboard.
```

First comment:

```text
I built VPSMonitor for people who run a few VPS hosts and want visibility without
installing a monitoring agent or creating another cloud dashboard.

It is open source, macOS-native and SSH-only. The app reads server status through
a temporary read-only bash script and keeps data local on the Mac.

I would appreciate feedback from Mac users, self-hosters and small-team DevOps
folks.
```

## Instagram Reel script

Length: 35-45 seconds.

Format: screen recording, no face required. Use subtitles because many viewers
watch muted.

Shot list:

1. 0-3s: Hook
   On-screen text: `Monitoring my Linux VPS from a Mac menu bar. No agent. No cloud.`
   Show the VPSMonitor dashboard.

2. 3-8s: Add server
   Show Settings or Add VPS screen.
   Subtitle: `Add a VPS with SSH key or password.`

3. 8-15s: Live metrics
   Show CPU, RAM, disk, latency, uptime cards.
   Subtitle: `CPU, RAM, disk, latency and uptime in one native macOS view.`

4. 15-23s: Project discovery
   Show found projects list.
   Subtitle: `It finds projects in /opt, /var/www, /srv, /app and links them to services/processes.`

5. 23-31s: Incident view
   Show incident analysis and copyable manual commands.
   Subtitle: `When something changes, it suggests what to check next.`

6. 31-38s: Menu bar
   Show menu bar dropdown.
   Subtitle: `All VPS hosts are always one click away.`

7. 38-45s: CTA
   Show GitHub repo.
   Subtitle: `Open source on GitHub: thealexpm/VPSMonitor`

Voiceover:

```text
I built VPSMonitor, a native macOS app for monitoring Linux VPS servers over SSH.
No agent, no cloud, no extra server setup.
It shows live resources, services, discovered projects, local history and
incident hints directly from the menu bar.
It is open source on GitHub.
```

Caption:

```text
I built VPSMonitor: a native macOS menu bar app for monitoring Linux VPS over SSH.

No agent on the server.
No cloud dashboard.
No extra open ports.

Open source on GitHub: github.com/thealexpm/VPSMonitor

#macos #linux #vps #devops #selfhosted #swiftui #opensource
```

## 14-day traction target

Current baseline:

- 42 clones
- 25 unique cloners
- 11 views
- 2 unique visitors

Target after launch:

- 100-300 unique visitors
- 20-50 stars
- 5-10 issues or comments with real feedback
- at least one external referrer besides github.com

Do not optimize for donations first. Optimize for relevant users, feedback and
stars. Sponsors can come later after trust and repeated usage.
