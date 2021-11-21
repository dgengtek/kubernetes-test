[node]
%{for item in inventory~}
%{if item.role == "node"~}
${item.hostname} ansible_host=${item.ip}
%{endif~}
%{endfor~}

[master]
%{for item in inventory~}
%{if item.role == "master"~}
${item.hostname} ansible_host=${item.ip}
%{endif~}
%{endfor~}

[cpn]
%{for item in inventory~}
%{if item.role == "cpn" || item.role == "master" ~}
${item.hostname} ansible_host=${item.ip}
%{endif~}
%{endfor~}

[all:vars]
cpn_api_ha_port=${cpn_api_ha_port}
cpn_api_port=${cpn_api_port}
vip=${vip}
network_prefix=${network_prefix}

[cpn:vars]
keepalived_password=${keepalived_password}
