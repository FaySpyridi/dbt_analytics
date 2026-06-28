with

    accounts as (

        select * from {{ ref('stg_raw_accounts') }}

    )

    , final as (

        select
            account_id
            , account_name
            , country_code
            , account_created_at
            , account_status

        from accounts

    )

select * from final
