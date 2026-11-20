# SPDX-License-Identifier: GPL-3.0-or-later
# Learn bounded, per-identity daily histograms from complete IPv4 snapshots.
# Data retention: 14 UTC days, 64 identities, 12 logarithmic buckets/metric.
# One histogram observation per 15 minutes; no packets, URLs or destinations saved.
function bucket(v, b) {
    for (b=1; b<12; b++) if (v <= bound[b]) return b
    return 12
}
function valid_id(id) {
    return id ~ /^m:[0-9a-f:]+$/ || id ~ /^i:[0-9.]+$/
}
function valid_ip(ip, a,n,j) {
    n=split(ip,a,".")
    if (n!=4) return 0
    for (j=1;j<=4;j++) if (a[j] !~ /^[0-9]+$/ || a[j]+0 > 255) return 0
    return 1
}
function identity(ip) { return (ip in mac) ? "m:" mac[ip] : "i:" ip }
function high_limit(value, floor) { return value > floor ? value : floor }
function percentile(id, metric, total, target, accumulated, d,b) {
    if (!total) return 0
    target=total*0.95
    accumulated=0
    for (b=1;b<=12;b++) {
        for (d=today-13;d<=today;d++) accumulated += hist[id SUBSEP d SUBSEP metric SUBSEP b]
        if (accumulated>=target) return bound[b]
    }
    return bound[12]
}
BEGIN {
    split("0 2 4 8 16 32 64 128 256 512 1024 2048",bound," ")
    today=int(now/86400)
    if (now+0 < 1500000000) exit 2
    # MAC-first identity; only complete ARP entries are acceptable.
    while ((getline line < arp)>0) {
        split(line, f, /[[:space:]]+/)
        v=tolower(f[4]); if (valid_ip(f[1]) && f[3]=="0x2" &&
            v ~ /^([0-9a-f][0-9a-f]:){5}[0-9a-f][0-9a-f]$/) mac[f[1]]=v
    }
    close(arp)
    # Reject malformed / future / stale rows, and bound memory even if state is corrupt.
    lines=0
    while ((getline line < history)>0 && lines<896) {
        lines++
        nf=split(line,f,"\t")
        id=f[2]; day=f[3]+0; last=f[4]+0; num=f[5]+0
        if (nf!=7 || f[1]!="v1" || !valid_id(id) || f[3] !~ /^[0-9]+$/ ||
            f[4] !~ /^[0-9]+$/ || f[5] !~ /^[0-9]+$/ ||
            day<today-13 || day>today || last>now || last<day*86400 || last>=(day+1)*86400 ||
            num<1 || num>96 || ( !(id in known) && known_n>=64)) continue
        if (!(id in known)) {known[id]=1;known_n++}
        idx=id SUBSEP day
        if (idx in samples) continue
        samples[idx]=num; last_sample[idx]=last
        for (metric=1;metric<=2;metric++) {
            size=split(f[metric+5], bins, ",")
            if (size!=12) {invalid[idx]=1;break}
            for (b=1;b<=12;b++) {
                if (bins[b] !~ /^[0-9]+$/ || bins[b]+0>96) {invalid[idx]=1;break}
                hist[id SUBSEP day SUBSEP metric SUBSEP b]=bins[b]+0
            }
        }
        if (invalid[idx]) {
            delete samples[idx]; delete last_sample[idx]
            for (metric=1;metric<=2;metric++) for (b=1;b<=12;b++)
                delete hist[id SUBSEP day SUBSEP metric SUBSEP b]
        }
    }
    close(history)
    while ((getline line < streak)>0 && streak_n<64) {
        nf=split(line,f,"\t")
        if (nf!=3 || !valid_id(f[1]) || f[2] !~ /^[0-9]+$/ || f[3] !~ /^[0-9]+$/) continue
        if (f[1] in prior) continue
        prior[f[1]]=1; streak_n++
        bad[f[1]]=f[2]<3?f[2]+0:3
        good[f[1]]=f[3]<3?f[3]+0:3
    }
    close(streak)
    if ((getline line < metadata)<=0 || split(line,meta,"\t")!=3 || meta[3]!=0) exit 2
    close(metadata)
    total=meta[1]+0; devices=meta[2]+0
    if (total<0 || total>2048 || devices<0 || devices>32) exit 2
}
{
    if (NF!=3 || !valid_ip($1) || $2 !~ /^[0-9]+$/ || $3 !~ /^[0-9]+$/ ||
        $2+0>2048 || $3+0>2048 || n>=32) exit 2
    ip[++n]=$1; conn[n]=$2+0; dest[n]=$3+0
    id=identity($1); key[n]=id; observed[id]=1
    days=0; count=0
    for (day=today-13;day<=today;day++) {
        k=id SUBSEP day
        if (k in samples) {
            count+=samples[k]
            if (samples[k]>=4) days++
        }
    }
    day_count[n]=days
    mature=(days>=7 && count>=28)
    # Count all observed devices, before selecting the top 12 for the UI.
    if (mature) training_ready++
    else training_learning++
    if (days>=14 && count>=56) training_stable++
    if (mature) {
        pconn=percentile(id,1,count); pdest=percentile(id,2,count)
        limit_conn[n]=high_limit(int(pconn*1.6+0.5),80)
        limit_dest[n]=high_limit(int(pdest*1.6+0.5),20)
    } else {
        limit_conn[n]=0; limit_dest[n]=0
    }
    # During training only extreme sustained traffic may raise a warning.
    is_high=(mature && (conn[n]>limit_conn[n] || dest[n]>limit_dest[n])) ||
        (!mature && (conn[n]>=512 || dest[n]>=160))
    if (is_high) {bad[id]=(bad[id]<3)?bad[id]+1:3; good[id]=0}
    else {bad[id]=0; good[id]=(good[id]<3)?good[id]+1:3}
    flag[n]=is_high? ((bad[id]>=3)?"anomaly":"watch") : (mature?"normal":"learning")
    if (is_high && bad[id]>=3) {
        printf "%s\t%s\t%d\t%d\t%d\t%d\n",id,ip[n],conn[n],dest[n],limit_conn[n],limit_dest[n] > candidate
        if (!alert_n++) {alert_ip=ip[n];alert_conn=conn[n];alert_dest=dest[n]}
    }
    if (!is_high && good[id]>=3) print id > recovered
    # Never poison the trained baseline with detected anomalies or repeated 60s observations.
    k=id SUBSEP today
    if (!is_high && ( !(k in last_sample) || now-last_sample[k]>=900 ) &&
        ((id in known) || known_n<64) && samples[k]<96) {
        if (!(id in known)) {known[id]=1;known_n++}
        hist[id SUBSEP today SUBSEP 1 SUBSEP bucket(conn[n])]++
        hist[id SUBSEP today SUBSEP 2 SUBSEP bucket(dest[n])]++
        samples[k]++; last_sample[k]=now
    }
}
END {
    if (now+0<1500000000 || meta[3]!=0 || error) exit 2
    # Three complete normal/absent samples are required to end an alert episode.
    for (id in prior) if (!(id in observed)) {
        bad[id]=0; good[id]=(good[id]<3)?good[id]+1:3
        if (good[id]>=3) print id > recovered
    }
    for (id in known) for (day=today-13;day<=today;day++) {
        k=id SUBSEP day
        if (!(k in samples) || samples[k]<1) continue
        printf "v1\t%s\t%d\t%d\t%d",id,day,last_sample[k],samples[k] > new_history
        for (metric=1;metric<=2;metric++) {
            printf "\t" > new_history
            for (b=1;b<=12;b++)
                printf "%s%d",(b==1?"":","),hist[id SUBSEP day SUBSEP metric SUBSEP b]+0 > new_history
        }
        printf "\n" > new_history
    }
    close(new_history)
    for (id in prior) if (!(id in observed) && good[id]<3)
        printf "%s\t%d\t%d\n",id,bad[id],good[id] > new_streak
    for (j=1;j<=n;j++) {
        id=key[j]
        printf "%s\t%d\t%d\n",id,bad[id],good[id] > new_streak
    }
    close(new_streak); close(candidate); close(recovered)
    # Generate the status in one pass; status consumer enforces 8KiB limit.
    progress=0
    for (j=1;j<=n;j++) if (day_count[j]>progress) progress=day_count[j]
    printf "{\"schema\":1,\"phase\":\"ready\",\"sampledAt\":%d,\"intervalSeconds\":60,\"source\":\"conntrack\",\"ipv4Only\":true,\"limited\":false,\"totalConnections\":%d,\"totalDevices\":%d,\"trainingDays\":%d,\"trainingTargetDays\":14,\"trainingReadyDevices\":%d,\"trainingLearningDevices\":%d,\"trainingStableDevices\":%d,\"devices\":[",now,total,devices,progress,training_ready,training_learning,training_stable > status
    # The conntrack parser captures up to 32 devices but the UI receives 12.
    # Prioritize active anomaly -> watch -> learning -> normal BEFORE capping.
    # Bounded selection (32 x 12) avoids external sort and extra tmpfs files.
    for (j=1;j<=n;j++) priority[j]=(flag[j]=="anomaly"?4:(flag[j]=="watch"?3:(flag[j]=="learning"?2:1)))
    for (slot=1;slot<=n && slot<=12;slot++) {
        best=0
        for (j=1;j<=n;j++) {
            if (selected[j]) continue
            if (!best || priority[j]>priority[best] ||
                (priority[j]==priority[best] && conn[j]>conn[best]) ||
                (priority[j]==priority[best] && conn[j]==conn[best] && dest[j]>dest[best])) best=j
        }
        if (!best) break
        selected[best]=1
        printf "%s{\"ip\":\"%s\",\"connections\":%d,\"destinations\":%d,\"trainingDays\":%d,\"baselineConnections\":%s,\"baselineDestinations\":%s,\"state\":\"%s\"}", (slot>1?",":""),ip[best],conn[best],dest[best],day_count[best],(limit_conn[best]?limit_conn[best]:"null"),(limit_dest[best]?limit_dest[best]:"null"),flag[best] > status
    }
    printf "],\"alert\":" > status
    if (alert_n) printf "{\"ip\":\"%s\",\"connections\":%d,\"destinations\":%d}",alert_ip,alert_conn,alert_dest > status
    else printf "null" > status
    print "}" > status
    close(status)
}
