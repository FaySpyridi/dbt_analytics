-- Silver layer building block. Every account-with-a-subscription crossed
-- with every month in int_date_spine. This guarantees "silent" months (an
-- account with $0 MRR in a given month) are present as real rows, which is
-- required to correctly detect new/churned/reactivated MRR later - a
-- lag() over a sparse time series would otherwise skip gaps.
 
with accounts as (
 
    select distinct account_id
    from {{ ref('int_subscription_priced') }}
 
)
 
, months as (
 
    select * from {{ ref('int_date_spine') }}
 
)
 
, final as (

    select
        a.account_id
        , m.month_start
        , m.month_end

    from accounts      as a
    cross join months  as m

)

select * from final