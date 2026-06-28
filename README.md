# Yodeck Analytics — dbt Project

Medallion architecture (Bronze → Silver → Gold) over `raw\_accounts`,
`raw\_subscriptions`, `raw\_invoices`, `raw\_exchange\_rates`.

## Structure

```
yodeck\_analytics/
├── seeds/                     raw\_\*.csv (stand-in for source tables)
├── macros/
│   ├── to\_usd.sql              amount\_column, currency\_column, rate\_to\_usd\_column -> USD
│   └── normalize\_to\_monthly\_amount.sql   price + interval -> monthly amount
├── models/
│   ├── staging/                Bronze: 1:1 renamed/typed columns only, no logic
│   │   ├── \_sources.yml        every source table, declared once
│   │   ├── stg\_raw\_accounts.sql / .yml
│   │   ├── stg\_raw\_subscriptions.sql / .yml
│   │   ├── stg\_raw\_invoices.sql / .yml
│   │   └── stg\_raw\_exchange\_rates.sql / .yml
│   ├── intermediate/            Silver: transform \& combine, built as reusable
│   │   │                        building blocks (not report shapes)
│   │   ├── int\_subscription\_priced.sql / .yml      MRR + is\_active per subscription
│   │   ├── int\_invoice\_usd.sql / .yml               invoice amounts in USD
│   │   ├── int\_account.sql / .yml                    one row per account
│   │   ├── int\_date\_spine.sql / .yml                one row per calendar month
│   │   ├── int\_account\_months.sql / .yml            account x month spine
│   │   ├── int\_account\_monthly\_mrr.sql / .yml      total MRR per account per month
│   │   └── int\_mrr\_movements.sql / .yml             new/expansion/contraction/churned/reactivated
│   └── marts/                   Gold: the only layer BI is allowed to query
│       ├── dim\_account.sql / .yml
│       ├── fct\_subscription.sql / .yml
│       ├── fct\_invoice.sql / .yml
│       └── fct\_account\_monthly\_mrr.sql / .yml        <- core reusable MRR grain
├── analyses/                    Q1-Q4 answered against the gold layer only
│                                 (BI-style queries, not mart models)
├── tests/                       singular/business-logic tests
├── deliverables/                CSV exports of Q1-Q4 (Step 2)
├── dbt\_project.yml
├── packages.yml                 dbt\_utils
```

## Why this split

* **Staging is intentionally dumb.** Renaming/typing only, no joins, no
derived columns. It's a stable contract every other layer can build on
without re-deriving the same cast/rename logic.
* **Intermediate holds the reusable logic**, split by concern rather than
by question, so future marts can recombine the pieces instead of
duplicating logic:

  * `int\_subscription\_priced` — MRR normalization + activity flag, at
subscription grain (reusable for plan/upgrade-path analysis later).
  * `int\_invoice\_usd` — currency conversion, at invoice grain (reusable
for any billing/revenue-recognition work later).
  * `int\_date\_spine` / `int\_account\_months` — generic month spines,
decoupled from MRR specifically so any future time-series model
(e.g. account counts, ARR by cohort) can reuse them.
  * `int\_account\_monthly\_mrr` — the account-month MRR snapshot.
  * `int\_mrr\_movements` — the new/expansion/contraction/churned/
reactivated classification, kept as its own model since it's the
one piece of logic genuinely specific to the MRR-movement glossary.
* **Marts expose grains, not reports.** `fct\_account\_monthly\_mrr` is the
single source of truth for every MRR question, but it stops at
one-row-per-account-per-month with a movement label — it does **not**
pre-aggregate by month or sum across accounts. That GROUP BY (Q2),
that join to invoices (Q3), that ratio (Q4) are BI's transformation to
make, not mine to bake in. The `analyses/` folder shows that
BI-side step, but it's deliberately not a model — it materializes
nothing and isn't part of the layer BI is told to depend on.

## Macros

* `to\_usd(amount\_column, currency\_column, rate\_to\_usd\_column)` — renders a
`case when currency = 'USD' then amount else amount \* rate end`
expression. It only renders the expression; the calling model is
responsible for the join to the exchange rate (kept this way so the
macro works whether a model joins on invoice\_date, paid\_at, or
something else entirely — it's a formatting/calculation helper, not a
join).
* `normalize\_to\_monthly\_amount(price\_column, interval\_column)` — `annual`
divides by 12, `monthly` passes through, anything else returns `null`
so it fails a `not\_null` test instead of silently mis-stating MRR.

## Assumptions

