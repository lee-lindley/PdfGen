/*
  Author: Lee Lindley
  Date: 07/18/2021

  Copyright (C) 2021 by Lee Lindley

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

*/
--
-- General purpose logging components
-- The core is an object oriented user defined type with logging methods.
-- Since the autonomous transactions write independently, you can get status
-- of the program before "succesful" completion that might be required for dbms_output.
-- In addition to generally useful logging, it is indeispensable for debugging and development.
--
ALTER SESSION SET plsql_code_type = NATIVE;
ALTER SESSION SET plsql_optimize_level=3;
whenever sqlerror continue
DROP TYPE applog_udt;
prompt ok drop fails for type not exists
DROP VIEW applog_v;
prompt ok if drop fails for view not exists
--
DROP TABLE applog_1;
DROP TABLE applog_2;
prompt ok if drop fails for table not exists
DROP TABLE applog_app;
prompt ok if drop fails for table not exists
DROP SEQUENCE applog_app_seq;
prompt ok if drop fails for sequence not exists
--
whenever sqlerror exit failure
--
-- table will contain a record for every "application" string that is used to do logging.
-- Whenever a new application string is used, a new record will be inserted into the table by the object constructor.
--
CREATE TABLE applog_app (
     app_id     NUMBER(38) 
    ,app_name   VARCHAR2(30) NOT NULL
    ,CONSTRAINT applog_app_pk PRIMARY KEY(app_id)    --ensures not null
    -- could have simultaneous constructors firing and crossing the streams.
    -- First one will win and second will raise exception. probably never happen in my lifetime.
    ,CONSTRAINT applog_app_fk1 UNIQUE(app_name)      
);
-- no reason for large jumps. Infrequently used sequence, thus nocache.
CREATE SEQUENCE applog_app_seq NOCACHE; 
--
-- The main logging table. It does not have the app_name string in it, so a join view can make it more convenient.
-- The Procedure applog_purge_old can be run to purge older log records. See below.
--
-- Do not put any indexes or FK constraints on this. We want inserts to be cheap and fast!!!
-- Reading the table is a person doing research. They can afford full table scans.
--
-- We use two tables with a synonym to facilitate purging without interruption. You will never
-- use these two table names directly, but instead the synonym "APPLOG".
--
CREATE TABLE applog_1 (
     app_id     NUMBER(38) NOT NULL 
    ,ts         timestamp WITH LOCAL TIME ZONE
    ,msg        VARCHAR2(4000) 
);
CREATE TABLE applog_2 (
     app_id     NUMBER(38) NOT NULL 
    ,ts         timestamp WITH LOCAL TIME ZONE
    ,msg        VARCHAR2(4000) 
);
CREATE OR REPLACE SYNONYM applog FOR applog_1;
whenever sqlerror exit failure
--
-- A view to allow querying via appname.
-- It is likely more efficient to write a query as follows instead
-- SELECT ts, msg
-- FROM applog
-- WHERE app_id = (SELECT app_id FROM applog_app WHERE app_name = 'xyz');
--
CREATE OR REPLACE VIEW applog_v(app_name, app_id, ts, msg)  AS
SELECT i.app_name, a.app_id, a.ts, a.msg
FROM applog_app i
INNER JOIN applog a
    ON a.app_id = i.app_id
