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
       PROGRAM-ID. PAUDBLOD.                                            
       AUTHOR.     AWS.                                                 
                                                                        
       ENVIRONMENT DIVISION.                                            
       CONFIGURATION SECTION.                                           
                                                                        
       INPUT-OUTPUT SECTION.                                            
       FILE-CONTROL.                                                    
           SELECT INFILE1 ASSIGN TO INFILE1                             
           ORGANIZATION IS SEQUENTIAL                                   
           ACCESS MODE  IS SEQUENTIAL                                   
           FILE STATUS IS WS-INFIL1-STATUS.                             
                                                                        
      *                                                                 
           SELECT INFILE2 ASSIGN TO INFILE2                             
           ORGANIZATION IS SEQUENTIAL                                   
           ACCESS MODE  IS SEQUENTIAL                                   
           FILE STATUS IS WS-INFIL2-STATUS.                             
                                                                        
      *                                                                 
      *----------------------------------------------------------------*
       DATA DIVISION.                                                   
      *----------------------------------------------------------------*
      *                                                                 
       FILE SECTION.                                                    
       FD INFILE1.                                                      
       01 INFIL1-REC                    PIC X(100).                     
       FD INFILE2.                                                      
       01 INFIL2-REC.                                                   
          05 ROOT-SEG-KEY               PIC S9(11) COMP-3.              
          05 CHILD-SEG-REC              PIC X(200).                     
      *                                                                 
      *----------------------------------------------------------------*
       WORKING-STORAGE SECTION.                                         
      *----------------------------------------------------------------*
       01 WS-VARIABLES.                                                 
         05 WS-PGMNAME                 PIC X(08) VALUE 'IMSUNLOD'.      
         05 CURRENT-DATE               PIC 9(06).                       
         05 CURRENT-YYDDD              PIC 9(05).                       
         05 WS-AUTH-DATE               PIC 9(05).                       
         05 WS-EXPIRY-DAYS             PIC S9(4) COMP.                  
         05 WS-DAY-DIFF                PIC S9(4) COMP.                  
         05 IDX                        PIC S9(4) COMP.                  
         05 WS-CURR-APP-ID             PIC 9(11).                       
      *                                                                 
         05 WS-NO-CHKP                 PIC  9(8) VALUE 0.               
         05 WS-AUTH-SMRY-PROC-CNT      PIC  9(8) VALUE 0.               
         05 WS-TOT-REC-WRITTEN         PIC S9(8) COMP VALUE 0.          
         05 WS-NO-SUMRY-READ           PIC S9(8) COMP VALUE 0.          
         05 WS-NO-SUMRY-DELETED        PIC S9(8) COMP VALUE 0.          
         05 WS-NO-DTL-READ             PIC S9(8) COMP VALUE 0.          
         05 WS-NO-DTL-DELETED          PIC S9(8) COMP VALUE 0.          
      *                                                                 
         05 WS-ERR-FLG                 PIC X(01) VALUE 'N'.             
           88 ERR-FLG-ON                         VALUE 'Y'.             
           88 ERR-FLG-OFF                        VALUE 'N'.             
         05 WS-END-OF-AUTHDB-FLAG      PIC X(01) VALUE 'N'.             
           88 END-OF-AUTHDB                      VALUE 'Y'.             
           88 NOT-END-OF-AUTHDB                  VALUE 'N'.             
         05 WS-MORE-AUTHS-FLAG         PIC X(01) VALUE 'N'.             
           88 MORE-AUTHS                         VALUE 'Y'.             
           88 NO-MORE-AUTHS                      VALUE 'N'.             
         05 WS-END-OF-INFILE1          PIC X(01) VALUE SPACES.          
         05 WS-END-OF-INFILE2          PIC X(01) VALUE SPACES.          
         05 WS-INFILE-STATUS           PIC X(02) VALUE SPACES.          
         05 WS-INFIL1-STATUS           PIC X(02) VALUE SPACES.          
         05 WS-INFIL2-STATUS           PIC X(02) VALUE SPACES.          
         05 END-ROOT-SEG-FILE          PIC X(01) VALUE SPACES.          
         05 END-CHILD-SEG-FILE         PIC X(01) VALUE SPACES.          
         05 WS-CUSTID-STATUS           PIC X(02) VALUE SPACES.          
            88 END-OF-FILE                       VALUE '10'.            
      *                                                                 
         05 WK-CHKPT-ID.                                                
            10  FILLER              PIC  X(04) VALUE 'RMAD'.            
            10  WK-CHKPT-ID-CTR     PIC  9(04) VALUE ZEROES.            
      *                                                                 
       01 WS-IMS-VARIABLES.                                             
      *   05 PSB-NAME                        PIC X(8) VALUE 'IMSUNLOD'. 
      *   05 PCB-OFFSET.                                                
      *      10 PAUT-PCB-NUM                 PIC S9(4) COMP VALUE +2.   
          05 IMS-RETURN-CODE                 PIC X(02).                 
             88 STATUS-OK                    VALUE '  ', 'FW'.          
             88 SEGMENT-NOT-FOUND            VALUE 'GE'.                
             88 DUPLICATE-SEGMENT-FOUND      VALUE 'II'.                
             88 WRONG-PARENTAGE              VALUE 'GP'.                
             88 END-OF-DB                    VALUE 'GB'.                
             88 DATABASE-UNAVAILABLE         VALUE 'BA'.                
             88 PSB-SCHEDULED-MORE-THAN-ONCE VALUE 'TC'.                
             88 COULD-NOT-SCHEDULE-PSB       VALUE 'TE'.                
             88 RETRY-CONDITION              VALUE 'BA', 'FH', 'TE'.    
          05 WS-IMS-PSB-SCHD-FLG             PIC X(1).                  
             88  IMS-PSB-SCHD                VALUE 'Y'.                 
             88  IMS-PSB-NOT-SCHD            VALUE 'N'.                 
                                                                        
      *                                                                 
       01 ROOT-QUAL-SSA.                                                
          05 QUAL-SSA-SEG-NAME      PIC X(08) VALUE 'PAUTSUM0'.         
          05 FILLER                 PIC X(01) VALUE '('.                
          05 QUAL-SSA-KEY-FIELD     PIC X(08) VALUE 'ACCNTID '.         
          05 QUAL-SSA-REL-OPER      PIC X(02) VALUE 'EQ'.               
          05 QUAL-SSA-KEY-VALUE     PIC S9(11) COMP-3.                  
          05 FILLER                 PIC X(01) VALUE ')'.                
      *                                                                 
       01 ROOT-UNQUAL-SSA.                                              
          05 FILLER                 PIC X(08) VALUE 'PAUTSUM0'.         
          05 FILLER                 PIC X(01) VALUE ' '.                
      *                                                                 
       01 CHILD-UNQUAL-SSA.                                             
          05 FILLER                 PIC X(08) VALUE 'PAUTDTL1'.         
          05 FILLER                 PIC X(01) VALUE ' '.                
      *                                                                 
       01 PRM-INFO.                                                     
          05 P-EXPIRY-DAYS          PIC 9(02).                          
          05 FILLER                 PIC X(01).                          
          05 P-CHKP-FREQ            PIC X(05).                          
          05 FILLER                 PIC X(01).                          
          05 P-CHKP-DIS-FREQ        PIC X(05).                          
          05 FILLER                 PIC X(01).                          
          05 P-DEBUG-FLAG           PIC X(01).                          
             88 DEBUG-ON            VALUE 'Y'.                          
             88 DEBUG-OFF           VALUE 'N'.                          
          05 FILLER                 PIC X(01).                          
      *                                                                 
      *                                                                 
       COPY IMSFUNCS.                                                   
      *----------------------------------------------------------------*
      *  IMS SEGMENT LAYOUT                                             
      *----------------------------------------------------------------*
                                                                        
      *- PENDING AUTHORIZATION SUMMARY SEGMENT - ROOT                   
       01 PENDING-AUTH-SUMMARY.                                         
       COPY CIPAUSMY.                                                   
                                                                        
      *- PENDING AUTHORIZATION DETAILS SEGMENT - CHILD                  
       01 PENDING-AUTH-DETAILS.                                         
       COPY CIPAUDTY.                                                   
                                                                        
      *                                                                 
      *----------------------------------------------------------------*
       LINKAGE SECTION.                                                 
      *----------------------------------------------------------------*
      * PCB MASKS FOLLOW                                                
       01 IO-PCB-MASK   PIC X(1).                                       
       COPY PAUTBPCB.                                                   
      *                                                                 
      *----------------------------------------------------------------*
       PROCEDURE DIVISION                  USING IO-PCB-MASK            
                                                 PAUTBPCB.              
      *                                          PGM-PCB-MASK.          
      *----------------------------------------------------------------*
      *                                                                 
       MAIN-PARA.                                                       
      *     DISPLAY 'CHECK PROG PCB:' PAUTBPCB.                         
            ENTRY 'DLITCBL'                 USING PAUTBPCB.             
                                                                        
            DISPLAY 'STARTING PAUDBLOD'.                                
      *                                                                 
           PERFORM 1000-INITIALIZE                THRU 1000-EXIT        
      *                                                                 
           PERFORM 2000-READ-ROOT-SEG-FILE        THRU 2000-EXIT        
           UNTIL   END-ROOT-SEG-FILE  = 'Y'                             
                                                                        
           PERFORM 3000-READ-CHILD-SEG-FILE       THRU 3000-EXIT        
           UNTIL   END-CHILD-SEG-FILE = 'Y'                             
                                                                        
           PERFORM 4000-FILE-CLOSE THRU 4000-EXIT                       
      *                                                                 
      *                                                                 
      *                                                                 
           GOBACK.                                                      
      *                                                                 
      *----------------------------------------------------------------*
       1000-INITIALIZE.                                                 
      *----------------------------------------------------------------*
      *                                                                 
           ACCEPT CURRENT-DATE     FROM DATE                            
           ACCEPT CURRENT-YYDDD    FROM DAY                             
                                                                        
           DISPLAY '*-------------------------------------*'            
           DISPLAY 'TODAYS DATE            :' CURRENT-DATE              
           DISPLAY ' '                                                  
                                                                        
           .                                                            
           OPEN INPUT  INFILE1                                          
           IF WS-INFIL1-STATUS =  SPACES OR '00'                        
              CONTINUE                                                  
           ELSE                                                         
              DISPLAY 'ERROR IN OPENING INFILE1:' WS-INFIL1-STATUS      
              PERFORM 9999-ABEND                                        
           END-IF                                                       
      *                                                                 
           OPEN INPUT INFILE2                                           
           IF WS-INFIL2-STATUS =  SPACES OR '00'                        
              CONTINUE                                                  
           ELSE                                                         
              DISPLAY 'ERROR IN OPENING INFILE2:' WS-INFIL2-STATUS      
              PERFORM 9999-ABEND                                        
           END-IF.                                                      
      *                                                                 
      *                                                                 
       1000-EXIT.                                                       
            EXIT.                                                       
      *                                                                 
      *----------------------------------------------------------------*
       2000-READ-ROOT-SEG-FILE.                                         
      *----------------------------------------------------------------*
      *                                                                 
      *     DISPLAY 'IN 2000 READ ROOT SEG FILE PARA'                   
            READ INFILE1                                                
                                                                        
            IF WS-INFIL1-STATUS =  SPACES OR '00'                       
               MOVE INFIL1-REC TO PENDING-AUTH-SUMMARY                  
               PERFORM 2100-INSERT-ROOT-SEG THRU 2100-EXIT              
            ELSE                                                        
               IF WS-INFIL1-STATUS = '10'                               
                  MOVE 'Y' TO END-ROOT-SEG-FILE                         
               ELSE                                                     
                  DISPLAY 'ERROR READING ROOT SEG INFILE'               
               END-IF                                                   
            END-IF.                                                     
                                                                        
       2000-EXIT.                                                       
            EXIT.                                                       
                                                                        
       2100-INSERT-ROOT-SEG.                                            
                                                                        
            CALL 'CBLTDLI'       USING  FUNC-ISRT                       
                                        PAUTBPCB                        
                                        PENDING-AUTH-SUMMARY            
                                        ROOT-UNQUAL-SSA.                
            DISPLAY ' *******************************'                  
      *     DISPLAY ' AFTER THE ROOT SEG INSERT CALL '                  
      *     DISPLAY 'PCB STATU: ' PAUT-PCB-STATUS                       
      *     DISPLAY 'SEG NAME : ' PAUT-SEG-NAME                         
            DISPLAY ' *******************************'                  
            IF PAUT-PCB-STATUS = SPACES                                 
               DISPLAY 'ROOT INSERT SUCCESS    '                        
            END-IF                                                      
            IF PAUT-PCB-STATUS = 'II'                                   
               DISPLAY 'ROOT SEGMENT ALREADY IN DB'                     
            END-IF                                                      
            IF PAUT-PCB-STATUS NOT EQUAL TO  SPACES AND 'II'            
                  DISPLAY 'ROOT INSERT FAILED  :' PAUT-PCB-STATUS       
                  PERFORM 9999-ABEND                                    
            END-IF                                                      
            .                                                           
       2100-EXIT.                                                       
            EXIT.                                                       
      *                                                                 
      *                                                                 
      *----------------------------------------------------------------*
       3000-READ-CHILD-SEG-FILE.                                        
      *----------------------------------------------------------------*
      *     DISPLAY 'IN 3000 READ CHILD SEG FILE PARA'                  
            READ INFILE2                                                
                                                                        
            IF WS-INFIL2-STATUS =  SPACES OR '00'                       
               IF ROOT-SEG-KEY IS NUMERIC                               
      *        DISPLAY 'GNGTO ROOT SEG KEY'                             
               MOVE ROOT-SEG-KEY  TO QUAL-SSA-KEY-VALUE                 
      *        DISPLAY 'ROOT-SEG-KEY : '    QUAL-SSA-KEY-VALUE          
      *        DISPLAY 'MOVED ROOT SEG KEY'                             
               MOVE CHILD-SEG-REC TO PENDING-AUTH-DETAILS               
               PERFORM 3100-INSERT-CHILD-SEG THRU 3100-EXIT             
               END-IF                                                   
            ELSE                                                        
               IF WS-INFIL2-STATUS = '10'                               
                  MOVE 'Y' TO END-CHILD-SEG-FILE                        
               ELSE                                                     
                  DISPLAY 'ERROR READING CHILD SEG INFILE'              
               END-IF                                                   
            END-IF.                                                     
       3000-EXIT.                                                       
            EXIT.                                                       
       3100-INSERT-CHILD-SEG.                                           
      *                                                                 
      *     DISPLAY 'IN 3100 INSERT CHILD SEG PARA'                     
            INITIALIZE PAUT-PCB-STATUS                                  
            CALL 'CBLTDLI'       USING  FUNC-GU                         
                                        PAUTBPCB                        
                                        PENDING-AUTH-SUMMARY            
                                        ROOT-QUAL-SSA.                  
               DISPLAY '***************************'                    
      *        DISPLAY ' AFTER ROOT SEG GU CALL    '                    
      *        DISPLAY 'PCB STATU: ' PAUT-PCB-STATUS                    
      *        DISPLAY 'SEG NAME : ' PAUT-SEG-NAME                      
               DISPLAY '***************************'                    
               IF PAUT-PCB-STATUS = SPACES                              
                  DISPLAY 'GU CALL TO ROOT SEG SUCCESS'                 
      *           ADD 2 TO PA-AUTH-DATE-9C                              
      *           ADD 2 TO PA-AUTH-TIME-9C                              
                  PERFORM 3200-INSERT-IMS-CALL  THRU 3200-EXIT          
               IF PAUT-PCB-STATUS NOT EQUAL TO  SPACES AND 'II'         
                  DISPLAY 'ROOT GU CALL FAIL:' PAUT-PCB-STATUS          
                  DISPLAY 'KFB AREA IN CHILD:' PAUT-KEYFB               
                    PERFORM 9999-ABEND                                  
               END-IF.                                                  
       3100-EXIT.                                                       
            EXIT.                                                       
      *                                                                 
       3200-INSERT-IMS-CALL.                                            
      *                                                                 
      *     DISPLAY 'IN 3200 INSERT CALL'                               
                  CALL 'CBLTDLI' USING  FUNC-ISRT                       
                                        PAUTBPCB                        
                                        PENDING-AUTH-DETAILS            
                                        CHILD-UNQUAL-SSA.               
                                                                        
            IF PAUT-PCB-STATUS = SPACES                                 
               DISPLAY 'CHILD SEGMENT INSERTED SUCCESS'                 
            END-IF                                                      
            IF PAUT-PCB-STATUS = 'II'                                   
               DISPLAY 'CHILD SEGMENT ALREADY IN DB'                    
            END-IF                                                      
            IF PAUT-PCB-STATUS NOT EQUAL TO  SPACES AND 'II'            
                  DISPLAY 'INSERT CALL FAIL FOR CHILD:' PAUT-PCB-STATUS 
                  DISPLAY 'KFB AREA IN CHILD:' PAUT-KEYFB               
                    PERFORM 9999-ABEND                                  
            END-IF.                                                     
                                                                        
       3200-EXIT.                                                       
            EXIT.                                                       
      *----------------------------------------------------------------*
       4000-FILE-CLOSE.                                                 
            DISPLAY 'CLOSING THE FILE'                                  
            CLOSE INFILE1.                                              
                                                                        
            IF WS-INFIL1-STATUS =  SPACES OR '00'                       
             CONTINUE                                                   
            ELSE                                                        
             DISPLAY 'ERROR IN CLOSING 1ST FILE:'WS-INFIL1-STATUS       
            END-IF.                                                     
            CLOSE INFILE2.                                              
                                                                        
            IF WS-INFIL2-STATUS =  SPACES OR '00'                       
             CONTINUE                                                   
            ELSE                                                        
             DISPLAY 'ERROR IN CLOSING 2ND FILE:'WS-INFIL2-STATUS       
            END-IF.                                                     
       4000-EXIT.                                                       
            EXIT.                                                       
      *----------------------------------------------------------------*
       9999-ABEND.                                                      
      *----------------------------------------------------------------*
      *                                                                 
           DISPLAY 'IMS LOAD ABENDING ...'                              
                                                                        
           MOVE 16 TO RETURN-CODE                                       
           GOBACK.                                                      
      *                                                                 
       9999-EXIT.                                                       
            EXIT.                                                       
