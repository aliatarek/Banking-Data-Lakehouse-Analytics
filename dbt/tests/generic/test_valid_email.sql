{% test valid_email(model, column_name) %}

select *
from {{ model }}
where {{ column_name }} is not null
  and {{ column_name }} !~ '^[^@]+@[^@]+\.[^@]+$'

{% endtest %}
