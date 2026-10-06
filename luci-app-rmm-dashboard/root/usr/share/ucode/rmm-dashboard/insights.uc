import * as fs from 'fs';
let vendor_cache={},vendor_stamp='';
function mac_key(mac) {
    return type(mac)=='string' && match(mac,/^[0-9a-f]{2}(:[0-9a-f]{2}){5}$/i) && !(int(substr(mac,0,2),16)&1) && mac!='00:00:00:00:00:00' ? uc(mac) : null;
}
export function vendors_for(macs,path) {
    let result={},wanted={},prefixes={},info=fs.stat(path);
    if (!info || info.type!='file' || info.size>8388608) return {vendors:{},vendor_error:'Local vendor database unavailable'};
    let stamp=path+'/'+info.mtime+'/'+info.size;
    if (stamp!=vendor_stamp || length(vendor_cache)>1024) {vendor_cache={};vendor_stamp=stamp;}
    for (let value in slice(macs,0,1024)) {
        let mac=mac_key(value);
        if (!mac || (int(substr(mac,0,2),16)&2)) continue;
        let prefix=replace(substr(mac,0,8),':','');prefixes[mac]=prefix;
        if(vendor_cache[prefix]==null)wanted[prefix]=true;
    }
    if(length(wanted)) {
        let file=fs.open(path,'r');
        if(!file)return {vendors:{},vendor_error:'Local vendor database unavailable'};
        let count=0;
        for(let line=file.read('line');type(line)=='string' && length(line);line=file.read('line')) {
            if(++count>100000){file.close();return {vendors:{},vendor_error:'Invalid vendor database'};}
            let fields=split(trim(line), '\t');
            if(length(fields)==2 && wanted[fields[0]])vendor_cache[fields[0]]=fields[1];
        }
        file.close();
        for(let prefix in wanted)if(vendor_cache[prefix]==null)vendor_cache[prefix]='';
    }
    for(let mac,prefix in prefixes)if(length(vendor_cache[prefix]))result[mac]=vendor_cache[prefix];
    return {vendors:result,vendor_registry:'IEEE MA-L'};
};
export function parse_traffic(text) {
    if(type(text)!='string' || length(text)>262144)die('Invalid traffic response');
    let data=json(text),clients={};
    if(type(data.columns)!='array' || type(data.data)!='array' || length(data.data)>2048)die('Invalid traffic response');
    let mac_index=index(data.columns,'mac'),rx_index=index(data.columns,'rx_bytes'),tx_index=index(data.columns,'tx_bytes');
    if(mac_index<0 || rx_index<0 || tx_index<0)die('Invalid traffic columns');
    for(let row in data.data) {
        if(type(row)!='array')die('Invalid traffic row');
        let mac=mac_key(row[mac_index]),rx=row[rx_index],tx=row[tx_index];
        if(!mac)continue;
        if(type(rx)!='int' || type(tx)!='int' || rx<0 || tx<0 || rx>9007199254740991 || tx>9007199254740991 || clients[mac])die('Invalid traffic counters');
        if(length(clients)>=512)die('Traffic client limit reached');
        clients[mac]={rx_bytes:rx,tx_bytes:tx};
    }
    return {status:'current',source:'nlbwmon',clients:clients};
};
let traffic_cache=null,traffic_at=0;
export function traffic_snapshot() {
    let now=time();
    if(traffic_cache && now>=traffic_at && now-traffic_at<30)return traffic_cache;
    traffic_at=now;
    if(!fs.access('/usr/sbin/nlbw'))return traffic_cache={status:'unavailable',reason:'nlbwmon not installed',at:now,clients:{}};
    if(!fs.access('/var/run/nlbwmon.sock'))return traffic_cache={status:'unavailable',reason:'nlbwmon is not running',at:now,clients:{}};
    try {
        // Fixed, bounded read command. No commit/reset, UCI write, netlink poll or arbitrary arguments.
        let file=fs.popen('/bin/busybox timeout 2 /usr/sbin/nlbw -c json -g mac -o mac 2>/dev/null','r');
        if(!file)die('Traffic accounting unavailable');
        let text=file.read(262145);file.close();
        let reply=parse_traffic(text);reply.at=now;traffic_cache=reply;
    }
    catch(err){traffic_cache={status:'unavailable',reason:'Traffic accounting unavailable',at:now,clients:{}};}
    return traffic_cache;
};
