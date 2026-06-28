with

    source as (

        select * from {{ source('rawdb', 'raw_exchange_rates') }}

    )

    , renamed as (

        select
            rate_date
            , upper(currency)                    as currency
            , cast(rate_to_usd as numeric(12,6)) as rate_to_usd

        from source

    )

select * from renamed