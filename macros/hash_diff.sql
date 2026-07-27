{% macro hash_diff(columns) -%}
    md5(concat({{ columns | join(', ') }}))
{%- endmacro %}
