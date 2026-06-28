{% macro to_usd(amount_column, currency_column, rate_to_usd_column) %}
{#-
    Converts an amount expressed in `currency_column` into USD.
 
    USD rows pass through unchanged (the exchange_rates source never contains
    a USD row, by design - see raw_exchange_rates). Every other currency is
    multiplied by the same-day rate_to_usd that the calling model is expected
    to have already joined in (this macro only renders the expression, it
    does not join - keeping it usable regardless of how a model sources its
    rate).
 
    Usage:
        {{ to_usd('i.amount', 'i.currency', 'fx.rate_to_usd') }} as amount_usd
-#}
    case
        when {{ currency_column }} = 'USD' then {{ amount_column }}
        else {{ amount_column }} * {{ rate_to_usd_column }}
    end
{% endmacro %}