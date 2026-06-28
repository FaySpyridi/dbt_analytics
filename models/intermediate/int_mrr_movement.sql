-- the account-month MRR snapshot and, per account, compares it to the
-- prior month to classify the change exactly per the assignment glossary:
--   new          - had no MRR last month, has it now, and never had MRR
--                   before either (true first dollar)
--   reactivated  - had no MRR last month, has it now, but DID have MRR at
--                   some earlier point (a comeback, not a first sale)
--   expansion    - had MRR last month, has more now
--   contraction  - had MRR last month, has less now (still > 0)
--   churned      - had MRR last month, has none now
--   retained     - had MRR last month, exactly the same amount now
--                   (no movement - excluded from movement totals by BI,
--                   kept here for completeness/auditability)
--   no_activity  - $0 MRR last month and this month (kept for completeness)
--
-- mrr_change is always signed so "Net MRR Change = sum(mrr_change)" holds
-- without any category-specific sign-flipping downstream.

with monthly_mrr as (

    select * from {{ ref('int_account_monthly_mrr') }}

)

, with_history as (

    select
        account_id
        , month_start
        , month_end
        , total_mrr                                                   as current_mrr
        , lag(total_mrr) over (
            partition by account_id order by month_start
        )                                                            as previous_mrr
        -- True if this account had any MRR in a month strictly before the
        -- previous one - i.e. excludes the immediately preceding month,
        -- which is what previous_mrr already covers. Needed to tell
        -- "new" apart from "reactivated".
        , coalesce(
            max(case when total_mrr > 0 then 1 else 0 end) over (
                partition by account_id
                order by month_start
                rows between unbounded preceding and 2 preceding
            ),
            0
        ) = 1                                                        as had_mrr_two_or_more_months_ago

    from monthly_mrr

)

, final as (

    select
        account_id
        , month_start
        , month_end
        , current_mrr
        , coalesce(previous_mrr, 0)                                       as previous_mrr
        , current_mrr - coalesce(previous_mrr, 0)                         as mrr_change
        , case
            when current_mrr > 0 and coalesce(previous_mrr, 0) = 0
                 and not had_mrr_two_or_more_months_ago               then 'new'
            when current_mrr > 0 and coalesce(previous_mrr, 0) = 0
                 and had_mrr_two_or_more_months_ago                   then 'reactivated'
            when current_mrr > coalesce(previous_mrr, 0) and previous_mrr > 0 then 'expansion'
            when current_mrr < coalesce(previous_mrr, 0) and current_mrr > 0  then 'contraction'
            when current_mrr = 0 and coalesce(previous_mrr, 0) > 0     then 'churned'
            when current_mrr = coalesce(previous_mrr, 0) and current_mrr > 0 then 'retained'
            else 'no_activity'
        end                                                              as mrr_movement_category
    from with_history

)

select * from final
