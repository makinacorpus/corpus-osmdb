{% set cfg = opts.ms_project %}
{% set data = cfg.data %}
{% for region, rdata in data.regions.items() %}
{% if region in data.build %}
osm-install-{{region}}-minutediff:
  mc_proxy.hook: []
osm-install-{{region}}-d:
  file.directory:
    - names:
      - {{cfg.data_root}}/{{region}}
      - {{cfg.data_root}}/{{region}}_diff
      - {{cfg.data_root}}/{{region}}_diff_scripts
    - makedirs: true
    - mode: 744
    - user: {{cfg.user}}
    - group: {{cfg.group}}
    - watch:
      - mc_proxy: osm-install-{{region}}-minutediff
osm-install-cron-{{region}}:
  file.managed:
    - name: {{cfg.data_root}}/{{region}}_diff_scripts/cron.sh
    - makedirs: true
    - mode: 755
    - user: {{cfg.user}}
    - group: {{cfg.user}}
    - source: ''
    - contents: |
                #!/usr/bin/env bash
                LOG="{{cfg.data_root}}/{{region}}_diff_scripts/cron.log"
                lock="${0}.lock"
                find "${lock}" -type f -mmin +60 -delete 1>/dev/null 2>&1
                find "${LOG}" -type f -size +30M -delete 1>/dev/null 2>&1
                if [ -e "${lock}" ];then
                  echo "Locked ${0}";exit 1
                fi
                touch "${lock}"
                echo "cron date: $(date)" >> "${LOG}"
                salt-call --local --out-file="${LOG}.last" --retcode-passthrough -lall --local \
                      mc_project.run_task {{cfg.name}} task_minutediff region="{{region}}" 1>/dev/null 2>/dev/null
                ret="${?}"
                cat "${LOG}.last"  >> "${LOG}" 2>/dev/null
                echo "cron date end: $(date)" >> "${LOG}"
                echo "ret: ${ret}" >> "${LOG}"
                rm -f "${lock}"
                if [ "x${ret}" != "x0" ];then
                  cat "${LOG}"
                fi
                exit "${ret}"
    - watch:
      - file: osm-install-{{region}}-d
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
                {{rdata.periodicity}} root {{cfg.data_root}}/{{region}}_diff_scripts/cron.sh
{% endif %}
{% endfor %}
