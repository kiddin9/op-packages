
//
//////////////////////////////////////////////////////////////////////

#pragma once
#pragma warning ( disable : 4100 ) // Disable warning messages: unreferenced formal parameter
#pragma warning ( disable : 4189 ) // Disable warning messages: local variable is initialized but not referenced
#include "Macrodef.h"
//#include "BLFProperty.h"
#include  "EnumVal.h"
#define MAX_FILE_LENGTH  1024
#define SECTOR_UNIT  512
#define	EMMC_ERASE_UNIT  (512*1024)   // 512K
#define	NAND_ERASE_UNIT  (128*1024)   // 128K
#define	NOR_ERASE_UNIT   (64*1024)    // 64K
#define READ_BLOCK_SIZE 0x800000 //8M

//different partitions of EMMC
#define PRIBOOT_PARTITION  1 
#define RECVBOOT_PARTITION  2
#define RPMB_PARTITION  3 
/* general  commands */
#define DLCMD_DO_ERASE_ALL_FLASH  (1)
#define DLCMD_DO_UPLOAD_DATA  (2)
#define DLCMD_RESETBBT  (4)
#define DLCMD_DO_ERASE_ALL_ONLY  (16)

const static TCHAR* FBF_IDNAME                     = _T("FBFD"); 
const static TCHAR* DKB_IDNAME                     = _T("DKBI");
const static TCHAR* OBM_IDNAME                     = _T("OBMI");
const static TCHAR* WTM_IDNAME                     = _T("WTMI");
const static TCHAR* TZI_IDNAME                     = _T("TZII");
const static TCHAR* ROMC_IDNAME                    = _T("ROMC");
const static TCHAR*  FBF_IMAGE_TYPE                = _T("FBF");

const static TCHAR* pszDKB_TIM_HEADER_NAME         = _T("DKB_ntimheader.bin"); 
const static TCHAR* pszDKB_TRUST_TIM_HEADER_NAME   = _T("DKB_timheader.bin");  
const static TCHAR* pszDKB_DUMMY_BIN               = _T("DKB_dummy.bin"); 
const static TCHAR* pszFBF_NTIM_HEADER_NAME        = _T("FBF_Ntimheader.bin");
const static TCHAR* pszFBF_TRUST_TIM_HEADER_NAME   = _T("FBF_timheader.bin");
const static TCHAR* pszDKB_FILE_NAME               = _T("Dkb.bin"); 
const static TCHAR* pszPREFERENCES	               = _T("Preferences");                                    
const static TCHAR* pszRUN_TIME_DLG	               = _T("Run-Time Dialog");                                
const static TCHAR* pszTIM_CFG                     = _T("TIM_Configuration");                               
const static TCHAR* pszBLF_VERSION_PRO             = _T("BLF_Version");    
const static TCHAR* pszBLF_VERSION_NUMBER          = _T("V2.0.0");                                  
const static TCHAR* pszBLF_VERSION_NUMBER_SECTOR_FLASH  = _T("V2.1.0"); 
const static TCHAR* pszBLF_VERSION_NUMBER_SECTOR_FLASH_WITH_DTIMPPSETTING  = _T("V2.2.0"); 
const static TCHAR* pszBLF_VERSION_NAND_NOR_FLASH  = _T("V3.0.0"); 
const static TCHAR* pszBLF_VERSION                 = _T("Blf_Version_Number");                              
const static TCHAR* pszRESET_BBT                   = _T("Reset_BBT");                                       
const static TCHAR* pszFBF_SECTOR_SIZE             = _T("FBF_Sector_Size");                                  
const static TCHAR* pszDATA_PAGE_SIZE              = _T("Data_Area_Size" );                                 
const static TCHAR* pszSPARE_AREA_SIZE             = _T("Spare_Area_Size" ); 
const static TCHAR* pszNAND_BLOCK_SIZE             = _T("Flash_Block_Size");    
const static TCHAR* pszMAX_OTA_IAMGE_SIZE          = _T("Max_OTA_Image_Size");  
const static TCHAR* pszOTA_IAMGE_SPLIT_SIZE         = _T("OTA_Image_Split_Size");  
const static TCHAR* pszFLASH_FAMILY_PRO            = _T("Flash_Family" );                                   
const static TCHAR* pszSKIP_BLOCK_NUMBER           = _T("Skip_Blocks_Number");                              
const static TCHAR* pszERASE_ALL_FLASH             = _T("Erase_All_Flash");
const static TCHAR* pszBOOTOPTION_AFTER_FLASH      = _T("UE_Boot_Option"); 
const static TCHAR* pszPROCESSOR_TYPE              = _T("Processor_Type");                                  
const static TCHAR* pszBOOT_FLASH_SIG              = _T("Boot_Flash_Signature");                            
const static TCHAR* pszTRUSTED                     = _T("Trusted");                                         
const static TCHAR* pszVERSION                     = _T("Version");                                         
const static TCHAR* pszISSUDT                      = _T("Issue_Date");                                      
const static TCHAR* pszOEMUID                      = _T("OEM_UniqueID");                                    
const static TCHAR* pszSIZE_OF_IMG                 = _T("Number_of_Images"); 
const static TCHAR* pszSIZE_OF_EMMCTYPE            = _T("Number_of_EMMCTypes"); 
const static TCHAR* pszSIZE_OF_RSV                 = _T("Size_of_Reserved_in_bytes");                       
const static TCHAR* pszNUM_OF_KEYS                 = _T("Number_of_Keys");                                  
const static TCHAR* pszEXT_RSV_DATA                = _T("[Extended_Reserved_Data]");                        
const static TCHAR* pszRSV_DATA                    = _T("[Reserved_Data]");                                 
const static TCHAR* pszEND_RSV_DATA                = _T("End_Reserved_Data");                               
const static TCHAR* pszFBF_SPLIT_SIZE_SETTING      = _T("Max_FBF_Split_Size");                          
const static TCHAR* pszUPLOAD_MAX_SIZE_SETTING     = _T("Max_Upload_Split_Size" );                      
const static TCHAR* pszWTM_FL_SIGTURE              = _T("WTM_Save_State_Flash_Signature");              
const static TCHAR* pszWTM_FL_EN_ADDR              = _T("WTM_Save_State_Flash_Entry_Address");          
const static TCHAR* pszWTM_BK_EN_ADDR              = _T("WTM_Save_State_BackUp_Entry_Address");         


