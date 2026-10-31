# Domain: Obligations & Calendar

Status: planned domain model. No `Obligation`, `CalendarEvent`, or
notification delivery exists yet.

## Entities

- **Obligation** — a tracked duty or deadline derived from a lease's
  approved `ContractualCondition`s (e.g. renewal notice deadline,
  indexation/readjustment date, a recurring payment due date). Has a type,
  a due date (or recurrence rule), status (pending/completed/missed), and
  a reference back to the `ContractualCondition` that generated it.
- **CalendarEvent** — the user-facing scheduling projection of one or more
  `Obligation`s, used to render calendar views and drive notifications.

## Relationships

```
Lease 1---* ContractualCondition
ContractualCondition 1---* Obligation
Obligation 1---* CalendarEvent   (an obligation may project to one or more
                                   calendar occurrences, e.g. a recurring one)
```

## Rules

- Obligations are generated only from approved contractual conditions
  (never from raw/unreviewed AI extraction).
- Obligation generation should be re-runnable/idempotent: regenerating from
  the same condition set must not create duplicate obligations.
- Changing a condition (e.g. via a new amendment) should not silently
  delete the historical record of what obligations existed under the prior
  condition — history matters for audit (e.g. "was the renewal notice
  obligation correctly tracked at the time").

## Notifications

Notification delivery (email, in-app) is a separate concern that consumes
upcoming `Obligation`/`CalendarEvent` due dates; it does not generate
obligations itself.
