with spine as (
 
    {{ dbt_utils.date_spine(
        datepart="month",
        start_date="(select date_trunc('month', min(start_date)) from " ~ ref('stg_raw_subscriptions') ~ ")",
        end_date="(select dateadd(month, 1, date_trunc('month', current_date)) from " ~ ref('stg_raw_subscriptions') ~ " limit 1)"
    ) }}
 
)
 
, final as (

    select
        date_month                                        as month_start
        , {{ dbt_utils.last_day('date_month', 'month') }} as month_end

    from spine

)

select * from final