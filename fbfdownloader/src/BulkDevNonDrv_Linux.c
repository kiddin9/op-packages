#include "BulkDevNonDrv_Linux.h"

#define MAX_RETRIES 5


int BulkDevNonDrv_check(void *_desc, int nLen, unsigned int type, int size)
{
    unsigned char *desc = (unsigned char *)_desc;

    if(nLen < size) return 0;
    if(desc[0] < size) return 0;
    if(desc[0] > nLen) return 0;
    if(desc[1] != type) return 0;

    return 1;
}

int BulkDevNonDrv_badname(const char *name)
{
    while(*name)
    {
        if(!isdigit(*name++))
            return 1;
    }

    return 0;
}

int BulkDevNonDrv_OpenDev(USB_HANDLE *usb)
{
    char DevDesc[1024];
    int bRet = 0;
    int hDevHandle = 0;
    int nLen = 0;
    int PipeIn = -1;
    int PipeOut = -1;
    int ifc_id = -1;

#ifdef __ANDROID__
    chmod(usb->DevName,0777);
#endif

#if 0
    char szBuffer[MAX_FILE_LENGTH];
    memset(szBuffer,0,sizeof(Tchar)*MAX_FILE_LENGTH);
    snprintf(szBuffer,sizeof(szBuffer),("su -c \"chmod -R 777 /dev/bus/usb/\""));
    int r = system(szBuffer);

    if(r!=0) {
        printf("Could not grant permissions to USB\n");
    }
#endif

    if((hDevHandle = open(usb->DevName, O_RDWR)) >= 0)
    {
#if PRINTLOG
        printf("Open dev OK\n");
#endif
		system("echo ---open usb OK--- > /dev/kmsg");
        nLen = read(hDevHandle, DevDesc, sizeof(DevDesc));
        if( BulkDevNonDrv_GetPipeOfDev(DevDesc, nLen, &PipeIn, &PipeOut, &ifc_id) )
        {
            //printf("GetPipeOfWTPTP OK!\n");
            nLen = ioctl(hDevHandle, USBDEVFS_CLAIMINTERFACE, &ifc_id);
            if(nLen == 0)
            {
#if PRINTLOG
                printf("Check ifc_id OK!\n");
#endif
				system("echo ---claim usb OK--- > /dev/kmsg");
                bRet = 1;
                usb->nPipeIn = PipeIn;
                usb->nPipeOut = PipeOut;
                usb->hDevHandle = hDevHandle;
#if PRINTLOG
                printf("DevName is %s, PipeIn is %d, PipeOut is %d, hDevHandle is 0x%X\n", usb->DevName, usb->nPipeIn, usb->nPipeOut, usb->hDevHandle);
#endif
			}
            else
            {
				system("echo ---claim usb FAIL--- > /dev/kmsg");
#if PRINTLOG
                printf("Check ifc_id fail! nLen: %d, errno(%d): %s\n", nLen, errno, strerror(errno));
#endif
				close(hDevHandle);
            }
        }
#if PRINTLOG
        else
            printf("GetPipeOfWTPTP fail!\n");
#endif
    }
    else
    {
		system("echo ---open usb FAIL--- > /dev/kmsg");
#if PRINTLOG
		printf("Open dev fail, hDevHandle=0x%X\n", hDevHandle);
#endif
    }

    return bRet;
}

int BulkDevNonDrv_CloseDev(USB_HANDLE *usb)
{
    int hDevHandle;

    hDevHandle = usb->hDevHandle;
    if(hDevHandle >= 0)
    {
        close(hDevHandle);
#if PRINTLOG
        printf("WTPTP dev: %s was closed!\n", usb->DevName);
#endif

        memset(usb->DevName, 0, 256);
        usb->hDevHandle = -1;
        usb->nPipeIn = -1;
        usb->nPipeOut = -1;

        return 1;
    }
    return 0;

}

