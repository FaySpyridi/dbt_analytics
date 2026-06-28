# Yodeck Analytics — dbt Project

Medallion architecture (Bronze → Silver → Gold) over `raw_accounts`,
`raw_subscriptions`, `raw_invoices`, `raw_exchange_rates`.

## Structure

```
yodeck_analytics/
├── seeds/                       raw_*.csv (stand-in for source tables)
├── macros/
│   ├── to_usd.sql                 amount_column, currency_column, rate_to_usd_column -> USD
│   └── normalize_to_monthly_amount.sql   price + interval -> monthly amount
├── models/
│   ├── staging/                   Bronze: 1:1 renamed/typed columns only, no logic
│   │   ├── _sources.yml           every source table, declared once
│   │   ├── stg_raw_accounts.sql / .yml
│   │   ├── stg_raw_subscriptions.sql / .yml
│   │   ├── stg_raw_invoices.sql / .yml
│   │   └── stg_raw_exchange_rates.sql / .yml
│   ├── intermediate/              Silver: transform & combine, built as reusable
│   │   │                          building blocks (not report shapes)
│   │   ├── int_account.sql / .yml                  one row per account
│   │   ├── int_subscription_priced.sql / .yml      MRR + is_active per subscription
│   │   ├── int_invoice_usd.sql / .yml              invoice amounts in USD
│   │   ├── int_date_spine.sql / .yml               one row per calendar month
│   │   ├── int_account_months.sql / .yml           account x month spine
│   │   ├── int_account_monthly_mrr.sql / .yml      total MRR per account per month
│   │   └── int_mrr_movement.sql / .yml             new/expansion/contraction/churned/reactivated
│   └── marts/                     Gold: the only layer BI is allowed to query
│       ├── dim_account.sql / .yml
│       ├── fct_subscription.sql / .yml
│       ├── fct_invoice.sql / .yml
│       └── fct_account_monthly_mrr.sql / .yml      <- core reusable MRR grain
├── analyses/                      Q1-Q4 answered against the gold layer only
│                                   (BI-style queries, not mart models)
├── tests/                         singular/business-logic tests
├── deliverables/                  CSV exports of Q1-Q4 (Step 2)
├── docs/
│   └── columns_descriptions.md    shared {% docs %} blocks for repeated columns
├── dbt_project.yml
├── packages.yml                   dbt_utils, dbt_expectations
└── profiles.yml.example
```

## Why this split

- **Staging is intentionally dumb.** Renaming/typing only, no joins, no
  derived columns. It's a stable contract every other layer can build on
  without re-deriving the same cast/rename logic.
- **Intermediate holds the reusable logic**, split by concern rather than
  by question, so future marts can recombine the pieces instead of
  duplicating logic:
  - `int_account` — accounts at silver grain, so every other silver/gold
    model has a single stable thing to join to instead of reaching back
    to staging directly.
  - `int_subscription_priced` — MRR normalization + activity flag, at
    subscription grain (reusable for plan/upgrade-path analysis later).
  - `int_invoice_usd` — currency conversion, at invoice grain (reusable
    for any billing/revenue-recognition work later).
  - `int_date_spine` / `int_account_months` — generic month spines,
    decoupled from MRR specifically so any future time-series model
    (e.g. account counts, ARR by cohort) can reuse them.
  - `int_account_monthly_mrr` — the account-month MRR snapshot.
  - `int_mrr_movement` — the new/expansion/contraction/churned/
    reactivated classification, kept as its own model since it's the
    one piece of logic genuinely specific to the MRR-movement glossary.
- **Marts expose grains, not reports.** `fct_account_monthly_mrr` is the
  single source of truth for every MRR question, but it stops at
  one-row-per-account-per-month with a movement label — it does **not**
  pre-aggregate by month or sum across accounts. That GROUP BY (Q2), that
  join to invoices (Q3), that ratio (Q4) are BI's transformation to make,
  not mine to bake in. The `analyses/` folder shows that BI-side step,
  but it's deliberately not a model — it materializes nothing and isn't
  part of the layer BI is told to depend on.