;
--
CREATE OR REPLACE TYPE applog_udt AS OBJECT (
/* 
    Purpose: Provide general purpose logging capability for PL/SQL applications

    Application accounts that need
    access to read tables or use the object should request grants
        GRANT SELECT ON applog_app TO you;
        GRANT SELECT ON applog TO you;
        GRANT SELECT ON applog_v TO you;
        GRANT EXECUTE ON applog_udt TO you;

    You might also consider creating public synonyms for the object, tables and views,
    or at least synonyms in your schema if different than the one to which deployed.


    Tables: applog_app -- small automatically populated lookup table app_name/app_id pairs
            applog -- all log records by app_id (actually a synonym to one of 2 base tables)
    View: applog_v -- joins on app_id to provide a view that includes the app_name string

    Type: applog_udt -- an object type with constructor and methods for performing simple logging

    Example of using this object:

        DECLARE
            -- instantiate an object instance for app_name 'bnft' which will automatically
            -- create the applog_app entry if it does not exist
            v_log_obj   applog_udt := applog_udt('bnft');
        BEGIN
            -- log a message for our app
            v_log_obj.log('whatever my message: '||sqlerrm);
            -- same but also do DBMS_OUTPUT.PUTLINE with the message too
            v_log_obj.log_p('whatever my message: '||sqlerrm);
        END;

    Example of an exception block:

        Assumes the following declarations in the program:
            g_sqlerrm                       VARCHAR2(512);
            g_backtrace                     VARCHAR2(32767);
            g_callstack                     VARCHAR2(32767); 
            g_log       applog_udt := applog_udt('my application name string');
        ...
        EXCEPTION WHEN OTHERS THEN
            g_sqlerrm := SQLERRM;
            g_backtrace := DBMS_UTILITY.FORMAT_ERROR_BACKTRACE;
            g_callstack := DBMS_UTILITY.FORMAT_CALL_STACK;
            g_log.log_p('sqlerrm    : '||g_sqlerrm);
            g_log.log_p('backtrace  : '||g_backtrace);
            g_log.log_p('callstack  : '||g_callstack);
            RAISE;

    Example of calling the static logging of a message without declaring/initializing 
    an instance of the object. Not efficient, but ok for exception blocks
        applog_udt.log('my app string', 'some message');
        applog_udt.log_p('my app string', 'some message');

*/
    app_id      NUMBER(38)
    ,app_name   VARCHAR2(30)
    -- member functions and procedures
    ,CONSTRUCTOR FUNCTION applog_udt(p_app_name VARCHAR2)
        RETURN SELF AS RESULT
    ,MEMBER PROCEDURE log(p_msg VARCHAR2)
    ,MEMBER PROCEDURE log_p(p_msg VARCHAR2) -- prints with dbms_output and then logs
    -- these are not efficient, but not so bad in an exception block.
    -- You do not have to declare a variable to hold the instance because it is temporary
    ,STATIC PROCEDURE log(p_app_name VARCHAR2, p_msg VARCHAR2 ) 
    ,STATIC PROCEDURE log_p(p_app_name VARCHAR2, p_msg VARCHAR2 ) 
);
/
--
CREATE OR REPLACE TYPE BODY applog_udt AS

    CONSTRUCTOR FUNCTION applog_udt(
        p_app_name  VARCHAR2
    )
    RETURN SELF AS RESULT
    IS
        -- we create the log messages independent from the main body who may commit or rollback separately
        PRAGMA AUTONOMOUS_TRANSACTION;
    BEGIN
        app_name := UPPER(p_app_name);
        BEGIN
            SELECT app_id INTO SELF.app_id 
            FROM applog_app 
            WHERE app_name = SELF.app_name
            ;
        EXCEPTION WHEN NO_DATA_FOUND
            THEN 
                app_id := applog_app_seq.NEXTVAL;
                INSERT INTO applog_app(app_id, app_name) VALUES (SELF.app_id, SELF.app_name));
                COMMIT;
        END;
        RETURN;
    END; -- end constructor applog_udt

    MEMBER PROCEDURE log(p_msg VARCHAR2)
    IS
        -- we create the log messages independent from the main body who may commit or rollback separately
        PRAGMA AUTONOMOUS_TRANSACTION;
    BEGIN
        -- we silently truncate the message to fit the 4000 char column
        INSERT INTO applog(app_id, ts, msg) VALUES (SELF.app_id, CURRENT_TIMESTAMP, SUBSTR(p_msg,1,4000));
        COMMIT;
    END; -- end procedure log

    MEMBER PROCEDURE log_p(p_msg VARCHAR2)
    IS
    -- log and print to console
    BEGIN
        -- note that we do not truncate the message for dbms_output
        DBMS_OUTPUT.PUT_LINE(app_name||' logmsg: '||p_msg);
        SELF.log(p_msg); 
    END; -- end procedure log_p


    STATIC PROCEDURE log(p_app_name VARCHAR2, p_msg VARCHAR2)
    IS
        l applog_udt := applog_udt(p_app_name);
    BEGIN
        l.log(p_msg);
    END
    ;
    STATIC PROCEDURE log_p(p_app_name VARCHAR2, p_msg VARCHAR2)
    IS
        l applog_udt := applog_udt(p_app_name);
    BEGIN
        l.log_p(p_msg);
    END
    ;

END;
/
show errors
--
ALTER SESSION SET plsql_code_type = INTERPRETED;
ALTER SESSION SET plsql_optimize_level=2;
--
whenever sqlerror exit failure
CREATE OR REPLACE PROCEDURE applog_purge_old(p_days NUMBER := 90)
AS
    v_log_obj   applog_udt := applog_udt('applog');
    v_which_table   VARCHAR2(128); -- 30 is true max, but many dba tables allow 128
    v_dest_table    VARCHAR2(128);
    v_rows          BINARY_INTEGER;
BEGIN
    v_log_obj.log_p('Procedure applog_purge_old called with arg p_days='||TO_CHAR(p_days));

    --
    -- Figure out which base table is currently being written to
    --
    SELECT table_name INTO v_which_table
    FROM user_synonyms
    WHERE synonym_name = 'APPLOG'
    ;
    --
    -- The one we are going to truncate and write to next is the other one
    --
    v_dest_table := CASE WHEN v_which_table = 'APPLOG_1' 
                         THEN 'APPLOG_2' 
                         ELSE 'APPLOG_1'
                    END;
    EXECUTE IMMEDIATE 'TRUNCATE TABLE '||v_dest_table;
    v_log_obj.log_p('truncated table '||v_dest_table);
    --
    -- Here is the magic. We swap the synonym. That means any
    -- new writes via the applog_udt object will insert into the 
    -- new destination table (which is currently empty) and no longer write to the
    -- old table. This takes care of any writes that are going on while we are performing
    -- the rest of this task and prevents any blocking that might otherwise happen
    -- from our activity
    --
    EXECUTE IMMEDIATE 'CREATE OR REPLACE SYNONYM applog FOR '||v_dest_table;
    --
    -- copy from the prior table any records less than X days old.
    -- The old table stays there and still has the "about to be forgotten" records
    -- until the next time we run
    --
    EXECUTE IMMEDIATE 'INSERT /*+ append */ INTO '||v_dest_table||'
        SELECT *
        FROM '||v_which_table||'
        WHERE ts > TRUNC(SYSDATE) - '||TO_CHAR(p_days)
    ;
    v_rows := SQL%rowcount;
    COMMIT;
    -- must commit before logging because logging writes to same table we just direct path wrote!!!
    v_log_obj.log_p('Copied back from '||v_which_table||' to '||v_dest_table||' '||TO_CHAR(v_rows)||' records less than '||TO_CHAR(p_days)||' days old');
END applog_purge_old;
/
show errors
-- put a record into the log for funzies
DECLARE
    v_logger applog_udt := applog_udt('applog');
BEGIN
    v_logger.log('This will be the first message in the log after code deploy from applog.sql');
END;
/