int BulkDevNonDrv_WaitDev()
{
    struct sockaddr_nl client;
    struct timeval tv;
    int CppLive, rcvlen, ret;
    fd_set fds;
    int buffersize = 2048;

    CppLive = socket(AF_NETLINK, SOCK_RAW, NETLINK_KOBJECT_UEVENT);
    memset(&client, 0, sizeof(client));
    client.nl_family = AF_NETLINK;
    client.nl_pid = getpid();
    client.nl_groups = 1;

    setsockopt(CppLive, SOL_SOCKET, SO_RCVBUF, &buffersize, sizeof(buffersize));
    bind(CppLive, (struct sockaddr*)&client, sizeof(client));

    //while(1)
    {
        char buff[2048] = {0};
        FD_ZERO(&fds);
        FD_SET(CppLive, &fds);
        tv.tv_sec = 0;
        tv.tv_usec = 100 * 1000;

        ret = select(CppLive+1, &fds, NULL, NULL, &tv);
        //if(ret<0)
        //    continue;

        //if(!(ret>0 && FD_ISSET(CppLive, &fds)))
        //    continue;

        rcvlen = recv(CppLive, &buff, sizeof(buff), 0);
        if(rcvlen>0)
        {
            for(int nIndex=0; nIndex<rcvlen; nIndex++)
            {
                if( '\0' == *(buff+nIndex) )
                    buff[nIndex] = '\n';
            }
#if PRINTLOG
            printf("%s\n", buff);
#endif
            //break;
        }
    }

    close(CppLive);
    return 0;
}