const static TCHAR* pszAUTH_PATH                   = _T("Authentication Path");                               
const static TCHAR* pszST_ADDR                     = _T("Start_Address");                                     
const static TCHAR* pszIMG_LIST	                   = _T("Image_List");                                       
const static TCHAR* pszENBL                        = _T("Enable");                                            
const static TCHAR* pszTIM_INCLUDED                = _T("Tim_Included");                                      
const static TCHAR* pszPATH                        = _T("Path");                                              
const static TCHAR* pszFL_ENTRY_ADDR               = _T("Flash_Entry_Address");                               
const static TCHAR* pszLOAD_ADDR                   = _T("Load_Address");                                      
const static TCHAR* pszSIZE_OF_IMGTOCRC            = _T("Size_To_CRC_in_bytes");                        
const static TCHAR* pszSIZE_OF_IMGTOHASH           = _T("Image_Size_To_Hash_in_bytes");                       
const static TCHAR* pszSIZE_OF_ERASE               = _T("Erase_Size");                                        
const static TCHAR* pszPARTITION                   = _T("Partition_Number");                                  
const static TCHAR* pszIMGID_NAME                  = _T("ID_Name");                                           
const static TCHAR* pszIMGID                       = _T("Image_ID");                                           
const static TCHAR* pszNTIMGID		           = _T("Next_Image_ID");                                    
const static TCHAR* pszHASH_ALGT_ID                = _T("Hash_Algorithm_ID");                                 
const static TCHAR* pszOFST		           = _T("Offset");                                           
const static TCHAR* pszTYPE		           = _T("Type");                                             
const static TCHAR* pszFLASH_PROP  	           = _T("Flash_Properties");                                 
const static TCHAR* pszFLASH_OPTIONS               = _T("Flash_Options");  
const static TCHAR* pszUE_OPTIONS                  = _T("UE_Options");
const static TCHAR* pszNONE_ERASESIZE              = _T("");                                                  
const static TCHAR* pszSPARE_SIZE                  = _T("Spare_Area_Size");                                   
const static TCHAR* pszDATA_SIZE                   = _T("Data_Area_Size");                                    
const static TCHAR* pszFLASHNANDID                 = _T("Flash_NandID");                                                                                                             
const static TCHAR* pszJTAG_TRUSTED                = _T("JTAG TRUSTED");                                         
const static TCHAR* pszJTAG_TIM	                   = _T("TIM Path");                                            
const static TCHAR* pszJTAG_KEY	                   = _T("KEY Path");                                            
const static TCHAR* pszPACKAGE_SIZE                = _T("Package_Size");   



