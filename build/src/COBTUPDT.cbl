      **************************************** *************************
      * Program:     COBTUPDT.CBL                                      *
      * Layer:       Business logic                                    *
      * Function:    Update Transaction type based on user input       *
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
       PROGRAM-ID. COBTUPDT.                                            
                                                                        
       ENVIRONMENT DIVISION.                                            
                                                                        
       CONFIGURATION SECTION.                                           
                                                                        
       INPUT-OUTPUT SECTION.                                            
       FILE-CONTROL.                                                    
           SELECT TR-RECORD ASSIGN TO INPFILE                           
                  ORGANIZATION IS SEQUENTIAL                            
                  ACCESS MODE IS SEQUENTIAL                             
                  FILE STATUS IS WS-INF-STATUS.                         
                                                                        
       DATA DIVISION.                                                   
                                                                        
       FILE SECTION.                                                    
       FD TR-RECORD RECORDING MODE F.                                   
       01 WS-INPUT-VARS.                                                
          05 INPUT-TYPE                            PIC X(1)             
                                                   VALUE SPACES.        
          05 INPUT-TR-NUMBER                       PIC X(2)             
                                                   VALUE SPACES.        
          05 INPUT-TR-DESC                         PIC X(50)            
                                                   VALUE SPACES.        
                                                                        
       WORKING-STORAGE SECTION.                                         
                                                                        
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
                                                                        
                                                                        
       01 FLAGS.                                                        
         05 LASTREC                                PIC X(1)             
                                                   VALUE SPACES.        
       01 WORKING-VARIABLES.                                            
         05 WS-RETURN-MSG                          PIC X(80)            
                                                   VALUE SPACES.        
                                                                        
       01 WS-MISC-VARS.                                                 
         05 WS-VAR-SQLCODE                     PIC ----9.               
                                                                        
       01  WS-INF-STATUS.                                               
           05  WS-INF-STAT1       PIC X.                                
           05  WS-INF-STAT2       PIC X.                                
                                                                        
       01 WS-INPUT-REC.                                                 
          05 INPUT-REC-TYPE                        PIC X(1)             
                                                   VALUE SPACES.        
          05 INPUT-REC-NUMBER                      PIC X(2)             
                                                   VALUE SPACES.        
          05 INPUT-REC-DESC                        PIC X(50)            
                                                   VALUE SPACES.        
                                                                        
                                                                        
       PROCEDURE DIVISION.                                              
                                                                        
       0001-OPEN-FILES.                                                 
           OPEN INPUT TR-RECORD.                                        
           IF WS-INF-STATUS = '00' THEN                                 
              DISPLAY 'OPEN FILE OK'                                    
           ELSE                                                         
              DISPLAY 'OPEN FILE NOT OK'                                
           END-IF                                                       
           EXIT.                                                        
                                                                        
       1001-READ-NEXT-RECORDS.                                          
               PERFORM 1002-READ-RECORDS                                
            PERFORM UNTIL LASTREC = 'Y'                                 
               PERFORM 1003-TREAT-RECORD                                
               PERFORM 1002-READ-RECORDS                                
            END-PERFORM.                                                
            PERFORM 2001-CLOSE-STOP                                     
            EXIT.                                                       
            STOP RUN.                                                   
       1002-READ-RECORDS.                                               
           READ TR-RECORD NEXT RECORD INTO WS-INPUT-REC                 
           AT END MOVE 'Y' TO LASTREC                                   
           END-READ.                                                    
           IF LASTREC NOT EQUAL TO 'Y' THEN                             
              DISPLAY 'PROCESSING   ' WS-INPUT-REC                      
           END-IF.                                                      
           EXIT.                                                        
                                                                        
       1003-TREAT-RECORD.                                               
           EVALUATE INPUT-REC-TYPE                                      
               WHEN 'A'                                                 
                   DISPLAY 'ADDING RECORD'                              
                   PERFORM 10031-INSERT-DB                              
               WHEN 'U'                                                 
                   DISPLAY 'UPDATING RECORD'                            
                   PERFORM 10032-UPDATE-DB                              
               WHEN 'D'                                                 
                   DISPLAY 'DELETING RECORD'                            
                   PERFORM 10033-DELETE-DB                              
               WHEN '*'                                                 
                   DISPLAY 'IGNORING COMMENTED LINE'                    
               WHEN OTHER                                               
                  STRING                                                
                  'ERROR: TYPE NOT VALID'                               
                  DELIMITED BY SIZE                                     
                  INTO WS-RETURN-MSG                                    
                  END-STRING                                            
                  PERFORM 9999-ABEND                                    
           END-EVALUATE.                                                
           EXIT.                                                        
                                                                        
       10031-INSERT-DB.                                                 
      ******************************************************************
      * SQL TO INSERT THE RECORD                                        
      ******************************************************************
      *                                                                 
      *KIX  EXEC SQL INSERT INTO CARDDEMO.TRANSACTION_TYPE ( TR_TYPE, T
           CALL "KIXCMD" USING
               BY CONTENT "SQL|EXEC||ii|INSERT INTO CARDDEMO.TRANSA"
                        & "CTION_TYPE ( TR_TYPE, TR_DESCRIPTION ) V"
                        & "ALUES ( ?, ? )"
               BY REFERENCE SQLCA
               BY REFERENCE INPUT-REC-NUMBER
               BY REFERENCE INPUT-REC-DESC
           END-CALL
           .
           MOVE SQLCODE TO WS-VAR-SQLCODE                               
                                                                        
           EVALUATE TRUE                                                
               WHEN SQLCODE = ZERO                                      
                  DISPLAY 'RECORD INSERTED SUCCESSFULLY'                
               WHEN SQLCODE < 0                                         
                  STRING                                                
                  'Error accessing:'                                    
                  ' TRANSACTION_TYPE table. SQLCODE:'                   
                  WS-VAR-SQLCODE                                        
                  DELIMITED BY SIZE                                     
                  INTO WS-RETURN-MSG                                    
                  END-STRING                                            
                  PERFORM 9999-ABEND                                    
           END-EVALUATE                                                 
           EXIT.                                                        
                                                                        
       10032-UPDATE-DB.                                                 
      ******************************************************************
      * SQL TO UPDATE THE RECORD                                        
      ******************************************************************
      *                                                                 
      *KIX  EXEC SQL UPDATE CARDDEMO.TRANSACTION_TYPE SET TR_DESCRIPTIO
           CALL "KIXCMD" USING
               BY CONTENT "SQL|EXEC||ii|UPDATE CARDDEMO.TRANSACTION"
                        & "_TYPE SET TR_DESCRIPTION = ? WHERE TR_TY"
                        & "PE = ?"
               BY REFERENCE SQLCA
               BY REFERENCE INPUT-REC-DESC
               BY REFERENCE INPUT-REC-NUMBER
           END-CALL
           MOVE SQLCODE TO WS-VAR-SQLCODE                               
           EVALUATE TRUE                                                
               WHEN SQLCODE = ZERO                                      
                  DISPLAY 'RECORD UPDATED SUCCESSFULLY'                 
               WHEN SQLCODE = +100                                      
                  STRING 'No records found.' DELIMITED BY SIZE          
                     INTO WS-RETURN-MSG                                 
                  END-STRING                                            
                  PERFORM 9999-ABEND                                    
               WHEN SQLCODE < 0                                         
                  STRING                                                
                  'Error accessing:'                                    
                  ' TRANSACTION_TYPE table. SQLCODE:'                   
                  WS-VAR-SQLCODE                                        
                  DELIMITED BY SIZE                                     
                  INTO WS-RETURN-MSG                                    
                  END-STRING                                            
                  PERFORM 9999-ABEND                                    
           END-EVALUATE                                                 
           EXIT.                                                        
       10033-DELETE-DB.                                                 
      ******************************************************************
      * SQL TO DELETE THE RECORD                                        
      ******************************************************************
      *                                                                 
      *KIX  EXEC SQL DELETE FROM CARDDEMO.TRANSACTION_TYPE WHERE TR_TYP
           CALL "KIXCMD" USING
               BY CONTENT "SQL|EXEC||i|DELETE FROM CARDDEMO.TRANSAC"
                        & "TION_TYPE WHERE TR_TYPE = ?"
               BY REFERENCE SQLCA
               BY REFERENCE INPUT-REC-NUMBER
           END-CALL
           .
           MOVE SQLCODE TO WS-VAR-SQLCODE                               
                                                                        
           EVALUATE TRUE                                                
               WHEN SQLCODE = ZERO                                      
                  DISPLAY 'RECORD DELETED SUCCESSFULLY'                 
               WHEN SQLCODE = +100                                      
               STRING 'No records found.' DELIMITED BY SIZE             
               INTO WS-RETURN-MSG                                       
               END-STRING                                               
               PERFORM 9999-ABEND                                       
                                                                        
               WHEN SQLCODE < 0                                         
                  STRING                                                
                  'Error accessing:'                                    
                  ' TRANSACTION_TYPE table. SQLCODE:'                   
                  WS-VAR-SQLCODE                                        
                  DELIMITED BY SIZE                                     
                  INTO WS-RETURN-MSG                                    
                  END-STRING                                            
                  PERFORM 9999-ABEND                                    
           END-EVALUATE                                                 
           EXIT.                                                        
                                                                        
                                                                        
                                                                        
       9999-ABEND.                                                      
           DISPLAY WS-RETURN-MSG.                                       
           MOVE 4 TO RETURN-CODE                                        
           EXIT.                                                        
       2001-CLOSE-STOP.                                                 
           CLOSE TR-RECORD.                                             
           EXIT.                                                        
                                                                        
