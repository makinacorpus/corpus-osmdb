# override retention policy not to conflict with mastersalt
include:
  - makina-states.services.backup.dbsmartbackup
{% set cfg = opts.ms_project %}
{% set settings = salt['mc_dbsmartbackup.settings']() %}
{% set data = cfg.data %}
{% for i in settings.types %}
/etc/dbsmartbackup/{{i}}.conf.local:
  file.managed:
    - contents: |
                KEEP_LASTS="{{data.keep_lasts}}"
                KEEP_DAYS="{{data.keep_days}}"
                KEEP_WEEKS="{{data.keep_weeks}}"
                KEEP_MONTHES="{{data.keep_monthes}}"
                KEEP_LOGS="{{data.keep_logs}}"
    - mode: 644
    - user: root
    - group: root
{% endfor %}

/etc/db_smart_backup_deactivated:
{% if cfg.default_env in ['dev'] or data.get('backup_disabled', False)%}
  file.managed:
    - mode: 644
    - user: root
    - group: root
{%else %}
  file.absent: []
{% endif %}