const static TCHAR* pszERASE_ONLY_OPTION           = _T("EraseOnly_Option");
const static TCHAR* pszERASE_ONLY_NUM              = _T("Total_Eraseonly_Areas");
const static TCHAR* pszERASE_ONLY_START_ADD        = _T("Eraseonly_Area_FlashStartAddress");
const static TCHAR* pszERASE_ONLY_SIZE             = _T("Eraseonly_Area_Size");
const static TCHAR* pszERASE_ONLY_PARTITION        = _T("Eraseonly_Area_Partition");


//Add support for trusted mode                                                                 
const static TCHAR* pszDIGITAL_SIGNATURE_DATA	   = _T("Digital_Signature_Data");
const static TCHAR* pszEND_DIGITAL_SIGNATURE_DATA  = _T("End_Digital_Signature_Data"); 
const static TCHAR* pszKEYS_DATA		   = _T("Keys_Data");
const static TCHAR* pszDSA_ALGORITHM               = _T("DSA_Algorithm");                             
const static TCHAR* pszHASHALG_ID                  = _T("Hash_Algorithm_ID"); 
const static TCHAR* pszENCRYPT_ALGID               = _T("Encrypt_Algorithm_ID");
const static TCHAR* pszKEY_ID                      = _T("Key_ID");
const static TCHAR* pszMODULUS_SIZE                = _T("Modulus_Size_in_bytes");                     
const static TCHAR* pszKEY_SIZE                    = _T("Key_Size_in_bits"); 
const static TCHAR* pszPUBLIC_KEY_SIZE             = _T("Public_Key_Size_in_bytes");
const static TCHAR* pszRSA_PUBLIC_EXP              = _T("RSA_Public_Exponent");                       
const static TCHAR* pszEND_RSA_PUBLIC_EXP          = _T("End_RSA_Public_Exponent");                   
const static TCHAR* pszRSA_SYS_MODULUS             = _T("RSA_System_Modulus");                        
const static TCHAR* pszEND_RSA_SYS_MODULUS         = _T("End_RSA_System_Modulus");                    
const static TCHAR* pszRSA_PRIVATE_KEY             = _T("RSA_Private_Key");                           
const static TCHAR* pszEND_RSA_PRIVATE_KEY         = _T("End_RSA_Private_Key");                       
const static TCHAR* pszECDSA_PUBLIC_KEY_COMX       = _T("ECDSA_Public_Key_CompX");                    
const static TCHAR* pszEND_ECDSA_PUBLIC_KEY_COMX   = _T("End_ECDSA_Public_Key_CompX");                
const static TCHAR* pszECDSA_PUBLIC_KEY_COMY	   = _T("ECDSA_Public_Key_CompY");                   
const static TCHAR* pszEND_ECDSA_PUBLIC_KEY_COMY   = _T("End_ECDSA_Public_Key_CompY");                
const static TCHAR* pszECDSA_PRIVATE_KEY	   = _T("ECDSA_Private_Key");                                
const static TCHAR* pszEND_ECDSA_PRIVATE_KEY	   = _T("End_ECDSA_Private_Key");                    


