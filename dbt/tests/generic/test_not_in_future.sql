{% test not_in_future(model, column_name) %}

select *
from {{ model }}
where {{ column_name }} is not null
  and {{ column_name }} > current_timestamp

{% endtest %}
