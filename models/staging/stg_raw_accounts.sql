with

    source as (

        select * from {{ source('rawdb', 'raw_accounts') }}

    )

    , renamed as (

        select
            account_id
            , account_name
            , upper(country) as country_code
            , created_at     as account_created_at
            , lower(status)  as account_status

        from source

    )

select * from renamed
