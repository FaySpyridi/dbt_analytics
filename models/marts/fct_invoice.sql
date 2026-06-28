with

    int_invoice_usd as (

        select * from {{ ref('int_invoice_usd') }}

    )

    , final as (

        select
            invoice_id
            , account_id
            , subscription_id
            , amount
            , currency
            , amount_usd
            , invoice_status
            , invoice_date
            , paid_at
            , (invoice_status = 'failed') as is_failed

        from int_invoice_usd

    )

select * from final
