{% set cfg = opts.ms_project %}
{% if cfg.data.has_db %}
{% set data = cfg.data %}
{% set ver = data.pgver%}
{% set db = cfg.data.db %}

{% set pkgssettings = salt['mc_pkgs.settings']() %}
include:
  - makina-states.localsettings.jdk

{% if grains['os_family'] in ['Debian'] %}
{% set dist = pkgssettings.udist %}
{% endif %}
{% if grains['os'] in ['Debian'] %}
{% set dist = pkgssettings.ubuntu_lts %}
{% endif %}

{{cfg.name}}-prereqs-osmosis:
  pkgrepo.managed:
    - humanname: haproxy ppa
    - name: deb http://ppa.launchpad.net/kakrueger/openstreetmap/ubuntu/ {{dist}} main
    - dist: {{dist}}
    - file: {{ salt['mc_locations.settings']().conf_dir }}/apt/sources.list.d/osm.list
    - keyid: B745A04C
    - keyserver: keyserver.ubuntu.com
    - watch:
      - mc_proxy: makina-states-jdk_last
  pkg.latest:
    - pkgs:
      - osmosis
    - watch:
      - pkgrepo: {{cfg.name}}-prereqs-osmosis

{% else %}
no-op: {mc_proxy.hook: []}
{% endif %}