int BulkDevNonDrv_FindAllSupportedDevices(PUSB_HANDLE hUSBArray[])
{
    char *base = "/dev/bus/usb";
    /*For AsiaTelco MIPS design, use proc dir*/
    //char *base = "/proc/bus/usb";
    char busname[64], devname[64];
    //char tmpBuffer[1024];
    char *DevDesc = (char *)malloc(1024);
    char *OrigiPtr = DevDesc;
    DIR *busdir, *devdir;
    struct dirent *de;

    struct usb_device_descriptor *dev;
    struct usb_config_descriptor *cfg;
    struct usb_interface_descriptor *ifc;
    USB_IFC_INFO info;

    int bRet = 0;
    int hDevHandle = 0;
    int nDevNameLen = 0;
    int bAdd = 0;
    int nIndex = 0;

    memset(busname, 0, sizeof(busname));
    memset(devname, 0, sizeof(devname));
    memset(DevDesc, 0, sizeof(DevDesc));

    busdir = opendir(base);
    if(0 == busdir)
        return 0;

    while( de = readdir(busdir) )
    {

        if(BulkDevNonDrv_badname(de->d_name))
            continue;

        sprintf(busname, "%s/%s", base, de->d_name);
        devdir = opendir(busname);
        if( 0 == devdir )
            continue;

        while( de = readdir(devdir) )
        {
            if(BulkDevNonDrv_badname(de->d_name))
            {
                continue;
            }

            int nBuffLen = sprintf(devname, "%s/%s", busname, de->d_name);
            if( ( hDevHandle = open(devname, O_RDWR) ) >= 0 )
            {
                //printf("Opened %s\n", devname);
                DevDesc = OrigiPtr;
                nBuffLen = read(hDevHandle, DevDesc, 1024);
                if( !BulkDevNonDrv_check( DevDesc, nBuffLen, USB_DT_DEVICE, USB_DT_DEVICE_SIZE ) )
                    continue;

                dev = (struct usb_device_descriptor *)DevDesc;
                nBuffLen -= dev->bLength;
                DevDesc += dev->bLength;

                if( BulkDevNonDrv_ChecHWIds2(dev->idVendor, dev->idProduct) )
                {
                    if( !BulkDevNonDrv_check( DevDesc, nBuffLen, USB_DT_CONFIG, USB_DT_CONFIG_SIZE ) )
                        continue;

                    info.serial_number[0] = 0;
                    if(dev->iSerialNumber)
                    {
                        struct usbdevfs_ctrltransfer ctrl;
                        __u16 buffer[128];
                        __u16 preCheck[128];
                        int nPreCheckCount = 0;
                        int result;

                        memset(buffer, 0, sizeof(buffer));
                        memset(preCheck, 0, sizeof(preCheck));
                        memset(&ctrl, 0, sizeof(ctrl));

                        ctrl.bRequestType = USB_DIR_IN | USB_TYPE_STANDARD | USB_RECIP_DEVICE;
                        ctrl.bRequest = USB_REQ_GET_DESCRIPTOR;
                        ctrl.wValue = (USB_DT_STRING << 8) | 0; //dev->iSerialNumber;
                        ctrl.wIndex = 0;//__le16_to_cpu(0x409);
                        ctrl.wLength = sizeof(preCheck);
                        ctrl.data = preCheck;

                        result = ioctl(hDevHandle, USBDEVFS_CONTROL, &ctrl);
                        if(result>0)
                        {
                            int nLoop;
                            nPreCheckCount = (result - 2) / 2;

                            for( nLoop = 1; nLoop <= nPreCheckCount; nLoop++ )
                            {
                                memset(buffer, 0, sizeof(buffer));
                                memset(&ctrl, 0, sizeof(ctrl));

                                ctrl.bRequestType = USB_DIR_IN | USB_TYPE_STANDARD | USB_RECIP_DEVICE;
                                ctrl.bRequest = USB_REQ_GET_DESCRIPTOR;
                                ctrl.wValue = (USB_DT_STRING << 8) | dev->iSerialNumber;
                                ctrl.wIndex = __le16_to_cpu(preCheck[nLoop]);
                                ctrl.wLength = sizeof(buffer);
                                ctrl.data = buffer;

                                result = ioctl(hDevHandle, USBDEVFS_CONTROL, &ctrl);
                                if(result>0)
                                {
                                    int i = 0;
                                    result /= 2;
                                    for(i=1; i<result; i++)
                                    {
                                        info.serial_number[i-1] = buffer[i];
                                    }
                                    info.serial_number[i-1] = 0;
                                    //printf("iSerialNumber: %s\n", info.serial_number);
                                }
                                else
                                {
#if PRINTLOG
                                    printf("Get iSerialNumber ioctl errno %d: %s\n", errno, strerror(errno));
#endif
                                }
                            }
                        }
                        else
                        {
#if PRINTLOG
                            printf("Pre-check ioctl errno %d: %s\n", errno, strerror(errno));
#endif
                        }
                    }

                    cfg = (struct usb_config_descriptor *)DevDesc;
                    nBuffLen -= cfg->bLength;
                    DevDesc += cfg->bLength;

                    for(int loop=0; loop<cfg->bNumInterfaces; )
                    {
                        if( !BulkDevNonDrv_check( DevDesc, nBuffLen, USB_DT_INTERFACE, USB_DT_INTERFACE_SIZE ) )
                        {
                            nBuffLen -= DevDesc[0];
                            DevDesc += DevDesc[0];
                            continue;
                        }

                        ifc = (struct usb_interface_descriptor *)DevDesc;
                        nBuffLen -= ifc->bLength;
                        DevDesc += ifc->bLength;

                        if( BulkDevNonDrv_ChecHWIds(dev->idVendor, dev->idProduct, ifc->bInterfaceNumber) )
                        {
                            USB_HANDLE usb;
                            strcpy(usb.DevName, devname);
                            if( 0 == strlen(info.serial_number) )
                            {
                                strcpy(usb.iSerialNumber, "None");
                            }
                            else
                            {
                                strcpy(usb.iSerialNumber, info.serial_number);
                            }
                            hUSBArray[nIndex] = (PUSB_HANDLE)malloc(sizeof(USB_HANDLE));
							NEW_USB_HANDLE(hUSBArray[nIndex]);
							COPY_USB_HANDLE(hUSBArray[nIndex],&usb);
                            nIndex++;
                            bRet = nIndex;
                            //printf("Got one supported dev: VID: 0x%X, PID: 0x%X, MI:0x%X\n", dev->idVendor, dev->idProduct, ifc->bInterfaceNumber);
                        }
                        loop++;
                    }
                }
                close(hDevHandle);
            }

            //if(IsSupported(devname, nBuffLen, DevName, nDevNameLen, bAdd))
            //    printf("%s\n", devname);
        }
        closedir(devdir);
    }
    closedir(busdir);
    free(OrigiPtr);
    DevDesc = NULL;
    OrigiPtr = NULL;
    return bRet;
}

