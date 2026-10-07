000100**************************************** *************************
000200* Program:     COTRTUPC.CBL                                      *
000300* Layer:       Business logic                                    *
000400* Function:    Accept and process TRANSACTION TYPE UPDATE        *
000500******************************************************************
000600* Copyright Amazon.com, Inc. or its affiliates.                   
000700* All Rights Reserved.                                            
000800*                                                                 
000900* Licensed under the Apache License, Version 2.0 (the "License"). 
001000* You may not use this file except in compliance with the License.
001100* You may obtain a copy of the License at                         
001200*                                                                 
001300*    http://www.apache.org/licenses/LICENSE-2.0                   
001400*                                                                 
001500* Unless required by applicable law or agreed to in writing,      
001600* software distributed under the License is distributed on an     
001700* "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,    
001800* either express or implied. See the License for the specific     
001900* language governing permissions and limitations under the License
002000******************************************************************
002100 IDENTIFICATION DIVISION.                                         
002200 PROGRAM-ID.                                                      
002300     COTRTUPC.                                                    
002400 DATE-WRITTEN.                                                    
002500     Dec 2022.                                                    
002600 DATE-COMPILED.                                                   
002700     Today.                                                       
002800                                                                  
002900 ENVIRONMENT DIVISION.                                            
003000 INPUT-OUTPUT SECTION.                                            
003100                                                                  
003200 DATA DIVISION.                                                   
003300                                                                  
003400 WORKING-STORAGE SECTION.                                         
003500 01  WS-MISC-STORAGE.                                             
003600******************************************************************
003700* General CICS related                                            
003800******************************************************************
003900   05 WS-CICS-PROCESSNG-VARS.                                     
004000      07 WS-RESP-CD                          PIC S9(09) COMP      
004100                                             VALUE ZEROS.         
004200      07 WS-REAS-CD                          PIC S9(09) COMP      
004300                                             VALUE ZEROS.         
004400      07 WS-TRANID                           PIC X(4)             
004500                                             VALUE SPACES.        
004600      07 WS-UCTRANS                          PIC X(4)             
004700                                             VALUE SPACES.        
004800******************************************************************
004900*      Input edits                                                
005000******************************************************************
005100*  Generic Input Edits                                            
005200   05  WS-GENERIC-EDITS.                                          
005300     10 WS-EDIT-VARIABLE-NAME                PIC X(25).           
005400                                                                  
005500     10 WS-EDIT-ALPHANUM-ONLY                PIC X(256).          
005600     10 WS-EDIT-ALPHANUM-LENGTH              PIC S9(4) COMP-3.    
005700                                                                  
005800     10 WS-EDIT-ALPHANUM-ONLY-FLAGS          PIC X(1).            
005900        88  FLG-ALPHNANUM-ISVALID            VALUE LOW-VALUES.    
006000        88  FLG-ALPHNANUM-NOT-OK             VALUE '0'.           
006100        88  FLG-ALPHNANUM-BLANK              VALUE 'B'.           
006200                                                                  
006300                                                                  
006400******************************************************************
006500*    Work variables                                               
006600******************************************************************
006700    05 WS-MISC-VARS.                                              
006800      10 WS-DISP-SQLCODE                    PIC ----9.            
006900      10 WS-STRING-MID                      PIC 9(3) VALUE 0.     
007000      10 WS-STRING-LEN                      PIC 9(3) VALUE 0.     
007100      10 WS-STRING-OUT                      PIC X(40).            
007200                                                                  
007300******************************************************************
007400*    Generic date edit variables CCYYMMDD                         
007500******************************************************************
007600     COPY 'CSUTLDWY'.                                             
007700******************************************************************
007800   05  WS-DATACHANGED-FLAG                   PIC X(1).            
007900     88  NO-CHANGES-FOUND                    VALUE '0'.           
008000     88  CHANGE-HAS-OCCURRED                 VALUE '1'.           
008100   05  WS-INPUT-FLAG                         PIC X(1).            
008200     88  INPUT-OK                            VALUE '0'.           
008300     88  INPUT-ERROR                         VALUE '1'.           
008400     88  INPUT-PENDING                       VALUE LOW-VALUES.    
008500   05  WS-RETURN-FLAG                        PIC X(1).            
008600     88  WS-RETURN-FLAG-OFF                  VALUE LOW-VALUES.    
008700     88  WS-RETURN-FLAG-ON                   VALUE '1'.           
008800   05  WS-PFK-FLAG                           PIC X(1).            
008900     88  PFK-VALID                           VALUE '0'.           
009000     88  PFK-INVALID                         VALUE '1'.           
009100                                                                  
009200*  Program specific edits                                         
009300*                                                                 
009400   05  WS-EDIT-TTYP-FLAG                     PIC X(1).            
009500     88  FLG-TRANFILTER-ISVALID              VALUE LOW-VALUES.    
009600     88  FLG-TRANFILTER-NOT-OK               VALUE '0'.           
009700     88  FLG-TRANFILTER-BLANK                VALUE 'B'.           
009800                                                                  
009900   05 WS-NON-KEY-FLAGS.                                           
010000     10  WS-EDIT-DESC-FLAGS                  PIC X(1).            
010100         88  FLG-DESCRIPTION-ISVALID          VALUE LOW-VALUES.   
010200         88  FLG-DESCRIPTION-NOT-OK           VALUE '0'.          
010300         88  FLG-DESCRIPTION-BLANK            VALUE 'B'.          
010400******************************************************************
010500* Output edits                                                    
010600******************************************************************
010700   05 CICS-OUTPUT-EDIT-VARS.                                      
010800     10  WS-EDIT-DATE-X                      PIC X(10).           
010900     10  FILLER REDEFINES WS-EDIT-DATE-X.                         
011000         20 WS-EDIT-DATE-X-YEAR              PIC X(4).            
011100         20 FILLER                           PIC X(1).            
011200         20 WS-EDIT-DATE-MONTH               PIC X(2).            
011300         20 FILLER                           PIC X(1).            
011400         20 WS-EDIT-DATE-DAY                 PIC X(2).            
011500     10  WS-EDIT-DATE-X REDEFINES                                 
011600         WS-EDIT-DATE-X                      PIC 9(10).           
011700     10  WS-EDIT-CURRENCY-9-2                PIC X(15).           
011800     10  WS-EDIT-CURRENCY-9-2-F              PIC +ZZZ,ZZZ,ZZZ.99. 
011900     10  WS-EDIT-NUMERIC-2                   PIC 9(02).           
012000     10  WS-EDIT-ALPHANUMERIC-2              PIC X(02).           
012100                                                                  
012200******************************************************************
012300*      File and data Handling                                     
012400******************************************************************
012500   05  WS-TABLE-READ-FLAGS.                                       
012600     10 WS-TRANTYPE-MASTER-READ-FLAG         PIC X(1).            
012700        88 FOUND-TRANTYPE-IN-TABLE          VALUE '1'.            
012800*  Alpha variables for editing numerics                           
012900*                                                                 
013000    05 TTYP-UPDATE-RECORD.                                        
013100***************************************************************** 
013200*    Data-structure for  TRANSACTION TYPE (RECLN 60)              
013300***************************************************************** 
013400         15  TTUP-UPDATE-TTYP-TYPE               PIC X(02).       
013500         15  TTUP-UPDATE-TTYP-TYPE-DESC          PIC X(50).       
013600         15  FILLER                              PIC X(08).       
013700                                                                  
013800                                                                  
013900******************************************************************
014000*      Output Message Construction                                
014100******************************************************************
014200   05  WS-INFO-MSG                           PIC X(40).           
014300     88  WS-NO-INFO-MESSAGE                 VALUES                
014400                                            SPACES LOW-VALUES.    
014500     88  FOUND-TRANTYPE-DATA                 VALUE                
014600         'Selected transaction type shown above'.                 
014700     88  PROMPT-FOR-SEARCH-KEYS              VALUE                
014800         'Enter transaction type to be maintained'.               
014900     88  PROMPT-CREATE-NEW-RECORD            VALUE                
015000         'Press F05 to add. F12 to cancel'.                       
015100     88  PROMPT-DELETE-CONFIRM               VALUE                
015200         'Delete this record ? Press F4 to confirm'.              
015300     88  CONFIRM-DELETE-SUCCESS              VALUE                
015400         'Delete successful.'.                                    
015500     88  PROMPT-FOR-CHANGES                  VALUE                
015600         'Update transaction type details shown.'.                
015700     88  PROMPT-FOR-NEWDATA                  VALUE                
015800         'Enter new transaction type details.'.                   
015900                                                                  
016000     88  PROMPT-FOR-CONFIRMATION             VALUE                
016100         'Changes validated.Press F5 to save'.                    
016200     88  CONFIRM-UPDATE-SUCCESS              VALUE                
016300         'Changes committed to database'.                         
016400     88  INFORM-FAILURE                      VALUE                
016500         'Changes unsuccessful'.                                  
016600                                                                  
016700   05  WS-RETURN-MSG                         PIC X(75).           
016800     88  WS-RETURN-MSG-OFF                   VALUE SPACES.        
016900     88  WS-EXIT-MESSAGE                     VALUE                
017000         'PF03 pressed.Exiting              '.                    
017100     88  WS-INVALID-KEY                      VALUE                
017200         'Invalid Key pressed. '.                                 
017300     88  WS-NAME-MUST-BE-ALPHA               VALUE                
017400         'Name can only contain alphabets and spaces'.            
017500     88  WS-RECORD-NOT-FOUND                 VALUE                
017600         'No record found for this key in database' .             
017700     88  NO-SEARCH-CRITERIA-RECEIVED         VALUE                
017800         'No input received'.                                     
017900     88  NO-CHANGES-DETECTED                 VALUE                
018000         'No change detected with respect to values fetched.'.    
018100     88  COULD-NOT-LOCK-REC-FOR-UPDATE       VALUE                
018200         'Could not lock record for update'.                      
018300     88  DATA-WAS-CHANGED-BEFORE-UPDATE      VALUE                
018400         'Record changed by some one else. Please review'.        
018500     88  WS-UPDATE-WAS-CANCELLED             VALUE                
018600         'Update was cancelled'.                                  
018700     88  TABLE-UPDATE-FAILED                 VALUE                
018800         'Update of record failed'.                               
018900     88  RECORD-DELETE-FAILED                VALUE                
019000         'Delete of record failed'.                               
019100     88  WS-DELETE-WAS-CANCELLED             VALUE                
019200         'Delete was cancelled'.                                  
019300     88  WS-INVALID-KEY-PRESSED              VALUE                
019400         'Invalid key pressed'.                                   
019500     88  CODING-TO-BE-DONE                   VALUE                
019600         'Looks Good.... so far'.                                 
019700******************************************************************
019800*      Literals and Constants                                     
019900******************************************************************
020000 01 WS-LITERALS.                                                  
020100    05 LIT-THISPGM                           PIC X(8)             
020200                                             VALUE 'COTRTUPC'.    
020300    05 LIT-THISTRANID                        PIC X(4)             
020400                                             VALUE 'CTTU'.        
020500    05 LIT-THISMAPSET                        PIC X(8)             
020600                                             VALUE 'COTRTUP '.    
020700    05 LIT-THISMAP                           PIC X(7)             
020800                                             VALUE 'CTRTUPA'.     
020900    05 LIT-ADMINPGM                           PIC X(8)            
021000                                             VALUE 'COADM01C'.    
021100    05 LIT-ADMINTRANID                        PIC X(4)            
021200                                             VALUE 'CA00'.        
021300    05 LIT-ADMINMAPSET                        PIC X(7)            
021400                                             VALUE 'COADM01'.     
021500    05 LIT-ADMINMAP                           PIC X(7)            
021600                                             VALUE 'COADM1A'.     
021700    05 LIT-LISTTPGM                           PIC X(8)            
021800                                             VALUE 'COTRTLIC'.    
021900    05 LIT-LISTTTRANID                        PIC X(4)            
022000                                             VALUE 'CTLI'.        
022100    05 LIT-LISTTMAPSET                        PIC X(7)            
022200                                             VALUE 'COTRTLI'.     
022300    05 LIT-LISTTMAP                           PIC X(7)            
022400                                             VALUE 'CTRTLIA'.     
022500                                                                  
022600                                                                  
022700******************************************************************
022800* Literals for use in INSPECT statements                          
022900******************************************************************
023000    05 LIT-ALL-ALPHANUM-FROM-X.                                   
023100       10 LIT-ALL-ALPHA-FROM-X.                                   
023200          15 LIT-UPPER                       PIC X(26)            
023300                           VALUE 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'.    
023400          15 LIT-LOWER                       PIC X(26)            
023500                           VALUE 'abcdefghijklmnopqrstuvwxyz'.    
023600       10 LIT-NUMBERS                        PIC X(10)            
023700                           VALUE '0123456789'.                    
023800******************************************************************
023900*Other common working storage Variables                           
024000******************************************************************
024100 COPY CVCRD01Y.                                                   
024200******************************************************************
024300*Lookups                                                          
024400******************************************************************
024500                                                                  
024600******************************************************************
024700* Variables for use in INSPECT statements                         
024800******************************************************************
024900 01  LIT-ALL-ALPHA-FROM     PIC X(52) VALUE SPACES.               
025000 01  LIT-ALL-ALPHANUM-FROM  PIC X(62) VALUE SPACES.               
025100 01  LIT-ALL-NUM-FROM       PIC X(10) VALUE SPACES.               
025200 77  LIT-ALPHA-SPACES-TO    PIC X(52) VALUE SPACES.               
025300 77  LIT-ALPHANUM-SPACES-TO PIC X(62) VALUE SPACES.               
025400 77  LIT-NUM-SPACES-TO      PIC X(10) VALUE SPACES.               
025500                                                                  
025600*IBM SUPPLIED COPYBOOKS                                           
025700 COPY DFHBMSCA.                                                   
025800 COPY DFHAID.                                                     
025900                                                                  
026000*COMMON COPYBOOKS                                                 
026100*Screen Titles                                                    
026200 COPY COTTL01Y.                                                   
026300                                                                  
026400*Transaction Type Update Screen Layout                            
026500 COPY COTRTUP.                                                    
026600                                                                  
026700*Current Date                                                     
026800 COPY CSDAT01Y.                                                   
026900                                                                  
027000*Common Messages                                                  
027100 COPY CSMSG01Y.                                                   
027200                                                                  
027300*Abend Variables                                                  
027400 COPY CSMSG02Y.                                                   
027500                                                                  
027600*Signed on user data                                              
027700 COPY CSUSR01Y.                                                   
027800                                                                  
027900******************************************************************
028000* Relational Database stuff                                       
028100******************************************************************
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
028500                                                                  
000010******************************************************************
000020* Copyright Amazon.com, Inc. or its affiliates.                   
000030* All Rights Reserved.                                            
000040*                                                                 
000050* Licensed under the Apache License, Version 2.0 (the "License"). 
000060* You may not use this file except in compliance with the License.
000070* You may obtain a copy of the License at                         
000080*                                                                 
000090*    http://www.apache.org/licenses/LICENSE-2.0                   
000091*                                                                 
000092* Unless required by applicable law or agreed to in writing,      
000093* software distributed under the License is distributed on an     
000094* "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,    
000095* either express or implied. See the License for the specific     
000096* language governing permissions and limitations under the License
000100******************************************************************
      ******************************************************************
      * DCLGEN TABLE(CARDDEMO.TRANSACTION_TYPE)                        *
      *        LIBRARY(SNJARAO.AWS.DCL(DCLTRTYP))                      *
      *        ACTION(REPLACE)                                         *
      *        LANGUAGE(COBOL)                                         *
      *        NAMES(DCL-)                                             *
      *        QUOTE                                                   *
      *        LABEL(YES)                                              *
      *        COLSUFFIX(YES)                                          *
      * ... IS THE DCLGEN COMMAND THAT MADE THE FOLLOWING STATEMENTS   *
      ******************************************************************
      *KIX  EXEC SQL DECLARE CARDDEMO.TRANSACTION_TYPE TABLE ( TR_TYPE 
      ******************************************************************
      * COBOL DECLARATION FOR TABLE CARDDEMO.TRANSACTION_TYPE          *
      ******************************************************************
       01  DCLTRANSACTION-TYPE.
      *    *************************************************************
      *                       TR_TYPE
           10 DCL-TR-TYPE          PIC X(2).
      *    *************************************************************
           10 DCL-TR-DESCRIPTION.
      *                       TR_DESCRIPTION LENGTH
              49 DCL-TR-DESCRIPTION-LEN
                 PIC S9(4) USAGE COMP.
      *                       TR_DESCRIPTION
              49 DCL-TR-DESCRIPTION-TEXT
                 PIC X(50).
      ******************************************************************
      * THE NUMBER OF COLUMNS DESCRIBED BY THIS DECLARATION IS 2       *
      ******************************************************************
028700                                                                  
000010******************************************************************
000020* Copyright Amazon.com, Inc. or its affiliates.                   
000030* All Rights Reserved.                                            
000040*                                                                 
000050* Licensed under the Apache License, Version 2.0 (the "License"). 
000060* You may not use this file except in compliance with the License.
000070* You may obtain a copy of the License at                         
000080*                                                                 
000090*    http://www.apache.org/licenses/LICENSE-2.0                   
000091*                                                                 
000092* Unless required by applicable law or agreed to in writing,      
000093* software distributed under the License is distributed on an     
000094* "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,    
000095* either express or implied. See the License for the specific     
000096* language governing permissions and limitations under the License
000100******************************************************************
      ******************************************************************
      * DCLGEN TABLE(CARDDEMO.TRANSACTION_TYPE_CATEGORY)               *
      *        LIBRARY(SNJARAO.AWS.DCL(DCLTRCAT))                      *
      *        ACTION(REPLACE)                                         *
      *        LANGUAGE(COBOL)                                         *
      *        NAMES(DCL-)                                             *
      *        QUOTE                                                   *
      *        LABEL(YES)                                              *
      *        COLSUFFIX(YES)                                          *
      * ... IS THE DCLGEN COMMAND THAT MADE THE FOLLOWING STATEMENTS   *
      ******************************************************************
      *KIX  EXEC SQL DECLARE CARDDEMO.TRANSACTION_TYPE_CATEGORY TABLE (
      ******************************************************************
      * COBOL DECLARATION FOR TABLE CARDDEMO.TRANSACTION_TYPE_CATEGORY *
      ******************************************************************
       01  DCLTRANSACTION-TYPE-CATEGORY.
      *    *************************************************************
      *                       TRC_TYPE_CODE
           10 DCL-TRC-TYPE-CODE    PIC X(2).
      *    *************************************************************
      *                       TRC_TYPE_CATEGORY
           10 DCL-TRC-TYPE-CATEGORY
              PIC X(4).
      *    *************************************************************
           10 DCL-TRC-CAT-DATA.
      *                       TRC_CAT_DATA LENGTH
              49 DCL-TRC-CAT-DATA-LEN
                 PIC S9(4) USAGE COMP.
      *                       TRC_CAT_DATA
              49 DCL-TRC-CAT-DATA-TEXT
                 PIC X(50).
      ******************************************************************
      * THE NUMBER OF COLUMNS DESCRIBED BY THIS DECLARATION IS 3       *
      ******************************************************************
028900                                                                  
029000******************************************************************
029100*Application Commmarea Copybook                                   
029200 COPY COCOM01Y.                                                   
029300                                                                  
029400 01 WS-THIS-PROGCOMMAREA.                                         
029500    05 TTUP-UPDATE-SCREEN-DATA.                                   
029600       10 TTUP-CHANGE-ACTION                     PIC X(1)         
029700                                                 VALUE LOW-VALUES.
029800          88 TTUP-DETAILS-NOT-FETCHED            VALUES           
029900                                                 LOW-VALUES,      
030000                                                 SPACES.          
030100          88 TTUP-INVALID-SEARCH-KEYS            VALUE 'K'.       
030200          88 TTUP-DETAILS-NOT-FOUND              VALUE 'X'.       
030300          88 TTUP-SHOW-DETAILS                   VALUE 'S'.       
030400*                                                                 
030500          88 TTUP-CREATE-NEW-RECORD              VALUE 'R'.       
030600          88 TTUP-REVIEW-NEW-RECORD              VALUE 'V'.       
030700          88 TTUP-DELETE-IN-PROGRESS             VALUES '9'       
030800                                                      , '8', '7'  
030900                                                      , '6'.      
031000          88 TTUP-CONFIRM-DELETE                 VALUE '9'.       
031100          88 TTUP-START-DELETE                   VALUE '8'.       
031200          88 TTUP-DELETE-DONE                    VALUE '7'.       
031300          88 TTUP-DELETE-FAILED                  VALUE '6'.       
031400***                                                               
031500          88 TTUP-CHANGES-MADE                   VALUES 'E', 'N'  
031600                                                      , 'L'       
031700                                                      , 'F'.      
031800          88 TTUP-CHANGES-NOT-OK                 VALUE 'E'.       
031900          88 TTUP-CHANGES-OK-NOT-CONFIRMED       VALUE 'N'.       
032000                                                                  
032100***                                                               
032200          88 TTUP-CHANGES-FAILED                 VALUES 'L', 'F'. 
032300          88 TTUP-CHANGES-OKAYED-LOCK-ERROR      VALUE 'L'.       
032400          88 TTUP-CHANGES-OKAYED-BUT-FAILED      VALUE 'F'.       
032500                                                                  
032600          88 TTUP-CHANGES-OKAYED-AND-DONE        VALUE 'C'.       
032700          88 TTUP-CHANGES-BACKED-OUT             VALUE 'B'.       
032800    05 TTUP-OLD-DETAILS.                                          
032900       10 TTUP-OLD-TTYP-DATA.                                     
033000          15  TTUP-OLD-TTYP-TYPE                 PIC X(02).       
033100          15  TTUP-OLD-TTYP-TYPE-DESC            PIC X(50).       
033200    05 TTUP-NEW-DETAILS.                                          
033300       10 TTUP-NEW-TTYP-DATA.                                     
033400          15  TTUP-NEW-TTYP-TYPE                 PIC X(02).       
033500          15  TTUP-NEW-TTYP-TYPE-DESC            PIC X(50).       
033600 01  WS-COMMAREA                                 PIC X(2000).     
033700                                                                  
033800                                                                  
033900 LINKAGE SECTION.                                                 
       COPY DFHEIBLK.
034000 01  DFHCOMMAREA.                                                 
034100   05  FILLER                                PIC X(1)             
034200       OCCURS 1 TO 32767 TIMES DEPENDING ON EIBCALEN.             
034300                                                                  
       PROCEDURE DIVISION USING DFHEIBLK DFHCOMMAREA.
034500 0000-MAIN.                                                       
034600                                                                  
034700                                                                  
      *KIX  EXEC CICS HANDLE ABEND LABEL(ABEND-ROUTINE)
           CALL "KIXCMD" USING
               BY CONTENT "HANDLE|ABEND|LABEL:1"
           END-CALL
           GO TO ABEND-ROUTINE DEPENDING ON RETURN-CODE
           CONTINUE
035100                                                                  
035200     INITIALIZE CC-WORK-AREA                                      
035300                WS-MISC-STORAGE                                   
035400                WS-COMMAREA                                       
035500***************************************************************** 
035600* Store our context                                               
035700***************************************************************** 
035800     MOVE LIT-THISTRANID       TO WS-TRANID                       
035900***************************************************************** 
036000* Ensure error message is cleared                               * 
036100***************************************************************** 
036200     SET WS-RETURN-MSG-OFF  TO TRUE                               
036300***************************************************************** 
036400* Store passed data if  any                *                      
036500***************************************************************** 
036600     IF EIBCALEN IS EQUAL TO 0                                    
036700         OR (CDEMO-FROM-PROGRAM = LIT-ADMINPGM                    
036800         AND NOT CDEMO-PGM-REENTER)                               
036900         OR (CDEMO-FROM-PROGRAM = LIT-LISTTPGM                    
037000         AND NOT CDEMO-PGM-REENTER)                               
037100        INITIALIZE CARDDEMO-COMMAREA                              
037200                   WS-THIS-PROGCOMMAREA                           
037300        SET CDEMO-PGM-ENTER TO TRUE                               
037400        SET TTUP-DETAILS-NOT-FETCHED TO TRUE                      
037500     ELSE                                                         
037600        MOVE DFHCOMMAREA (1:LENGTH OF CARDDEMO-COMMAREA)  TO      
037700                          CARDDEMO-COMMAREA                       
037800        MOVE DFHCOMMAREA(LENGTH OF CARDDEMO-COMMAREA + 1:         
037900                         LENGTH OF WS-THIS-PROGCOMMAREA ) TO      
038000                          WS-THIS-PROGCOMMAREA                    
038100     END-IF                                                       
038200***************************************************************** 
038300* Store the Mapped PF Key                                         
038400* Remap PFkeys as needed.                                         
038500***************************************************************** 
038600     PERFORM YYYY-STORE-PFKEY                                     
038700        THRU YYYY-STORE-PFKEY-EXIT                                
038800                                                                  
038900***************************************************************** 
039000* Check the AID to see if its valid at this point               * 
039100* Change the key to some valid value if possible                  
039200* F3 - Exit                                                       
039300* Enter show screen again                                         
039400* F4 - Delete                                                     
039500* F5 - Save                                                       
039600* F12 - Cancel                                                    
039700***************************************************************** 
039800     SET PFK-INVALID TO TRUE                                      
039900                                                                  
040000     PERFORM 0001-CHECK-PFKEYS                                    
040100        THRU 0001-CHECK-PFKEYS-EXIT                               
040200***************************************************************** 
040300*       Simulate initial entry if the following flags are set     
040400***************************************************************** 
040500     EVALUATE TRUE                                                
040600        WHEN CCARD-AID-PFK12                                      
040700         AND (TTUP-SHOW-DETAILS                                   
040800          OR  TTUP-CREATE-NEW-RECORD                              
040900          OR  TTUP-DETAILS-NOT-FOUND)                             
041000        WHEN TTUP-CHANGES-OKAYED-AND-DONE                         
041100        WHEN TTUP-CHANGES-FAILED                                  
041200        WHEN TTUP-CHANGES-BACKED-OUT                              
041300         AND  (TTUP-OLD-DETAILS EQUAL LOW-VALUES                  
041400          OR   TTUP-OLD-DETAILS EQUAL SPACES)                     
041500        WHEN TTUP-DELETE-DONE                                     
041600        WHEN TTUP-DELETE-FAILED                                   
041700             SET CDEMO-PGM-ENTER          TO TRUE                 
041800             SET TTUP-DETAILS-NOT-FETCHED TO TRUE                 
041900     END-EVALUATE                                                 
042000***************************************************************** 
042100* Decide what to do based on PF KEY PRESSED AND CONTEXT           
042200***************************************************************** 
042300     EVALUATE TRUE                                                
042400******************************************************************
042500*       USER PRESSES PF03 TO EXIT                                 
042600*  OR   USER IS DONE WITH UPDATE                                  
042700*            XCTL TO CALLING PROGRAM OR MAIN MENU                 
042800******************************************************************
042900        WHEN CCARD-AID-PFK03                                      
043000                                                                  
043100             IF CDEMO-FROM-TRANID    EQUAL LOW-VALUES             
043200             OR CDEMO-FROM-TRANID    EQUAL SPACES                 
043300                MOVE LIT-ADMINTRANID   TO CDEMO-TO-TRANID         
043400             ELSE                                                 
043500                MOVE CDEMO-FROM-TRANID TO CDEMO-TO-TRANID         
043600             END-IF                                               
043700                                                                  
043800             IF CDEMO-FROM-PROGRAM   EQUAL LOW-VALUES             
043900             OR CDEMO-FROM-PROGRAM   EQUAL SPACES                 
044000                MOVE LIT-ADMINPGM     TO CDEMO-TO-PROGRAM         
044100             ELSE                                                 
044200                MOVE CDEMO-FROM-PROGRAM TO CDEMO-TO-PROGRAM       
044300             END-IF                                               
044400                                                                  
044500             MOVE LIT-THISTRANID     TO CDEMO-FROM-TRANID         
044600             MOVE LIT-THISPGM        TO CDEMO-FROM-PROGRAM        
044700                                                                  
044800             SET  CDEMO-USRTYP-ADMIN TO TRUE                      
044900             SET  CDEMO-PGM-ENTER    TO TRUE                      
045000             MOVE LIT-THISMAPSET     TO CDEMO-LAST-MAPSET         
045100             MOVE LIT-THISMAP        TO CDEMO-LAST-MAP            
045200                                                                  
      *KIX  EXEC CICS SYNCPOINT
           CALL "KIXCMD" USING
               BY CONTENT "SYNCPOINT"
           END-CALL
           GO TO ABEND-ROUTINE DEPENDING ON RETURN-CODE
           CONTINUE
045600                                                                  
      *KIX  EXEC CICS XCTL PROGRAM (CDEMO-TO-PROGRAM) COMMAREA(CARDDEMO-
           CALL "KIXCMD" USING
               BY CONTENT "XCTL|PROGRAM=|COMMAREA="
               BY REFERENCE CDEMO-TO-PROGRAM
               BY REFERENCE CARDDEMO-COMMAREA
           END-CALL
           GO TO ABEND-ROUTINE DEPENDING ON RETURN-CODE
           CONTINUE
046100******************************************************************
046200*       CLEAR SCREEN, CLEAR SAVED CONTEXT                         
046300*       ASK USER FOR SEARCH KEYS                                  
046400******************************************************************
046500        WHEN NOT CDEMO-PGM-REENTER                                
046600         AND CDEMO-FROM-PROGRAM   EQUAL LIT-ADMINPGM              
046700        WHEN NOT CDEMO-PGM-REENTER                                
046800         AND CDEMO-FROM-PROGRAM   EQUAL LIT-LISTTPGM              
046900        WHEN CDEMO-PGM-ENTER                                      
047000         AND TTUP-DETAILS-NOT-FETCHED                             
047100             INITIALIZE WS-THIS-PROGCOMMAREA                      
047200                        WS-MISC-STORAGE                           
047300                        CDEMO-ACCT-ID                             
047400             PERFORM 3000-SEND-MAP THRU                           
047500                     3000-SEND-MAP-EXIT                           
047600             SET CDEMO-PGM-REENTER        TO TRUE                 
047700             SET TTUP-DETAILS-NOT-FETCHED TO TRUE                 
047800             GO TO COMMON-RETURN                                  
047900******************************************************************
048000*       USER PRESSED F04 AFTER BEING ASKED TO VERIFY DELETE       
048100******************************************************************
048200        WHEN CCARD-AID-PFK04                                      
048300         AND TTUP-CONFIRM-DELETE                                  
048400             SET TTUP-START-DELETE                TO TRUE         
048500             PERFORM 9800-DELETE-PROCESSING                       
048600                THRU 9800-DELETE-PROCESSING-EXIT                  
048700             PERFORM 3000-SEND-MAP THRU                           
048800                     3000-SEND-MAP-EXIT                           
048900             GO TO COMMON-RETURN                                  
049000******************************************************************
049100*       USER PRESSED F04.ASK FOR DELETE CONFIRMATION              
049200******************************************************************
049300        WHEN CCARD-AID-PFK04                                      
049400         AND TTUP-SHOW-DETAILS                                    
049500             SET TTUP-CONFIRM-DELETE              TO TRUE         
049600             PERFORM 3000-SEND-MAP THRU                           
049700                     3000-SEND-MAP-EXIT                           
049800             GO TO COMMON-RETURN                                  
049900******************************************************************
050000*       USER PRESSED F05. WHEN NO RECORD WAS FOUND.               
050100*       ASK TO CONFIRM NEW RECORD CREATION                        
050200******************************************************************
050300        WHEN CCARD-AID-PFK05                                      
050400         AND TTUP-DETAILS-NOT-FOUND                               
050500            SET TTUP-CREATE-NEW-RECORD TO TRUE                    
050600             PERFORM 3000-SEND-MAP THRU                           
050700                     3000-SEND-MAP-EXIT                           
050800             GO TO COMMON-RETURN                                  
050900******************************************************************
051000*       USER PRESSED F05 AND CONFIRMED THAT CHANGES CAN BE SAVED  
051100*       EDITS HAVE PASSED                                         
051200*       SO SAVE THE CHANGES                                       
051300******************************************************************
051400        WHEN CCARD-AID-PFK05                                      
051500         AND TTUP-CHANGES-OK-NOT-CONFIRMED                        
051600           PERFORM 9600-WRITE-PROCESSING                          
051700              THRU 9600-WRITE-PROCESSING-EXIT                     
051800             PERFORM 3000-SEND-MAP                                
051900                THRU 3000-SEND-MAP-EXIT                           
052000             GO TO COMMON-RETURN                                  
052100******************************************************************
052200*       USER PRESSED F12. CANCEL THE ACTION                       
052300******************************************************************
052400         WHEN CCARD-AID-PFK12                                     
052500         AND (TTUP-CHANGES-OK-NOT-CONFIRMED                       
052600          OR  TTUP-CONFIRM-DELETE                                 
052700          OR  TTUP-SHOW-DETAILS)                                  
052800             SET FOUND-TRANTYPE-IN-TABLE  TO TRUE                 
052900             PERFORM 2000-DECIDE-ACTION                           
053000                THRU 2000-DECIDE-ACTION-EXIT                      
053100             PERFORM 3000-SEND-MAP                                
053200                THRU 3000-SEND-MAP-EXIT                           
053300             GO TO COMMON-RETURN                                  
053400******************************************************************
053500*       CHECK THE USER INPUTS                                     
053600*       DECIDE WHAT TO DO                                         
053700*       PRESENT NEXT STEPS TO USER                                
053800******************************************************************
053900        WHEN WS-INVALID-KEY-PRESSED                               
054000             PERFORM 3000-SEND-MAP                                
054100                THRU 3000-SEND-MAP-EXIT                           
054200             GO TO COMMON-RETURN                                  
054300******************************************************************
054400*       CHECK THE USER INPUTS                                     
054500*       DECIDE WHAT TO DO                                         
054600*       PRESENT NEXT STEPS TO USER                                
054700******************************************************************
054800        WHEN OTHER                                                
054900             PERFORM 1000-PROCESS-INPUTS                          
055000                THRU 1000-PROCESS-INPUTS-EXIT                     
055100             PERFORM 2000-DECIDE-ACTION                           
055200                THRU 2000-DECIDE-ACTION-EXIT                      
055300             PERFORM 3000-SEND-MAP                                
055400                THRU 3000-SEND-MAP-EXIT                           
055500             GO TO COMMON-RETURN                                  
055600     END-EVALUATE                                                 
055700     .                                                            
055800                                                                  
055900 COMMON-RETURN.                                                   
056000     MOVE WS-RETURN-MSG     TO CCARD-ERROR-MSG                    
056100                                                                  
056200     MOVE  CARDDEMO-COMMAREA    TO WS-COMMAREA                    
056300     MOVE  WS-THIS-PROGCOMMAREA TO                                
056400            WS-COMMAREA(LENGTH OF CARDDEMO-COMMAREA + 1:          
056500                         LENGTH OF WS-THIS-PROGCOMMAREA )         
056600                                                                  
      *KIX  EXEC CICS RETURN TRANSID (LIT-THISTRANID) COMMAREA (WS-COMMA
           CALL "KIXCMD" USING
               BY CONTENT "RETURN|TRANSID=|COMMAREA=|LENGTH="
               BY REFERENCE LIT-THISTRANID
               BY REFERENCE WS-COMMAREA
               BY CONTENT LENGTH OF WS-COMMAREA
           END-CALL
           GO TO ABEND-ROUTINE DEPENDING ON RETURN-CODE
           CONTINUE
           GOBACK
057200     .                                                            
057300 0000-MAIN-EXIT.                                                  
057400     EXIT                                                         
057500     .                                                            
057600                                                                  
057700 0001-CHECK-PFKEYS.                                               
057800                                                                  
057900*    Should mirror logic in PFKey attribut para                   
058000*    3391-PFKEY-ATTRS                                             
058100                                                                  
058200     IF (CCARD-AID-PFK03)                                         
058300     OR (CCARD-AID-ENTER AND NOT TTUP-CONFIRM-DELETE)             
058400     OR (CCARD-AID-PFK04 AND (TTUP-SHOW-DETAILS                   
058500                        OR   TTUP-CONFIRM-DELETE )                
058600        )                                                         
058700                                                                  
058800     OR (CCARD-AID-PFK05 AND (                                    
058900                             TTUP-CHANGES-OK-NOT-CONFIRMED        
059000                        OR   TTUP-DETAILS-NOT-FOUND               
059100                        OR   TTUP-DELETE-IN-PROGRESS              
059200                             )                                    
059300        )                                                         
059400     OR (CCARD-AID-PFK12 AND (                                    
059500                             TTUP-CHANGES-OK-NOT-CONFIRMED        
059600                        OR   TTUP-SHOW-DETAILS                    
059700                        OR   TTUP-DETAILS-NOT-FOUND               
059800                        OR   TTUP-CONFIRM-DELETE                  
059900                        OR   TTUP-CREATE-NEW-RECORD               
060000                             )                                    
060100       )                                                          
060200        SET PFK-VALID                  TO TRUE                    
060300     ELSE                                                         
060400        SET PFK-INVALID                TO TRUE                    
060500        IF WS-RETURN-MSG-OFF                                      
060600           SET WS-INVALID-KEY-PRESSED  TO TRUE                    
060700        END-IF                                                    
060800     END-IF                                                       
060900                                                                  
061000                                                                  
061100*    IF PFK-INVALID                                               
061200*      SET WS-INVALID-KEY  TO TRUE                                
061300*      SET CCARD-AID-ENTER TO TRUE                                
061400*    ELSE                                                         
061500*      CONTINUE                                                   
061600*    END-IF                                                       
061700                                                                  
061800     .                                                            
061900                                                                  
062000                                                                  
062100 0001-CHECK-PFKEYS-EXIT.                                          
062200     EXIT                                                         
062300     .                                                            
062400                                                                  
062500 1000-PROCESS-INPUTS.                                             
062600     PERFORM 1100-RECEIVE-MAP                                     
062700        THRU 1100-RECEIVE-MAP-EXIT                                
062800     PERFORM 1150-STORE-MAP-IN-NEW                                
062900        THRU 1150-STORE-MAP-IN-NEW-EXIT                           
063000     PERFORM 1200-EDIT-MAP-INPUTS                                 
063100        THRU 1200-EDIT-MAP-INPUTS-EXIT                            
063200     MOVE WS-RETURN-MSG  TO CCARD-ERROR-MSG                       
063300     MOVE LIT-THISPGM    TO CCARD-NEXT-PROG                       
063400     MOVE LIT-THISMAPSET TO CCARD-NEXT-MAPSET                     
063500     MOVE LIT-THISMAP    TO CCARD-NEXT-MAP                        
063600     .                                                            
063700*                                                                 
063800 1000-PROCESS-INPUTS-EXIT.                                        
063900     EXIT                                                         
064000     .                                                            
064100 1100-RECEIVE-MAP.                                                
      *KIX  EXEC CICS RECEIVE MAP(LIT-THISMAP) MAPSET(LIT-THISMAPSET) IN
           CALL "KIXCMD" USING
               BY CONTENT "RECEIVE|MAP=|MAPSET=|INTO=|RESP=|RESP2="
               BY REFERENCE LIT-THISMAP
               BY REFERENCE LIT-THISMAPSET
               BY REFERENCE CTRTUPAI
               BY REFERENCE WS-RESP-CD
               BY REFERENCE WS-REAS-CD
           END-CALL
           GO TO ABEND-ROUTINE DEPENDING ON RETURN-CODE
           CONTINUE
064800     .                                                            
064900 1100-RECEIVE-MAP-EXIT.                                           
065000     EXIT.                                                        
065100                                                                  
065200 1150-STORE-MAP-IN-NEW.                                           
065300                                                                  
065400     IF  TTUP-DETAILS-NOT-FOUND                                   
065500     AND NOT CCARD-AID-PFK05                                      
065600     AND FUNCTION TRIM(TRTYPCDI OF CTRTUPAI)                      
065700           = TTUP-NEW-TTYP-TYPE                                   
065800         GO TO 1150-STORE-MAP-IN-NEW-EXIT                         
065900     ELSE                                                         
066000         CONTINUE                                                 
066100     END-IF                                                       
066200                                                                  
066300     INITIALIZE TTUP-NEW-DETAILS                                  
066400******************************************************************
066500*    Transaction Type                                             
066600******************************************************************
066700     IF  TRTYPCDI OF CTRTUPAI = '*'                               
066800     OR  TRTYPCDI OF CTRTUPAI = SPACES                            
066900         MOVE LOW-VALUES           TO TTUP-NEW-TTYP-TYPE          
067000     ELSE                                                         
067100         MOVE FUNCTION TRIM(TRTYPCDI OF CTRTUPAI)                 
067200                                   TO TTUP-NEW-TTYP-TYPE          
067300     END-IF                                                       
067400                                                                  
067500******************************************************************
067600*    Transaction Desc                                             
067700******************************************************************
067800     IF  TRTYDSCI OF CTRTUPAI = '*'                               
067900     OR  TRTYDSCI OF CTRTUPAI = SPACES                            
068000         MOVE LOW-VALUES           TO TTUP-NEW-TTYP-TYPE-DESC     
068100     ELSE                                                         
068200         MOVE FUNCTION TRIM(TRTYDSCI OF CTRTUPAI)                 
068300                                   TO TTUP-NEW-TTYP-TYPE-DESC     
068400     END-IF                                                       
068500     .                                                            
068600 1150-STORE-MAP-IN-NEW-EXIT.                                      
068700     EXIT                                                         
068800     .                                                            
068900 1200-EDIT-MAP-INPUTS.                                            
069000     SET INPUT-OK                  TO TRUE                        
069100******************************************************************
069200*    VALIDATE THE SEARCH KEYS                                     
069300******************************************************************
069400*    The key  was not in database. User sent the same key. So     
069500*    dont edit again. Set tran filter to valid and skip           
069600*    rest of edits                                                
069700*                                                                 
069800     IF  TTUP-DETAILS-NOT-FOUND                                   
069900     AND FUNCTION TRIM(TRTYPCDI OF CTRTUPAI)                      
070000           = TTUP-NEW-TTYP-TYPE                                   
070100         IF CCARD-AID-PFK05                                       
070200            CONTINUE                                              
070300         ELSE                                                     
070400            SET TTUP-DETAILS-NOT-FETCHED    TO TRUE               
070500         END-IF                                                   
070600         SET FLG-TRANFILTER-ISVALID         TO TRUE               
070700         GO TO 1200-EDIT-MAP-INPUTS-EXIT                          
070800     ELSE                                                         
070900         CONTINUE                                                 
071000     END-IF                                                       
071100                                                                  
071200     IF  TTUP-CREATE-NEW-RECORD                                   
071300     OR  TTUP-CHANGES-OK-NOT-CONFIRMED                            
071400         CONTINUE                                                 
071500     ELSE                                                         
071600         PERFORM 1210-EDIT-TRANTYPE                               
071700            THRU 1210-EDIT-TRANTYPE-EXIT                          
071800                                                                  
071900*        IF THE SEARCH CONDITIONS HAVE PROBLEMS FLAG THEM         
072000         IF  FLG-TRANFILTER-BLANK                                 
072100             IF WS-RETURN-MSG-OFF                                 
072200                SET NO-SEARCH-CRITERIA-RECEIVED TO TRUE           
072300             END-IF                                               
072400             SET TTUP-DETAILS-NOT-FETCHED       TO TRUE           
072500             GO TO 1200-EDIT-MAP-INPUTS-EXIT                      
072600         END-IF                                                   
072700                                                                  
072800         IF  FLG-TRANFILTER-NOT-OK                                
072900             SET TTUP-INVALID-SEARCH-KEYS       TO TRUE           
073000             SET TTUP-DETAILS-NOT-FETCHED       TO TRUE           
073100             GO TO 1200-EDIT-MAP-INPUTS-EXIT                      
073200         END-IF                                                   
073300                                                                  
073400         IF TTUP-DETAILS-NOT-FETCHED                              
073500            GO TO 1200-EDIT-MAP-INPUTS-EXIT                       
073600         END-IF                                                   
073700     END-IF                                                       
073800******************************************************************
073900*    SEARCH KEYS ALREADY VALIDATED. CHECK OTHER INPUTS            
074000******************************************************************
074100     SET FLG-TRANFILTER-ISVALID    TO TRUE                        
074200*                                                                 
074300     PERFORM 1205-COMPARE-OLD-NEW                                 
074400        THRU 1205-COMPARE-OLD-NEW-EXIT                            
074500                                                                  
074600     IF  NO-CHANGES-FOUND                                         
074700     OR  TTUP-CHANGES-OK-NOT-CONFIRMED                            
074800     OR  TTUP-CHANGES-OKAYED-AND-DONE                             
074900         MOVE LOW-VALUES           TO WS-NON-KEY-FLAGS            
075000         GO TO 1200-EDIT-MAP-INPUTS-EXIT                          
075100     END-IF                                                       
075200                                                                  
075300     SET TTUP-CHANGES-NOT-OK       TO TRUE                        
075400                                                                  
075500******************************************************************
075600*    Edit Description                                             
075700******************************************************************
075800     MOVE 'Transaction Desc'       TO WS-EDIT-VARIABLE-NAME       
075900     MOVE TTUP-NEW-TTYP-TYPE-DESC  TO WS-EDIT-ALPHANUM-ONLY       
076000     MOVE 50                       TO WS-EDIT-ALPHANUM-LENGTH     
076100     PERFORM 1230-EDIT-ALPHANUM-REQD                              
076200        THRU 1230-EDIT-ALPHANUM-REQD-EXIT                         
076300     MOVE WS-EDIT-ALPHANUM-ONLY-FLAGS                             
076400                                   TO WS-EDIT-DESC-FLAGS          
076500                                                                  
076600*    Cross field edits begin here                                 
076700*                                                                 
076800*       No cross edits in this program so far                     
076900                                                                  
077000*    Set green light for confirmation if no errors found          
077100                                                                  
077200     IF INPUT-ERROR                                               
077300        CONTINUE                                                  
077400     ELSE                                                         
077500        SET TTUP-CHANGES-OK-NOT-CONFIRMED TO TRUE                 
077600     END-IF                                                       
077700     .                                                            
077800                                                                  
077900 1200-EDIT-MAP-INPUTS-EXIT.                                       
078000     EXIT                                                         
078100     .                                                            
078200                                                                  
078300 1205-COMPARE-OLD-NEW.                                            
078400     SET NO-CHANGES-FOUND           TO TRUE                       
078500                                                                  
078600     IF  FUNCTION UPPER-CASE (                                    
078700         TTUP-NEW-TTYP-TYPE)    =                                 
078800         FUNCTION UPPER-CASE (                                    
078900         TTUP-OLD-TTYP-TYPE)                                      
079000     AND FUNCTION UPPER-CASE (                                    
079100         FUNCTION TRIM (TTUP-NEW-TTYP-TYPE-DESC))=                
079200         FUNCTION UPPER-CASE (                                    
079300         FUNCTION TRIM (TTUP-OLD-TTYP-TYPE-DESC))                 
079400     AND FUNCTION LENGTH (                                        
079500         FUNCTION TRIM (TTUP-NEW-TTYP-TYPE-DESC))=                
079600         FUNCTION LENGTH (                                        
079700         FUNCTION TRIM (TTUP-OLD-TTYP-TYPE-DESC))                 
079800                                                                  
079900         IF WS-RETURN-MSG-OFF                                     
080000            SET NO-CHANGES-DETECTED   TO TRUE                     
080100         ELSE                                                     
080200            CONTINUE                                              
080300         END-IF                                                   
080400     ELSE                                                         
080500         IF WS-RETURN-MSG-OFF                                     
080600            SET CHANGE-HAS-OCCURRED   TO TRUE                     
080700         ELSE                                                     
080800             CONTINUE                                             
080900         END-IF                                                   
081000         GO TO 1205-COMPARE-OLD-NEW-EXIT                          
081100     END-IF                                                       
081200     .                                                            
081300                                                                  
081400 1205-COMPARE-OLD-NEW-EXIT.                                       
081500     EXIT                                                         
081600     .                                                            
081700                                                                  
081800                                                                  
081900*                                                                 
082000 1210-EDIT-TRANTYPE.                                              
082100     SET FLG-TRANFILTER-NOT-OK    TO TRUE                         
082200                                                                  
082300******************************************************************
082400*    Edit Tran Type code                                          
082500******************************************************************
082600     MOVE 'Tran Type code'         TO WS-EDIT-VARIABLE-NAME       
082700     MOVE TTUP-NEW-TTYP-TYPE       TO WS-EDIT-ALPHANUM-ONLY       
082800     MOVE 2                        TO WS-EDIT-ALPHANUM-LENGTH     
082900     PERFORM 1245-EDIT-NUM-REQD                                   
083000        THRU 1245-EDIT-NUM-REQD-EXIT                              
083100     MOVE WS-EDIT-ALPHANUM-ONLY-FLAGS                             
083200                                   TO WS-EDIT-TTYP-FLAG           
083300                                                                  
083400     IF FLG-TRANFILTER-ISVALID                                    
083500        COMPUTE WS-EDIT-NUMERIC-2                                 
083600             = FUNCTION NUMVAL(TTUP-NEW-TTYP-TYPE)                
083700        END-COMPUTE                                               
083800        MOVE WS-EDIT-NUMERIC-2      TO WS-EDIT-ALPHANUMERIC-2     
083900        INSPECT WS-EDIT-ALPHANUMERIC-2                            
084000                REPLACING ALL SPACES BY ZEROS                     
084100        MOVE WS-EDIT-ALPHANUMERIC-2 TO TTUP-NEW-TTYP-TYPE         
084200     END-IF                                                       
084300     .                                                            
084400                                                                  
084500 1210-EDIT-TRANTYPE-EXIT.                                         
084600     EXIT                                                         
084700     .                                                            
084800                                                                  
084900 1230-EDIT-ALPHANUM-REQD.                                         
085000*    Initialize                                                   
085100     SET FLG-ALPHNANUM-NOT-OK          TO TRUE                    
085200                                                                  
085300*    Not supplied                                                 
085400     IF WS-EDIT-ALPHANUM-ONLY(1:WS-EDIT-ALPHANUM-LENGTH)          
085500                                       EQUAL LOW-VALUES           
085600     OR WS-EDIT-ALPHANUM-ONLY(1:WS-EDIT-ALPHANUM-LENGTH)          
085700         EQUAL SPACES                                             
085800     OR FUNCTION LENGTH(FUNCTION TRIM(                            
085900        WS-EDIT-ALPHANUM-ONLY(1:WS-EDIT-ALPHANUM-LENGTH))) = 0    
086000                                                                  
086100        SET INPUT-ERROR                TO TRUE                    
086200        SET FLG-ALPHNANUM-BLANK        TO TRUE                    
086300        IF WS-RETURN-MSG-OFF                                      
086400           STRING                                                 
086500             FUNCTION TRIM(WS-EDIT-VARIABLE-NAME)                 
086600             ' must be supplied.'                                 
086700             DELIMITED BY SIZE                                    
086800             INTO WS-RETURN-MSG                                   
086900           END-STRING                                             
087000        END-IF                                                    
087100                                                                  
087200        GO TO  1230-EDIT-ALPHANUM-REQD-EXIT                       
087300     END-IF                                                       
087400                                                                  
087500*    Only Alphabets,numbers and space allowed                     
087600     MOVE LIT-ALL-ALPHANUM-FROM-X TO LIT-ALL-ALPHANUM-FROM        
087700                                                                  
087800     INSPECT WS-EDIT-ALPHANUM-ONLY(1:WS-EDIT-ALPHANUM-LENGTH)     
087900       CONVERTING LIT-ALL-ALPHANUM-FROM                           
088000               TO LIT-ALPHANUM-SPACES-TO                          
088100                                                                  
088200     IF FUNCTION LENGTH(                                          
088300             FUNCTION TRIM(                                       
088400             WS-EDIT-ALPHANUM-ONLY(1:WS-EDIT-ALPHANUM-LENGTH)     
088500                            )) = 0                                
088600        CONTINUE                                                  
088700     ELSE                                                         
088800        SET INPUT-ERROR           TO TRUE                         
088900        SET FLG-ALPHNANUM-NOT-OK  TO TRUE                         
089000        IF WS-RETURN-MSG-OFF                                      
089100           STRING                                                 
089200             FUNCTION TRIM(WS-EDIT-VARIABLE-NAME)                 
089300             ' can have numbers or alphabets only.'               
089400             DELIMITED BY SIZE                                    
089500             INTO WS-RETURN-MSG                                   
089600           END-STRING                                             
089700        END-IF                                                    
089800        GO TO  1230-EDIT-ALPHANUM-REQD-EXIT                       
089900     END-IF                                                       
090000                                                                  
090100     SET FLG-ALPHNANUM-ISVALID    TO TRUE                         
090200     .                                                            
090300 1230-EDIT-ALPHANUM-REQD-EXIT.                                    
090400     EXIT                                                         
090500     .                                                            
090600                                                                  
090700 1245-EDIT-NUM-REQD.                                              
090800*    Initialize                                                   
090900     SET FLG-ALPHNANUM-NOT-OK          TO TRUE                    
091000                                                                  
091100*    Not supplied                                                 
091200     IF WS-EDIT-ALPHANUM-ONLY(1:WS-EDIT-ALPHANUM-LENGTH)          
091300                                       EQUAL LOW-VALUES           
091400     OR WS-EDIT-ALPHANUM-ONLY(1:WS-EDIT-ALPHANUM-LENGTH)          
091500         EQUAL SPACES                                             
091600     OR FUNCTION LENGTH(FUNCTION TRIM(                            
091700        WS-EDIT-ALPHANUM-ONLY(1:WS-EDIT-ALPHANUM-LENGTH))) = 0    
091800                                                                  
091900        SET INPUT-ERROR                TO TRUE                    
092000        SET FLG-ALPHNANUM-BLANK        TO TRUE                    
092100        IF WS-RETURN-MSG-OFF                                      
092200           STRING                                                 
092300             FUNCTION TRIM(WS-EDIT-VARIABLE-NAME)                 
092400             ' must be supplied.'                                 
092500             DELIMITED BY SIZE                                    
092600             INTO WS-RETURN-MSG                                   
092700           END-STRING                                             
092800        END-IF                                                    
092900        GO TO  1245-EDIT-NUM-REQD-EXIT                            
093000     END-IF                                                       
093100                                                                  
093200*    Only all numeric allowed                                     
093300                                                                  
093400     IF FUNCTION TEST-NUMVAL(WS-EDIT-ALPHANUM-ONLY(1:             
093500                             WS-EDIT-ALPHANUM-LENGTH)) = 0        
093600        CONTINUE                                                  
093700     ELSE                                                         
093800        SET INPUT-ERROR           TO TRUE                         
093900        SET FLG-ALPHNANUM-NOT-OK  TO TRUE                         
094000        IF WS-RETURN-MSG-OFF                                      
094100           STRING                                                 
094200             FUNCTION TRIM(WS-EDIT-VARIABLE-NAME)                 
094300             ' must be numeric.'                                  
094400             DELIMITED BY SIZE                                    
094500             INTO WS-RETURN-MSG                                   
094600           END-STRING                                             
094700        END-IF                                                    
094800        GO TO  1245-EDIT-NUM-REQD-EXIT                            
094900     END-IF                                                       
095000*                                                                 
095100                                                                  
095200*    Must not be zero                                             
095300                                                                  
095400     IF FUNCTION NUMVAL(WS-EDIT-ALPHANUM-ONLY(1:                  
095500                        WS-EDIT-ALPHANUM-LENGTH)) = 0             
095600        SET INPUT-ERROR           TO TRUE                         
095700        SET FLG-ALPHNANUM-NOT-OK  TO TRUE                         
095800        IF WS-RETURN-MSG-OFF                                      
095900           STRING                                                 
096000             FUNCTION TRIM(WS-EDIT-VARIABLE-NAME)                 
096100             ' must not be zero.'                                 
096200             DELIMITED BY SIZE                                    
096300             INTO WS-RETURN-MSG                                   
096400           END-STRING                                             
096500        END-IF                                                    
096600        GO TO  1245-EDIT-NUM-REQD-EXIT                            
096700     ELSE                                                         
096800        CONTINUE                                                  
096900     END-IF                                                       
097000                                                                  
097100                                                                  
097200     SET FLG-ALPHNANUM-ISVALID    TO TRUE                         
097300     .                                                            
097400 1245-EDIT-NUM-REQD-EXIT.                                         
097500     EXIT                                                         
097600     .                                                            
097700                                                                  
097800 2000-DECIDE-ACTION.                                              
097900     EVALUATE TRUE                                                
098000******************************************************************
098100*       NO DETAILS SHOWN.                                         
098200*       SO GET THEM AND SETUP DETAIL EDIT SCREEN                  
098300******************************************************************
098400        WHEN TTUP-DETAILS-NOT-FETCHED                             
098500******************************************************************
098600*       CHANGES MADE. BUT USER CANCELS                            
098700******************************************************************
098800        WHEN CCARD-AID-PFK12                                      
098900           IF  FLG-TRANFILTER-ISVALID                             
099000               SET WS-RETURN-MSG-OFF               TO TRUE        
099100               PERFORM 9000-READ-TRANTYPE                         
099200                  THRU 9000-READ-TRANTYPE-EXIT                    
099300               IF FOUND-TRANTYPE-IN-TABLE                         
099400                  SET TTUP-SHOW-DETAILS            TO TRUE        
099500               ELSE                                               
099600                  SET TTUP-DETAILS-NOT-FOUND       TO TRUE        
099700               END-IF                                             
099800           ELSE                                                   
099900               EVALUATE TRUE                                      
100000                  WHEN TTUP-CONFIRM-DELETE                        
100100                   SET WS-DELETE-WAS-CANCELLED     TO TRUE        
100200                   SET TTUP-DETAILS-NOT-FETCHED    TO TRUE        
100300                  WHEN TTUP-CHANGES-OK-NOT-CONFIRMED              
100400                   SET WS-UPDATE-WAS-CANCELLED     TO TRUE        
100500                   SET TTUP-CHANGES-BACKED-OUT     TO TRUE        
100600                  WHEN OTHER                                      
100700                   SET TTUP-DETAILS-NOT-FETCHED    TO TRUE        
100800               END-EVALUATE                                       
100900                                                                  
101000           END-IF                                                 
101100******************************************************************
101200*       DETAILS SHOWN                                             
101300*       BUT USER PRESSES F4 FOR DELETE                            
101400*       ASK THE USER TO CONFIRM THE DELETE                        
101500******************************************************************
101600        WHEN TTUP-CONFIRM-DELETE                                  
101700         AND CCARD-AID-PFK12                                      
101800           SET TTUP-CONFIRM-DELETE                 TO TRUE        
101900******************************************************************
102000*       DETAILS SHOWN                                             
102100*       CHECK CHANGES AND ASK CONFIRMATION IF GOOD                
102200******************************************************************
102300        WHEN TTUP-SHOW-DETAILS                                    
102400           IF INPUT-ERROR                                         
102500           OR NO-CHANGES-DETECTED                                 
102600           OR WS-INVALID-KEY                                      
102700              CONTINUE                                            
102800           ELSE                                                   
102900              SET TTUP-CHANGES-OK-NOT-CONFIRMED TO TRUE           
103000           END-IF                                                 
103100******************************************************************
103200*       DETAILS SHOWN                                             
103300*       BUT INPUT EDIT ERRORS FOUND                               
103400******************************************************************
103500        WHEN TTUP-CHANGES-NOT-OK                                  
103600            CONTINUE                                              
103700******************************************************************
103800*       CHANGES BACKED OUT                                        
103900*       GO BACK TO CHANGES NOT OK STATE                           
104000******************************************************************
104100        WHEN TTUP-CHANGES-BACKED-OUT                              
104200            SET TTUP-CHANGES-NOT-OK            TO TRUE            
104300******************************************************************
104400*       PROBLEMS FOUND IN SEARCH KEYS                             
104500******************************************************************
104600        WHEN TTUP-INVALID-SEARCH-KEYS                             
104700            CONTINUE                                              
104800******************************************************************
104900*       SEARCH KEY WAS VALID.                                     
105000*       BUT DATA WAS NOT FOUND IN TABLE                           
105100*       CUSTOMER DECIDES TO CONTINUE AND ADD RECORD               
105200******************************************************************
105300        WHEN CCARD-AID-PFK05                                      
105400         AND TTUP-DETAILS-NOT-FOUND                               
105500            SET TTUP-CREATE-NEW-RECORD TO TRUE                    
105600******************************************************************
105700*       DETAILS EDITED , FOUND OK, CONFIRM SAVE REQUESTED         
105800*       CONFIRMATION NOT GIVEN. SO SHOW DETAILS AGAIN             
105900******************************************************************
106000        WHEN TTUP-CHANGES-OK-NOT-CONFIRMED                        
106100            CONTINUE                                              
106200******************************************************************
106300*       SHOW CONFIRMATION. GO BACK TO SQUARE 1                    
106400******************************************************************
106500        WHEN TTUP-CHANGES-OKAYED-AND-DONE                         
106600            SET TTUP-SHOW-DETAILS TO TRUE                         
106700            IF CDEMO-FROM-TRANID    EQUAL LOW-VALUES              
106800            OR CDEMO-FROM-TRANID    EQUAL SPACES                  
106900               MOVE ZEROES       TO CDEMO-ACCT-ID                 
107000                                    CDEMO-CARD-NUM                
107100               MOVE LOW-VALUES   TO CDEMO-ACCT-STATUS             
107200            END-IF                                                
107300        WHEN OTHER                                                
107400             MOVE LIT-THISPGM    TO ABEND-CULPRIT                 
107500             MOVE '0001'         TO ABEND-CODE                    
107600             MOVE SPACES         TO ABEND-REASON                  
107700             MOVE 'UNEXPECTED DATA SCENARIO'                      
107800                                 TO ABEND-MSG                     
107900             PERFORM ABEND-ROUTINE                                
108000                THRU ABEND-ROUTINE-EXIT                           
108100     END-EVALUATE                                                 
108200     .                                                            
108300 2000-DECIDE-ACTION-EXIT.                                         
108400     EXIT                                                         
108500     .                                                            
108600                                                                  
108700                                                                  
108800                                                                  
108900 3000-SEND-MAP.                                                   
109000     PERFORM 3100-SCREEN-INIT                                     
109100        THRU 3100-SCREEN-INIT-EXIT                                
109200     PERFORM 3200-SETUP-SCREEN-VARS                               
109300        THRU 3200-SETUP-SCREEN-VARS-EXIT                          
109400     PERFORM 3250-SETUP-INFOMSG                                   
109500        THRU 3250-SETUP-INFOMSG-EXIT                              
109600     PERFORM 3300-SETUP-SCREEN-ATTRS                              
109700        THRU 3300-SETUP-SCREEN-ATTRS-EXIT                         
109800     PERFORM 3390-SETUP-INFOMSG-ATTRS                             
109900        THRU 3390-SETUP-INFOMSG-ATTRS-EXIT                        
110000     PERFORM 3391-SETUP-PFKEY-ATTRS                               
110100        THRU 3391-SETUP-PFKEY-ATTRS-EXIT                          
110200     PERFORM 3400-SEND-SCREEN                                     
110300        THRU 3400-SEND-SCREEN-EXIT                                
110400     .                                                            
110500                                                                  
110600 3000-SEND-MAP-EXIT.                                              
110700     EXIT                                                         
110800     .                                                            
110900                                                                  
111000 3100-SCREEN-INIT.                                                
111100     MOVE LOW-VALUES                TO CTRTUPAO                   
111200                                                                  
111300     MOVE FUNCTION CURRENT-DATE     TO WS-CURDATE-DATA            
111400                                                                  
111500     MOVE CCDA-TITLE01              TO TITLE01O OF CTRTUPAO       
111600     MOVE CCDA-TITLE02              TO TITLE02O OF CTRTUPAO       
111700     MOVE LIT-THISTRANID            TO TRNNAMEO OF CTRTUPAO       
111800     MOVE LIT-THISPGM               TO PGMNAMEO OF CTRTUPAO       
111900                                                                  
112000     MOVE FUNCTION CURRENT-DATE     TO WS-CURDATE-DATA            
112100                                                                  
112200     MOVE WS-CURDATE-MONTH          TO WS-CURDATE-MM              
112300     MOVE WS-CURDATE-DAY            TO WS-CURDATE-DD              
112400     MOVE WS-CURDATE-YEAR(3:2)      TO WS-CURDATE-YY              
112500                                                                  
112600     MOVE WS-CURDATE-MM-DD-YY       TO CURDATEO OF CTRTUPAO       
112700                                                                  
112800     MOVE WS-CURTIME-HOURS          TO WS-CURTIME-HH              
112900     MOVE WS-CURTIME-MINUTE         TO WS-CURTIME-MM              
113000     MOVE WS-CURTIME-SECOND         TO WS-CURTIME-SS              
113100                                                                  
113200     MOVE WS-CURTIME-HH-MM-SS       TO CURTIMEO OF CTRTUPAO       
113300                                                                  
113400     .                                                            
113500                                                                  
113600 3100-SCREEN-INIT-EXIT.                                           
113700     EXIT                                                         
113800     .                                                            
113900                                                                  
114000 3200-SETUP-SCREEN-VARS.                                          
114100*    INITIALIZE SEARCH CRITERIA                                   
114200     IF CDEMO-PGM-ENTER                                           
114300        CONTINUE                                                  
114400     ELSE                                                         
114500        EVALUATE TRUE                                             
114600         WHEN TTUP-DETAILS-NOT-FETCHED                            
114700            PERFORM 3201-SHOW-INITIAL-VALUES                      
114800               THRU 3201-SHOW-INITIAL-VALUES-EXIT                 
114900         WHEN TTUP-SHOW-DETAILS                                   
115000         WHEN TTUP-CONFIRM-DELETE                                 
115100         WHEN TTUP-DELETE-FAILED                                  
115200         WHEN TTUP-DELETE-DONE                                    
115300         WHEN TTUP-CHANGES-BACKED-OUT                             
115400            INITIALIZE TTUP-NEW-DETAILS                           
115500            PERFORM 3202-SHOW-ORIGINAL-VALUES                     
115600               THRU 3202-SHOW-ORIGINAL-VALUES-EXIT                
115700         WHEN TTUP-CHANGES-MADE                                   
115800         WHEN TTUP-CHANGES-NOT-OK                                 
115900         WHEN TTUP-DETAILS-NOT-FOUND                              
116000         WHEN TTUP-INVALID-SEARCH-KEYS                            
116100         WHEN TTUP-CREATE-NEW-RECORD                              
116200         WHEN TTUP-CHANGES-OKAYED-AND-DONE                        
116300            PERFORM 3203-SHOW-UPDATED-VALUES                      
116400               THRU 3203-SHOW-UPDATED-VALUES-EXIT                 
116500         WHEN OTHER                                               
116600            INITIALIZE TTUP-NEW-DETAILS                           
116700            PERFORM 3202-SHOW-ORIGINAL-VALUES                     
116800               THRU 3202-SHOW-ORIGINAL-VALUES-EXIT                
116900        END-EVALUATE                                              
117000      END-IF                                                      
117100     .                                                            
117200 3200-SETUP-SCREEN-VARS-EXIT.                                     
117300     EXIT                                                         
117400     .                                                            
117500                                                                  
117600 3201-SHOW-INITIAL-VALUES.                                        
117700     MOVE LOW-VALUES                     TO  TRTYPCDO OF CTRTUPAO 
117800                                             TRTYPCDO OF CTRTUPAO 
117900     .                                                            
118000                                                                  
118100 3201-SHOW-INITIAL-VALUES-EXIT.                                   
118200     EXIT                                                         
118300     .                                                            
118400                                                                  
118500 3202-SHOW-ORIGINAL-VALUES.                                       
118600                                                                  
118700     MOVE LOW-VALUES                     TO WS-NON-KEY-FLAGS      
118800                                                                  
118900     MOVE TTUP-OLD-TTYP-TYPE             TO TRTYPCDO OF CTRTUPAO  
119000     MOVE TTUP-OLD-TTYP-TYPE-DESC        TO TRTYDSCO OF CTRTUPAO  
119100                                                                  
119200     .                                                            
119300                                                                  
119400 3202-SHOW-ORIGINAL-VALUES-EXIT.                                  
119500     EXIT                                                         
119600     .                                                            
119700 3203-SHOW-UPDATED-VALUES.                                        
119800                                                                  
119900     MOVE TTUP-NEW-TTYP-TYPE             TO TRTYPCDO OF CTRTUPAO  
120000     MOVE TTUP-NEW-TTYP-TYPE-DESC        TO TRTYDSCO OF CTRTUPAO  
120100     .                                                            
120200                                                                  
120300 3203-SHOW-UPDATED-VALUES-EXIT.                                   
120400     EXIT                                                         
120500     .                                                            
120600                                                                  
120700                                                                  
120800                                                                  
120900                                                                  
121000 3250-SETUP-INFOMSG.                                              
121100*    SETUP INFORMATION MESSAGE                                    
121200                                                                  
121300         EVALUATE TRUE                                            
121400         WHEN CDEMO-PGM-ENTER                                     
121500              SET  PROMPT-FOR-SEARCH-KEYS    TO TRUE              
121600         WHEN TTUP-DETAILS-NOT-FETCHED                            
121700         WHEN TTUP-INVALID-SEARCH-KEYS                            
121800              SET PROMPT-FOR-SEARCH-KEYS     TO TRUE              
121900         WHEN TTUP-DETAILS-NOT-FOUND                              
122000              SET PROMPT-CREATE-NEW-RECORD   TO TRUE              
122100         WHEN TTUP-SHOW-DETAILS                                   
122200         WHEN TTUP-CHANGES-BACKED-OUT                             
122300         AND (TTUP-OLD-TTYP-TYPE    = LOW-VALUES                  
122400         OR   TTUP-OLD-TTYP-TYPE    = SPACES)                     
122500              SET  PROMPT-FOR-SEARCH-KEYS    TO TRUE              
122600         WHEN TTUP-CHANGES-BACKED-OUT                             
122700         WHEN TTUP-CHANGES-NOT-OK                                 
122800              SET PROMPT-FOR-CHANGES         TO TRUE              
122900         WHEN TTUP-CONFIRM-DELETE                                 
123000              SET PROMPT-DELETE-CONFIRM      TO TRUE              
123100         WHEN TTUP-DELETE-FAILED                                  
123200              SET INFORM-FAILURE             TO TRUE              
123300         WHEN TTUP-DELETE-DONE                                    
123400              SET CONFIRM-DELETE-SUCCESS     TO TRUE              
123500         WHEN TTUP-CREATE-NEW-RECORD                              
123600              SET PROMPT-FOR-NEWDATA         TO TRUE              
123700         WHEN TTUP-CHANGES-OK-NOT-CONFIRMED                       
123800              SET PROMPT-FOR-CONFIRMATION    TO TRUE              
123900         WHEN TTUP-CHANGES-OKAYED-AND-DONE                        
124000              SET CONFIRM-UPDATE-SUCCESS     TO TRUE              
124100         WHEN TTUP-CHANGES-OKAYED-LOCK-ERROR                      
124200              SET INFORM-FAILURE             TO TRUE              
124300         WHEN TTUP-CHANGES-OKAYED-BUT-FAILED                      
124400              SET INFORM-FAILURE             TO TRUE              
124500         WHEN WS-NO-INFO-MESSAGE                                  
124600             SET PROMPT-FOR-SEARCH-KEYS      TO TRUE              
124700     END-EVALUATE                                                 
124800                                                                  
124900* Center justify the text                                         
125000*                                                                 
125100     COMPUTE WS-STRING-LEN =                                      
125200             FUNCTION LENGTH(                                     
125300                      FUNCTION TRIM(WS-INFO-MSG)                  
125400                            )                                     
125500     COMPUTE WS-STRING-MID =                                      
125600            (FUNCTION LENGTH(WS-INFO-MSG)                         
125700                          - WS-STRING-LEN) / 2 + 1                
125800     MOVE WS-INFO-MSG(1:WS-STRING-LEN)                            
125900       TO WS-STRING-OUT(WS-STRING-MID:                            
126000                        WS-STRING-LEN)                            
126100                                                                  
126200     MOVE WS-STRING-OUT                  TO INFOMSGO OF CTRTUPAO  
126300                                                                  
126400     MOVE WS-RETURN-MSG                  TO ERRMSGO  OF CTRTUPAO  
126500     .                                                            
126600 3250-SETUP-INFOMSG-EXIT.                                         
126700     EXIT                                                         
126800     .                                                            
126900 3300-SETUP-SCREEN-ATTRS.                                         
127000                                                                  
127100*    PROTECT ALL FIELDS                                           
127200     PERFORM 3310-PROTECT-ALL-ATTRS                               
127300        THRU 3310-PROTECT-ALL-ATTRS-EXIT                          
127400                                                                  
127500*    UNPROTECT BASED ON CONTEXT                                   
127600     EVALUATE TRUE                                                
127700        WHEN TTUP-DETAILS-NOT-FETCHED                             
127800        WHEN TTUP-INVALID-SEARCH-KEYS                             
127900        WHEN TTUP-DETAILS-NOT-FOUND                               
128000        WHEN TTUP-CHANGES-BACKED-OUT                              
128100         AND (TTUP-OLD-TTYP-TYPE    = LOW-VALUES                  
128200         OR   TTUP-OLD-TTYP-TYPE    = SPACES)                     
128300*            Make Search Keys editable                            
128400             MOVE DFHBMFSE      TO TRTYPCDA OF CTRTUPAI           
128500        WHEN TTUP-SHOW-DETAILS                                    
128600        WHEN TTUP-CHANGES-NOT-OK                                  
128700        WHEN TTUP-CREATE-NEW-RECORD                               
128800        WHEN TTUP-CHANGES-BACKED-OUT                              
128900             PERFORM 3320-UNPROTECT-FEW-ATTRS                     
129000                THRU 3320-UNPROTECT-FEW-ATTRS-EXIT                
129100        WHEN TTUP-CHANGES-OK-NOT-CONFIRMED                        
129200        WHEN TTUP-CHANGES-OKAYED-AND-DONE                         
129300        WHEN TTUP-DELETE-IN-PROGRESS                              
129400*            Keep all fields protected                            
129500             CONTINUE                                             
129600        WHEN OTHER                                                
129700             MOVE DFHBMFSE      TO TRTYPCDA OF CTRTUPAI           
129800     END-EVALUATE                                                 
129900                                                                  
130000******************************************************************
130100*    POSITION CURSOR - ORDER BASED ON SCREEN LOCATION             
130200******************************************************************
130300     EVALUATE TRUE                                                
130400        WHEN TTUP-DETAILS-NOT-FETCHED                             
130500        WHEN TTUP-DETAILS-NOT-FOUND                               
130600        WHEN TTUP-INVALID-SEARCH-KEYS                             
130700        WHEN FLG-TRANFILTER-NOT-OK                                
130800        WHEN FLG-TRANFILTER-BLANK                                 
130900        WHEN TTUP-CHANGES-OKAYED-AND-DONE                         
131000        WHEN TTUP-CHANGES-BACKED-OUT                              
131100         AND (TTUP-OLD-TTYP-TYPE    = LOW-VALUES                  
131200         OR   TTUP-OLD-TTYP-TYPE    = SPACES)                     
131300             MOVE -1             TO TRTYPCDL OF CTRTUPAI          
131400*    Description                                                  
131500        WHEN TTUP-CREATE-NEW-RECORD                               
131600        WHEN NO-CHANGES-DETECTED                                  
131700        WHEN FLG-DESCRIPTION-NOT-OK                               
131800        WHEN FLG-DESCRIPTION-BLANK                                
131900        WHEN TTUP-CHANGES-MADE                                    
132000        WHEN TTUP-CHANGES-BACKED-OUT                              
132100        WHEN TTUP-SHOW-DETAILS                                    
132200            MOVE -1              TO TRTYDSCL OF CTRTUPAI          
132300        WHEN OTHER                                                
132400            MOVE -1              TO TRTYPCDL OF CTRTUPAI          
132500      END-EVALUATE                                                
132600                                                                  
132700******************************************************************
132800*    SETUP COLOR                                                  
132900******************************************************************
133000*    Transaction Type code filer                                  
133100     IF FLG-TRANFILTER-NOT-OK                                     
133200     OR TTUP-DELETE-FAILED                                        
133300        MOVE DFHRED              TO TRTYPCDC OF CTRTUPAO          
133400     END-IF                                                       
133500                                                                  
133600     IF  FLG-TRANFILTER-BLANK                                     
133700     AND CDEMO-PGM-REENTER                                        
133800         MOVE '*'                TO TRTYPCDO OF CTRTUPAO          
133900         MOVE DFHRED             TO TRTYPCDC OF CTRTUPAO          
134000     END-IF                                                       
134100                                                                  
134200     IF TTUP-DETAILS-NOT-FETCHED                                  
134300     OR TTUP-DETAILS-NOT-FOUND                                    
134400     OR TTUP-INVALID-SEARCH-KEYS                                  
134500     OR FLG-TRANFILTER-BLANK                                      
134600     OR FLG-TRANFILTER-NOT-OK                                     
134700        GO TO 3300-SETUP-SCREEN-ATTRS-EXIT                        
134800     ELSE                                                         
134900        CONTINUE                                                  
135000     END-IF                                                       
135100                                                                  
135200******************************************************************
135300*    Using Copy replacing to set attribs for remaining vars       
135400*    Write specific code only if rules differ                     
135500******************************************************************
135600                                                                  
135700*    Transaction Description Status                               
135800     COPY CSSETATY REPLACING                                      
135900       ==(TESTVAR1)== BY ==DESCRIPTION==                          
136000       ==(SCRNVAR2)== BY ==TRTYDSC==                              
136100       ==(MAPNAME3)== BY ==CTRTUPA== .                            
136200                                                                  
136300     .                                                            
136400 3300-SETUP-SCREEN-ATTRS-EXIT.                                    
136500     EXIT                                                         
136600     .                                                            
136700                                                                  
136800 3310-PROTECT-ALL-ATTRS.                                          
136900     MOVE DFHBMPRF              TO TRTYPCDA OF CTRTUPAI           
137000                                   TRTYDSCA OF CTRTUPAI           
137100                                   INFOMSGA OF CTRTUPAI           
137200     .                                                            
137300 3310-PROTECT-ALL-ATTRS-EXIT.                                     
137400     EXIT                                                         
137500     .                                                            
137600                                                                  
137700 3320-UNPROTECT-FEW-ATTRS.                                        
137800                                                                  
137900     MOVE DFHBMFSE              TO TRTYDSCA OF CTRTUPAI           
138000     MOVE DFHBMPRF              TO INFOMSGA OF CTRTUPAI           
138100     .                                                            
138200 3320-UNPROTECT-FEW-ATTRS-EXIT.                                   
138300     EXIT                                                         
138400     .                                                            
138500                                                                  
138600 3390-SETUP-INFOMSG-ATTRS.                                        
138700     IF  WS-NO-INFO-MESSAGE                                       
138800         MOVE DFHBMDAR           TO INFOMSGA OF CTRTUPAI          
138900     ELSE                                                         
139000         MOVE DFHBMASB           TO INFOMSGA OF CTRTUPAI          
139100     END-IF                                                       
139200     .                                                            
139300 3390-SETUP-INFOMSG-ATTRS-EXIT.                                   
139400     EXIT                                                         
139500     .                                                            
139600                                                                  
139700 3391-SETUP-PFKEY-ATTRS.                                          
139800*    Should reflect in 0001-CHECK-PFKEYS                          
139900*    Enter key                                                    
140000     IF TTUP-CONFIRM-DELETE                                       
140100        MOVE DFHBMDAR            TO FKEYSA   OF CTRTUPAI          
140200     ELSE                                                         
140300        MOVE DFHBMASB            TO FKEYSA   OF CTRTUPAI          
140400     END-IF                                                       
140500*    F4                                                           
140600     IF TTUP-SHOW-DETAILS                                         
140700     OR TTUP-CONFIRM-DELETE                                       
140800         MOVE DFHBMASB           TO FKEY04A  OF CTRTUPAI          
140900     END-IF                                                       
141000*    F5                                                           
141100     IF TTUP-CHANGES-OK-NOT-CONFIRMED                             
141200     OR TTUP-DETAILS-NOT-FOUND                                    
141300         MOVE DFHBMASB           TO FKEY05A  OF CTRTUPAI          
141400     END-IF                                                       
141500*    F12                                                          
141600     IF TTUP-CHANGES-OK-NOT-CONFIRMED                             
141700     OR TTUP-SHOW-DETAILS                                         
141800     OR TTUP-DETAILS-NOT-FOUND                                    
141900     OR TTUP-CONFIRM-DELETE                                       
142000     OR TTUP-CREATE-NEW-RECORD                                    
142100         MOVE DFHBMASB           TO FKEY12A  OF CTRTUPAI          
142200     END-IF                                                       
142300     .                                                            
142400 3391-SETUP-PFKEY-ATTRS-EXIT.                                     
142500     EXIT                                                         
142600     .                                                            
142700                                                                  
142800 3400-SEND-SCREEN.                                                
142900                                                                  
143000     MOVE LIT-THISMAPSET         TO CCARD-NEXT-MAPSET             
143100     MOVE LIT-THISMAP            TO CCARD-NEXT-MAP                
143200                                                                  
      *KIX  EXEC CICS SEND MAP(CCARD-NEXT-MAP) MAPSET(CCARD-NEXT-MAPSET)
           CALL "KIXCMD" USING
               BY CONTENT "SEND|MAP=|MAPSET=|FROM=|CURSOR|ERASE|FRE"
                        & "EKB|RESP="
               BY REFERENCE CCARD-NEXT-MAP
               BY REFERENCE CCARD-NEXT-MAPSET
               BY REFERENCE CTRTUPAO
               BY REFERENCE WS-RESP-CD
           END-CALL
           GO TO ABEND-ROUTINE DEPENDING ON RETURN-CODE
           CONTINUE
144100     .                                                            
144200 3400-SEND-SCREEN-EXIT.                                           
144300     EXIT                                                         
144400     .                                                            
144500                                                                  
144600                                                                  
144700 9000-READ-TRANTYPE.                                              
144800                                                                  
144900     INITIALIZE TTUP-OLD-DETAILS                                  
145000                                                                  
145100     SET  WS-NO-INFO-MESSAGE      TO TRUE                         
145200                                                                  
145300     PERFORM 9100-GET-TRANSACTION-TYPE                            
145400        THRU 9100-GET-TRANSACTION-TYPE-EXIT                       
145500                                                                  
145600     IF FLG-TRANFILTER-NOT-OK                                     
145700        GO TO 9000-READ-TRANTYPE-EXIT                             
145800     END-IF                                                       
145900                                                                  
146000                                                                  
146100     PERFORM 9500-STORE-FETCHED-DATA                              
146200        THRU 9500-STORE-FETCHED-DATA-EXIT                         
146300     .                                                            
146400                                                                  
146500                                                                  
146600 9000-READ-TRANTYPE-EXIT.                                         
146700     EXIT                                                         
146800     .                                                            
146900 9100-GET-TRANSACTION-TYPE.                                       
147000                                                                  
147100*    Read the Card file. Access via alternate index ACCTID        
147200*                                                                 
147300     MOVE TTUP-NEW-TTYP-TYPE TO DCL-TR-TYPE                       
147400                                                                  
      *KIX  EXEC SQL SELECT TR_TYPE ,TR_DESCRIPTION INTO :DCL-TR-TYPE ,
           CALL "KIXCMD" USING
               BY CONTENT "SQL|EXEC||ioO|SELECT TR_TYPE ,TR_DESCRIP"
                        & "TION FROM CARDDEMO.TRANSACTION_TYPE WHER"
                        & "E TR_TYPE = ?"
               BY REFERENCE SQLCA
               BY REFERENCE DCL-TR-TYPE
               BY REFERENCE DCL-TR-TYPE
               BY REFERENCE DCL-TR-DESCRIPTION
           END-CALL
148300                                                                  
148400     MOVE SQLCODE                            TO WS-DISP-SQLCODE   
148500                                                                  
148600     EVALUATE TRUE                                                
148700         WHEN SQLCODE = ZERO                                      
148800            SET FOUND-TRANTYPE-IN-TABLE     TO TRUE               
148900         WHEN SQLCODE = +100                                      
149000            SET INPUT-ERROR                 TO TRUE               
149100            SET FLG-TRANFILTER-NOT-OK       TO TRUE               
149200            IF WS-RETURN-MSG-OFF                                  
149300              SET WS-RECORD-NOT-FOUND       TO TRUE               
149400            END-IF                                                
149500         WHEN SQLCODE < 0                                         
149600            SET INPUT-ERROR                 TO TRUE               
149700            SET FLG-TRANFILTER-NOT-OK       TO TRUE               
149800            IF WS-RETURN-MSG-OFF                                  
149900              STRING                                              
150000              'Error accessing:'                                  
150100              ' TRANSACTION_TYPE table. SQLCODE:'                 
150200              WS-DISP-SQLCODE                                     
150300              ':'                                                 
150400              SQLERRM OF SQLCA                                    
150500              DELIMITED BY SIZE                                   
150600              INTO WS-RETURN-MSG                                  
150700              END-STRING                                          
150800            END-IF                                                
150900     END-EVALUATE                                                 
151000     EXIT                                                         
151100     .                                                            
151200 9100-GET-TRANSACTION-TYPE-EXIT.                                  
151300     EXIT                                                         
151400     .                                                            
151500                                                                  
151600                                                                  
151700 9500-STORE-FETCHED-DATA.                                         
151800                                                                  
151900     INITIALIZE TTUP-OLD-DETAILS                                  
152000******************************************************************
152100*    Transaction Type data                                        
152200******************************************************************
152300     MOVE DCL-TR-TYPE         TO TTUP-OLD-TTYP-TYPE               
152400     MOVE DCL-TR-DESCRIPTION-TEXT(1: DCL-TR-DESCRIPTION-LEN)      
152500                              TO TTUP-OLD-TTYP-TYPE-DESC          
152600                                                                  
152700     .                                                            
152800 9500-STORE-FETCHED-DATA-EXIT.                                    
152900     EXIT                                                         
153000     .                                                            
153100 9600-WRITE-PROCESSING.                                           
153200                                                                  
153300***************************************************************** 
153400* Update Transaction Type *                                       
153500***************************************************************** 
153600*    Issue Update                                                 
153700*                                                                 
153800     MOVE TTUP-NEW-TTYP-TYPE TO DCL-TR-TYPE                       
153900     MOVE FUNCTION TRIM(TTUP-NEW-TTYP-TYPE-DESC)                  
154000                             TO DCL-TR-DESCRIPTION-TEXT           
154100     COMPUTE DCL-TR-DESCRIPTION-LEN                               
154200      = FUNCTION LENGTH(TTUP-NEW-TTYP-TYPE-DESC)                  
154300                                                                  
      *KIX  EXEC SQL UPDATE CARDDEMO.TRANSACTION_TYPE SET TR_DESCRIPTIO
           CALL "KIXCMD" USING
               BY CONTENT "SQL|EXEC||Ii|UPDATE CARDDEMO.TRANSACTION"
                        & "_TYPE SET TR_DESCRIPTION = ? WHERE TR_TY"
                        & "PE = ?"
               BY REFERENCE SQLCA
               BY REFERENCE DCL-TR-DESCRIPTION
               BY REFERENCE DCL-TR-TYPE
           END-CALL
154900                                                                  
155000***************************************************************** 
155100* Did Transaction Type update succeed ?  *                        
155200***************************************************************** 
155300     MOVE SQLCODE                       TO WS-DISP-SQLCODE        
155400                                                                  
155500     EVALUATE TRUE                                                
155600         WHEN SQLCODE = ZERO                                      
      *KIX  EXEC CICS SYNCPOINT
           CALL "KIXCMD" USING
               BY CONTENT "SYNCPOINT"
           END-CALL
           GO TO ABEND-ROUTINE DEPENDING ON RETURN-CODE
           CONTINUE
155800         WHEN SQLCODE = +100                                      
155900            PERFORM 9700-INSERT-RECORD                            
156000               THRU 9700-INSERT-RECORD-EXIT                       
156100         WHEN SQLCODE = -911                                      
156200            SET INPUT-ERROR                    TO TRUE            
156300            IF  WS-RETURN-MSG-OFF                                 
156400                SET COULD-NOT-LOCK-REC-FOR-UPDATE                 
156500                                               TO TRUE            
156600            END-IF                                                
156700         WHEN SQLCODE < 0                                         
156800            SET TABLE-UPDATE-FAILED            TO TRUE            
156900              STRING                                              
157000              'Error updating:'                                   
157100              ' TRANSACTION_TYPE Table. SQLCODE:'                 
157200              WS-DISP-SQLCODE                                     
157300              ':'                                                 
157400              SQLERRM OF SQLCA                                    
157500              DELIMITED BY SIZE                                   
157600              INTO WS-RETURN-MSG                                  
157700              END-STRING                                          
157800     END-EVALUATE                                                 
157900                                                                  
158000     EVALUATE TRUE                                                
158100        WHEN COULD-NOT-LOCK-REC-FOR-UPDATE                        
158200             SET TTUP-CHANGES-OKAYED-LOCK-ERROR TO TRUE           
158300        WHEN TABLE-UPDATE-FAILED                                  
158400             SET TTUP-CHANGES-OKAYED-BUT-FAILED TO TRUE           
158500        WHEN DATA-WAS-CHANGED-BEFORE-UPDATE                       
158600             SET TTUP-SHOW-DETAILS              TO TRUE           
158700        WHEN OTHER                                                
158800           SET TTUP-CHANGES-OKAYED-AND-DONE     TO TRUE           
158900     END-EVALUATE                                                 
159000                                                                  
159100     EXIT                                                         
159200     .                                                            
159300 9600-WRITE-PROCESSING-EXIT.                                      
159400     EXIT                                                         
159500     .                                                            
159600 9700-INSERT-RECORD.                                              
      *KIX  EXEC SQL INSERT INTO CARDDEMO.TRANSACTION_TYPE (TR_TYPE, TR
           CALL "KIXCMD" USING
               BY CONTENT "SQL|EXEC||iI|INSERT INTO CARDDEMO.TRANSA"
                        & "CTION_TYPE (TR_TYPE, TR_DESCRIPTION) VAL"
                        & "UES ( ? ,?)"
               BY REFERENCE SQLCA
               BY REFERENCE DCL-TR-TYPE
               BY REFERENCE DCL-TR-DESCRIPTION
           END-CALL
160300                                                                  
160400     EVALUATE TRUE                                                
160500         WHEN SQLCODE = ZERO                                      
      *KIX  EXEC CICS SYNCPOINT
           CALL "KIXCMD" USING
               BY CONTENT "SYNCPOINT"
           END-CALL
           GO TO ABEND-ROUTINE DEPENDING ON RETURN-CODE
           CONTINUE
160700         WHEN OTHER                                               
160800            SET TABLE-UPDATE-FAILED            TO TRUE            
160900              STRING                                              
161000              'Error inserting record into:'                      
161100              ' TRANSACTION_TYPE Table. SQLCODE:'                 
161200              WS-DISP-SQLCODE                                     
161300              ':'                                                 
161400              SQLERRM OF SQLCA                                    
161500              DELIMITED BY SIZE                                   
161600              INTO WS-RETURN-MSG                                  
161700              END-STRING                                          
161800            GO TO 9700-INSERT-RECORD-EXIT                         
161900     END-EVALUATE                                                 
162000     .                                                            
162100 9700-INSERT-RECORD-EXIT.                                         
162200     EXIT                                                         
162300     .                                                            
162400 9800-DELETE-PROCESSING.                                          
162500     MOVE TTUP-OLD-TTYP-TYPE TO DCL-TR-TYPE                       
162600                                                                  
      *KIX  EXEC SQL DELETE FROM CARDDEMO.TRANSACTION_TYPE WHERE TR_TYP
           CALL "KIXCMD" USING
               BY CONTENT "SQL|EXEC||i|DELETE FROM CARDDEMO.TRANSAC"
                        & "TION_TYPE WHERE TR_TYPE = ?"
               BY REFERENCE SQLCA
               BY REFERENCE DCL-TR-TYPE
           END-CALL
163100                                                                  
163200     MOVE SQLCODE                             TO WS-DISP-SQLCODE  
163300                                                                  
163400     EVALUATE TRUE                                                
163500         WHEN SQLCODE = ZERO                                      
163600            SET TTUP-DELETE-DONE              TO TRUE             
      *KIX  EXEC CICS SYNCPOINT
           CALL "KIXCMD" USING
               BY CONTENT "SYNCPOINT"
           END-CALL
           GO TO ABEND-ROUTINE DEPENDING ON RETURN-CODE
           CONTINUE
163800         WHEN SQLCODE = -532                                      
163900            SET RECORD-DELETE-FAILED          TO TRUE             
164000              STRING                                              
164100              'Please delete associated child records first:'     
164200              'SQLCODE :'                                         
164300              WS-DISP-SQLCODE                                     
164400              ':'                                                 
164500              SQLERRM OF SQLCA                                    
164600              SQLERRM OF SQLCA                                    
164700              DELIMITED BY SIZE                                   
164800              INTO WS-RETURN-MSG                                  
164900              END-STRING                                          
165000         WHEN OTHER                                               
165100            SET RECORD-DELETE-FAILED          TO TRUE             
165200            SET TTUP-DELETE-FAILED            TO TRUE             
165300              STRING                                              
165400              'Delete failed with message:'                       
165500              'SQLCODE :'                                         
165600              WS-DISP-SQLCODE                                     
165700              ':'                                                 
165800              SQLERRM OF SQLCA                                    
165900              DELIMITED BY SIZE                                   
166000              INTO WS-RETURN-MSG                                  
166100              END-STRING                                          
166200     END-EVALUATE                                                 
166300     .                                                            
166400 9800-DELETE-PROCESSING-EXIT.                                     
166500     EXIT                                                         
166600     .                                                            
166700                                                                  
166800******************************************************************
166900*Common code to store PFKey                                       
167000******************************************************************
167100 COPY 'CSSTRPFY'                                                  
167200     .                                                            
167300                                                                  
167400                                                                  
167500 ABEND-ROUTINE.                                                   
167600                                                                  
167700     IF ABEND-MSG EQUAL LOW-VALUES                                
167800        MOVE 'UNEXPECTED ABEND OCCURRED.' TO ABEND-MSG            
167900     END-IF                                                       
168000                                                                  
168100     MOVE LIT-THISPGM       TO ABEND-CULPRIT                      
168200     MOVE '9999'            TO ABEND-CODE                         
168300                                                                  
      *KIX  EXEC CICS SEND FROM (ABEND-DATA) LENGTH(LENGTH OF ABEND-DATA
           CALL "KIXCMD" USING
               BY CONTENT "SEND|FROM=|LENGTH=|NOHANDLE|ERASE"
               BY REFERENCE ABEND-DATA
               BY CONTENT LENGTH OF ABEND-DATA
           END-CALL
           GO TO ABEND-ROUTINE DEPENDING ON RETURN-CODE
           CONTINUE
169000                                                                  
      *KIX  EXEC CICS HANDLE ABEND CANCEL
           CALL "KIXCMD" USING
               BY CONTENT "HANDLE|ABEND|CANCEL"
           END-CALL
           GO TO ABEND-ROUTINE DEPENDING ON RETURN-CODE
           CONTINUE
169400                                                                  
      *KIX  EXEC CICS ABEND ABCODE(ABEND-CODE)
           CALL "KIXCMD" USING
               BY CONTENT "ABEND|ABCODE="
               BY REFERENCE ABEND-CODE
           END-CALL
           GO TO ABEND-ROUTINE DEPENDING ON RETURN-CODE
           CONTINUE
169800     .                                                            
169900 ABEND-ROUTINE-EXIT.                                              
170000     EXIT                                                         
170100     .                                                            
170200                                                                  
