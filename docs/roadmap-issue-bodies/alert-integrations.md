Add optional external alert integrations for server down/recovered events and stopped services.

Acceptance criteria:
- User can configure Telegram, Slack or Discord webhook destinations.
- Alerts include server name, status, stopped services and suggested manual checks.
- Integrations are optional and disabled by default.
- No metric data is sent unless the user explicitly enables an integration.
