-- Silver layer building block. Account-month grain: total MRR for an
-- account as of the END of each month. A subscription counts toward a
-- month if it was active (per int_subscription_priced) at that month's
-- last day. Where an account has more than one overlapping active
-- subscription, their MRR is summed rather than de-duplicated - each
-- represents real billed recurring revenue (see README for the full
-- reasoning and the alternative considered).

with account_months as (

    select * from {{ ref('int_account_months') }}

)

, subscriptions as (

    select * from {{ ref('int_subscription_priced') }}

)

, subscription_mrr_by_month as (

    select
        am.account_id
        , am.month_start
        , am.month_end
        , s.subscription_id
        , s.mrr_amount
    from account_months am
    inner join subscriptions s
        on am.account_id = s.account_id
        and s.start_date <= am.month_end
        and (s.end_date is null or s.end_date > am.month_end)

)

, final as (

    select
        am.account_id
        , am.month_start
        , am.month_end
        , coalesce(sum(smm.mrr_amount), 0)        as total_mrr
        , count(distinct smm.subscription_id)     as active_subscription_count
    from account_months                           as am
    left join subscription_mrr_by_month           as smm
        on am.account_id = smm.account_id
        and am.month_start = smm.month_start
    group by
        am.account_id
        , am.month_start
        , am.month_end

)

select * from final
