# override retention policy not to conflict with mastersalt
{% set cfg = opts.ms_project %}
{% if cfg.data.has_db %}
{% set settings = salt['mc_dbsmartbackup.settings']() %}
{% set data = cfg.data %}
{% for i in ['mongod', 'slapd', 'mysql', 'postgresql'] %}
/etc/dbsmartbackup/{{i}}.conf.local:
  file.managed:
    - contents: |
                KEEP_LASTS="{{settings.keep_lasts}}"
                KEEP_DAYS="{{settings.keep_days}}"
                KEEP_WEEKS="{{settings.keep_weeks}}"
                KEEP_MONTHES="{{settings.keep_monthes}}"
                KEEP_LOGS="{{settings.keep_logs}}"
    - mode: 644
    - user: root
    - group: root
{% endfor %}
{% endif %}
