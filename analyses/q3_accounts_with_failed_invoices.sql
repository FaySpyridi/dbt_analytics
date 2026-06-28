-- Q3: Which accounts have at least one failed invoice in the last 3
-- months? What is their current MRR? How many are on an active
-- subscription?

with accounts_with_failed_invoice as (

    select distinct account_id
    from {{ ref('fct_invoice') }}
    where is_failed
        and invoice_date >= dateadd(
            month, -3, current_date
        )

),

current_account_mrr as (

    select
        account_id,
        sum(mrr_amount) as current_mrr,
        bool_or(is_active) as has_active_subscription
    from {{ ref('fct_subscription') }}
    where is_active
    group by 1

)

select
    f.account_id,
    coalesce(m.current_mrr, 0)               as current_mrr,
    coalesce(m.has_active_subscription, false) as has_active_subscription
from accounts_with_failed_invoice f
left join current_account_mrr m
    on f.account_id = m.account_id
order by current_mrr desc
