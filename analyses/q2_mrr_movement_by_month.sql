-- Q2: For each month, MRR movement by category (new, expansion,
-- contraction, churned, reactivated) and the net MRR change per month.
-- 'retained' and 'no_activity' are excluded - they represent $0 movement
-- by definition and aren't part of the glossary's five categories.

select
    month_start,
    mrr_movement_category,
    sum(mrr_change) as mrr_amount
from {{ ref('fct_account_monthly_mrr') }}
where mrr_movement_category in ('new', 'expansion', 'contraction', 'churned', 'reactivated')
group by 1, 2

union all

select
    month_start,
    'net_mrr_change' as mrr_movement_category,
    sum(mrr_change)   as mrr_amount
from {{ ref('fct_account_monthly_mrr') }}
where mrr_movement_category in ('new', 'expansion', 'contraction', 'churned', 'reactivated')
group by 1

order by 1, 2
