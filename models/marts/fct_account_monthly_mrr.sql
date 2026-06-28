with

    int_mrr_movement as (

        select * from {{ ref('int_mrr_movement') }}

    )

    , final as (

        select
            account_id
            , month_start
            , month_end
            , current_mrr
            , previous_mrr
            , mrr_change
            , mrr_movement_category

        from int_mrr_movement

    )

select * from final
