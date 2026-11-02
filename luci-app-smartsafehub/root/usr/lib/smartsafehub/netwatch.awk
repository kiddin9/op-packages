# SPDX-License-Identifier: GPL-3.0-or-later
# Bounded connection snapshot. Only IPv4 forwarded-looking private -> public
# tuples are counted; a snapshot is an observation, NOT an intrusion verdict.
function local_ip(ip, n,a) {
    n = split(ip,a,".")
    if (n != 4) return 0
    for (i=1;i<=4;i++) if (a[i] !~ /^[0-9]+$/ || a[i] < 0 || a[i] > 255) return 0
    return a[1] == 10 || (a[1] == 172 && a[2] >= 16 && a[2] <= 31) ||
        (a[1] == 192 && a[2] == 168) || (a[1] == 100 && a[2] >= 64 && a[2] <= 127)
}
function public_ip(ip, n,a) {
    n = split(ip,a,".")
    if (n != 4) return 0
    for (i=1;i<=4;i++) if (a[i] !~ /^[0-9]+$/ || a[i] < 0 || a[i] > 255) return 0
    return !local_ip(ip) && a[1] != 0 && a[1] != 127 && a[1] < 224 &&
        !(a[1] == 169 && a[2] == 254) && !(a[1] == 198 && (a[2] == 18 || a[2] == 19))
}
BEGIN {
    while ((getline line < previous) > 0) {
        split(line, fields, "\t")
        if (fields[1] ~ /^[0-9.]+$/) { prev_count[fields[1]] = fields[2]+0; prev_dest[fields[1]] = fields[3]+0 }
    }
    close(previous)
}
{
    if (NR > 2048) { truncated=1; exit }
    if ($0 !~ /(^|[[:space:]])(tcp|udp|icmp|ipv4)([[:space:]]|$)/) next
    src=""; dst=""; proto=""
    for (j=1;j<=NF;j++) {
        if ($j == "tcp" || $j == "udp") proto=$j
        if ($j ~ /^src=/ && src == "") src=substr($j,5)
        if ($j ~ /^dst=/ && dst == "") dst=substr($j,5)
    }
    if (proto == "" || !local_ip(src) || !public_ip(dst)) next
    # Bound the number of tracked devices and distinct destination pairs.
    if (!(src in dev_seen)) {
        if (dev_n >= 32) { truncated=1; next }
        dev_seen[src]=1; order[++dev_n]=src
    }
    count[src]++; total++
    key=src SUBSEP dst
    if (!(key in dest_seen)) { dest_seen[key]=1; destinations[src]++ }
}
END {
    printf "" > snapshot
    for (k=1;k<=dev_n;k++) {
        ip=order[k]
        # Partial snapshots are never a trustworthy consecutive baseline.
        if (!truncated) printf "%s\t%d\t%d\n", ip,count[ip],destinations[ip] > snapshot
        if (!truncated &&
            ((count[ip] >= 120 && prev_count[ip] >= 120) ||
             (destinations[ip] >= 40 && prev_dest[ip] >= 40))) {
            if (candidate_ip == "") {
                candidate_ip=ip; candidate_connections=count[ip]; candidate_dest=destinations[ip]
            }
            printf "%s\t%d\t%d\n", ip, count[ip], destinations[ip] > candidate
        }
    }
    close(snapshot)
    close(candidate)
    printf "{\"schema\":1,\"phase\":\"ready\",\"sampledAt\":%d,\"intervalSeconds\":60,\"source\":\"conntrack\",\"ipv4Only\":true,\"limited\":%s,\"totalConnections\":%d,\"totalDevices\":%d,\"devices\":[", now, truncated ? "true":"false",total,dev_n > status
    for (k=1;k<=dev_n && k<=12;k++) {
        ip=order[k]
        printf "%s{\"ip\":\"%s\",\"connections\":%d,\"destinations\":%d}", (k > 1 ? "," : ""),ip,count[ip],destinations[ip] > status
    }
    printf "],\"alert\":" > status
    if (candidate_ip != "")
        printf "{\"ip\":\"%s\",\"connections\":%d,\"destinations\":%d}",candidate_ip,candidate_connections,candidate_dest > status
    else printf "null" > status
    print "}" > status
    close(status)
}
