-- Q4: Month-over-month MRR retention rate - of the MRR that existed last
-- month, what % is still active this month?
-- Retention rate = (current month MRR from accounts that already had MRR
-- last month) / (previous month total MRR) * 100.
-- "Current month MRR from existing accounts" excludes 'new' MRR (accounts
-- with no MRR last month) by construction, since previous_mrr = 0 for
-- those rows and they don't contribute to the numerator's underlying base.

select
    month_start,
    sum(case when previous_mrr > 0 then current_mrr else 0 end) as retained_mrr_this_month,
    sum(previous_mrr)                                            as total_mrr_last_month,
    round(
        100.0 * sum(case when previous_mrr > 0 then current_mrr else 0 end)
        / nullif(sum(previous_mrr), 0)
    , 2)                                                          as mrr_retention_rate_pct
from {{ ref('fct_account_monthly_mrr') }}
group by 1
order by 1
