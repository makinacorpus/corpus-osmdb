{% import "makina-states/services/db/postgresql/init.sls" as pgsql with context %}
include:
  - makina-states.services.db.postgresql.hooks
{% set cfg = opts.ms_project %}
{% if cfg.data.has_db %}
{% set data = cfg.data %}
{% for dregion in data.regions%}
{% for region, rdata in dregion.items() %}
{% set name = 'planet_{0}'.format(region) %}
{% if region in data.build %}
{% set droot = cfg.data_root%}
{% set fname = rdata.pbf.split('/')[-1] %}
{% set hash = rdata.get('hash',
                        '{0}.md5'.format(rdata.pbf)) %}
{% set pbf = "/".join([droot, fname]) %}
{% set orig_pbf = pbf %}
# download full osm export
download-pbf-{{region}}:
  file.managed:
    - source: {{rdata.pbf}}
    - mode: 775
    - name: {{pbf}}
    - source_hash: {{hash}}
    - user: {{cfg.user}}
    - group: {{cfg.group}}
    - unless: test -e {{droot}}/skip_import_{{region}}
    # do not redownload big files
    - onlyif: test $(stat -c "%s" "{{pbf}}" 2>/dev/null||echo 0) -lt 1000000000
{% if rdata.get('tmpfs_size', '') %}
{% set mount = "/".join([droot, fname+'_fs']) %}
{% set pbf = "/".join([droot, fname+'_fs', fname]) %}
# mount it in ram if asked to
mountpbfintmpfs-{{region}}:
  file.directory:
    - name: {{mount}}
    - makedirs: true
    - user: {{cfg.user}}
    - group: {{cfg.group}}
    - unless: test -e {{droot}}/skip_import_{{region}}
    - watch:
      - file: download-pbf-{{region}}
  cmd.run:
    - name: mount -t tmpfs none "{{mount}}" -o size={{rdata.tmpfs_size}},rw,users,uid={{cfg.user}}
    - unless: test -e {{droot}}/skip_import_{{region}}
    - onlyif: test "x$(mount|grep tmpfs|grep -q "{{mount}}";echo $?)" != "x0"
    - watch:
      - file: mountpbfintmpfs-{{region}}
copy-mountpbfintmpfs-{{region}}:
  file.copy:
    - name: {{pbf}}
    - source: {{orig_pbf}}
    - user: {{cfg.user}}
    - group: {{cfg.group}}
    - unless: test -e {{droot}}/skip_import_{{region}}
    - watch:
      - cmd: mountpbfintmpfs-{{region}}
    - watch_in:
      - cmd: do-import-{{region}}
{% endif %}

# create the tempory db
{% set prod_db = 'planet_'+region %}
{% set db = 'planet_'+region+'_tmp' %}
{{ pgsql.postgresql_db(db, template="postgis", wait_for_template=False) }}
{{ pgsql.postgresql_user(db, password=cfg.data.db.password, db=db) }}

# run import
do-import-{{region}}:
  cmd.run:
    - env:
        PGPASS: "{{cfg.data.db.password}}"
    - name: |
            time osm2pgsql -c {{rdata.osm2pgql_args.strip()}} \
            -H 127.0.0.1 -d {{db}} -U {{db}} {{pbf}} && \
            touch {{droot}}/skip_import_{{region}}
    - unless: test -e {{droot}}/skip_import_{{region}}
    - user: {{cfg.user}}
    - watch:
      - file: download-pbf-{{region}}
umountpbfintmpfs-{{region}}:
  cmd.run:
    - name: umount "{{mount}}"
    - onlyif: test "x$(mount|grep tmpfs|grep -q "{{mount}}";echo $?)" = "x0"
    - watch:
      - file: mountpbfintmpfs-{{region}}
    - watch_in:
      - cmd: do-replace-prod-{{region}}
{% set prodswitch = "{0}/skip_prod_{1}".format(cfg.data_root, region) %}

# replace production database by import
do-replace-prod-{{region}}:
  cmd.run:
    - watch:
      - cmd: do-import-{{region}}
    - user: root
    - unless: test -e "{{prodswitch}}"
    - name: |
            set -e
            die() {
              ret="$1";shift;echo "${@}";if [ "x${ret}" != "x0" ];then exit 1;fi
            }
            if [ "x$(echo '\l'|su postgres -c psql -- -t|awk '{print $1}'|grep -v '|'|sort -u|egrep -q "^{{prod_db}}$";echo $?)" = "x0" ];then
              dropdb "{{prod_db}}"
            fi
            die "${?}" dropdb
            echo 'alter database "{{db}}" rename to "{{prod_db}}"'| su postgres -c psql
            die "${?}" rename
            echo 'alter database "{{prod_db}}" owner to "{{prod_db}}_owners"'| su postgres -c  psql
            die "${?}" grant
            touch "{{prodswitch}}"
    - onlyif: test "x$(echo '\l'|su postgres -c psql -- -t|awk '{print $1}'|grep -v '|'|sort -u|egrep -q "^{{db}}$";echo $?)" = "x0"

do-replace-prod-{{region}}-perms:
  cmd.run:
    - watch_in:
      - file: osm-install-cron-{{region}}
    - watch:
      - cmd: do-replace-prod-{{region}}
    - user: postgres
    - cwd: /
    - unless: test "x$(echo 'select * from planet_osm_nodes limit 3;'|psql "postgresql://{{prod_db}}:{{cfg.data.db.password}}@localhost:5432/{{prod_db}}" -t|wc -l)" = "x4"

    - name: |
            set -e
            die() {
              ret="$1";shift;echo "${@}";if [ "x${ret}" != "x0" ];then exit 1;fi
            }
            echo 'GRANT ALL PRIVILEGES ON DATABASE {{prod_db}} TO {{prod_db}}_owners;'| psql
            die "${?}" grant1
            echo 'GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO {{prod_db}}_owners;'| psql -d "{{prod_db}}"
            die "${?}" grant2
            echo 'GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO {{prod_db}}_owners;'| psql -d "{{prod_db}}"
            die "${?}" grant3
            echo 'GRANT ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA public TO {{prod_db}}_owners;'| psql -d "{{prod_db}}"
            die "${?}" grant4

osm-install-cron-{{region}}:
  file.managed:
    - name: {{cfg.data_root}}/minutediff-{{region}}
    - mode: 700
    - user: root
    - source: ''
    - contents: |
                #!/usr/bin/env bash
                LOG="{{cfg.data_root}}/log"
                lock="${0}.lock"
                if [ -e "${lock}" ];then
                  echo "Locked ${0}";exit 1
                fi
                touch "${lock}"
                salt-call --out="${LOG}" --retcode-passthrough -lall --local mc_project.run_task {{cfg.name}} task_minutediff region="{{region}}" 1>/dev/null 2>/dev/null
                ret="${?}"
                rm -f "${lock}"
                if [ "x${ret}" != "x0" ];then
                  cat "${LOG}"
                fi
                exit "${ret}"

osm-install-run-cron-{{region}}:
  file.managed:
    - watch:
      - file: osm-install-cron-{{region}}
    - name: /etc/cron.d/minutediff-{{region}}
    - mode: 700
    - user: root
    - source: ''
    - contents: |
                #!/usr/bin/env bash
                MAILTO="{{cfg.data.mail}}"
                {{rdata.periodicity}} root {{cfg.data_root}}/minutediff-{{region}}
{%endif%}
{%endfor%}
{%endfor%}


{% else %}
no-op: {mc_proxy.hook: []}
{%endif%}
