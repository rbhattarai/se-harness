# Contract: notify-webhook

**Provider:** lending-webapp (defines the webhook + SSE protocol both apps implement) ·
**Consumers:** loan-webapp

Real-time sync between the two apps: after either app writes a loan change, it calls the
other app's `/notify`; the receiver broadcasts a `loan-updated` SSE event so connected
browser tabs reload.

## Webhook

```
POST /notify
Content-Type: application/json

{}            # empty body — the event is a pure "something changed" signal;
              # receivers re-read apps/data/loans.json
```

Targets are resolved from env vars (Docker service names in compose, localhost in dev):

| Caller | Env var | Default |
|---|---|---|
| loan-webapp → lending-webapp | `LENDING_WEBAPP_URL` | `https://localhost:3001` |
| lending-webapp → loan-webapp | `LOAN_WEBAPP_URL` | `https://localhost:3000` |

## SSE stream

```
GET /events        → text/event-stream
event: loan-updated
```

Browsers subscribe on page load; on `loan-updated` they reload the page.

Changing the endpoint path, event name, or moving to a payload-carrying event is a
breaking change for the other app — `contract-check.sh` flags it on push/PR.
