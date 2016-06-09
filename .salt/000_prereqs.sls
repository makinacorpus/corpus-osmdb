{%- import "makina-states/services/db/postgresql/hooks.sls" as hooks with context %}
{%- set pg = salt['mc_pgsql.settings']() %}
{%- set cfg = opts.ms_project %}
{%- set orchestrate = hooks.orchestrate %}
{%- import "makina-states/services/db/postgresql/init.sls" as pgsql with context %}
{%- import "makina-states/services/db/postgresql/hooks.sls" as hooks with context %}
{%- set data = cfg.data %}
{%- set ver = data.pgver%}
{%- set db = cfg.data.db %}
include:
  - makina-states.services.db.postgresql
  - makina-states.services.gis.postgis
  - makina-states.services.gis.ubuntugis


{%- set sysctls = {} %}
{%- for dsysctl in data.sysctls %}
{%- for sysctl, val in dsysctl.items() %}
{%- if val is not none %}
{%- do sysctls.update({sysctl: val})%}
{%- endif %}
{%- endfor %}
{%- endfor %}
{%- for sysctl, val in sysctls.items() %}
{{sysctl}}-{{cfg.name}}:
  sysctl.present:
    - config: /etc/sysctl.d/00_{{cfg.name}}sysctls.conf
    - name: {{sysctl}}
    - value: {{val}}
    - watch_in:
      - service: reload-sysctls-{{cfg.name}}
{% endfor %}
{% if sysctls %}
reload-sysctls-{{cfg.name}}:
  service.running:
    - name: procps
    - enable: true
    - watch_in:
      - mc_proxy: {{orchestrate['base']['postbase']}}
      - pkgs: {{cfg.name}}-prereqs
{% endif %}


{{cfg.name}}-prereqs:
  pkg.latest:
    - pkgs:
      - autoconf
      - automake
      - build-essential
      - bzip2
      - curl
      - cython
      - fonts-khmeros
      - fonts-sil-padauk
      - fonts-sipa-arundina
      - g++
      - gdal-bin
      - geoip-bin
      - gettext
      - git
      - groff
      - libbz2-dev
      - libdb-dev
      - libfreetype6-dev
      - libgdal1-dev
      - libgdbm-dev
      - libgeoip-dev
      - libgeos-dev
      - libopenjpeg-dev
      - libpq-dev
      - libreadline-dev
      - libsigc++-2.0-dev
      - libsqlite0-dev
      - libsqlite3-dev
      - libssl-dev
      - libtiff5
      - libtiff5-dev
      - libtool
      - libwebp5
      - libwebp-dev
      - libwww-perl
      - libxml2-dev
      - libxslt1-dev
      - m4
      - man-db
      - libmapnik-dev
      - libcurl4-gnutls-dev
      #- libcurl4-openssl-dev
      - mapnik-utils
      - node-carto
      - osm2pgsql
      - pkg-config
      - poppler-utils
      - python-dev
      - python-numpy
      - tcl8.4
      - tcl8.4-dev
      - tcl8.5
      - tcl8.5-dev
      - tk8.5-dev
      - ttf-dejavu
      {% if not pg.xenial_onward %}
      - ttf-indic-fonts-core
      - ttf-tamil-fonts
      - ttf-kannada-fonts
      - fonts-droid
      {% else %}
      - fonts-indic
      - fonts-knda
      - fonts-droid-fallback
      - fonts-taml
      {% endif %}
      - ttf-unifont
      - unzip
      - zlib1g-dev
    - require:
      - pkg: postgresql-pkgs
    - watch_in:
      - mc_proxy: {{orchestrate['base']['postbase']}}


buildosmconvert-{{cfg.name}}:
  cmd.run:
    - unless: test -e {{cfg.data_root}}/osmconvert
    - name: |
          wget -O - http://m.m.i24.cc/osmconvert.c | \
            cc -x c - -lz -O3 -o osmconvert
    - user: {{cfg.user}}
    - cwd: {{cfg.data_root}}
    - watch_in:
      - mc_proxy: {{orchestrate['base']['postbase']}}

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
      - mc_proxy: {{orchestrate['base']['postbase']}}
{% endif %}
