{% macro surrogate_key(columns) -%}
    md5(concat({{ columns | join(', ') }}))
{%- endmacro %}