const static TCHAR* pszEND_EXT_RSV_DATA	           = _T("End_Extended_Reserved_Data");                        
const static TCHAR* pszCLK_ENABLE                  = _T("Clock_Enable");                                       
const static TCHAR* pszEND_CLK_ENABLE              = _T("End_Clock_Enable");                                   
const static TCHAR* pszDDR_GEO	                   = _T("DDR_Geometry");                                      
const static TCHAR* pszEND_DDR_GEO	           = _T("End_DDR_Geometry");                                  
const static TCHAR* pszDDR_TIMING	           = _T("DDR_Timing");                                        
const static TCHAR* pszEND_DDR_TIMING	           = _T("End_DDR_Timing");                                    
const static TCHAR* pszDDR_CUSTOM	           = _T("DDR_Custom");                                        
const static TCHAR* pszEND_DDR_CUSTOM	           = _T("End_DDR_Custom");                                    
const static TCHAR* pszFREQ	                   = _T("Frequency");                                         
const static TCHAR* pszEND_FREQ	                   = _T("End_Frequency");                                     
const static TCHAR* pszVOL	                   = _T("Voltages");                                          
const static TCHAR* pszEND_VOL	                   = _T("End_Voltages");                                      
const static TCHAR* pszCFG_MEM_CTRL	           = _T("Configure_Memory_Control");                          
const static TCHAR* pszEND_CFG_MEM_CTRL	           = _T("End_Configure_Memory_Control");                      
const static TCHAR* pszTRUST_Z         	           = _T("Trust_Zone");                                        
const static TCHAR* pszEND_TRUST_Z                 = _T("End_Trust_Zone");                                     
const static TCHAR* pszTRUST_Z_RE 	           = _T("Trust_Zone_Regid");                                  
const static TCHAR* pszEND_TRUST_Z_RE 	           = _T("End_Trus_Zone_Regid");                               
const static TCHAR* pszOPDIV      	           = _T("OpDiv");                                             
const static TCHAR* pszEND_OPDIV      	           = _T("End_OpDiv");                                         
const static TCHAR* pszOPMOD                       = _T("OpMode");                                             
const static TCHAR* pszEND_OPMOD                   = _T("End_OpMode");                                         
const static TCHAR* pszERDVEC                      = _T("ErdVec");                                             
const static TCHAR* pszEND_ERDVEC                  = _T("End_ErdVec");  

const static TCHAR* pszTR069_INFO			= _T("TRFU");
const static TCHAR* pszTR069_ENABLED		= _T("Enabled");
const static TCHAR* pszTR069_FLASH_ADDR		= _T("Flash_Address");
const static TCHAR* pszTR069_MAGIC			= _T("Magic");
const static TCHAR* pszTR069_INFO_END		= _T("End_TRFU");

const static TCHAR* pszFOTA_INFO			= _T("OTAI");
const static TCHAR* pszFOTA_ENABLED		    = _T("Enabled");
const static TCHAR* pszFOTA_FLASH_ADDR		= _T("Flash_Address");
const static TCHAR* pszFOTA_MAGIC			= _T("Magic");
const static TCHAR* pszFOTA_INFO_END		= _T("End_OTAI");

const static TCHAR* pszDDR_TYPE_BEGIN		= _T("DTYP");
const static TCHAR* pszDDR_TYPE_VALUE		= _T("DDR_Type");
const static TCHAR* pszDDR_TYPE_END			= _T("End_DTYP");

const static TCHAR* pszDDR_BYTE_SELECT_BEGIN = _T("DDBS");
const static TCHAR* pszDDR_BYTE_SELECT = _T("DDR_Byte_Select");
const static TCHAR* pszDDR_BYTE_SELECT_END = _T("End_DDBS");


//LTG LWG SELECT PACKAGE
const static TCHAR* pszLTG_LWG_SELECT_BEGIN		= _T("LTWS");
const static TCHAR* pszLTG_LWG_SELECT_VALUE	    = _T("LTG_LWG_Select");
const static TCHAR* pszLTG_LWG_SELECT_END		= _T("End_LTWS");

const static TCHAR* pszCUSTOMER_TRANSFER_INFO = _T("CITA_CUMIZED_INFO_TRANSFER_TOAP_ID");
const static TCHAR* pszCUSTOMER_TRANSFER_INFO_END = _T("End_CITA_CUMIZED_INFO_TRANSFER_TOAP_ID");

const static TCHAR* pszBBMIDTYPE = _T("BBMT");
const static TCHAR* pszBBMIDTYPE_END = _T("End_BBMT");

