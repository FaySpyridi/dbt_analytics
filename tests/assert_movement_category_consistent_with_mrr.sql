-- Singular test: catches a logic regression in int_mrr_movements (e.g. a
-- future edit to the case statement) by checking the category always
-- matches what the underlying numbers say it should be. Returns 0 rows
-- when everything is consistent.

select *
from {{ ref('fct_account_monthly_mrr') }}
where
    (mrr_movement_category in ('new', 'reactivated') and previous_mrr != 0)
    or (mrr_movement_category = 'churned' and (current_mrr != 0 or previous_mrr = 0))
    or (mrr_movement_category = 'expansion' and current_mrr <= previous_mrr)
    or (mrr_movement_category = 'contraction' and (current_mrr >= previous_mrr or current_mrr = 0))
    or (mrr_movement_category = 'retained' and current_mrr != previous_mrr)
    or (mrr_movement_category = 'no_activity' and (current_mrr != 0 or previous_mrr != 0))