int BulkDevNonDrv_CheckDevForNetLink(USB_HANDLE *usb, const char *NetLinkBuff, int nBuffLen, int *bAdd)
{
    char DevName[256] = {0};
    int nDevNameLen = 0;
    int bRet = 0;

    bRet = BulkDevNonDrv_IsSupported(NetLinkBuff, nBuffLen, DevName, &nDevNameLen, bAdd);
    if(bRet)
    {
        strcpy(usb->DevName, DevName);
    }
    return bRet;
}

int BulkDevNonDrv_IsSupported(const char *NetLinkBuff, int nBuffLen, char *Dev_Name, int *nDevNameLen, int *bAdd)
{
    int nIndex = 0;
    char* position = NULL;
    long lVID = 0, lPID = 0;
    int bFound = 0;
    int bRet = 0;
    char tmpNetLinkBuff[4096];
    char* sUSBDescription;
    /*AsiaTelco MIPS use proc instead of dev, really strange*/
    //string sDevName = "/proc/";
    char sDevName[512] = "/dev/";
    char sVID[64] = "0x";
    char sPID[64] = "0x";

    // Prepare the device information buffer
    memcpy(tmpNetLinkBuff, NetLinkBuff, nBuffLen);
    for(; nIndex<nBuffLen; nIndex++)
    {
        if( '\0' == *(tmpNetLinkBuff+nIndex) )
            tmpNetLinkBuff[nIndex] = '\n';
    }
    sUSBDescription = tmpNetLinkBuff;
    //printf("tmpNetLinkBuff is: %s\n", tmpNetLinkBuff);

    // Check is a wtptp device
    position = strstr(sUSBDescription,"PRODUCT=");
    if(position!=NULL)
    {
        char *EndPtr;
        char* tmpPos = position+8;
        for(; tmpPos[0] != '/'; tmpPos++)
        {
			strncat(sVID, tmpPos, 1);
            //sVID += sUSBDescription[tmpPos];
        }
        for(tmpPos++; tmpPos[0] != '/'; tmpPos++)
        {
			strncat(sPID, tmpPos, 1);
            //sPID += sUSBDescription[tmpPos];
        }
        lVID = strtol(sVID, &EndPtr, 16);
        lPID = strtol(sPID, &EndPtr, 16);
        //printf("hardwareId is: %s_%s\n", sVID.c_str(), sPID.c_str());
        //printf("hardwareId is: %X_%X\n", lVID, lPID);
        strcpy(Dev_Name, sDevName);
        *nDevNameLen = strlen(sDevName);
    }

    if( BulkDevNonDrv_ChecHWIds2(lVID, lPID) )
    {
        // Get Dev Name
        position = strstr(sUSBDescription,"DEVNAME=");
		//printf("\nDevName is:-----------\n %s\n---------------\n", sUSBDescription.c_str());
        if(position!=NULL)
        {
            char* tmpPos = position+8;
            for(; tmpPos[0] != '\n'; tmpPos++)
            {
				strncat(sDevName, tmpPos, 1);
                //sDevName += sUSBDescription[tmpPos];
            }
            //printf("sDevName is: %s\n", sDevName.c_str());
            strcpy(Dev_Name, sDevName);
        	*nDevNameLen = strlen(sDevName);
            //nDevNameLen = sDevName.copy(Dev_Name, sDevName.length());
            
            *bAdd = strstr(sUSBDescription,"add@")!=NULL ? 1 : 0;
			*bAdd = strstr(sUSBDescription,"bind@")!=NULL ? 2 : *bAdd;
            bRet = 1;
            //printf("It is a support device, return the Dev_Name: %s and bAdd: %d\n", Dev_Name, bAdd);
        }
		//printf("\nbAdd: %d\n",bAdd);
    }
    //else
        //printf("This is not a support device.\n");

    return bRet;
}