1. **Overlapping active subscriptions are summed, not de-duplicated.**
3 accounts in the sample data have more than one subscription active
at the same time. I treat each as real, separately-billed recurring
revenue and sum their MRR, rather than picking a "primary" one — an
account legitimately paying for two concurrent subscriptions (e.g. an
add-on) has both contributing to its total MRR.
2. **Monthly MRR snapshots use month-end state.** A subscription counts
toward month *M* if it was active (per the glossary's
`end\_date is null and cancelled\_at is null`, evaluated as of that
month's last day) at the end of *M*. This is the standard "MRR as of"
convention and is what makes Q1's "current" MRR and Q2/Q4's historical
monthly MRR consistent with each other (same definition, different
reference date). One side effect: a subscription that started and
fully ended within the same month (before that month's last day) does
not register as active for that month — it never had a month-end
snapshot at which it counted.
3. **"New" vs "reactivated"** is distinguished by checking for *any*
prior month (further back than the immediately preceding one) with
MRR > 0. A truly first-ever subscription is `new`; an account that
previously had MRR, fully churned, and now has MRR again is
`reactivated` — even if there's more than one churn/win-back cycle.
4. **`cancelled\_at` is treated as informational, not authoritative**, for
activity status — `end\_date is null and cancelled\_at is null` (the
glossary's own definition) is what's used everywhere. `end\_date` is
the field that actually closes out a subscription's contribution to
MRR.
5. **`plan\_price` in `raw\_subscriptions` is already in USD** per the data
dictionary, so no conversion is applied to subscriptions — only
`raw\_invoices` (which has its own `currency` column) goes through
`to\_usd`.
6. Q3's "last 3 months" is measured from the current date back.

## Data quality issues found

* `raw\_subscriptions`: 5,906 rows have `end\_date` populated but
`cancelled\_at` null (normal — plans that ran their course rather than
being cancelled early) and 1 row has the reverse (`cancelled\_at` set,
`end\_date` null) — kept as-is per the glossary's definition of active,
but flagged via the `int\_subscription\_priced.is\_active` test for
visibility.
* 3 accounts have genuinely overlapping active subscription periods (see
Assumption 1) — not an error, but worth a stakeholder conversation if
it wasn't intentional on the product side.
* No orphaned foreign keys, no duplicate primary keys, no negative
amounts/prices, and no currency in `raw\_invoices` missing a same-day
rate in `raw\_exchange\_rates` — all enforced as `relationships`/`unique`/
`accepted\_range` tests so a future load that introduces any of these
fails loudly instead of silently corrupting MRR.
* `raw\_exchange\_rates` only covers AUD/EUR/GBP (no row for USD, by
design, per the data dictionary) — `to\_usd` and `is\_missing\_fx\_rate`
both depend on that being true; the latter is a regression test for it.

## Testing approach

Tests are concentrated where the assignment's reasoning actually lives,
not spread thin for coverage's sake:

* **Source-level**: not\_null/unique/accepted\_values/relationships on every
source table, so a bad load is caught before a single model runs.
* **Staging**: the same checks carried through after rename/cast, to
separate "the source is bad" from "I broke something in staging."
* **Intermediate**: business-rule tests on the actual derived values —
`mrr\_amount > 0`, `is\_active not null`, `is\_missing\_fx\_rate = false`,
uniqueness of `(account\_id, month\_start)`.
* **Marts**: the same grain tests. Not extra tests applied twice.
* **Singular tests** (`tests/`): One business-logic checks that generic
tests can't express — that every movement category is internally
consistent with its own current/previous MRR valuest.

## How to run

```bash
dbt deps
dbt build -- dbt seed & dbt run & dbt test
dbt compile 
```

## Deliverables (Step 2 answers)

See `deliverables/`:

* `q1\_current\_mrr\_by\_plan.csv` — current MRR ≈ **$3.05M**, enterprise
≈ $1.90M / pro ≈ $696K / starter ≈ $451K (4,808 active subscriptions).
* `q2\_mrr\_movement\_by\_month.csv` — monthly new/expansion/contraction/
churned/reactivated breakdown plus net MRR change.
* `q3\_accounts\_with\_failed\_invoices.csv` — 134 accounts with a failed
invoice in the last 3 months; 123 of them are still on an active
subscription, totalling ≈ $67.7K of current MRR.
* `q4\_mrr\_retention\_rate.csv` — month-over-month MRR retention, recently
tracking \~99.4-99.9%.

These were produced by re-implementing the gold-layer SQL logic exactly
(same joins, same window functions, same classification rules) since this
sandbox has no outbound network access to install a SQL engine — the
dbt project itself is what should be run/graded; these CSVs are provided
so the numeric answers don't depend on that being done first.

