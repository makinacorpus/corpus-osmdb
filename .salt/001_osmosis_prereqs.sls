{% set cfg = opts.ms_project %}
{% set data = cfg.data %}

include:
  - makina-states.localsettings.jdk

{{cfg.name}}-prereqs-osmosis:
  pkg.latest:
    - pkgs:
      - osmosis
