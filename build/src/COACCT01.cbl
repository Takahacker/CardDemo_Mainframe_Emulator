000100 IDENTIFICATION DIVISION.                                         
000200 PROGRAM-ID.           COACCT01 IS INITIAL.                       
000300 AUTHOR.               AWS.                                       
000400 DATE-WRITTEN.         03/21.                                     
000500 DATE-COMPILED.                                                   
000600                                                                  
000700 ENVIRONMENT DIVISION.                                            
000800                                                                  
000900 DATA DIVISION.                                                   
001000                                                                  
001100 WORKING-STORAGE SECTION.                                         
001700                                                                  
001800 01 WS-MQ-MSG-FLAG                PIC X(01) VALUE 'N'.            
001900    88  NO-MORE-MSGS              VALUE 'Y'.                      
002000                                                                  
002100 01 WS-RESP-QUEUE-STS            PIC X(01) VALUE 'N'.             
002200    88  RESP-QUEUE-OPEN          VALUE 'Y'.                       
002300                                                                  
002400 01 WS-ERR-QUEUE-STS             PIC X(01) VALUE 'N'.             
002500    88  ERR-QUEUE-OPEN          VALUE 'Y'.                        
002600                                                                  
002700 01 WS-REPLY-QUEUE-STS           PIC X(01) VALUE 'N'.             
002800    88  REPLY-QUEUE-OPEN         VALUE 'Y'.                       
002900                                                                  
003700                                                                  
003800 01 WS-CICS-RESP-CDS.                                             
003900    05  WS-CICS-RESP1-CD        PIC S9(08) COMP VALUE ZERO.       
004000    05  WS-CICS-RESP2-CD        PIC S9(08) COMP VALUE ZERO.       
004300    05  WS-CICS-RESP1-CD-D      PIC 9(08) VALUE ZERO.             
004400    05  WS-CICS-RESP2-CD-D      PIC 9(08) VALUE ZERO.             
004500                                                                  
004600***********************************************                   
004700**             DATE FIELDS                   **                   
004800***********************************************                   
004900 01 WS-DATE-TIME.                                                 
005000    10 WS-ABS-TIME                  PIC S9(15) COMP-3 VALUE ZERO. 
005100    10 WS-MMDDYYYY                  PIC X(10) VALUE SPACES.       
005200    10 WS-TIME                      PIC X(8)  VALUE SPACES.       
004600***********************************************                   
004700**             MQ FIELDS                     **                   
004800***********************************************                   
005000 01 MQ-QUEUE                        PIC X(48).                    
005100 01 MQ-QUEUE-REPLY                  PIC X(48).                    
005200 01 MQ-HCONN                        PIC S9(09) BINARY VALUE 0.    
005300 01 MQ-CONDITION-CODE               PIC S9(09) BINARY VALUE 0.    
005400 01 MQ-REASON-CODE                  PIC S9(09) BINARY VALUE 0.    
005500 01 MQ-HOBJ                         PIC S9(09) BINARY VALUE 0.    
005600 01 MQ-OPTIONS                      PIC S9(09) BINARY VALUE 0.    
005700 01 MQ-BUFFER-LENGTH                PIC S9(09) BINARY.            
005800 01 MQ-BUFFER                       PIC X(1000).                  
005900 01 MQ-DATA-LENGTH                  PIC S9(09) BINARY.            
006000 01 MQ-CORRELID                     PIC X(24).                    
006100 01 MQ-MSG-ID                       PIC X(24).                    
006200 01 MQ-MSG-COUNT                    PIC 9(09).                    
006300 01 SAVE-CORELID                    PIC X(24).                    
006400 01 SAVE-MSGID                      PIC X(24).                    
006500 01 SAVE-REPLY2Q                    PIC X(48).                    
006600 01 MQ-ERR-DISPLAY.                                               
006700     05 MQ-ERROR-PARA                   PIC X(25) .               
006800     05 FILLER                          PIC X(02) VALUE SPACES.   
006900     05 MQ-APPL-RETURN-MESSAGE          PIC X(25).                
007000     05 FILLER                          PIC X(02) VALUE SPACES.   
007100     05 MQ-APPL-CONDITION-CODE          PIC 9(02).                
007200     05 FILLER                          PIC X(02) VALUE SPACES.   
007300     05 MQ-APPL-REASON-CODE             PIC 9(05).                
007400     05 FILLER                          PIC X(02) VALUE SPACES.   
007500     05 MQ-APPL-QUEUE-NAME              PIC X(48).                
007600                                                                  
007700                                                                  
007800 01 MQ-GET-MESSAGE-OPTIONS.                                       
007900 COPY CMQGMOV.                                                    
008000                                                                  
008100                                                                  
008200 01 MQ-PUT-MESSAGE-OPTIONS.                                       
008300 COPY CMQPMOV.                                                    
008400                                                                  
008500                                                                  
008600 01 MQ-MESSAGE-DESCRIPTOR.                                        
008700 COPY CMQMDV.                                                     
008800                                                                  
008900                                                                  
009000 01 MQ-OBJECT-DESCRIPTOR.                                         
009100 COPY CMQODV.                                                     
009200                                                                  
009300                                                                  
009400 01 MQ-CONSTANTS.                                                 
009500 COPY CMQV.                                                       
009600                                                                  
009700 01 MQ-GET-QUEUE-MESSAGE.                                         
009800 COPY CMQTML.                                                     
009900                                                                  
010000 01  QUEUE-INFO.                                                  
010100     05 QMGR-NAME                   PIC X(48) VALUE SPACES.       
010200     05 INPUT-QUEUE-NAME            PIC X(48) VALUE SPACES.       
010300     05 REPLY-QUEUE-NAME            PIC X(48) VALUE SPACES.       
010400     05 ERROR-QUEUE-NAME            PIC X(48) VALUE SPACES.       
010500                                                                  
010600 01 INPUT-QUEUE-HANDLE              PIC S9(09) BINARY VALUE 0.    
010700                                                                  
010800 01 OUTPUT-QUEUE-HANDLE             PIC S9(09) BINARY VALUE 0.    
010900                                                                  
011000 01 ERROR-QUEUE-HANDLE              PIC S9(09) BINARY VALUE 0.    
011100                                                                  
011200 01 QMGR-HANDLE-CONN                PIC S9(09) BINARY VALUE 0.    
011300 01 QUEUE-MESSAGE                   PIC X(1000).                  
011400 01 REQUEST-MESSAGE                 PIC X(1000).                  
011500 01 REPLY-MESSAGE                   PIC X(1000).                  
011600 01 ERROR-MESSAGE                   PIC X(1000).                  
011700 01 REQUEST-MSG-COPY.                                             
011700    10 WS-FUNC                      PIC X(04) VALUE SPACES.       
011700    10 WS-KEY                       PIC 9(11) VALUE ZEROES.       
011700    10 WS-FILLER                    PIC X(985) VALUE SPACES.      
011800                                                                  
       01 WS-VARIABLES.                                                 
          05 LIT-ACCTFILENAME                      PIC X(8)             
                                                   VALUE 'ACCTDAT '.    
          05 WS-RESP-CD                          PIC S9(09) COMP        
                                                   VALUE ZEROS.         
          05 WS-REAS-CD                          PIC S9(09) COMP        
                                                   VALUE ZEROS.         
         05  WS-XREF-RID.                                               
           10  WS-CARD-RID-CARDNUM                 PIC X(16).           
           10  WS-CARD-RID-CUST-ID                 PIC 9(09).           
           10  WS-CARD-RID-CUST-ID-X REDEFINES                          
                  WS-CARD-RID-CUST-ID              PIC X(09).           
           10  WS-CARD-RID-ACCT-ID                 PIC 9(11).           
           10  WS-CARD-RID-ACCT-ID-X REDEFINES                          
                  WS-CARD-RID-ACCT-ID              PIC X(11).           
                                                                        
       01 WS-ACCT-RESPONSE.                                             
                                                                        
           05  WS-ACCT-LBL                       PIC X(13) VALUE        
                                                     'ACCOUNT ID : '.   
           05  WS-ACCT-ID                        PIC 9(11) VALUE ZEROES.
           05  WS-STATUS-LBL                     PIC X(17) VALUE        
                                                'ACCOUNT STATUS : '.    
           05  WS-ACCT-ACTIVE-STATUS             PIC X(01) VALUE SPACES.
           05  WS-CURR-BAL-LBL                   PIC X(10) VALUE        
                                                     'BALANCE : '.      
           05  WS-ACCT-CURR-BAL                  PIC S9(10)V99          
                                                           VALUE ZEROES.
           05  WS-CRDT-LMT-LBL                   PIC X(15) VALUE        
                                                 'CREDIT LIMIT : '.     
           05  WS-ACCT-CREDIT-LIMIT              PIC S9(10)V99          
                                                           VALUE ZEROES.
           05  WS-CASH-LIMIT-LBL                 PIC X(13) VALUE        
                                                 'CASH LIMIT : '.       
           05  WS-ACCT-CASH-CREDIT-LIMIT         PIC S9(10)V99          
                                                           VALUE ZEROES.
           05  WS-OPEN-DATE-LBL                  PIC X(12) VALUE        
                                                 'OPEN DATE : '.        
           05  WS-ACCT-OPEN-DATE                 PIC X(10) VALUE SPACES.
           05  WS-EXPR-DATE-LBL                  PIC X(12) VALUE        
                                                 'EXPR DATE : '.        
           05  WS-ACCT-EXPIRAION-DATE            PIC X(10) VALUE SPACES.
           05  WS-REISSUE-DT-LBL                 PIC X(12) VALUE        
                                                 'REIS DATE : '.        
           05  WS-ACCT-REISSUE-DATE              PIC X(10) VALUE SPACES.
           05  WS-CURR-CYC-CREDIT-LBL            PIC X(13) VALUE        
                                                 'CREDIT BAL : '.       
           05  WS-ACCT-CURR-CYC-CREDIT           PIC S9(10)V99          
                                                           VALUE ZEROES.
           05  WS-CURR-CYC-DEBIT-LBL             PIC X(12) VALUE        
                                                 'DEBIT BAL : '.        
           05  WS-ACCT-CURR-CYC-DEBIT            PIC S9(10)V99          
                                                           VALUE ZEROES.
           05  WS-ACCT-GRP-LBL                   PIC X(11) VALUE        
                                                 'GROUP ID : '.         
           05  WS-ACCT-GROUP-ID                  PIC X(10) VALUE SPACES.
      *ACCOUNT RECORD LAYOUT                                            
       COPY CVACT01Y.                                                   
                                                                        
