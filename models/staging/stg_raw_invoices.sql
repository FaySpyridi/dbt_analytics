with

    source as (

        select * from {{ source('rawdb', 'raw_invoices') }}

    )

    , renamed as (

        select
            invoice_id
            , account_id
            , subscription_id
            , cast(amount as numeric(12,6)) as amount
            , upper(currency)               as currency
            , lower(status)                 as invoice_status
            , invoice_date
            , paid_at

        from source

    )

select * from renamed