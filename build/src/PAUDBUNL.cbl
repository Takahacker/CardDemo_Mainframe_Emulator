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
       PROGRAM-ID. PAUDBUNL.                                            
       AUTHOR.     AWS.                                                 
                                                                        
       ENVIRONMENT DIVISION.                                            
       CONFIGURATION SECTION.                                           
                                                                        
       INPUT-OUTPUT SECTION.                                            
       FILE-CONTROL.                                                    
           SELECT OPFILE1 ASSIGN TO OUTFIL1                             
           ORGANIZATION IS SEQUENTIAL                                   
           ACCESS MODE  IS SEQUENTIAL                                   
           FILE STATUS IS WS-OUTFL1-STATUS.                             
                                                                        
      *                                                                 
           SELECT OPFILE2 ASSIGN TO OUTFIL2                             
           ORGANIZATION IS SEQUENTIAL                                   
           ACCESS MODE  IS SEQUENTIAL                                   
           FILE STATUS IS WS-OUTFL2-STATUS.                             
                                                                        
      *                                                                 
      *----------------------------------------------------------------*
       DATA DIVISION.                                                   
      *----------------------------------------------------------------*
      *                                                                 
       FILE SECTION.                                                    
       FD OPFILE1.                                                      
       01 OPFIL1-REC                    PIC X(100).                     
       FD OPFILE2.                                                      
       01 OPFIL2-REC.                                                   
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
         05 WS-END-OF-ROOT-SEG         PIC X(01) VALUE SPACES.          
         05 WS-END-OF-CHILD-SEG        PIC X(01) VALUE SPACES.          
         05 WS-INFILE-STATUS           PIC X(02) VALUE SPACES.          
         05 WS-OUTFL1-STATUS           PIC X(02) VALUE SPACES.          
         05 WS-OUTFL2-STATUS           PIC X(02) VALUE SPACES.          
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
       COPY PAUTBPCB.                                                   
      *                                                                 
      *----------------------------------------------------------------*
       PROCEDURE DIVISION                  USING PAUTBPCB.              
      *                                          PGM-PCB-MASK.          
      *----------------------------------------------------------------*
      *                                                                 
       MAIN-PARA.                                                       
            ENTRY 'DLITCBL'                 USING PAUTBPCB.             
                                                                        
      *                                                                 
           PERFORM 1000-INITIALIZE                THRU 1000-EXIT        
      *                                                                 
           PERFORM 2000-FIND-NEXT-AUTH-SUMMARY    THRU 2000-EXIT        
           UNTIL   WS-END-OF-ROOT-SEG = 'Y'                             
                                                                        
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
                                                                        
      *    ACCEPT PRM-INFO FROM SYSIN                                   
           DISPLAY 'STARTING PROGRAM PAUDBUNL::'                        
           DISPLAY '*-------------------------------------*'            
           DISPLAY 'TODAYS DATE            :' CURRENT-DATE              
           DISPLAY ' '                                                  
                                                                        
           .                                                            
           OPEN OUTPUT OPFILE1                                          
           IF WS-OUTFL1-STATUS =  SPACES OR '00'                        
              CONTINUE                                                  
           ELSE                                                         
              DISPLAY 'ERROR IN OPENING OPFILE1:' WS-OUTFL1-STATUS      
              PERFORM 9999-ABEND                                        
           END-IF                                                       
      *                                                                 
           OPEN OUTPUT OPFILE2                                          
           IF WS-OUTFL2-STATUS =  SPACES OR '00'                        
              CONTINUE                                                  
           ELSE                                                         
              DISPLAY 'ERROR IN OPENING OPFILE2:' WS-OUTFL2-STATUS      
              PERFORM 9999-ABEND                                        
           END-IF.                                                      
      *                                                                 
      *                                                                 
       1000-EXIT.                                                       
            EXIT.                                                       
      *                                                                 
      *----------------------------------------------------------------*
       2000-FIND-NEXT-AUTH-SUMMARY.                                     
      *----------------------------------------------------------------*
      *                                                                 
      *     DISPLAY 'IN 2000 READ ROOT SEGMENT PARA'                    
      *              PAUT-PCB-STATUS                                    
            INITIALIZE PAUT-PCB-STATUS                                  
            CALL 'CBLTDLI'            USING  FUNC-GN                    
                                        PAUTBPCB                        
                                        PENDING-AUTH-SUMMARY            
                                        ROOT-UNQUAL-SSA.                
      *     DISPLAY ' *******************************'                  
      *     DISPLAY ' AFTER THE ROOT SEG IMS CALL    '                  
      *     DISPLAY 'SEG LEVEL: ' PAUT-SEG-LEVEL                        
      *     DISPLAY 'PCB STATU: ' PAUT-PCB-STATUS                       
      *     DISPLAY 'SEG NAME   : ' PAUT-SEG-NAME                       
      *     DISPLAY ' *******************************'                  
               IF PAUT-PCB-STATUS = SPACES                              
      *             SET NOT-END-OF-AUTHDB TO TRUE                       
                    ADD 1                 TO WS-NO-SUMRY-READ           
                    ADD 1                 TO WS-AUTH-SMRY-PROC-CNT      
                    MOVE PENDING-AUTH-SUMMARY TO OPFIL1-REC             
                    INITIALIZE ROOT-SEG-KEY                             
                    INITIALIZE CHILD-SEG-REC                            
                    MOVE PA-ACCT-ID           TO ROOT-SEG-KEY           
      *             DISPLAY 'WRITING FIRST FILE'                        
                    IF PA-ACCT-ID IS NUMERIC                            
                    WRITE OPFIL1-REC                                    
                    INITIALIZE WS-END-OF-CHILD-SEG                      
                    PERFORM 3000-FIND-NEXT-AUTH-DTL THRU 3000-EXIT      
                    UNTIL  WS-END-OF-CHILD-SEG='Y'                      
                    END-IF                                              
               END-IF                                                   
               IF PAUT-PCB-STATUS = 'GB'                                
                    SET END-OF-AUTHDB     TO TRUE                       
                    MOVE 'Y' TO WS-END-OF-ROOT-SEG                      
               END-IF                                                   
               IF PAUT-PCB-STATUS NOT EQUAL TO  SPACES AND 'GB'         
                  DISPLAY 'AUTH SUM  GN FAILED  :' PAUT-PCB-STATUS      
                  DISPLAY 'KEY FEEDBACK AREA    :' PAUT-KEYFB           
                    PERFORM 9999-ABEND                                  
            .                                                           
       2000-EXIT.                                                       
            EXIT.                                                       
      *                                                                 
      *                                                                 
      *----------------------------------------------------------------*
       3000-FIND-NEXT-AUTH-DTL.                                         
      *----------------------------------------------------------------*
      *                                                                 
      *     DISPLAY 'IN 3000 READ CHILD SEGMENT PARA'                   
            CALL 'CBLTDLI'            USING  FUNC-GNP                   
                                        PAUTBPCB                        
                                        PENDING-AUTH-DETAILS            
                                        CHILD-UNQUAL-SSA.               
      *        DISPLAY '***************************'                    
      *        DISPLAY ' AFTER CHILD SEG IMS CALL  '                    
      *        DISPLAY 'PCB STATU: ' PAUT-PCB-STATUS                    
      *        DISPLAY 'SEG NAME   : ' PAUT-SEG-NAME                    
      *        DISPLAY '***************************'                    
               IF PAUT-PCB-STATUS = SPACES                              
                    SET MORE-AUTHS       TO TRUE                        
                    ADD 1                 TO WS-NO-SUMRY-READ           
                    ADD 1                 TO WS-AUTH-SMRY-PROC-CNT      
                    MOVE PENDING-AUTH-DETAILS TO CHILD-SEG-REC          
                    WRITE OPFIL2-REC                                    
               END-IF                                                   
               IF PAUT-PCB-STATUS = 'GE'                                
      *             SET NO-MORE-AUTHS    TO TRUE                        
                    MOVE 'Y' TO WS-END-OF-CHILD-SEG                     
                    DISPLAY 'CHILD SEG FLAG GE : '                      
                             WS-END-OF-CHILD-SEG                        
               END-IF                                                   
               IF PAUT-PCB-STATUS NOT EQUAL TO  SPACES AND 'GE'         
                  DISPLAY 'GNP CALL FAILED  :' PAUT-PCB-STATUS          
                  DISPLAY 'KFB AREA IN CHILD:' PAUT-KEYFB               
                    PERFORM 9999-ABEND                                  
               END-IF.                                                  
               INITIALIZE PAUT-PCB-STATUS.                              
       3000-EXIT.                                                       
            EXIT.                                                       
      *                                                                 
      *----------------------------------------------------------------*
       4000-FILE-CLOSE.                                                 
            DISPLAY 'CLOSING THE FILE'                                  
            CLOSE OPFILE1.                                              
                                                                        
            IF WS-OUTFL1-STATUS =  SPACES OR '00'                       
             CONTINUE                                                   
            ELSE                                                        
             DISPLAY 'ERROR IN CLOSING 1ST FILE:'WS-OUTFL1-STATUS       
            END-IF.                                                     
            CLOSE OPFILE2.                                              
                                                                        
            IF WS-OUTFL2-STATUS =  SPACES OR '00'                       
             CONTINUE                                                   
            ELSE                                                        
             DISPLAY 'ERROR IN CLOSING 2ND FILE:'WS-OUTFL2-STATUS       
            END-IF.                                                     
       4000-EXIT.                                                       
            EXIT.                                                       
      *----------------------------------------------------------------*
       9999-ABEND.                                                      
      *----------------------------------------------------------------*
      *                                                                 
           DISPLAY 'IMSUNLOD ABENDING ...'                              
                                                                        
           MOVE 16 TO RETURN-CODE                                       
           GOBACK.                                                      
      *                                                                 
       9999-EXIT.                                                       
            EXIT.                                                       
