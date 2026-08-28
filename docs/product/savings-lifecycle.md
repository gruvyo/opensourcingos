# Savings lifecycle

Accepted 2026-08-08. This note governs Calculations, Schedule, Savings Realization,
Dashboard, Savings, and Reports.

## Vocabulary

- **Estimated savings** are the reportable pipeline projection.
- **Executed savings** are the confirmed commercial result. Execution is an
  explicit, audited decision; it is not inferred merely from elapsed time.
- **Accrued executed savings** are the executed schedule periods through the
  reporting date. This gives organizations useful time-based reporting even
  when Savings Realization is not enabled.
- **Realized savings** are actual achieved savings captured through the optional
  **Savings Realization** workflow.

`Realized` is not a Calculation stage. Calculations explain how a value was
derived; Schedule owns when it is reportable; Savings Realization compares the
executed schedule with actual results.

## Schedule behavior

Every estimated or executed value must have a schedule. Estimated and executed
values coexist so the contracted outcome can be compared with the pipeline
projection. Executing a schedule creates a durable snapshot; it never relabels
or overwrites the estimate.

The schedule is the time-based savings ledger. Its core columns are spend
addressed, estimated savings, and executed savings. When Savings Realization is
enabled, actual/realized savings, variance or leakage, and finance validation
appear against the same periods.

The existing savings invariants remain authoritative: term normalization,
hard/soft baseline rules, null semantics, negative reductions, whole-term total
invariance, and month-based fiscal-year allocation.

## Execution decision

The Schedule owns the explicit **Mark as executed** action. The action requires
an existing schedule, records who and when, and preserves the estimated values.

Actorless executions created before these controls remain preserved when their
workspace no longer has any profile that can truthfully own the decision. They
carry an internal, read-only legacy-provenance marker. The marker cannot be set
through the application; every new execution still requires a real actor.

When a sourcing project is moved to **Complete**, the user must resolve any
estimated-only schedule before the project closes:

1. mark the scheduled savings as executed; or
2. complete the project with no executed savings and provide a reason.

The product must not silently convert an estimate to executed savings. A
cancelled project preserves its historical estimate but does not create
executed savings. Earlier finalizing statuses may show reminders; Complete is
the enforcement point.

### Corrections and reversals

An executed schedule is a locked financial record. Ordinary edits and deletes
are available only while a calculation is estimated. A correction is an
explicit, audited transaction that updates the estimated values and executed
snapshots together; the prior values remain in the audit history.

If realization evidence exists, correction preserves every period identity,
entered actual, and realized value. It re-bases the comparison fields, clears
any superseded Finance validation, and requires an administrator. Before
realization evidence exists, procurement users and administrators may correct
the schedule, including replacing empty tracking shells.

Only an administrator may reverse an execution, and only when it was premature:
no actual, realized, or Finance-validated evidence may exist. Empty tracking
shells are removed as part of the reversal. A completed sourcing project must
be reopened first or atomically recorded as having no executed savings with a
written reason. Once realization evidence exists, correction is the only
remedy; reversal is permanently refused.

## Savings Realization

Savings Realization is an organization-level capability and is off by default.
When disabled, the product still reports estimated, executed, and accrued
executed savings. When enabled, project schedules, the portfolio Realization
view, Dashboard, Savings, Reports, and supplier history expose one coherent
actual-versus-executed workflow.

Actual spend may support a calculated realized value when the comparison is
defensible. Direct actual-savings entry remains available because cost
avoidance is counterfactual and cannot always be derived safely from spend
alone. Every manual value and finance validation must retain its actor and time.

## Portfolio measures

Dashboard and reporting should distinguish, without double counting:

1. spend addressed;
2. estimated savings still in the pipeline;
3. executed savings;
4. accrued executed savings through the selected period; and
5. validated realized savings, when Savings Realization is enabled.
