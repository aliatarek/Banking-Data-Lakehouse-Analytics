{% macro link_hash_key(hash_keys) -%}
    md5(concat({{ hash_keys | join(', ') }}))
{%- endmacro %}
