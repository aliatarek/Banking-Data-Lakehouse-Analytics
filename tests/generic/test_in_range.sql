{% test in_range(model, column_name, min_value, max_value=none) %}

select *
from {{ model }}
where {{ column_name }} is not null
  and (
    {{ column_name }} < {{ min_value }}
    {% if max_value is not none %}
    or {{ column_name }} > {{ max_value }}
    {% endif %}
  )

{% endtest %}
