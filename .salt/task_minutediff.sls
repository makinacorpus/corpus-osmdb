{% import "makina-states/services/db/postgresql/init.sls" as pgsql with context %}

# call with salt-call mc_project.run_task task_minutediff region=<region>
# this will KeyError if not given
{% set cfg = opts.ms_project %}
{% set data = cfg.data %}
{% set pregion = data.get('region', None) %}
{% if not pregion %}
YOU MUST SELECT A REGION via region=arg!
{% endif %}

{% if pregion%}
{% for dregion in data.regions %}
{% for region, rdata in dregion.items() %}
{% set name = 'planet_{0}'.format(region) %}
{% if region in data.build and region == pregion %}
{% set droot = cfg.data_root%}
{% set db = 'planet_'+region %}

{% set statusd = "{0}/{1}-osmdif".format(droot, region) %}
{% set status = "{0}/status.txt".format(statusd) %}
# update last minute diff status file

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
    - name: |
            osmosis --read-replication-interval-init workingDirectory={{statusd}}
    - env:
        WORKDIR_OSM: {{statusd}}

first-minutediff-{{region}}-status:
  cmd.run:
    - name: curl "{{rdata.initial_state}}" > {{statusd}}/state.txt
    - unless: test -e "{{statusd}}/initial_import_{{region}}"
    - user: {{cfg.user}}
    - watch:
      - cmd: first-minutediff-{{region}}

first-minutediff-{{region}}-initialimport:
  file.managed:
    - unless: test -e "{{statusd}}/initial_import_{{region}}"
    - name: {{statusd}}/configuration.txt
    - source: salt://makina-projects/{{cfg.name}}/files/configuration.txt
    - user: {{cfg.user}}
    - group: {{cfg.user}}
    - template: jinja
    - defaults:
        ttl: {{rdata.ttl}}
    - watch:
      - cmd: first-minutediff-{{region}}-status
  cmd.run:
    - use_vt: true
    - unless: test -e "{{statusd}}/initial_import_{{region}}"
    - user: {{cfg.user}}
    - cwd: {{statusd}}
    - watch:
      - file: first-minutediff-{{region}}-initialimport
    - name: |
            rm -f download.lock
            osmosis --read-replication-interval workingDirectory="{{statusd}}" \
              --simplify-change --write-xml-change changes.osc.gz
    - env:
        WORKDIR_OSM: {{statusd}}

osm-import-{{region}}:
  cmd.run:
    - use_vt: true
    - watch:
      - cmd: first-minutediff-{{region}}-initialimport
    - unless: test -e "{{statusd}}/initial_import_{{region}}"
    - env:
        PGPASS: "{{cfg.data.db.password}}"
    - user: {{cfg.user}}
    - cwd: {{statusd}}
    - name: |
            time osm2pgsql -a {{rdata.osm2pgql_args.strip()}} \
            -H 127.0.0.1 -d "{{db}}" -U "{{db}}" changes.osc.gz && \
            touch "{{statusd}}/initial_import_{{region}}"

# limit interval to 3 days max
minutediff-{{region}}-import-ttl:
  file.managed:
    - name: {{statusd}}/configuration.txt
    - source: salt://makina-projects/{{cfg.name}}/files/configuration.txt
    - user: {{cfg.user}}
    - group: {{cfg.user}}
    - template: jinja
    - defaults:
        ttl: {{60*60*24*3}}
    - watch:
      - cmd: osm-import-{{region}}

# grab the last data for 3 hours each hour to be sure everything is ok
minutediff-{{region}}-import-pre:
  file.managed:
    - name: {{statusd}}/genimport.py
    - user: {{cfg.user}}
    - mode: 755
    - watch:
      - file: minutediff-{{region}}-import-ttl
    - contents: |
                #!/usr/bin/env python
                import datetime
                import urllib2
                import sys
                dt = datetime.datetime.now() - datetime.timedelta(hours=3)
                with open('{{statusd}}/state.txt', 'w') as fic:
                  content = urllib2.urlopen(
                    'http://osm.personalwerk.de/'
                    'replicate-sequences/'
                    '?Y={0}&m={1}&d={2}&H={3}&i={4}&s={5}&stream=minute'.format(
                      dt.year, dt.month, dt.day,
                      dt.hour, dt.minute, dt.second)).read()
                  fic.write(content)
  cmd.run:
    - onlyif: test -e "{{statusd}}/initial_import_{{region}}"
    - name: {{statusd}}/genimport.py
    - user: {{cfg.user}}
    - watch:
      - file: minutediff-{{region}}-import-pre

osm-pull-lastdiff-{{region}}:
  cmd.run:
    - use_vt: true
    - watch:
      - cmd: minutediff-{{region}}-import-pre
    - user: {{cfg.user}}
    - cwd: {{statusd}}
    - name: osmosis --rri workingDirectory=. --wxc changes.osc.gz

osm-import-lastdiff-{{region}}:
  cmd.run:
    - use_vt: true
    - onlyif: test -e "{{statusd}}/initial_import_{{region}}"
    - watch:
      - cmd: osm-pull-lastdiff-{{region}}
    - env:
        PGPASS: "{{cfg.data.db.password}}"
    - user: {{cfg.user}}
    - cwd: {{statusd}}
    - name: |
            time osm2pgsql -a {{rdata.osm2pgql_args.strip()}} \
            -H 127.0.0.1 -d "{{db}}" -U "{{db}}" changes.osc.gz
{#
http://wiki.openstreetmap.org/wiki/User:Stephankn/knowledgebase#Cleanup_of_ways_outside_the_bounding_box
seems too much harmfull for now, need investigating
osm-bordelcleanup-{{region}}:
  file.managed:
    - name: {{statusd}}/cleanup.sql
    - source: salt://makina-projects/{{cfg.name}}/files/cleanup.sql
    - user: {{cfg.user}}
    - mode: 755
    - watch:
      - cmd: osm-import-lastdiff-{{region}}
  cmd.run:
    - use_vt: true
    - name: psql "postgresql://{{db}}:{{cfg.data.db.password}}@localhost:5432/{{db}}" -f "{{statusd}}/cleanup.sql"
    - user: {{cfg.user}}
    - watch:
      - file: osm-bordelcleanup-{{region}}
#}
{%endif%}
{%endfor%}
{%endfor%}
{% else %}
no-op: {mc_proxy.hook: []}
{%endif%}
