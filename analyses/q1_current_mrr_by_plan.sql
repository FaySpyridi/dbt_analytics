-- Q1: What is the current total MRR across active subscriptions?
-- Break it down by plan.
-- This is exactly the kind of BI-side transformation the mart layer does
-- not pre-bake: a simple GROUP BY on top of the gold fct_subscription.

select
    plan_name,
    sum(mrr_amount) as mrr,
    count(*)        as active_subscription_count
from {{ ref('fct_subscription') }}
where is_active
group by 1
order by mrr desc
