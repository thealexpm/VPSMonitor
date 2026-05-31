# VPS Monitor

A native macOS menu bar app for monitoring multiple Linux VPS hosts over SSH — no agent, no cloud, no setup on the server side.

It uses your existing SSH keys to connect, runs a small read-only shell script remotely, and shows live metrics right in the menu bar.

---

## Features

- **Menu bar status** — see all servers at a glance: how many are up, color-coded health indicator
- **Per-server dashboard** — CPU, RAM, disk space, uptime, SSH response time
- **Project detection** — finds services in `/opt` and links them to their `systemd` units
- **Push notifications** — get notified when a server goes down, comes back, or a service stops
- **Metric history** — sparkline charts that build up over time as the app polls your servers
- **Multiple servers** — add, edit, and delete servers from Settings at any time
- **Zero server-side setup** — no agent to install; the app runs a one-shot bash script over SSH

---

## Requirements

| Requirement | Version |
|---|---|
| macOS | 14 Sonoma or later |
| Xcode Command Line Tools | any recent version |
| Swift | 6.0+ (ships with CLT) |
| SSH key | authorized on your VPS |

---

## Quick Start

```bash
# 1. Clone
git clone https://github.com/YOUR_USERNAME/VPSMonitor.git
cd VPSMonitor

# 2. Build and launch
./script/build_and_run.sh
```

The script compiles the app, bundles it into `dist/VPSMonitor.app`, and opens it. A VPS Monitor icon appears in the menu bar.

**3.** Click the menu bar icon → **Settings** → add your first VPS (host, SSH user, refresh interval).

That's it. The app starts polling immediately.

---

## Setting Up SSH Access

The app connects using whichever SSH key is already loaded in your SSH agent or configured in `~/.ssh/config`. No password prompts — SSH must be able to connect without interaction.

**Verify your key works:**
```bash
ssh user@your.server.address "echo ok"
```

If that prints `ok`, the app will work. If it asks for a password or fails, set up key-based auth first:

```bash
# Generate a key if you don't have one
ssh-keygen -t ed25519

# Copy it to your server
ssh-copy-id user@your.server.address
```

**Non-standard SSH port?** Add a `Host` block to `~/.ssh/config`:
```
Host my-vps
    HostName your.server.address
    User root
    Port 2222
    IdentityFile ~/.ssh/id_ed25519
```

Then use `my-vps` as the host in the app's Settings.

---

## Build

The build script handles everything:

```bash
./script/build_and_run.sh
```

It sets the correct SDK path, runs `swift build`, assembles the `.app` bundle in `dist/`, and opens it while closing any previous instance.

To build without launching:
```bash
SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk swift build
```

### Diagnostic probe

To test SSH connectivity and print raw inventory data without the GUI:
```bash
SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk swift run VPSMonitorProbe
```

> Edit `Sources/VPSMonitorProbe/main.swift` to point at your server before running.

---

## How It Works

Each polling cycle the app:

1. Opens an SSH connection to the server
2. Pipes a self-contained bash script to `bash -s` — no files are written to the server
3. The script reads `/proc/stat`, `/proc/meminfo`, `df`, `/proc/uptime`, and `systemctl` output
4. Parses the structured output on the Mac side
5. Builds a project list by matching `/opt` subdirectories against `systemd` units

The server is never modified. The script is read-only and exits cleanly after each run.

---

## Project Structure

```
Sources/
  VPSMonitor/           # SwiftUI app (menu bar + dashboard + settings)
  VPSMonitorCore/       # Business logic, models, SSH service (importable library)
  VPSMonitorProbe/      # CLI tool for testing SSH connectivity
Tests/
  VPSMonitorCoreTests/  # Unit tests for the inventory parser
Resources/
  AppIcon.icns          # App icon
script/
  build_and_run.sh      # One-command build + launch script
```

---

## License

MIT. See [LICENSE](LICENSE).