const static TCHAR* pszFLASHGEOPKGID = _T("FGPI");
const static TCHAR* pszFLASHGEOPKGID_END = _T("End_FGPI");

const static TCHAR* pszBBCS_BEGIN		= _T("BBCS");
const static TCHAR* pszBBCS_VALUE		= _T("Enabled");
const static TCHAR* pszBBCS_END			= _T("End_BBCS");

const static TCHAR* pszCRCS_BEGIN		= _T("CRCS");
const static TCHAR* pszCRCS_VALUE		= _T("Enabled");
const static TCHAR* pszCRCS_END			= _T("End_CRCS");

// Added by ZQQ to support DTIM 2012-03-28
const static TCHAR* pszDTIM_KEYS_DATA	 = _T("DTIM_Keys_Data");
const static TCHAR* pszEND_DTIM_KEYS_DATA	 = _T("End_DTIM_Keys_Data"); 

const static TCHAR* pszPRODUCTION_MODE  = _T("ProductionMode");

const static TCHAR* pszDDR_FLASH_MCP_MAP = _T("DDR_Flash_Mcp_Map");
const static TCHAR* pszEND_DDR_FLASH_MCP_MAP = _T("End_DDR_Flash_Mcp_Map");              

// definition for PXA92x  
//Added by zqq 2012-2-3 

const static TCHAR* pszPXA92x_TIM_CFG                          = _T("TIM Configuration");                                         
const static TCHAR* pszPXA92x_SKIP_BLOCK_CFG                   = _T("Skip Block Configuration");   
const static TCHAR* pszPXA92x_TRUSTED			       = _T("Trusted");
const static TCHAR* pszPXA92x_TOTAL_SKIPBLOCK                  = _T("Total Skip Block Numbers");
const static TCHAR* pszPXA92x_SKIP_BLOCK_NUMBER                = _T("Skip Block Number");
const static TCHAR* pszPXA92x_ERASE_ALL_FLASH                  = _T("Erase All Flash");           
const static TCHAR* pszPXA92x_FLASHER_ADRES                    = _T("FlasherLoadAddress");               
const static TCHAR* pszPXA92x_VERSION                          = _T("Version");
const static TCHAR* pszPXA92x_ISSUDT                           = _T("Issue Date");
const static TCHAR* pszPXA92x_OEMUID                           = _T("OEM UniqueID");
const static TCHAR* pszPXA92x_PROCESSOR_TYPE                   = _T("Processor Type");
const static TCHAR* pszPXA92x_BOOT_FLASH_SIG                   = _T("Boot Flash Signature");
const static TCHAR* pszPXA92x_SIZE_OF_IMG  	               = _T("Number of Images");
const static TCHAR* pszPXA92x_SIZE_OF_RSV                      = _T("Size of Reserved in bytes");
const static TCHAR* pszPXA92x_NUM_OF_KEYS                      = _T("Number of Keys");
const static TCHAR* pszPXA92x_EXT_RSV_DATA                     = _T("Extended Reserved Data");
const static TCHAR* pszPXA92x_END_EXT_RSV_DATA                 = _T("End Extended Reserved Data");
const static TCHAR* pszPXA92x_RSV_DATA                         = _T("[Reserved Data]");
const static TCHAR* pszPXA92x_END_RSV_DATA                     = _T("End Reserved Data");
const static TCHAR* pszPXA92x_WTM_FL_SIGTURE                   = _T("WTM Save State Flash Signature");
const static TCHAR* pszPXA92x_WTM_FL_EN_ADDR                   = _T("WTM Save State Flash Entry Address");
const static TCHAR* pszPXA92x_WTM_BK_EN_ADDR                   = _T("WTM Save State BackUp Entry Address");


