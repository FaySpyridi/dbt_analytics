{% macro normalize_to_monthly_amount(price_column, interval_column) %}
{#-
    Normalises a subscription price to a monthly amount so monthly and
    annual plans are comparable as MRR.
 
    - monthly plans: plan_price already is the monthly amount -> unchanged
    - annual plans: plan_price is the full annual amount -> divide by 12
    - anything else (unexpected/unknown interval): null, so it surfaces via
      a not_null/accepted_values test rather than silently being miscounted
 
    Usage:
        {{ normalize_to_monthly_amount('s.plan_price_usd', 's.plan_interval') }} as mrr_amount
-#}
    case
        when {{ interval_column }} = 'monthly' then {{ price_column }}
        when {{ interval_column }} = 'annual' then {{ price_column }} / 12.0
        else null
    end
{% endmacro %}