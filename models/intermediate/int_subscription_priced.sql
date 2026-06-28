-- Silver layer building block. Adds the two pieces of logic every other
-- model that touches subscriptions needs: a normalized MRR figure
-- (monthly/annual -> monthly) and a clear "is this active right now" flag.
-- Kept separate from any monthly time-series logic so it can be reused by
-- future models that need subscription-level (not account-month-level)
-- detail - e.g. plan-tier churn analysis, upgrade/downgrade path analysis.

with subscriptions as (

    select * from {{ ref('stg_raw_subscriptions') }}

)

, final as (

    select
        subscription_id
        , account_id
        , plan_name
        , plan_interval
        , plan_price
        , {{ normalize_to_monthly_amount('plan_price', 'plan_interval') }} as mrr_amount
        , start_date
        , end_date
        , cancelled_at
        -- Glossary definition: "A subscription where end_date is null and
        -- cancelled_at is null."
        , (
            (end_date is null and cancelled_at is null)
        ) as is_active

    from subscriptions

)

select * from final