const static TCHAR* pszPXA92x_FL_PATH			       = _T("Flasher Path");
const static TCHAR* pszPXA92x_AUTH_PATH		               = _T("Authentication Path");
const static TCHAR* pszPXA92x_JTAG_TIM_PATH                    = _T("Jtag TIM File Path");
const static TCHAR* pszPXA92x_ST_ADDR		    	       = _T("Start Address");
const static TCHAR* pszPXA92x_IMEI_PATH                        = _T("IMEI File Path");
const static TCHAR* pszPXA92x_MEP_PATH                         = _T("MEP File Path");
const static TCHAR* pszPXA92x_IMG_LIST		               = _T("Image List");
const static TCHAR* pszPXA92x_ENBL			       = _T("Enable");
const static TCHAR* pszPXA92x_PATH			       = _T("Path");
const static TCHAR* pszPXA92x_FL_ENTRY_ADDR                    = _T("Flash Entry Address");
const static TCHAR* pszPXA92x_LOAD_ADDR                        = _T("Load Address");
const static TCHAR* pszPXA92x_SIZE_OF_IMGTOCRC                 = _T("Image Size To CRC in bytes");
const static TCHAR* pszPXA92x_SIZE_OF_IMGTOHASH                = _T("Image Size To Hash in bytes");
const static TCHAR* pszPXA92x_SIZE_OF_ERASE                    = _T("Erase Size");


const static TCHAR* pszPXA92x_PARTITION                        = _T("Partition Number");
const static TCHAR* pszPXA92x_IMGID_NAME                       = _T("ID Name");
const static TCHAR* pszPXA92x_IMGID		 	       = _T("Image ID");
const static TCHAR* pszPXA92x_NTIMGID		               = _T("Next Image ID");
const static TCHAR* pszPXA92x_HASH_ALGT_ID                     = _T("Hash Algorithm ID");
const static TCHAR* pszPXA92x_OFST			       = _T("Offset");
const static TCHAR* pszPXA92x_TYPE			       = _T("Type");
const static TCHAR* pszPXA92x_OLD_FLASHER		       = _T("Flasher Property");
const static TCHAR* pszPXA92x_FLASH_PROP  	               = _T("Flash Properties");
const static TCHAR* pszPXA92x_CFG_FILE_PATH	               = _T("Flash Configuration File Path");
const static TCHAR* pszPXA92x_TAVOR_PROP		       = _T("Tavor Flasher Properties");
const static TCHAR* pszPXA92x_NONE_ERASESIZE                   = _T("");            
const static TCHAR* pszPXA92x_SPARE_SIZE                       = _T("Spare Area Size");
const static TCHAR* pszPXA92x_DATA_SIZE                        = _T("Data Area Size");

const static TCHAR* pszPXA92x_JTAG_TRUSTED	               = _T("JTAG TRUSTED");
const static TCHAR* pszPXA92x_JTAG_TIM		               = _T("TIM Path");    
const static TCHAR* pszPXA92x_JTAG_KEY		               = _T("KEY Path");    

