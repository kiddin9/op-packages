FBFDownloader_makefile is the Makefile of fbfdownloader
libmakefile is the Makefile of libfbfdown.a, api is in fbfdownload.h.


//return 0 SUCCRSS
//return 1 FAIL
//timeout 0 Infinite Wait
//timeout >0 Wait N seconds for Download
int fbfdownload(char * strBinFilePath, int timeout);