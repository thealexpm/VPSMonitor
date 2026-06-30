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
