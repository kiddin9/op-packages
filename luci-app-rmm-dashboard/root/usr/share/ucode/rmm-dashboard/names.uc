import * as fs from 'fs';

function valid_mac(mac) {
    return type(mac)=='string' && match(mac,/^[0-9a-f]{2}(:[0-9a-f]{2}){5}$/i) && !(int(substr(mac,0,2),16)&1) && mac!='00:00:00:00:00:00';
}
function valid_name(name) {
    return type(name)=='string' && length(name)<=256 && !match(name,/[[:cntrl:]]/);
}
export function read_names(path) {
    let info=fs.lstat(path);
    if (!info) {
        let err=fs.error();
        if (err=='No such file or directory') return {};
        die(err ?? 'Unable to read client names');
    }
    if (info.type!='file' || info.size>131072) die('Invalid client name storage');
    let text=fs.readfile(path);
    if (text==null) die(fs.error() ?? 'Unable to read client names');
    let data=json(text);
    if (type(data)!='object' || data.version!=1 || type(data.names)!='object' || length(data.names)>512) die('Invalid client name storage');
    for (let mac,name in data.names)
        if (!valid_mac(mac) || mac!=uc(mac) || !valid_name(name) || !length(trim(name))) die('Invalid client name storage');
    return data.names;
};
// The caller supplies a fixed server-side path, never an RPC argument.
export function save_name(path,mac,name,previous) {
    if (!valid_mac(mac) || !valid_name(name) || !valid_name(previous)) die('Invalid client name');
    mac=uc(mac);name=trim(name);
    let directory=fs.dirname(path);
    if (!fs.stat(directory) && !fs.mkdir(directory,0700)) die(fs.error() ?? 'Unable to create name storage');
    let lock=path+'.lock', temporary=path+'.tmp';
    if (!fs.mkdir(lock,0700)) die('Client names are busy; retry');
    try {
        let names=read_names(path);
        if ((names[mac] ?? '')!=previous) die('Client name changed; refresh before saving');
        if (!length(name)) delete names[mac];
        else names[mac]=name;
        if (length(names)>512) die('Client name limit reached');
        let content=sprintf('%J', {version:1,names})+'\n';
        if (length(content)>131072) die('Client name storage limit reached');
        fs.unlink(temporary);
        let file=fs.open(temporary,'w',0600);
        if (!file) die(fs.error() ?? 'Unable to save client names');
        let written=file.write(content), closed=file.close();
        if (written!=length(content) || !closed) die('Unable to save client names');
        if (!fs.rename(temporary,path)) die(fs.error() ?? 'Unable to save client names');
        fs.rmdir(lock);
        return names;
    }
    catch (err) {
        fs.unlink(temporary);fs.rmdir(lock);die(err);
    }
};