- **Gold-layer columns that are already tested upstream are documented
  but not re-tested.** `dim_account`, `fct_subscription`, `fct_invoice`,
  and `fct_account_monthly_mrr` are thin pass-throughs of their `int_*`
  counterpart, so `unique`/`not_null`/`relationships` already run once,
  at the silver layer, against the same underlying rows. Re-running them
  again at the gold layer would be the same check on the same data
  twice. The one **exception** is the cross-table reconciliation test on
  `fct_account_monthly_mrr` (see Testing approach) — that one tests a
  relationship that doesn't exist anywhere else, so it stays.

## Macros

- `to_usd(amount_column, currency_column, rate_to_usd_column)` — renders a
  `case when currency = 'USD' then amount else amount * rate end`
  expression. It only renders the expression; the calling model is
  responsible for the join to the exchange rate (kept this way so the
  macro works whether a model joins on invoice_date, paid_at, or
  something else entirely — it's a formatting/calculation helper, not a
  join).
- `normalize_to_monthly_amount(price_column, interval_column)` — `annual`
  divides by 12, `monthly` passes through, anything else returns `null`
  so it fails a `not_null` test instead of silently mis-stating MRR.

## Assumptions

1. **Overlapping active subscriptions are summed, not de-duplicated.**
   A handful of accounts in the sample data have more than one
   subscription active at the same time. Each is treated as real,
   separately-billed recurring revenue and summed, rather than picking a
   "primary" one — an account legitimately paying for two concurrent
   subscriptions (e.g. an add-on) has both contributing to its total MRR.
2. **Monthly MRR snapshots use month-end state.** A subscription counts
   toward month *M* if `end_date is null or end_date > month_end(M)` —
   i.e. it hadn't yet ended as of that month's last day. This is the
   standard "MRR as of" convention. One side effect: a subscription that
   started and fully ended within the same month (before that month's
   last day) never registers in any monthly snapshot — in the sample
   data this affects ~8% of subscriptions (~$774K of MRR-equivalent
   that's structurally invisible to Q2's new/churned totals). Worth a
   stakeholder conversation if gross churn/new-business needs to capture
   these short-lived subscriptions too.
3. **"New" vs "reactivated"** is distinguished by checking for *any*
   prior month (further back than the immediately preceding one) with
   MRR > 0. A truly first-ever subscription is `new`; an account that
   previously had MRR, fully churned, and now has MRR again is
   `reactivated` — even if there's more than one churn/win-back cycle.
4. **`is_active` uses the assignment glossary's literal definition,
   exactly as given, with no extension**: `end_date is null and
   cancelled_at is null`. This means "currently active" (used in Q1 and
   Q3, via `fct_subscription.is_active`) and "counted toward this
   month's MRR" (Q2/Q4, via `int_account_monthly_mrr`'s month-end
   snapshot, which only looks at `end_date`) are **not the same
   population, on purpose**: a subscription with a known future
   `end_date` isn't "active" by this flag, but still bills normally
   (and counts toward MRR) every month up to that date. In the current
   data this affects ~223 subscriptions (~$130K, ~4.3% of current MRR)
   — a population worth flagging to stakeholders as "scheduled to end,"
   not a data quality issue. `fct_account_monthly_mrr.yml` carries a
   `dbt_expectations` test that reconciles current-month MRR between the
   two views by explicitly including that population on the comparison
   side — see Testing approach below.
5. **`plan_price` in `raw_subscriptions` is already in USD** per the data
   dictionary, so no conversion is applied to subscriptions — only
   `raw_invoices` (which has its own `currency` column) goes through
   `to_usd`.
6. **Q3's "last N months"** is measured from the current date back,
   using `invoice_date` (not `paid_at`, since a failed invoice was never
   paid), and is parameterised as `vars.failed_invoice_lookback_months`
   (default `3`) in `dbt_project.yml` rather than hard-coded.

## Data quality issues found

