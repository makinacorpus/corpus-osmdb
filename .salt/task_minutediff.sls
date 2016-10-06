{% import "makina-states/services/db/postgresql/init.sls" as pgsql with context %}

# call with salt-call mc_project.run_task task_minutediff region=<region>
# this will KeyError if not given
{% set cfg = opts.ms_project %}
{% set data = cfg.data %}
{% set pregion = data.get('regions', {}) %}
{% for region, rdata in pregion.items() %}
{% set name = 'planet_{0}'.format(region) %}
{% if region in data.build %}
{% set droot = cfg.data_root%}
{% set db = 'planet_'+region %}

{% set statusd = "{0}/{1}_diff".format(droot, region) %}
{% set status = "{0}/status.txt".format(statusd) %}
# update last minute diff status file


{% macro silent_cmd(cmd) %}
    - name: |
            {{cmd}} 1>'{{cmd}}.stdout' 2>'{{cmd}}.stderr'
            ret=$?
            if [ "x${ret}" != "x0" ];then
              cat '{{cmd}}.stdout'
              cat '{{cmd}}.stderr'
            fi
            exit $ret
{% endmacro %}

minutediff-{{region}}-scripts:
  mc_proxy.hook : []

first-minutediff-{{region}}:
  file.directory:
    - name: {{statusd}}
    - user: {{cfg.user}}
    - group: {{cfg.group}}
    - makedirs: true
  cmd.run:
    - unless: test -e {{statusd}}/configuration.txt
    - user: {{cfg.user}}
    - watch:
      - file: first-minutediff-{{region}}
    - cwd: {{statusd}}
    - name: osmosis --read-replication-interval-init workingDirectory={{statusd}}
    - env:
        WORKDIR_OSM: {{statusd}}

first-minutediff-{{region}}-status:
  cmd.run:
    - name: curl "{{rdata.initial_state}}" > {{statusd}}/state.txt
    - unless: test -e "{{statusd}}/state.txt"
    - user: {{cfg.user}}
    - watch:
      - cmd: first-minutediff-{{region}}

first-minutediff-{{region}}-initialimport-t:
  file.managed:
    - unless: test -e "{{statusd}}/initial_import_{{region}}"
    - name: {{statusd}}/configuration.txt
    - source: salt://makina-projects/{{cfg.name}}/files/configuration.txt
    - makedirs: true
    - mode: 644
    - user: {{cfg.user}}
    - group: {{cfg.group}}
    - template: jinja
    - defaults:
        ttl: {{rdata.get('fttl', data.fttl)}}
    - watch:
      - cmd: first-minutediff-{{region}}-status
    - watch_in:
      - mc_proxy: minutediff-{{region}}-scripts

first-minutediff-{{region}}-initialimport:
  file.managed:
    - name: {{cfg.data_root}}/{{region}}_diff_scripts/ftosmosis.sh
    - contents: |
           #!/usr/bin/env bash
           cd {{statusd}} || exit 1
           rm -f download.lock
           echo "BEGIN: $(date)"
           export WORKDIR_OSM={{statusd}}
           osmosis --read-replication-interval workingDirectory=. \
              --simplify-change --write-xml-change changes.osc.gz && \
              touch "{{statusd}}/initial_osmosis_{{region}}"
           ret=$?
           echo "END: $(date)"
           exit $ret
    - unless: >
            test -e "{{statusd}}/initial_osmosis_{{region}}"
            || test -e "{{statusd}}/initial_import_{{region}}"
    - makedirs: true
    - mode: 750
    - user: {{cfg.user}}
    - group: {{cfg.group}}
    - template: jinja
    - watch_in:
      - mc_proxy: minutediff-{{region}}-scripts
  cmd.run:
    - user: {{cfg.user}}
    {{silent_cmd('{0}/{1}_diff_scripts/ftosmosis.sh'.format(
        cfg.data_root, region))}}
    - unless: test -e "{{statusd}}/initial_import_{{region}}"
    - watch:
      - mc_proxy: minutediff-{{region}}-scripts
      - file: first-minutediff-{{region}}-initialimport-t

osm-import-{{region}}:
  file.managed:
    - name: {{cfg.data_root}}/{{region}}_diff_scripts/ftosm2pgsql.sh
    - contents: |
           #!/usr/bin/env bash
           cd {{statusd}} || exit 1
           rm -f download.lock
           echo "BEGIN: $(date)"
           export PGPASS="{{cfg.data.db.password}}"
           osm2pgsql -a {{rdata.osm2pgql_args.strip()}} \
            -H 127.0.0.1 -d "{{db}}" -U "{{db}}" changes.osc.gz && \
            touch "{{statusd}}/initial_import_{{region}}"
           ret=$?
           echo "END: $(date)"
           exit $ret
    - makedirs: true
    - mode: 750
    - user: {{cfg.user}}
    - group: {{cfg.group}}
    - template: jinja
    - watch_in:
      - mc_proxy: minutediff-{{region}}-scripts
  cmd.run:
    - user: {{cfg.user}}
    {{silent_cmd('{0}/{1}_diff_scripts/ftosm2pgsql.sh'.format(
        cfg.data_root, region))}}
    - unless: test -e "{{statusd}}/initial_import_{{region}}"
    - watch:
      - cmd: first-minutediff-{{region}}-initialimport
      - mc_proxy: minutediff-{{region}}-scripts

