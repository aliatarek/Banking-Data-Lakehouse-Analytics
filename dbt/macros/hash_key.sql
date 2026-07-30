{% macro hash_key(column_name) -%}
    md5(upper(trim(cast({{ column_name }} as varchar))))
{%- endmacro %}
