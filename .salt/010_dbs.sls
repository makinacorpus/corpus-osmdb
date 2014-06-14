{% set cfg = opts.ms_project %}
{% if cfg.data.has_db %}
include:
  - makina-states.services.db.postgresql
{% import "makina-states/services/db/postgresql/init.sls" as pgsql with context %}
{% set data = cfg.data %}
{% set ver = data.pgver%}
{% set db = cfg.data.db %}
{% set dbgroups = []%}
{% for dregion in data.regions%}
{% for region, rdata in dregion.items() %}
{% for suf in ['', '_tmp'] %}
{% set name = 'planet_{0}{1}'.format(region, suf) %}
{% do dbgroups.append('{0}_owners'.format(name)) %}
{{ pgsql.install_pg_ext('hstore', name) }}
{{ pgsql.postgresql_db(name, template="postgis", wait_for_template=False) }}
{{ pgsql.postgresql_user(name, password=db.password, db=name) }}
{%endfor %}
{%endfor%}
{%endfor%}
{% for dbext in db.extra %}
{% for db, dbdata in dbext.items() %}
{{ pgsql.postgresql_db(db, template="postgis", wait_for_template=False) }}
{{ pgsql.postgresql_user(dbdata.user, password=dbdata.password, db=db) }}
{%endfor %}
{%endfor%}
{% else %}
no-op: {mc_proxy.hook: []}
{% endif %}