011900                                                                  
012000 LINKAGE SECTION.                                                 
       COPY DFHEIBLK.
012100                                                                  
       01  DFHCOMMAREA PIC X(1).
       PROCEDURE DIVISION USING DFHEIBLK DFHCOMMAREA.
012300                                                                  
012400 1000-CONTROL.                                                    
012500                                                                  
013600      MOVE SPACES TO                                              
013700                    INPUT-QUEUE-NAME                              
013800                    QMGR-NAME                                     
013900                    QUEUE-MESSAGE                                 
014000                                                                  
014100      INITIALIZE MQ-ERR-DISPLAY                                   
014200                                                                  
014600     PERFORM 2100-OPEN-ERROR-QUEUE                                
015300******************************************************************
015400* GET THE QUEUE NAME WHICH STARTED THE TRANSACTION               *
015500******************************************************************
      *KIX  EXEC CICS RETRIEVE INTO(MQTM) RESP(WS-CICS-RESP1-CD) RESP2(W
           CALL "KIXCMD" USING
               BY CONTENT "RETRIEVE|INTO=|RESP=|RESP2="
               BY REFERENCE MQTM
               BY REFERENCE WS-CICS-RESP1-CD
               BY REFERENCE WS-CICS-RESP2-CD
           END-CALL
016100     IF WS-CICS-RESP1-CD =  0                       
016200       MOVE MQTM-QNAME  TO INPUT-QUEUE-NAME                       
016300       MOVE 'CARD.DEMO.REPLY.ACCT' TO REPLY-QUEUE-NAME            
016400     ELSE                                                         
016500       MOVE 'CICS RETREIVE' TO MQ-ERROR-PARA                      
016600       MOVE WS-CICS-RESP1-CD TO WS-CICS-RESP1-CD-D                
016700       MOVE WS-CICS-RESP2-CD TO WS-CICS-RESP2-CD                  
016800       STRING 'RESP: ', WS-CICS-RESP1-CD-D , WS-CICS-RESP2-CD-D,  
016900              'END' DELIMITED BY SIZE                             
017000              INTO MQ-APPL-RETURN-MESSAGE                         
017100       END-STRING                                                 
017200                                                                  
             PERFORM 9000-ERROR                                         
017400       PERFORM 8000-TERMINATION                                   
017500     END-IF                                                       
014500                                                                  
014800     PERFORM 2300-OPEN-INPUT-QUEUE                                
014900     PERFORM 2400-OPEN-OUTPUT-QUEUE                               
012700     PERFORM 3000-GET-REQUEST                                     
012800     PERFORM 4000-MAIN-PROCESS UNTIL                              
012900             NO-MORE-MSGS                                         
013000                                                                  
013100     PERFORM 8000-TERMINATION.                                    
013200                                                                  
015000     .                                                            
015100                                                                  
017800 2300-OPEN-INPUT-QUEUE.                                           
017900* OPEN-INPUT WILL OPEN A QUEUE FOR GET PROCESSING                 
018000                                                                  
018400                                                                  
018500     MOVE SPACES           TO MQOD-OBJECTQMGRNAME                 
018600     MOVE INPUT-QUEUE-NAME TO MQOD-OBJECTNAME                     
018700                                                                  
018800     COMPUTE MQ-OPTIONS = MQOO-INPUT-SHARED                       
018900                        + MQOO-SAVE-ALL-CONTEXT                   
019000                        + MQOO-FAIL-IF-QUIESCING                  
019100                                                                  
019200     CALL 'MQOPEN' USING QMGR-HANDLE-CONN                         
019300                         MQ-OBJECT-DESCRIPTOR                     
019400                         MQ-OPTIONS                               
019500                         MQ-HOBJ                                  
019600                         MQ-CONDITION-CODE                        
019700                         MQ-REASON-CODE                           
019800                                                                  
019900     EVALUATE MQ-CONDITION-CODE                                   
020000         WHEN MQCC-OK                                             
020100              MOVE MQ-CONDITION-CODE TO MQ-APPL-CONDITION-CODE    
020200              MOVE MQ-REASON-CODE    TO MQ-APPL-REASON-CODE       
020300              MOVE MQ-HOBJ           TO INPUT-QUEUE-HANDLE        
020400              SET  REPLY-QUEUE-OPEN  TO TRUE                      
020500         WHEN OTHER                                               
020600              MOVE MQ-CONDITION-CODE TO MQ-APPL-CONDITION-CODE    
020700              MOVE MQ-REASON-CODE    TO MQ-APPL-REASON-CODE       
020800              MOVE INPUT-QUEUE-NAME  TO MQ-APPL-QUEUE-NAME        
020900              MOVE 'INP MQOPEN ERR'  TO MQ-APPL-RETURN-MESSAGE    
021000              PERFORM 9000-ERROR                                  
021100              PERFORM 8000-TERMINATION                            
021200     END-EVALUATE.                                                
021300                                                                  
021400 2400-OPEN-OUTPUT-QUEUE.                                          
021500                                                                  
021600* OPEN-OUTPUT WILL OPEN A QUEUE FOR PUT PROCESSING                
021700                                                                  
022100                                                                  
022200     MOVE SPACES            TO MQOD-OBJECTQMGRNAME                
022300     MOVE REPLY-QUEUE-NAME  TO MQOD-OBJECTNAME                    
022400                                                                  
022500     COMPUTE MQ-OPTIONS = MQOO-OUTPUT                             
022600                        + MQOO-PASS-ALL-CONTEXT                   
022700                        + MQOO-FAIL-IF-QUIESCING                  
022800                                                                  
022900     CALL 'MQOPEN' USING QMGR-HANDLE-CONN                         
023000                         MQ-OBJECT-DESCRIPTOR                     
023100                         MQ-OPTIONS                               
023200                         MQ-HOBJ                                  
023300                         MQ-CONDITION-CODE                        
023400                         MQ-REASON-CODE                           
023500                                                                  
023600     EVALUATE MQ-CONDITION-CODE                                   
023700         WHEN MQCC-OK                                             
023800              MOVE MQ-CONDITION-CODE TO MQ-APPL-CONDITION-CODE    
023900              MOVE MQ-REASON-CODE    TO MQ-APPL-REASON-CODE       
024000              MOVE MQ-HOBJ           TO OUTPUT-QUEUE-HANDLE       
024100              SET  RESP-QUEUE-OPEN   TO TRUE                      
024200         WHEN OTHER                                               
024300              MOVE MQ-CONDITION-CODE TO MQ-APPL-CONDITION-CODE    
024400              MOVE MQ-REASON-CODE    TO MQ-APPL-REASON-CODE       
024500              MOVE REPLY-QUEUE-NAME  TO MQ-APPL-QUEUE-NAME        
024600              MOVE 'OUT MQOPEN ERR'  TO MQ-APPL-RETURN-MESSAGE    
024700              PERFORM 9000-ERROR                                  
024800              PERFORM 8000-TERMINATION                            
024900     END-EVALUATE.                                                
025000                                                                  
025100 2100-OPEN-ERROR-QUEUE.                                           
025200                                                                  
025300* OPEN-OUTPUT WILL OPEN A QUEUE FOR PUT PROCESSING                
025400                                                                  
025800                                                                  
025900     MOVE 'CARD.DEMO.ERROR' TO ERROR-QUEUE-NAME                   
026000     MOVE SPACES            TO MQOD-OBJECTQMGRNAME                
026100     MOVE ERROR-QUEUE-NAME  TO MQOD-OBJECTNAME                    
026200                                                                  
026300     COMPUTE MQ-OPTIONS = MQOO-OUTPUT                             
026400                        + MQOO-PASS-ALL-CONTEXT                   
026500                        + MQOO-FAIL-IF-QUIESCING                  
026600                                                                  
026700     CALL 'MQOPEN' USING QMGR-HANDLE-CONN                         
026800                         MQ-OBJECT-DESCRIPTOR                     
026900                         MQ-OPTIONS                               
027000                         MQ-HOBJ                                  
027100                         MQ-CONDITION-CODE                        
027200                         MQ-REASON-CODE                           
027300                                                                  
027400     EVALUATE MQ-CONDITION-CODE                                   
027500         WHEN MQCC-OK                                             
027600              MOVE MQ-CONDITION-CODE TO MQ-APPL-CONDITION-CODE    
027700              MOVE MQ-REASON-CODE    TO MQ-APPL-REASON-CODE       
027800              MOVE MQ-HOBJ           TO ERROR-QUEUE-HANDLE        
027900              SET  ERR-QUEUE-OPEN   TO TRUE                       
028000         WHEN OTHER                                               
028100              MOVE MQ-CONDITION-CODE TO MQ-APPL-CONDITION-CODE    
028200              MOVE MQ-REASON-CODE    TO MQ-APPL-REASON-CODE       
028300              MOVE ERROR-QUEUE-NAME  TO MQ-APPL-QUEUE-NAME        
028400              MOVE 'ERR MQOPEN ERR'  TO MQ-APPL-RETURN-MESSAGE    
028500              DISPLAY MQ-ERR-DISPLAY                              
028600              PERFORM 8000-TERMINATION                            
028700     END-EVALUATE.                                                
028800                                                                  
028900                                                                  
029000 4000-MAIN-PROCESS.                                               
      *KIX  EXEC CICS SYNCPOINT
           CALL "KIXCMD" USING
               BY CONTENT "SYNCPOINT"
           END-CALL
029400                                                                  
029500     PERFORM 3000-GET-REQUEST                                     
029600     .                                                            
029700                                                                  
029800                                                                  
029900 3000-GET-REQUEST.                                                
030000* GET WILL GET A MESSAGE FROM THE QUEUE                           
030700*** ADDED 5000 MS (5 SECS) AS THE WAIT INTERVAL FOR GET           
030800     MOVE 5000                            TO MQGMO-WAITINTERVAL   
030900     MOVE SPACES                          TO MQ-CORRELID          
031000     MOVE SPACES                          TO MQ-MSG-ID            
031100     MOVE INPUT-QUEUE-NAME                TO MQ-QUEUE             
031200     MOVE INPUT-QUEUE-HANDLE              TO MQ-HOBJ              
031300     MOVE 1000                            TO MQ-BUFFER-LENGTH     
031400     MOVE MQMI-NONE         TO MQMD-MSGID                         
031500     MOVE MQCI-NONE         TO MQMD-CORRELID                      
031500     INITIALIZE REQUEST-MSG-COPY  REPLACING NUMERIC BY ZEROES     
031600                                                                  
031700     COMPUTE MQGMO-OPTIONS = MQGMO-SYNCPOINT                      
031800                           + MQGMO-FAIL-IF-QUIESCING              
031900                           + MQGMO-CONVERT                        
032000                           + MQGMO-WAIT                           
032100                                                                  
032200     CALL 'MQGET'  USING MQ-HCONN                                 
032300                         MQ-HOBJ                                  
032400                         MQ-MESSAGE-DESCRIPTOR                    
032500                         MQ-GET-MESSAGE-OPTIONS                   
032600                         MQ-BUFFER-LENGTH                         
032700                         MQ-BUFFER                                
032800                         MQ-DATA-LENGTH                           
032900                         MQ-CONDITION-CODE                        
033000                         MQ-REASON-CODE                           
033100                                                                  
033200                                                                  
033300     IF MQ-CONDITION-CODE = MQCC-OK                               
033400        MOVE MQMD-MSGID        TO MQ-MSG-ID                       
033500        MOVE MQMD-CORRELID     TO MQ-CORRELID                     
033600        MOVE MQMD-REPLYTOQ     TO MQ-QUEUE-REPLY                  
033700        MOVE MQ-CONDITION-CODE TO MQ-APPL-CONDITION-CODE          
033800        MOVE MQ-REASON-CODE    TO MQ-APPL-REASON-CODE             
033900        MOVE MQ-BUFFER         TO REQUEST-MESSAGE                 
034000        MOVE MQ-CORRELID       TO SAVE-CORELID                    
034100        MOVE MQ-QUEUE-REPLY    TO SAVE-REPLY2Q                    
034200        MOVE MQ-MSG-ID         TO SAVE-MSGID                      
034300        MOVE REQUEST-MESSAGE   TO REQUEST-MSG-COPY                
034400        PERFORM 4000-PROCESS-REQUEST-REPLY                        
034500        ADD  1                 TO MQ-MSG-COUNT                    
034600     ELSE                                                         
034700        IF MQ-REASON-CODE  =  MQRC-NO-MSG-AVAILABLE               
034800          SET NO-MORE-MSGS             TO  TRUE                   
034900                                                                  
035000        ELSE                                                      
035100           MOVE MQ-CONDITION-CODE TO MQ-APPL-CONDITION-CODE       
035200           MOVE MQ-REASON-CODE    TO MQ-APPL-REASON-CODE          
035300           MOVE INPUT-QUEUE-NAME  TO MQ-APPL-QUEUE-NAME           
035400           MOVE 'INP MQGET ERR:'  TO MQ-APPL-RETURN-MESSAGE       
035500           PERFORM 9000-ERROR                                     
035600           PERFORM 8000-TERMINATION                               
035700       END-IF                                                     
035800     END-IF.                                                      
035900                                                                  
036000 4000-PROCESS-REQUEST-REPLY.                                      
036100     MOVE SPACES TO REPLY-MESSAGE                                 
036100     INITIALIZE WS-DATE-TIME REPLACING NUMERIC BY ZEROES          
036100     IF WS-FUNC = 'INQA' AND WS-KEY > ZEROES                      
              MOVE WS-KEY       TO  WS-CARD-RID-ACCT-ID                 
                                                                        
      *KIX  EXEC CICS READ DATASET (LIT-ACCTFILENAME) RIDFLD (WS-CARD-RI
           CALL "KIXCMD" USING
               BY CONTENT "READ|DATASET=|RIDFLD=|KEYLENGTH=|INTO=|L"
                        & "ENGTH=|RESP=|RESP2="
               BY REFERENCE LIT-ACCTFILENAME
               BY REFERENCE WS-CARD-RID-ACCT-ID-X
               BY CONTENT LENGTH OF WS-CARD-RID-ACCT-ID-X
               BY REFERENCE ACCOUNT-RECORD
               BY CONTENT LENGTH OF ACCOUNT-RECORD
               BY REFERENCE WS-RESP-CD
               BY REFERENCE WS-REAS-CD
           END-CALL
                                                                        
           EVALUATE WS-RESP-CD                                          
               WHEN 0                                     
                    MOVE ACCT-ID          TO WS-ACCT-ID                 
                    MOVE ACCT-ACTIVE-STATUS                             
                                          TO WS-ACCT-ACTIVE-STATUS      
                    MOVE ACCT-CURR-BAL    TO WS-ACCT-CURR-BAL           
                    MOVE ACCT-CREDIT-LIMIT                              
                                          TO WS-ACCT-CREDIT-LIMIT       
                    MOVE ACCT-CASH-CREDIT-LIMIT                         
                                          TO WS-ACCT-CASH-CREDIT-LIMIT  
                    MOVE ACCT-OPEN-DATE   TO WS-ACCT-OPEN-DATE          
                    MOVE ACCT-EXPIRAION-DATE                            
                                          TO WS-ACCT-EXPIRAION-DATE     
                    MOVE ACCT-REISSUE-DATE                              
                                          TO WS-ACCT-REISSUE-DATE       
                    MOVE ACCT-CURR-CYC-CREDIT                           
                                          TO WS-ACCT-CURR-CYC-CREDIT    
                    MOVE ACCT-CURR-CYC-DEBIT                            
                                          TO WS-ACCT-CURR-CYC-DEBIT     
                    MOVE ACCT-GROUP-ID    TO WS-ACCT-GROUP-ID           
                    MOVE WS-ACCT-RESPONSE TO REPLY-MESSAGE              
                    PERFORM 4100-PUT-REPLY                              
               WHEN 13                                     
                    STRING 'INVALID REQUEST PARAMETERS '                
                           'ACCT ID : 'WS-KEY                           
                           DELIMITED BY SIZE                            
                           INTO                                         
                           REPLY-MESSAGE                                
                    END-STRING                                          
                    PERFORM 4100-PUT-REPLY                              
      *                                                                 
               WHEN OTHER                                               
017200                                                                  
035100           MOVE WS-RESP-CD        TO MQ-APPL-CONDITION-CODE       
035200           MOVE WS-REAS-CD        TO MQ-APPL-REASON-CODE          
035300           MOVE INPUT-QUEUE-NAME  TO MQ-APPL-QUEUE-NAME           
035400           MOVE 'ERROR WHILE READING ACCTFILE'                    
035400                                  TO MQ-APPL-RETURN-MESSAGE       
                  PERFORM 9000-ERROR                                    
017400            PERFORM 8000-TERMINATION                              
      *           PERFORM SEND-LONG-TEXT                                
           END-EVALUATE                                                 
           ELSE                                                         
                    STRING 'INVALID REQUEST PARAMETERS '                
                           'ACCT ID : 'WS-KEY                           
                           'FUNCTION : 'WS-FUNC                         
                           DELIMITED BY SIZE                            
                           INTO                                         
                           REPLY-MESSAGE                                
                    END-STRING                                          
                    PERFORM 4100-PUT-REPLY                              
036100     END-IF                                                       
036100                                                                  
036100                                                                  
036800     .                                                            
036900                                                                  
037000 4100-PUT-REPLY.                                                  
037100                                                                  
037200* PUT WILL PUT A MESSAGE ON THE QUEUE AND CONVERT IT TO A STRING  
037300                                                                  
037600                                                                  
037700     MOVE REPLY-MESSAGE                TO MQ-BUFFER               
037800     MOVE 1000                         TO MQ-BUFFER-LENGTH        
037900     MOVE SAVE-MSGID                   TO MQMD-MSGID              
038000     MOVE SAVE-CORELID                 TO MQMD-CORRELID           
038100     MOVE MQFMT-STRING                 TO MQMD-FORMAT             
038200                                                                  
038300     COMPUTE MQMD-CODEDCHARSETID      =  MQCCSI-Q-MGR             
038400                                                                  
038500     COMPUTE MQPMO-OPTIONS = MQPMO-SYNCPOINT                      
038600                           + MQPMO-DEFAULT-CONTEXT                
038700                           + MQPMO-FAIL-IF-QUIESCING              
038800                                                                  
038900     CALL 'MQPUT'  USING MQ-HCONN                                 
039000                         OUTPUT-QUEUE-HANDLE                      
039100                         MQ-MESSAGE-DESCRIPTOR                    
039200                         MQ-PUT-MESSAGE-OPTIONS                   
039300                         MQ-BUFFER-LENGTH                         
039400                         MQ-BUFFER                                
039500                         MQ-CONDITION-CODE                        
039600                         MQ-REASON-CODE                           
039700                                                                  
039800     EVALUATE MQ-CONDITION-CODE                                   
039900         WHEN MQCC-OK                                             
040000              MOVE MQ-CONDITION-CODE TO MQ-APPL-CONDITION-CODE    
040100              MOVE MQ-REASON-CODE    TO MQ-APPL-REASON-CODE       
040200         WHEN OTHER                                               
040300              MOVE MQ-CONDITION-CODE TO MQ-APPL-CONDITION-CODE    
040400              MOVE MQ-REASON-CODE    TO MQ-APPL-REASON-CODE       
040500              MOVE REPLY-QUEUE-NAME  TO MQ-APPL-QUEUE-NAME        
040600              MOVE 'MQPUT ERR'       TO MQ-APPL-RETURN-MESSAGE    
040700              PERFORM 9000-ERROR                                  
040800              PERFORM 8000-TERMINATION                            
040900     END-EVALUATE.                                                
041000                                                                  
041100 9000-ERROR.                                                      
041200* PUT WILL PUT A MESSAGE ON THE QUEUE AND CONVERT IT TO A STRING  
041300                                                                  
041600                                                                  
041700     MOVE MQ-ERR-DISPLAY               TO ERROR-MESSAGE,          
041800     MOVE ERROR-MESSAGE                TO MQ-BUFFER               
041900     MOVE 1000                         TO MQ-BUFFER-LENGTH        
042200     MOVE MQFMT-STRING                 TO MQMD-FORMAT             
042300                                                                  
042400     COMPUTE MQMD-CODEDCHARSETID      =  MQCCSI-Q-MGR             
042500                                                                  
042600     COMPUTE MQPMO-OPTIONS = MQPMO-SYNCPOINT                      
042700                           + MQPMO-DEFAULT-CONTEXT                
042800                           + MQPMO-FAIL-IF-QUIESCING              
042900                                                                  
043000     CALL 'MQPUT'  USING MQ-HCONN                                 
043100                         ERROR-QUEUE-HANDLE                       
043200                         MQ-MESSAGE-DESCRIPTOR                    
043300                         MQ-PUT-MESSAGE-OPTIONS                   
043400                         MQ-BUFFER-LENGTH                         
043500                         MQ-BUFFER                                
043600                         MQ-CONDITION-CODE                        
043700                         MQ-REASON-CODE                           
043800                                                                  
043900     EVALUATE MQ-CONDITION-CODE                                   
044000         WHEN MQCC-OK                                             
044100              MOVE MQ-CONDITION-CODE TO MQ-APPL-CONDITION-CODE    
044200              MOVE MQ-REASON-CODE    TO MQ-APPL-REASON-CODE       
044300         WHEN OTHER                                               
044400              MOVE MQ-CONDITION-CODE TO MQ-APPL-CONDITION-CODE    
044500              MOVE MQ-REASON-CODE    TO MQ-APPL-REASON-CODE       
044600              MOVE ERROR-QUEUE-NAME  TO MQ-APPL-QUEUE-NAME        
044700              MOVE 'MQPUT ERR'       TO MQ-APPL-RETURN-MESSAGE    
044800              DISPLAY MQ-ERR-DISPLAY                              
044900              PERFORM 8000-TERMINATION                            
045000     END-EVALUATE.                                                
045100     .                                                            
045200 8000-TERMINATION.                                                
045300                                                                  
045400     IF REPLY-QUEUE-OPEN                                          
045500        PERFORM 5000-CLOSE-INPUT-QUEUE                            
045600     END-IF                                                       
045700     IF RESP-QUEUE-OPEN                                           
045800        PERFORM 5100-CLOSE-OUTPUT-QUEUE                           
045900     END-IF                                                       
046000     IF ERR-QUEUE-OPEN                                            
046100        PERFORM 5200-CLOSE-ERROR-QUEUE                            
046200     END-IF                                                       
      *KIX  EXEC CICS RETURN
           CALL "KIXCMD" USING
               BY CONTENT "RETURN"
           END-CALL
           GOBACK
046400     GOBACK.                                                      
046500                                                                  
046600 5000-CLOSE-INPUT-QUEUE.                                          
046700     MOVE INPUT-QUEUE-NAME           TO MQ-QUEUE                  
046800     MOVE INPUT-QUEUE-HANDLE         TO MQ-HOBJ                   
046900     COMPUTE MQ-OPTIONS = MQCO-NONE                               
047000                                                                  
047100     CALL 'MQCLOSE' USING MQ-HCONN                                
047200                          MQ-HOBJ                                 
047300                          MQ-OPTIONS                              
047400                          MQ-CONDITION-CODE                       
047500                          MQ-REASON-CODE                          
047600                                                                  
047700     EVALUATE MQ-CONDITION-CODE                                   
047800         WHEN MQCC-OK                                             
047900              MOVE MQ-CONDITION-CODE TO MQ-APPL-CONDITION-CODE    
048000              MOVE MQ-REASON-CODE    TO MQ-APPL-REASON-CODE       
048100         WHEN OTHER                                               
048200              MOVE MQ-CONDITION-CODE TO MQ-APPL-CONDITION-CODE    
048300              MOVE MQ-REASON-CODE    TO MQ-APPL-REASON-CODE       
048400              MOVE INPUT-QUEUE-NAME  TO MQ-APPL-QUEUE-NAME        
048500              MOVE 'MQCLOSE ERR'     TO MQ-APPL-RETURN-MESSAGE    
048600              PERFORM 8000-TERMINATION                            
048700     END-EVALUATE.                                                
048800 5100-CLOSE-OUTPUT-QUEUE.                                         
048900     MOVE REPLY-QUEUE-NAME            TO MQ-QUEUE                 
049000     MOVE OUTPUT-QUEUE-HANDLE         TO MQ-HOBJ                  
049100     COMPUTE MQ-OPTIONS = MQCO-NONE                               
049200                                                                  
049300     CALL 'MQCLOSE' USING MQ-HCONN                                
049400                          MQ-HOBJ                                 
049500                          MQ-OPTIONS                              
049600                          MQ-CONDITION-CODE                       
049700                          MQ-REASON-CODE                          
049800                                                                  
049900     EVALUATE MQ-CONDITION-CODE                                   
050000         WHEN MQCC-OK                                             
050100              MOVE MQ-CONDITION-CODE TO MQ-APPL-CONDITION-CODE    
050200              MOVE MQ-REASON-CODE    TO MQ-APPL-REASON-CODE       
050300         WHEN OTHER                                               
050400              MOVE MQ-CONDITION-CODE TO MQ-APPL-CONDITION-CODE    
050500              MOVE MQ-REASON-CODE    TO MQ-APPL-REASON-CODE       
050600              MOVE INPUT-QUEUE-NAME  TO MQ-APPL-QUEUE-NAME        
050700              MOVE 'MQCLOSE ERR'     TO MQ-APPL-RETURN-MESSAGE    
050800              PERFORM 8000-TERMINATION                            
050900     END-EVALUATE.                                                
051000                                                                  
051100 5200-CLOSE-ERROR-QUEUE.                                          
051200     MOVE ERROR-QUEUE-NAME          TO MQ-QUEUE                   
051300     MOVE ERROR-QUEUE-HANDLE         TO MQ-HOBJ                   
051400     COMPUTE MQ-OPTIONS = MQCO-NONE                               
051500                                                                  
051600     CALL 'MQCLOSE' USING MQ-HCONN                                
051700                          MQ-HOBJ                                 
051800                          MQ-OPTIONS                              
051900                          MQ-CONDITION-CODE                       
052000                          MQ-REASON-CODE                          
052100                                                                  
052200     EVALUATE MQ-CONDITION-CODE                                   
052300         WHEN MQCC-OK                                             
052400              MOVE MQ-CONDITION-CODE TO MQ-APPL-CONDITION-CODE    
052500              MOVE MQ-REASON-CODE    TO MQ-APPL-REASON-CODE       
052600         WHEN OTHER                                               
052700              MOVE MQ-CONDITION-CODE TO MQ-APPL-CONDITION-CODE    
052800              MOVE MQ-REASON-CODE    TO MQ-APPL-REASON-CODE       
052900              MOVE ERROR-QUEUE-NAME  TO MQ-APPL-QUEUE-NAME        
053000              MOVE 'MQCLOSE ERR'     TO MQ-APPL-RETURN-MESSAGE    
053100              PERFORM 9000-ERROR                                  
053200              PERFORM 8000-TERMINATION                            
053300     END-EVALUATE.                                                
053400                                                                  
