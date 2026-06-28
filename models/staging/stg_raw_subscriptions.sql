with

    source as (

        select * from {{ source('rawdb', 'raw_subscriptions') }}

    )

    , renamed as (

        select
            subscription_id
            , account_id
            , lower(plan_name)                  as plan_name
            , lower(plan_interval)              as plan_interval
            , cast(plan_price as numeric(12,6)) as plan_price
            , start_date
            , end_date
            , cancelled_at

        from source

    )

select * from renamed