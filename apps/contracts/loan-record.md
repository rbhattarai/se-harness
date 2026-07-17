# Contract: loan-record

**Provider:** loan-webapp (creates records) · **Consumers:** lending-webapp (reads,
assigns approver, approves/rejects) · **Store:** `apps/data/loans.json` (shared volume)

Any change to this shape or the status transitions is a breaking change for the consumer —
`contract-check.sh` will flag it on push/PR.

## Record shape

```json
{
  "id": "LOAN-20260417-AB12",
  "applicantName": "Jane Smith",
  "amount": 25000,
  "status": "New",
  "approver": "John Doe",
  "createdAt": "2026-04-17T10:00:00.000Z"
}
```

| Field | Type | Written by | Notes |
|---|---|---|---|
| `id` | string | loan-webapp | `LOAN-YYYYMMDD-XXXX` (date + 4-char random alphanumeric) |
| `applicantName` | string | loan-webapp | |
| `amount` | number | loan-webapp | |
| `status` | string | both | see transitions below |
| `approver` | string | lending-webapp | set on `assign-approver` |
| `createdAt` | string | loan-webapp | ISO 8601 |

## Status transitions

```
New → Pending            (lending-webapp: assign-approver)
Pending → Approved       (lending-webapp: approve)
Pending → Rejected       (lending-webapp: reject)
```

## Related store

`apps/data/loan-approvers.json` — owned entirely by lending-webapp
(`{ id: "APR-YYYYMMDD-XXXX", name, createdAt }`); not consumed by loan-webapp, so not a
separate contract.
