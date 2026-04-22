#ifndef FBF_H
#define FBF_H

#include <stdlib.h>
#include <stdio.h>

//return 0 SUCCRSS
//return 1 FAIL
//timeout 0 Infinite Wait
//timeout >0 Wait N seconds for Download
#ifdef __cplusplus
extern "C"{
#endif 
int fbfdownload(char * strBinFilePath, int timeout);

#ifdef __cplusplus
}
#endif 



#endif
