--ALTER SESSION SET plsql_code_type = NATIVE;
--ALTER SESSION SET plsql_optimize_level=3;
/*
  Author: Lee Lindley
  Date: 07/24/2021

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
-- General purpose logging components.
-- The core is an object oriented user defined type with logging methods.
--
-- Since the autonomous transactions write independently, you can get status
-- of the program before "succesful" completion that might be required for dbms_output.
-- For long running processes that means you can "tail" the log (select * from app_log_tail_v)
-- to watch what is happening. It also means that if the thing blows up or is hung,
-- and does not display the dbms_output for you, you can still go see it in the log table.
--
-- Since the messages include a high precision timestamp, you can see from the time between
-- log messages the elapsed time for operations. Mining the log for this information is fun.
-- The view app_log_tail_v shows you how to use an analytic to calculate that elapsed time.
--
-- In addition to generally useful logging, it is indispensable for debugging and development.
--
whenever sqlerror continue
DROP TYPE app_log_udt FORCE;
prompt ok drop failed for type not exists
DROP VIEW app_log_v;
prompt ok if drop failed for view not exists
DROP VIEW app_log_base_v;
prompt ok if drop failed for view not exists
DROP VIEW app_log_tail_v;
prompt ok if drop failed for view not exists
--
DROP TABLE app_log_1;
DROP TABLE app_log_2;
prompt ok if drop fails for table not exists
DROP TABLE app_log_app;
prompt ok if drop fails for table not exists
DROP SEQUENCE app_log_app_seq;
prompt ok if drop fails for sequence not exists
--
whenever sqlerror exit failure
--
-- table will contain a record for every "application" string that is used to do logging.
-- Whenever a new application string is used, a new record will be inserted into the table by the object constructor.
--
CREATE TABLE app_log_app (
     app_id     NUMBER(38) 
    ,app_name   VARCHAR2(30) NOT NULL
    ,CONSTRAINT app_log_app_pk PRIMARY KEY(app_id)    --ensures not null
    -- could have simultaneous constructors firing and crossing the streams.
    -- First one will win and second will raise exception. probably never happen in my lifetime.
    ,CONSTRAINT app_log_app_fk1 UNIQUE(app_name)      
);
-- no reason for large jumps. Infrequently used sequence, thus nocache.
CREATE SEQUENCE app_log_app_seq NOCACHE; 
--
-- The main logging table. It does not have the app_name string in it, so a join view can make it more convenient.
-- The Procedure app_log_udt.purge_old can be run to purge older log records. 
--
-- Do not put any indexes or FK constraints on this. We want inserts to be cheap and fast!!!
-- Reading the table is a person doing research. They can afford full table scans.
--
-- We use two tables with a synonym to facilitate purging without interruption. You will never
-- use these two table names directly, but instead the synonym "APP_LOG" if you are in the same schema
-- (or if you create a public synonym), or the view APP_LOG_BASE_V which uses the local synonym.
-- The synonym switches between the tables during purge events.
--
CREATE TABLE app_log_1 (
     app_id     NUMBER(38) NOT NULL 
    ,ts         timestamp WITH LOCAL TIME ZONE
    ,msg        VARCHAR2(4000) 
);
CREATE TABLE app_log_2 (
     app_id     NUMBER(38) NOT NULL 
    ,ts         timestamp WITH LOCAL TIME ZONE
    ,msg        VARCHAR2(4000) 
);
CREATE OR REPLACE SYNONYM app_log FOR app_log_1;
whenever sqlerror exit failure
-- when the synonym changes, so do the views that use it
CREATE OR REPLACE VIEW app_log_base_v(app_id, ts, msg)  AS
SELECT app_id, ts, msg
FROM app_log
;
--
-- A view to allow querying via appname.
--
CREATE OR REPLACE VIEW app_log_v(app_name, app_id, ts, msg)  AS
SELECT i.app_name, a.app_id, a.ts, a.msg
FROM app_log_app i
INNER JOIN app_log a
    ON a.app_id = i.app_id
;
--
-- Tail the last 20 records of the log
--
CREATE OR REPLACE VIEW app_log_tail_v(time_stamp, elapsed, logmsg, app_name) AS
    WITH a AS (
        SELECT app_id, ts, msg 
        FROM app_log 
        ORDER BY ts DESC FETCH FIRST 20 ROWS ONLY
    ), b AS (
        SELECT app_name, ts, ts - (LAG(ts) OVER (ORDER BY ts)) AS ts_diff, msg
        FROM a
        INNER JOIN app_log_app ap 
            ON ap.app_id = a.app_id
    ) SELECT 
         TO_CHAR(ts, 'HH24:MI.SS.FF2')  AS time_stamp
        ,TO_CHAR(EXTRACT(MINUTE FROM ts_diff)*60 + EXTRACT(SECOND FROM ts_diff), '999.9999') 
                                        AS elapsed
        ,SUBSTR(msg,1,75)               AS logmsg
        ,app_name                       AS appname
    FROM b
    ORDER BY b.ts
;
--
CREATE OR REPLACE TYPE app_log_udt FORCE AS OBJECT (
/* 
    Purpose: Provide general purpose logging capability for PL/SQL applications

    Tables: app_log_app     -- small automatically populated lookup table app_name/app_id pairs
            app_log         -- all log records by app_id (actually a synonym to one of 2 base tables)
    Views: app_log_base_v   -- uses the synonym to pick the base table
           app_log_v        -- joins on app_id to provide a view that includes the app_name string
           app_log_tail_v   -- last 20 records of log joined on app_id with elapsed time from prior record

    Type: app_log_udt       -- an object type with constructor and methods for performing simple logging

    Example of using this object:

        DECLARE
            -- instantiate an object instance for app_name 'bnft' which will automatically
            -- create the app_log_app entry if it does not exist
            v_log_obj   app_log_udt := app_log_udt('bnft');
        BEGIN
            -- log a message for our app
            v_log_obj.log('whatever my message: '||sqlerrm);
            -- same but also do DBMS_OUTPUT.PUT_LINE with the message too
            v_log_obj.log_p('whatever my message: '||sqlerrm);
        END;

    Example of an exception block:

        Assumes the following declarations in the program:
            g_sqlerrm                       VARCHAR2(512);
            g_backtrace                     VARCHAR2(32767);
            g_callstack                     VARCHAR2(32767); 
            g_log       app_log_udt := app_log_udt('my application name string');
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
        app_log_udt.log('my app string', 'some message');
        app_log_udt.log_p('my app string', 'some message');

*/
    app_id      NUMBER(38)
    ,app_name   VARCHAR2(30)
    -- member functions and procedures
    ,CONSTRUCTOR FUNCTION app_log_udt(p_app_name VARCHAR2)
        RETURN SELF AS RESULT
    ,MEMBER PROCEDURE log(p_msg VARCHAR2)
    ,MEMBER PROCEDURE log_p(p_msg VARCHAR2) -- prints with dbms_output and then logs
    -- these are not efficient, but not so bad in an exception block.
    -- You do not have to declare a variable to hold the instance because it is temporary
    ,STATIC PROCEDURE log(p_app_name VARCHAR2, p_msg VARCHAR2) 
    ,STATIC PROCEDURE log_p(p_app_name VARCHAR2, p_msg VARCHAR2) 
    -- should only be used by the schema owner, but only trusted application accounts
    -- are getting execute on this udt so fine with me. If you are concerned, then
    -- break this procedure out standalone
    ,STATIC PROCEDURE purge_old(p_days NUMBER := 90)
);
/
--
CREATE OR REPLACE TYPE BODY app_log_udt AS

    CONSTRUCTOR FUNCTION app_log_udt(
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
            FROM app_log_app 
            WHERE app_name = SELF.app_name
            ;
        EXCEPTION WHEN NO_DATA_FOUND
            THEN 
                app_id := app_log_app_seq.NEXTVAL;
                INSERT INTO app_log_app(app_id, app_name) VALUES (SELF.app_id, SELF.app_name);
                COMMIT;
        END;
        RETURN;
    END; -- end constructor app_log_udt

    MEMBER PROCEDURE log(p_msg VARCHAR2)
    IS
        -- we create the log messages independent from the main body who may commit or rollback separately
        PRAGMA AUTONOMOUS_TRANSACTION;
    BEGIN
        -- we silently truncate the message to fit the 4000 char column
        INSERT INTO app_log(app_id, ts, msg) VALUES (SELF.app_id, CURRENT_TIMESTAMP, SUBSTR(p_msg,1,4000));
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
        l app_log_udt := app_log_udt(p_app_name);
    BEGIN
        l.log(p_msg);
    END
    ;
    STATIC PROCEDURE log_p(p_app_name VARCHAR2, p_msg VARCHAR2)
    IS
        l app_log_udt := app_log_udt(p_app_name);
    BEGIN
        l.log_p(p_msg);
    END
    ;

    STATIC PROCEDURE purge_old(p_days NUMBER := 90)
    IS
        v_log_obj       app_log_udt := app_log_udt('app_log');
        v_which_table   VARCHAR2(128); -- 30 is true max, but many dba tables allow 128
        v_dest_table    VARCHAR2(128);
        v_rows          BINARY_INTEGER;
    BEGIN
        v_log_obj.log_p('Procedure purge_old called with arg p_days='||TO_CHAR(p_days));
    
        --
        -- Figure out which base table is currently being written to
        --
        SELECT table_name INTO v_which_table
        FROM user_synonyms
        WHERE synonym_name = 'APP_LOG'
        ;
        --
        -- The one we are going to truncate and write to next is the other one
        --
        v_dest_table := CASE WHEN v_which_table = 'APP_LOG_1' 
                             THEN 'APP_LOG_2' 
                             ELSE 'APP_LOG_1'
                        END;
        EXECUTE IMMEDIATE 'TRUNCATE TABLE '||v_dest_table||' DROP ALL STORAGE';
        v_log_obj.log_p('truncated table '||v_dest_table);
        --
        -- Here is the magic. We swap the synonym. That means any
        -- new writes via the app_log_udt object will insert into the 
        -- new destination table (which is currently empty) and no longer write to the
        -- old table. This takes care of any writes that are going on while we are performing
        -- the rest of this task and prevents any blocking that might otherwise happen
        -- from our activity. The views will also resolve through the local synonym, so
        -- there is a brief time where the existing log records have disappeared until
        -- we commit the insert.
        --
        -- I was happy with an implementation of this using a single table and a dummy
        -- partitioned table with exchange partition, but it was pointed out that not
        -- everyone pays for the partition license.
        --
        EXECUTE IMMEDIATE 'CREATE OR REPLACE SYNONYM app_log FOR '||v_dest_table;
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
    END purge_old;
END;
/
show errors
--
--ALTER SESSION SET plsql_code_type = INTERPRETED;
--ALTER SESSION SET plsql_optimize_level=2;
--
-- put a record into the log for funzies
DECLARE
    v_logger app_log_udt := app_log_udt('app_log');
BEGIN
    v_logger.log('This will be the first message in the log after code deploy from app_log.sql');
END;
/
--GRANT EXECUTE ON app_log_udt TO ???; -- trusted application schemas only. Not people
-- select can be granted to roles and people who are trusted to see log messages.
-- that depends on what you are putting in the log messages. Hopefully no secrets.
--GRANT SELECT ON app_log_1 TO ???; 
--GRANT SELECT ON app_log_2 TO ???; 
--GRANT SELECT ON app_log_app TO ???; 
--GRANT SELECT ON app_log_v TO ???; 
--GRANT SELECT ON app_log_tail_v TO ???; 
--GRANT SELECT ON app_log_base_v TO ???;