const static TCHAR* pszPXA92x_ERASE_ALL                        = _T("Erase All");   
const static TCHAR* pszPXA92x_END_ERASE_ALL                    = _T("End Erase All");
const static TCHAR* pszPXA92x_CLK_ENABLE                       = _T("Clock Enable");
const static TCHAR* pszPXA92x_END_CLK_ENABLE     	       = _T("End Clock Enable");
const static TCHAR* pszPXA92x_DDR_GEO	                       = _T("DDR Geometry");
const static TCHAR* pszPXA92x_END_DDR_GEO	               = _T("End DDR Geometry");
const static TCHAR* pszPXA92x_DDR_TIMING	               = _T("DDR Timing");  
const static TCHAR* pszPXA92x_END_DDR_TIMING	               = _T("End DDR Timing");
const static TCHAR* pszPXA92x_DDR_CUSTOM	               = _T("DDR Custom");  
const static TCHAR* pszPXA92x_END_DDR_CUSTOM	               = _T("End DDR Custom");
const static TCHAR* pszPXA92x_FREQ	                       = _T("Frequency");                                                                        
const static TCHAR* pszPXA92x_END_FREQ	                       = _T("End Frequency");                                                                    
const static TCHAR* pszPXA92x_VOL	                       = _T("Voltages");                                                                         
const static TCHAR* pszPXA92x_END_VOL	                       = _T("End Voltages");                                                                     
const static TCHAR* pszPXA92x_CFG_MEM_CTRL	               = _T("Configure Memory Control");                                                         
const static TCHAR* pszPXA92x_END_CFG_MEM_CTRL	               = _T("End Configure Memory Control");                                                     
const static TCHAR* pszPXA92x_TRUST_Z         	               = _T("Trust Zone");                                                                          
const static TCHAR* pszPXA92x_END_TRUST_Z         	       = _T("End Trust Zone");                                                                      
const static TCHAR* pszPXA92x_TRUST_Z_RE 	               = _T("Trust Zone Regid");                                                                 
const static TCHAR* pszPXA92x_END_TRUST_Z_RE 	               = _T("End Trust Zone Regid");                                                             
const static TCHAR* pszPXA92x_OPDIV      	               = _T("OpDiv");                                                                         
const static TCHAR* pszPXA92x_END_OPDIV      	               = _T("End OpDiv");                                                                    
const static TCHAR* pszPXA92x_OPMOD                            = _T("OpMode");                                                                           
const static TCHAR* pszPXA92x_END_OPMOD                        = _T("End OpMode");                                                                       
const static TCHAR* pszPXA92x_ERDVEC                           = _T("ErdVec");                                                                        
const static TCHAR* pszPXA92x_END_ERDVEC                       = _T("End ErdVec");                                                                       
const static TCHAR* pszPXA92x_DEVICE_USB_MAP                   = _T("DEVICE_USBPORT_MAP");                                                               
const static TCHAR* pszPXA92x_DEVICE_USBPORT_NUMBER            = _T("MAX Device USB Port Number");                                                      
const static TCHAR* pszPXA92x_DEVICE_USB_PORT                  = _T("Device USB Port");                                                                  
const static TCHAR* pszPXA92x_ERASE_ONLY                       = _T("Erase only Area");                                                                  
const static TCHAR* pszPXA92x_ERASE_ONLY_NUM                   = _T("Erase Area Num");                                                                   
const static TCHAR* pszPXA92x_ERASE_ONLY_START_ADD             = _T("Erase Flash Start Address");                                                       
const static TCHAR* pszPXA92x_ERASE_ONLY_LENGTH                = _T("Erase Length");
const static TCHAR* pszPXA92x_ERASE_ONLY_PARTITION             = _T("Erase Area Partition");
const static TCHAR* pszPXA92x_DEV_HEADER_0	               = _T("DEV_HEADER_0");
const static TCHAR* pszPXA92x_BLOCK_SIZE_NAME                  = _T("Block_Size_0");
const static TCHAR* pszPXA92x_FLASHFAMLIY                      = _T("FlashFamily");
const static TCHAR* pszPXA92x_FLASHINI                         = _T("INTEL_FLASHER_INPUT_FILE");
const static TCHAR* pszPXA92x_FLASH_BLOCKS                     = _T("Number_of_Blocks_0");


                                                              

const static TCHAR* pszUPLOAD_PROPERTY	    = _T("Upload_Property");
const static TCHAR* pszMAX_UPLOAD_SIZE	    = _T("Max_Upload_Size");
const static TCHAR* pszUPLOADAREA_NUM	    = _T("Upload_Area_Nums");
const static TCHAR* pszUPLOAD_RESETUE	    = _T("ResetUE_AfterUpload");
const static TCHAR* pszUPLOAD_TIMEDELAY_RESET	   = _T("Reset_DelayTime");
const static TCHAR* pszUPLOADAREA_LIST	    = _T("Upload_Areas_List");
const static TCHAR* pszUPLOADAREA_TYPE	    = _T("Area_Type");
const static TCHAR* pszUPLOADAREA_SUBTYPE	= _T("Area_SubType");
const static TCHAR* pszUPLOADAREA_OFFSET    = _T("Area_Offset");
const static TCHAR* pszUPLOADAREA_DATATSIZE	= _T("Area_DataSize");
const static TCHAR* pszUPLOADAREA_PARTITION	= _T("Area_Partition");
const static TCHAR* pszUPLOADAREA_SPAREAREA	= _T("Area_UploadWithSpareArea");
const static TCHAR* pszUPLOADAREA_SAVEFILE	= _T("Area_UploadData_SaveFile");
const static TCHAR* pszBLFVERSION			= _T("Blf_Version");
const static TCHAR* pszFlashFamily			= _T("Flash_Family");
const static TCHAR* pszPlatFormType			= _T("PlatForm_Type");