int BulkDevNonDrv_ChecHWIds(long idVendor, long idProduct, long MI)
{
    int nIndex = 0;
    int bFound = 0;

    for(nIndex=0; 0x0!=HWIds_CurrentTable[nIndex][0]; nIndex++)
    {
        if( idVendor == HWIds_CurrentTable[nIndex][0] \
                && idProduct == HWIds_CurrentTable[nIndex][1] \
                && ( -1 == MI || -1 == HWIds_CurrentTable[nIndex][2] || MI == HWIds_CurrentTable[nIndex][2] ) )
        {
            bFound = 1;
            break;
        }
    }

    return bFound;
}

int BulkDevNonDrv_GetPipeOfDev(/*int fd, */char *ptr, int len, int *ept_in_id, int *ept_out_id, int *ifc_id)
{
    struct usb_device_descriptor *dev;
    struct usb_config_descriptor *cfg;
    struct usb_interface_descriptor *ifc;
    struct usb_endpoint_descriptor *ept;
    //USB_IFC_INFO info;

    int in, out;
    unsigned i;
    unsigned e;

    if(!BulkDevNonDrv_check(ptr, len, USB_DT_DEVICE, USB_DT_DEVICE_SIZE))
        return 0;

    dev = (struct usb_device_descriptor *) ptr;
    len -= dev->bLength;
    ptr += dev->bLength;

    if(!BulkDevNonDrv_check(ptr, len, USB_DT_CONFIG, USB_DT_CONFIG_SIZE))
        return 0;

    cfg = (struct usb_config_descriptor *) ptr;
    len -= cfg->bLength;
    ptr += cfg->bLength;

    //info.dev_vendor = dev->idVendor;
    //info.dev_product = dev->idProduct;
    //info.dev_class = dev->bDeviceClass;
    //info.dev_subclass = dev->bDeviceSubClass;
    //info.dev_protocol = dev->bDeviceProtocol;
    //info.writable = writable;

    // read device serial number (if there is one)
    /*info.serial_number[0] = 0;
    if (dev->iSerialNumber)
    {

        struct usbdevfs_ctrltransfer  ctrl;
        __u16 buffer[128];
        int result;

        memset(buffer, 0, sizeof(buffer));

        ctrl.bRequestType = USB_DIR_IN|USB_TYPE_STANDARD|USB_RECIP_DEVICE;
        ctrl.bRequest = USB_REQ_GET_DESCRIPTOR;
        ctrl.wValue = (USB_DT_STRING << 8) | dev->iSerialNumber;
        ctrl.wIndex = 0;
        ctrl.wLength = sizeof(buffer);
        ctrl.data = buffer;

        result = ioctl(fd, USBDEVFS_CONTROL, &ctrl);
        if (result > 0)
        {
            int i;
            // skip first word, and copy the rest to the serial string, changing shorts to bytes.
            result /= 2;
            for (i = 1; i < result; i++)
                info.serial_number[i - 1] = buffer[i];
            info.serial_number[i - 1] = 0;
        }
        else
        {
            printf("errno(%d): %s\n", errno, strerror(errno));
        }
    }*/

    for(i = 0; i < cfg->bNumInterfaces;)
    {
        if( !BulkDevNonDrv_check( ptr, len, USB_DT_INTERFACE, USB_DT_INTERFACE_SIZE ) )
        {
            len -= *ptr;
            ptr += *ptr;
            continue;
        }

        i++;
        ifc = (struct usb_interface_descriptor *) ptr;
        len -= ifc->bLength;
        ptr += ifc->bLength;

        if( !BulkDevNonDrv_ChecHWIds(dev->idVendor, dev->idProduct, ifc->bInterfaceNumber) )
            continue;

        in = -1;
        out = -1;
        //info.ifc_class = ifc->bInterfaceClass;
        //info.ifc_subclass = ifc->bInterfaceSubClass;
        //info.ifc_protocol = ifc->bInterfaceProtocol;

        for(e = 0; e < ifc->bNumEndpoints; e++)
        {
            if(!BulkDevNonDrv_check(ptr, len, USB_DT_ENDPOINT, USB_DT_ENDPOINT_SIZE))
                return 0;

            ept = (struct usb_endpoint_descriptor *) ptr;
            len -= ept->bLength;
            ptr += ept->bLength;

            if((ept->bmAttributes & 0x03) != 0x02)
                continue;

            if(ept->bEndpointAddress & 0x80)
            {
                in = ept->bEndpointAddress;
            }
            else
            {
                out = ept->bEndpointAddress;
            }
        }

        //info.has_bulk_in = (in != -1);
        //info.has_bulk_out = (out != -1);
        *ept_in_id = in;
        *ept_out_id = out;
        *ifc_id = ifc->bInterfaceNumber;
        //printf("ept_in_id: %d, ept_out_id: %d, ifc_id: %d\n", *ept_in_id, *ept_out_id, *ifc_id);

        return 1;
    }
    return 0;
}
int BulkDevNonDrv_Write(USB_HANDLE *h, const void *_data, int len)
{
    unsigned char *data = (unsigned char*) _data;
    unsigned count = 0;
    struct usbdevfs_bulktransfer bulk;
    int n;

    if(h->nPipeOut == 0)
    {
        return -1;
    }

    if(len == 0)
    {
        bulk.ep = h->nPipeOut;
        bulk.len = 0;
        bulk.data = data;
        bulk.timeout = 0;

        n = ioctl(h->hDevHandle, USBDEVFS_BULK, &bulk);
        if(n != 0)
        {
#if DEBUG_MODE
            printf("1ERROR: n = %d, errno = %d (%s)\n",
                   n, errno, strerror(errno));
#endif

            return -1;
        }
        return n;
    }

    while(len > 0)
    {
        int xfer;
        xfer = len;
        bulk.ep = h->nPipeOut;
        bulk.len = xfer;
        bulk.data = data;
        bulk.timeout = 5000;
        n = ioctl(h->hDevHandle, USBDEVFS_BULK, &bulk);
        if(n != xfer)
        {
#if DEBUG_MODE
            printf("2ERROR: n = %d, errno = %d (%s)\n",
                   n, errno, strerror(errno));
#endif
            return -1;
        }

        count += xfer;
        len -= xfer;
        data += xfer;
    }
    return count;
}

int BulkDevNonDrv_Read(USB_HANDLE *h, void *_data, int len, int timeout)
{
    unsigned char *data = (unsigned char*) _data;
    unsigned count = 0;
    struct usbdevfs_bulktransfer bulk;
    int n, retry;

    if(h->nPipeIn == 0)
    {
        return -1;
    }

    while(len > 0)
    {
        int xfer = len;
        //int xfer = (len > 4096) ? 4096 : len;
        bulk.ep = h->nPipeIn;
        bulk.len = xfer;
        bulk.data = data;
        bulk.timeout = timeout;
        retry = 0;

        do
        {
            n = ioctl(h->hDevHandle, USBDEVFS_BULK, &bulk);
            if( n < 0 )
            {

                if ( ++retry > MAX_RETRIES )
                {
#if DEBUG_MODE
                    printf("ERROR: n = %d, errno = %d (%s)\n",n, errno, strerror(errno));
#endif

                    return -1;
                }
                usleep(10000);
            }
        }
        while( n < 0 );

        count += n;
        len -= n;
        data += n;

        if(n < xfer)
        {
            break;
        }
    }

    return count;
}