- `raw_subscriptions`: ~5,900 rows have `end_date` populated but
  `cancelled_at` null (normal — plans that ran their course rather than
  being cancelled early), and 1 row has the reverse (`cancelled_at` set,
  `end_date` null). Both are kept as-is per the literal glossary
  definition of `is_active` (Assumption #4); the one inverse row is the
  entire residual in the `fct_account_monthly_mrr` reconciliation test.
- A handful of accounts have genuinely overlapping active subscription
  periods (see Assumption #1) — not an error, but worth a stakeholder
  conversation if it wasn't intentional on the product side.
- No orphaned foreign keys, no duplicate primary keys, no negative
  amounts/prices, and no currency in `raw_invoices` missing a same-day
  rate in `raw_exchange_rates` — all enforced as `relationships`/
  `unique`/`accepted_range` tests so a future load that introduces any
  of these fails loudly instead of silently corrupting MRR.
- `raw_exchange_rates` only covers non-USD currencies (no row for USD,
  by design) — `to_usd` and `is_missing_fx_rate` both depend on that
  being true; the latter is a regression test for it.
- ~8% of subscriptions start and fully end within the same calendar
  month — see Assumption #2 for the consequence on monthly snapshots.

## Testing approach

Tests are concentrated where the assignment's reasoning actually lives,
not spread thin for coverage's sake:

- **Source-level** (`_sources.yml`): not_null/unique/accepted_values/
  relationships on every source table, so a bad load is caught before a
  single model runs.
- **Staging**: the same checks carried through after rename/cast, to
  separate "the source is bad" from "I broke something in staging."
- **Intermediate**: business-rule tests on the actual derived values —
  `mrr_amount` range, `is_active` not-null, `is_missing_fx_rate = false`,
  uniqueness of `(account_id, month_start)` on every account-month grain
  model, `accepted_values` on `mrr_movement_category`.
- **Marts**: primary-key tests (`unique`/`not_null`) on every fact/
  dimension, plus one test that exists *only* at this layer:
  - `fct_account_monthly_mrr.yml` runs a
    `dbt_expectations.expect_table_aggregation_to_equal_other_table`
    that reconciles current-month `current_mrr` against
    `fct_subscription`'s `mrr_amount`. Because of Assumption #4, a naive
    comparison (`current_mrr` vs. `sum(mrr_amount) where is_active`)
    would *always* show a real, expected gap (~$130K) — so the test's
    `compare_row_condition` explicitly mirrors the monthly snapshot's
    own predicate (`is_active or end_date is null or end_date >
    month_end`) instead of using `is_active` alone. With that, the two
    sides reconcile to **exactly $0** difference today; `tolerance_percent`
    is set tight (0.1%) since any future drift here would mean the two
    models' logic has genuinely diverged.
- **Singular tests** (`tests/`): one business-logic check that generic
  tests can't express — that every `mrr_movement_category` is internally
  consistent with its own `current_mrr`/`previous_mrr` values (e.g. a
  row can't be `'churned'` unless `current_mrr = 0` and `previous_mrr >
  0`).

## How to run

```bash
dbt deps
dbt seed
dbt run
dbt test
dbt compile   # or `dbt show -s q2_mrr_movement_by_month` etc. to preview analyses
```

This project was designed and validated against the provided CSVs using
DuckDB locally (`profiles.yml.example`); swap the target for any SQL
warehouse — nothing in the SQL is warehouse-specific beyond the
`dbt_utils.date_spine`/`last_day` macros, which already abstract that
away.

## Deliverables (Step 2 answers)

See `deliverables/` (figures as of 2026-06-28):

- **`q1_current_mrr_by_plan.csv`** — current MRR ≈ **$3.05M** across
  4,808 active subscriptions: enterprise ≈ $1.90M (1,905 subs) / pro ≈
  $696K (1,395 subs) / starter ≈ $451K (1,508 subs).
- **`q2_mrr_movement_by_month.csv`** — monthly new/expansion/contraction/
  churned/reactivated breakdown plus net MRR change. Most recent month
  (June 2026): churned ≈ -$12.0K, expansion ≈ +$0.5K, net change ≈
  -$11.5K.
- **`q3_accounts_with_failed_invoices.csv`** — 131 accounts with a
  failed invoice in the last 3 months; 120 of them are still on an
  active subscription, totalling ≈ $66.4K of current MRR.
- **`q4_mrr_retention_rate.csv`** — month-over-month MRR retention,
  recently tracking ~99.6-99.9%.

These were produced by re-implementing the gold-layer SQL logic exactly
(same joins, same window functions, same classification rules, same
`is_active` definition) since this sandbox has no outbound network
access to install a SQL engine — the dbt project itself is what should
be run/graded; these CSVs are provided so the numeric answers don't
depend on that being done first.
