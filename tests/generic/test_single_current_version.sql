{% test single_current_version(model, column_name) %}

select {{ column_name }}
from {{ model }}
where is_current
group by {{ column_name }}
having count(*) > 1

{% endtest %}
