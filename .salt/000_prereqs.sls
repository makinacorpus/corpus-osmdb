{% set cfg = opts.ms_project %}
{% if cfg.data.has_db %}
{% import "makina-states/services/db/postgresql/init.sls" as pgsql with context %}
{% set data = cfg.data %}
{% set ver = data.pgver%}
{% set db = cfg.data.db %}
include:
  - makina-states.services.gis.postgis

{% set pkgssettings = salt['mc_pkgs.settings']() %}
{% if grains['os_family'] in ['Debian'] %}
{% set dist = pkgssettings.udist %}
{% endif %}
{% if grains['os'] in ['Debian'] %}
{% set dist = pkgssettings.ubuntu_lts %}
{% endif %}

{{cfg.name}}-prereqs:
  pkgrepo.managed:
    - humanname: haproxy ppa
    - name: deb http://ppa.launchpad.net/kakrueger/openstreetmap/ubuntu/ {{dist}} main
    - dist: {{dist}}
    - file: {{ salt['mc_locations.settings']().conf_dir }}/apt/sources.list.d/osm.list
    - keyid: B745A04C
    - keyserver: keyserver.ubuntu.com
  pkg.latest:
    - pkgs:
      - osm2pgsql
    - watch:
      - pkgrepo: {{cfg.name}}-prereqs
    - watch_in:
      - mc_proxy: makina-postgresql-pre-base

{%for dsysctl in data.sysctls %}
{%for sysctl, val in dsysctl.items() %}
{% if val is not none %}
{{sysctl}}-{{cfg.name}}:
  sysctl.present:
    - config: /etc/sysctl.d/00_{{cfg.name}}sysctls.conf
    - name: {{sysctl}}
    - value: {{val}}
    - watch_in:
      - mc_proxy: makina-postgresql-pre-base
      - service: reload-sysctls-{{cfg.name}}
{% endif %}
{% endfor %}
{% endfor %}
{% set optim = data.get('pg_optim', []) %}
{% if optim %}
pgtune-{{cfg.name}}:
  file.managed:
    - name: /etc/postgresql/{{ver}}/main/conf.d/optim{{cfg.name}}.conf
    - source: ''
    - contents: |
                {% for o in optim %}
                {{o}}
                {% endfor %}
    - mode: 755
    - group: user
    - group: root
    - watch_in:
      - mc_proxy: makina-postgresql-pre-base
      - service: reload-sysctls-{{cfg.name}}
{% endif %}
{% if grains['os'] in ['Ubuntu'] %}
reload-sysctls-{{cfg.name}}:
  service.running:
    - name: procps
    - enable: true
    - watch:
      - mc_proxy: makina-postgresql-pre-base
{% endif %}

buildosmconvert-{{cfg.name}}:
  cmd.run:
    - name: wget -O - http://m.m.i24.cc/osmconvert.c | cc -x c - -lz -O3 -o osmconvert
    - user: {{cfg.user}}
    - cwd: {{cfg.data_root}}

{% else %}
no-op: {mc_proxy.hook: []}
{% endif %}