const static TCHAR* pszEMMCIMAGEPROPERTY    = _T("EMMC_Images_list_Property");
const static TCHAR* pszEMMCIMGIDNUM			    = _T("ImageID_num");
const static TCHAR* pszEMMCTYPECFG		    = _T("EmmcType");

//mutliple Nand size
const static TCHAR* pszNAND_SIGNATURE_NUMBER		= _T("Nand_Signature_Number");
const static TCHAR* pszNAND_IMAGE_PROPERTY			= _T("Nand_Images_list_Property");
const static TCHAR* pszNANDSIGN						= _T("NandSign");
const static TCHAR* pszNANDSIGN_VALUE			    = _T("NandSign_Value");
const static TCHAR* pszNANDSIGN_NANDIDNUMBER		= _T("NandSign_NandIdNumber");
const static TCHAR* pszNANDID						= _T("NandId");
const static TCHAR* pszNANDSIZE						= _T("NandSize");
const static TCHAR* pszIMAGENUMBER					= _T("ImageNumber");

//#define  pszNAND_SIGNATURE_NUMBER		 _T("NAND_Signature_Number")
//#define  pszNAND_IMAGE_PROPERTY			_T("NAND_Images_list_Property")
//#define pszNANDSIGN						_T("NandSign")
//#define  pszNANDSIGN_VALUE			     _T("NandSign_Value")
//#define  pszNANDSIGN_NANDIDNUMBER		 _T("NandSign_NandIdNumber")
//#define  pszNANDID						 _T("NandId")
//#define  pszNANDSIZE					 _T("NandSize")
//#define  pszIMAGENUMBER					 _T("ImageNumber")
















#define MAX_DDR_VENDOR_NUM 34
#define MAX_DDR_SIZE_NUM 20

struct stDdrVendorIdNameMap{
	unsigned int nDdrVendorID;
	TCHAR	 strDdrVendorName[128];
};

static const struct stDdrVendorIdNameMap vendorDdrPidNameMap[MAX_DDR_VENDOR_NUM]={
	{0x01,_T("SAMSUNG")}, 
	{0x02,_T("QIMONDA")},
	{0x03,_T("ELPIDA")},
	{0x04,_T("ETRON")},
	{0x05,_T("NANYA")},
	{0x06,_T("HYNIX")},
	{0x07,_T("MOSEL")},
	{0x08,_T("WINBOND")},
	{0x09,_T("ESMT")},
	{0x0A,_T("RESERVED")},
	{0x0B,_T("SPANSION")},
	{0x0C,_T("SST")},
	{0x0D,_T("ZMOS")},
	{0x0E,_T("INTEL")},
	{0x0F,_T("NUMONYX")},
	{0x10,_T("MICRON")},
	{0x11,_T("TOSHIBA")},
	{0x12,_T("FIDELIX")},
	{0x13,_T("ReservedVendor1")},
	{0x14,_T("ReservedVendor2")},
    {0x15,_T("ReservedVendor3")},
	{0x16,_T("ReservedVendor4")},
	{0x17,_T("ReservedVendor5")},
	{0x18,_T("ReservedVendor6")},
	{0x19,_T("ReservedVendor7")},
	{0x1A,_T("ReservedVendor8")},
	{0x1B,_T("ReservedVendor9")},
	{0x1C,_T("JSC")},
	{0x1D,_T("ReservedVendor11")},
	{0x1E,_T("ReservedVendor12")},
	{0xF8,_T("Fidelix")},
	{0xFD,_T("ESMT2")},
	{0xFE,_T("Numonyx")},
	{0xFF,_T("Micron")},
};


#define RESERVED_DDR_FOR_SMALLMEMORY		0x300000  /* Reserved 3MB DDR Size for OBM on platform Nezha and Nezha2 */		
#define RESERVED_DDR_FOR_LARGEMEMORY		0x1E00000 /* Reserved 30MB DDR Size for OBM */	
#define UNIT_GB								0x40000000