# limit interval to 3 days max
minutediff-{{region}}-import-ttl:
  file.managed:
    - name: {{statusd}}/configuration.txt
    - source: salt://makina-projects/{{cfg.name}}/files/configuration.txt
    - user: {{cfg.user}}
    - group: {{cfg.user}}
    - template: jinja
    - defaults:
        ttl: {{rdata.get('ttl', data.ttl)}}
    - watch:
      - cmd: osm-import-{{region}}

# grab the last data for 3 hours each hour to be sure everything is ok
minutediff-{{region}}-import-pre:
  file.managed:
    - onlyif: test -e "{{cfg.data_root}}/initial_import_{{region}}"
    - name: {{cfg.data_root}}/{{region}}_diff_scripts/genimport.py
    - user: {{cfg.user}}
    - mode: 750
    - contents: |
                #!/usr/bin/env python
                import datetime
                import urllib2
                import sys
                hours = int({{rdata.get('diff_hours', 1)}})
                dt = datetime.datetime.now() - datetime.timedelta(hours=hours)
                with open('{{statusd}}/state.txt', 'w') as fic:
                  content = urllib2.urlopen(
                    '{{data.diffurl}}'.format(
                      dt.year, dt.month, dt.day,
                      dt.hour, dt.minute, dt.second)).read()
                  fic.write(content)
    - watch_in:
      - mc_proxy: minutediff-{{region}}-scripts
  cmd.run:
    - onlyif: test -e "{{cfg.data_root}}/initial_import_{{region}}"
    - name: {{cfg.data_root}}/{{region}}_diff_scripts/genimport.py
    - user: {{cfg.user}}
    - watch:
      - file: minutediff-{{region}}-import-ttl
      - mc_proxy: minutediff-{{region}}-scripts

osm-pull-lastdiff-{{region}}:
  file.managed:
    - name: {{cfg.data_root}}/{{region}}_diff_scripts/osmosis.sh
    - contents: |
           #!/usr/bin/env bash
           cd {{statusd}} || exit 1
           echo "BEGIN: $(date)"
           export WORKDIR_OSM={{statusd}}
           osmosis --read-replication-interval workingDirectory=. \
              --simplify-change --write-xml-change changes.osc.gz
           ret=$?
           echo "END: $(date)"
           exit $ret
    - makedirs: true
    - mode: 750
    - user: {{cfg.user}}
    - group: {{cfg.group}}
    - template: jinja
    - watch_in:
      - mc_proxy: minutediff-{{region}}-scripts
  cmd.run:
    - user: {{cfg.user}}
    {{silent_cmd('{0}/{1}_diff_scripts/osmosis.sh'.format(
        cfg.data_root, region)  )}}
    - onlyif: test -e "{{statusd}}/initial_import_{{region}}"
    - watch:
      - cmd: minutediff-{{region}}-import-pre
      - mc_proxy: minutediff-{{region}}-scripts

osm-import-lastdiff-{{region}}:
  file.managed:
    - name: {{cfg.data_root}}/{{region}}_diff_scripts/osm2pgsql.sh
    - contents: |
           #!/usr/bin/env bash
           cd {{statusd}} || exit 1
           echo "BEGIN: $(date)"
           export PGPASS="{{cfg.data.db.password}}"
           osm2pgsql -a {{rdata.osm2pgql_args.strip()}} \
            -H 127.0.0.1 -d "{{db}}" -U "{{db}}" changes.osc.gz
           ret=$?
           echo "END: $(date)"
           exit $ret
    - makedirs: true
    - mode: 750
    - user: {{cfg.user}}
    - group: {{cfg.group}}
    - template: jinja
    - watch_in:
      - mc_proxy: minutediff-{{region}}-scripts
  cmd.run:
    - user: {{cfg.user}}
    {{silent_cmd('{0}/{1}_diff_scripts/osm2pgsql.sh'.format(
        cfg.data_root, region))}}
    - onlyif: test -e "{{statusd}}/initial_import_{{region}}"
    - watch:
      - cmd: osm-pull-lastdiff-{{region}}
      - mc_proxy: minutediff-{{region}}-scripts
{%endif%}
{%endfor%}
