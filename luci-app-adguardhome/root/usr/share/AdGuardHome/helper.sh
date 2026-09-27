#!/bin/sh
# Auxiliary functions specially used for reading and writing YAML
config_editor() {
    awk -v yaml="$1" -v value="$2" -v file="$3" -v ro="$4" '
    BEGIN{split(yaml,part,"\.");s="";i=1;l=length(part);}
    {
        if (match($0,s""part[i]":")) {
            if (i==l) {
                split($0,t,": ");
                if (ro==""){
                    system("sed -i '\''"FNR"c\\" t[1] ": " value "'\'' " file " >/dev/null 2>&1");
                } else {
                    print(t[2]);
                }
                exit;
            }
            s=s"[- ]{2}";
            i++;
        }
    }' "$3"
}
