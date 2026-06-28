with

    int_subscription_priced as (

        select * from {{ ref('int_subscription_priced') }}

    )

    , final as (

        select
            subscription_id
            , account_id
            , plan_name
            , plan_interval
            , plan_price
            , mrr_amount
            , start_date
            , end_date
            , cancelled_at
            , is_active

        from int_subscription_priced

    )

select * from final
