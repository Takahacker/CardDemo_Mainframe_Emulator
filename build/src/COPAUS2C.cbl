      ******************************************************************
      * Program     : COPAUS2C.CBL
      * Application : CardDemo - Authorization Module
      * Type        : CICS COBOL IMS DB2 Program
      * Function    : Mark Authorization Message Fraud
      ******************************************************************
      * Copyright Amazon.com, Inc. or its affiliates.
      * All Rights Reserved.
      *
      * Licensed under the Apache License, Version 2.0 (the "License").
      * You may not use this file except in compliance with the License.
      * You may obtain a copy of the License at
      *
      *    http://www.apache.org/licenses/LICENSE-2.0
      *
      * Unless required by applicable law or agreed to in writing,
      * software distributed under the License is distributed on an
      * "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
      * either express or implied. See the License for the specific
      * language governing permissions and limitations under the License
      ******************************************************************
       IDENTIFICATION DIVISION.
       PROGRAM-ID. COPAUS2C.                                            
       AUTHOR.     AWS.                                                 
                                                                        
       ENVIRONMENT DIVISION.                                            
       CONFIGURATION SECTION.                                           
                                                                        
       DATA DIVISION.                                                   
       WORKING-STORAGE SECTION.                                         
                                                                        
       01 WS-VARIABLES.                                                 
         05 WS-PGMNAME                 PIC X(08) VALUE 'COPAUS2C'.      
         05 WS-LENGTH                  PIC S9(4) COMP VALUE ZERO.       
         05 WS-AUTH-TIME               PIC 9(09).                       
         05 WS-AUTH-TIME-AN REDEFINES WS-AUTH-TIME                      
                                       PIC X(09).                       
         05 WS-AUTH-TS.                                                 
            10 WS-AUTH-YY              PIC X(02).                       
            10 FILLER                  PIC X(01) VALUE '-'.             
            10 WS-AUTH-MM              PIC X(02).                       
            10 FILLER                  PIC X(01) VALUE '-'.             
            10 WS-AUTH-DD              PIC X(02).                       
            10 FILLER                  PIC X(01) VALUE ' '.             
            10 WS-AUTH-HH              PIC X(02).                       
            10 FILLER                  PIC X(01) VALUE '.'.             
            10 WS-AUTH-MI              PIC X(02).                       
            10 FILLER                  PIC X(01) VALUE '.'.             
            10 WS-AUTH-SS              PIC X(02).                       
            10 WS-AUTH-SSS             PIC X(03).                       
            10 FILLER                  PIC X(03) VALUE '000'.           
         05 WS-ERR-FLG                 PIC X(01) VALUE 'N'.             
            88 ERR-FLG-ON                        VALUE 'Y'.             
            88 ERR-FLG-OF                        VALUE 'N'.             
         05 WS-SQLCODE                 PIC +9(06).                      
         05 WS-SQLSTATE                PIC +9(09).                      
                                                                        
         05 WS-ABS-TIME                PIC S9(15) COMP-3 VALUE 0.       
         05 WS-CUR-DATE                PIC X(08) VALUE SPACES.          
                                                                        
      *COPY DFHBMSCA.                                                   
      /****************************************************             
      * SQL INCLUDE FOR SQLCA                             *             
      *****************************************************             
      * SQLCA - area de comunicacao do SQL (layout do Db2 para COBOL)
       01  SQLCA.
           05  SQLCAID                 PIC X(8).
           05  SQLCABC                 PIC S9(9) COMP.
           05  SQLCODE                 PIC S9(9) COMP.
           05  SQLERRM.
               49  SQLERRML            PIC S9(4) COMP.
               49  SQLERRMC            PIC X(70).
           05  SQLERRP                 PIC X(8).
           05  SQLERRD                 OCCURS 6 TIMES
                                       PIC S9(9) COMP.
           05  SQLWARN.
               10  SQLWARN0            PIC X.
               10  SQLWARN1            PIC X.
               10  SQLWARN2            PIC X.
               10  SQLWARN3            PIC X.
               10  SQLWARN4            PIC X.
               10  SQLWARN5            PIC X.
               10  SQLWARN6            PIC X.
               10  SQLWARN7            PIC X.
           05  SQLEXT.
               10  SQLWARN8            PIC X.
               10  SQLWARN9            PIC X.
               10  SQLWARNA            PIC X.
               10  SQLSTATE            PIC X(5).
      ******************************************************************
      * DCLGEN TABLE(AWSTSSC.AUTHFRDS)                                 *
      *        LIBRARY(XXXXXXX.DB2.DCLGEN(AUTHFRDS))                   *
      *        LANGUAGE(COBOL)                                         *
      *        QUOTE                                                   *
      * ... IS THE DCLGEN COMMAND THAT MADE THE FOLLOWING STATEMENTS   *
      ******************************************************************
      * Copyright Amazon.com, Inc. or its affiliates.
      * All Rights Reserved.
      *
      * Licensed under the Apache License, Version 2.0 (the "License").
      * You may not use this file except in compliance with the License.
      * You may obtain a copy of the License at
      *
      *    http://www.apache.org/licenses/LICENSE-2.0
      *
      * Unless required by applicable law or agreed to in writing,
      * software distributed under the License is distributed on an
      * "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
      * either express or implied. See the License for the specific
      * language governing permissions and limitations under the License
      ******************************************************************

      *KIX  EXEC SQL DECLARE CARDDEMO.AUTHFRDS TABLE ( CARD_NUM CHAR(16
      ******************************************************************
      * COBOL DECLARATION FOR TABLE AWSTSSC.AUTHFRDS                   *
      ******************************************************************
       01  DCLAUTHFRDS.                                                 
           10 CARD-NUM             PIC X(16).                           
           10 AUTH-TS              PIC X(26).                           
           10 AUTH-TYPE            PIC X(4).                            
           10 CARD-EXPIRY-DATE     PIC X(4).                            
           10 MESSAGE-TYPE         PIC X(6).                            
           10 MESSAGE-SOURCE       PIC X(6).                            
           10 AUTH-ID-CODE         PIC X(6).                            
           10 AUTH-RESP-CODE       PIC X(2).                            
           10 AUTH-RESP-REASON     PIC X(4).                            
           10 PROCESSING-CODE      PIC X(6).                            
           10 TRANSACTION-AMT      PIC S9(10)V9(2) USAGE COMP-3.        
           10 APPROVED-AMT         PIC S9(10)V9(2) USAGE COMP-3.        
           10 MERCHANT-CATAGORY-CODE                                    
              PIC X(4).                                                 
           10 ACQR-COUNTRY-CODE    PIC X(3).                            
           10 POS-ENTRY-MODE       PIC S9(4) USAGE COMP.                
           10 MERCHANT-ID          PIC X(15).                           
           10 MERCHANT-NAME.                                            
              49 MERCHANT-NAME-LEN                                      
                 PIC S9(4) USAGE COMP.                                  
              49 MERCHANT-NAME-TEXT                                     
                 PIC X(22).                                             
           10 MERCHANT-CITY        PIC X(13).                           
           10 MERCHANT-STATE       PIC X(2).                            
           10 MERCHANT-ZIP         PIC X(9).                            
           10 TRANSACTION-ID       PIC X(15).                           
           10 MATCH-STATUS         PIC X(1).                            
           10 AUTH-FRAUD           PIC X(1).                            
           10 FRAUD-RPT-DATE       PIC X(10).                           
           10 ACCT-ID              PIC S9(11)V USAGE COMP-3.            
           10 CUST-ID              PIC S9(9)V USAGE COMP-3.             
      ******************************************************************
      * THE NUMBER OF COLUMNS DESCRIBED BY THIS DECLARATION IS 26      *
      ******************************************************************
                                                                        
                                                                        
       LINKAGE SECTION.                                                 
       COPY DFHEIBLK.
       01  DFHCOMMAREA.                                                 
           02 WS-ACCT-ID                    PIC 9(11).                  
           02 WS-CUST-ID                    PIC 9(9).                   
           02 WS-FRAUD-AUTH-RECORD.                                     
              COPY CIPAUDTY.                                            
           02 WS-FRAUD-STATUS-RECORD.                                   
              05 WS-FRD-ACTION              PIC X(01).                  
                 88 WS-REPORT-FRAUD         VALUE 'F'.                  
                 88 WS-REMOVE-FRAUD         VALUE 'R'.                  
              05 WS-FRD-UPDATE-STATUS       PIC X(01).                  
                 88 WS-FRD-UPDT-SUCCESS     VALUE 'S'.                  
                 88 WS-FRD-UPDT-FAILED      VALUE 'F'.                  
              05 WS-FRD-ACT-MSG             PIC X(50).                  
                                                                        
       PROCEDURE DIVISION USING DFHEIBLK DFHCOMMAREA.
       MAIN-PARA.                                                       
                                                                        
      *KIX  EXEC CICS ASKTIME NOHANDLE ABSTIME(WS-ABS-TIME) NOHANDLE
           CALL "KIXCMD" USING
               BY CONTENT "ASKTIME|NOHANDLE|ABSTIME=|NOHANDLE"
               BY REFERENCE WS-ABS-TIME
           END-CALL
      *KIX  EXEC CICS FORMATTIME ABSTIME(WS-ABS-TIME) MMDDYY(WS-CUR-DATE
           CALL "KIXCMD" USING
               BY CONTENT "FORMATTIME|ABSTIME=|MMDDYY=|DATESEP|NOHA"
                        & "NDLE"
               BY REFERENCE WS-ABS-TIME
               BY REFERENCE WS-CUR-DATE
           END-CALL
           MOVE WS-CUR-DATE       TO PA-FRAUD-RPT-DATE                  
                                                                        
           MOVE PA-AUTH-ORIG-DATE(1:2) TO WS-AUTH-YY                    
           MOVE PA-AUTH-ORIG-DATE(3:2) TO WS-AUTH-MM                    
           MOVE PA-AUTH-ORIG-DATE(5:2) TO WS-AUTH-DD                    
                                                                        
           COMPUTE WS-AUTH-TIME = 999999999 - PA-AUTH-TIME-9C           
           MOVE WS-AUTH-TIME-AN(1:2) TO WS-AUTH-HH                      
           MOVE WS-AUTH-TIME-AN(3:2) TO WS-AUTH-MI                      
           MOVE WS-AUTH-TIME-AN(5:2) TO WS-AUTH-SS                      
           MOVE WS-AUTH-TIME-AN(7:3) TO WS-AUTH-SSS                     
                                                                        
           MOVE PA-CARD-NUM          TO CARD-NUM                        
           MOVE WS-AUTH-TS           TO AUTH-TS                         
           MOVE PA-AUTH-TYPE         TO AUTH-TYPE                       
           MOVE PA-CARD-EXPIRY-DATE  TO CARD-EXPIRY-DATE                
           MOVE PA-MESSAGE-TYPE      TO MESSAGE-TYPE                    
           MOVE PA-MESSAGE-SOURCE    TO MESSAGE-SOURCE                  
           MOVE PA-AUTH-ID-CODE      TO AUTH-ID-CODE                    
           MOVE PA-AUTH-RESP-CODE    TO AUTH-RESP-CODE                  
           MOVE PA-AUTH-RESP-REASON  TO AUTH-RESP-REASON                
           MOVE PA-PROCESSING-CODE   TO PROCESSING-CODE                 
           MOVE PA-TRANSACTION-AMT   TO TRANSACTION-AMT                 
           MOVE PA-APPROVED-AMT      TO APPROVED-AMT                    
           MOVE PA-MERCHANT-CATAGORY-CODE                               
                                     TO MERCHANT-CATAGORY-CODE          
           MOVE PA-ACQR-COUNTRY-CODE TO ACQR-COUNTRY-CODE               
           MOVE PA-POS-ENTRY-MODE    TO POS-ENTRY-MODE                  
           MOVE PA-MERCHANT-ID       TO MERCHANT-ID                     
           MOVE LENGTH OF PA-MERCHANT-NAME TO MERCHANT-NAME-LEN         
           MOVE PA-MERCHANT-NAME     TO MERCHANT-NAME-TEXT              
           MOVE PA-MERCHANT-CITY     TO MERCHANT-CITY                   
           MOVE PA-MERCHANT-STATE    TO MERCHANT-STATE                  
           MOVE PA-MERCHANT-ZIP      TO MERCHANT-ZIP                    
           MOVE PA-TRANSACTION-ID    TO TRANSACTION-ID                  
           MOVE PA-MATCH-STATUS      TO MATCH-STATUS                    
           MOVE WS-FRD-ACTION        TO AUTH-FRAUD                      
           MOVE WS-ACCT-ID           TO ACCT-ID                         
           MOVE WS-CUST-ID           TO CUST-ID                         
                                                                        
      *KIX  EXEC SQL INSERT INTO CARDDEMO.AUTHFRDS (CARD_NUM ,AUTH_TS ,
           CALL "KIXCMD" USING
               BY CONTENT "SQL|EXEC||iiiiiiiiiiiiiiiiIiiiiiiii|INSE"
                        & "RT INTO CARDDEMO.AUTHFRDS (CARD_NUM ,AUT"
                        & "H_TS ,AUTH_TYPE ,CARD_EXPIRY_DATE ,MESSA"
                        & "GE_TYPE ,MESSAGE_SOURCE ,AUTH_ID_CODE ,A"
                        & "UTH_RESP_CODE ,AUTH_RESP_REASON ,PROCESS"
                        & "ING_CODE ,TRANSACTION_AMT ,APPROVED_AMT "
                        & ",MERCHANT_CATAGORY_CODE ,ACQR_COUNTRY_CO"
                        & "DE ,POS_ENTRY_MODE ,MERCHANT_ID ,MERCHAN"
                        & "T_NAME ,MERCHANT_CITY ,MERCHANT_STATE ,M"
                        & "ERCHANT_ZIP ,TRANSACTION_ID ,MATCH_STATU"
                        & "S ,AUTH_FRAUD ,FRAUD_RPT_DATE ,ACCT_ID ,"
                        & "CUST_ID) VALUES ( ? ,TIMESTAMP_FORMAT (?"
                        & ", 'YY-MM-DD HH24.MI.SSNNNNNN') ,? ,? ,? "
                        & ",? ,? ,? ,? ,? ,? ,? ,? ,? ,? ,? ,? ,? ,"
                        & "? ,? ,? ,? ,? ,CURRENT DATE ,? ,? )"
               BY REFERENCE SQLCA
               BY REFERENCE CARD-NUM
               BY REFERENCE AUTH-TS
               BY REFERENCE AUTH-TYPE
               BY REFERENCE CARD-EXPIRY-DATE
               BY REFERENCE MESSAGE-TYPE
               BY REFERENCE MESSAGE-SOURCE
               BY REFERENCE AUTH-ID-CODE
               BY REFERENCE AUTH-RESP-CODE
               BY REFERENCE AUTH-RESP-REASON
               BY REFERENCE PROCESSING-CODE
               BY REFERENCE TRANSACTION-AMT
               BY REFERENCE APPROVED-AMT
               BY REFERENCE MERCHANT-CATAGORY-CODE
               BY REFERENCE ACQR-COUNTRY-CODE
               BY REFERENCE POS-ENTRY-MODE
               BY REFERENCE MERCHANT-ID
               BY REFERENCE MERCHANT-NAME
               BY REFERENCE MERCHANT-CITY
               BY REFERENCE MERCHANT-STATE
               BY REFERENCE MERCHANT-ZIP
               BY REFERENCE TRANSACTION-ID
               BY REFERENCE MATCH-STATUS
               BY REFERENCE AUTH-FRAUD
               BY REFERENCE ACCT-ID
               BY REFERENCE CUST-ID
           END-CALL
           IF SQLCODE = ZERO                                            
              SET WS-FRD-UPDT-SUCCESS TO TRUE                           
              MOVE 'ADD SUCCESS'      TO WS-FRD-ACT-MSG                 
           ELSE                                                         
              IF SQLCODE = -803                                         
                 PERFORM FRAUD-UPDATE                                   
              ELSE                                                      
                 SET WS-FRD-UPDT-FAILED  TO TRUE                        
                                                                        
                 MOVE SQLCODE            TO WS-SQLCODE                  
                 MOVE SQLSTATE           TO WS-SQLSTATE                 
                                                                        
                 STRING ' SYSTEM ERROR DB2: CODE:' WS-SQLCODE           
                        ', STATE: ' WS-SQLSTATE   DELIMITED BY SIZE     
                 INTO WS-FRD-ACT-MSG                                    
                 END-STRING                                             
              END-IF                                                    
           END-IF                                                       
                                                                        
      *KIX  EXEC CICS RETURN
           CALL "KIXCMD" USING
               BY CONTENT "RETURN"
           END-CALL
           GOBACK
           .                                                            
       FRAUD-UPDATE.                                                    
      *KIX  EXEC SQL UPDATE CARDDEMO.AUTHFRDS SET AUTH_FRAUD = :AUTH-FR
           CALL "KIXCMD" USING
               BY CONTENT "SQL|EXEC||iii|UPDATE CARDDEMO.AUTHFRDS S"
                        & "ET AUTH_FRAUD = ?, FRAUD_RPT_DATE = CURR"
                        & "ENT DATE WHERE CARD_NUM = ? AND AUTH_TS "
                        & "= TIMESTAMP_FORMAT (?, 'YY-MM-DD HH24.MI"
                        & ".SSNNNNNN')"
               BY REFERENCE SQLCA
               BY REFERENCE AUTH-FRAUD
               BY REFERENCE CARD-NUM
               BY REFERENCE AUTH-TS
           END-CALL
           IF SQLCODE = ZERO                                            
              SET WS-FRD-UPDT-SUCCESS TO TRUE                           
              MOVE 'UPDT SUCCESS'     TO WS-FRD-ACT-MSG                 
           ELSE                                                         
              SET WS-FRD-UPDT-FAILED  TO TRUE                           
                                                                        
              MOVE SQLCODE            TO WS-SQLCODE                     
              MOVE SQLSTATE           TO WS-SQLSTATE                    
                                                                        
              STRING ' UPDT ERROR DB2: CODE:' WS-SQLCODE                
                     ', STATE: ' WS-SQLSTATE   DELIMITED BY SIZE        
              INTO WS-FRD-ACT-MSG                                       
              END-STRING                                                
           END-IF                                                       
           .                                                            
