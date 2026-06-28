with invoices as (

    select * from {{ ref('stg_raw_invoices') }}

)

, exchange_rates as (

    select * from {{ ref('stg_raw_exchange_rates') }}

)

, invoices_with_rate as (

    select
        i.invoice_id
        , i.account_id
        , i.subscription_id
        , i.amount
        , i.currency
        , i.invoice_status
        , i.invoice_date
        , i.paid_at
        , fx.rate_to_usd

    from invoices            as i
    left join exchange_rates as fx
        on i.currency = fx.currency
        and i.invoice_date = fx.rate_date
        and i.currency != 'USD'

)

, final as (

    select
        invoice_id
        , account_id
        , subscription_id
        , amount
        , {{ to_usd('amount', 'currency', 'rate_to_usd') }} as amount_usd
        , currency
        , invoice_status
        , invoice_date
        , paid_at
        -- Surfaces as a data-quality flag (tested as accepted_values: [false])
        -- rather than silently producing a null amount_usd downstream.
        , (currency != 'USD' and rate_to_usd is null)       as is_missing_fx_rate

    from invoices_with_rate

)

select * from final

