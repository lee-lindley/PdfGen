whenever sqlerror exit failure
set define on
-- set these to your own naming convention.
-- If you already have types that server the purpose, change these defines to those
-- names and comment out the compiles below
--
define d_arr_integer_udt="arr_integer_udt"
define d_arr_varchar2_udt="arr_varchar2_udt"
--define d_arr_arr_varchar2_udt="arr_arr_varchar2_udt"
define d_arr_clob_udt="arr_clob_udt"
define d_arr_arr_clob_udt="arr_arr_clob_udt"
--
define use_app_log="TRUE"
-- Comment this next section out if you set use_app_log to false
------------------------------------------------------
define subdir="plsql_utilities/app_log"
prompt deploying &&subdir/install_app_log.sql
@&&subdir/install_app_log.sql
------------------------------------------------------
set define on
define subdir=plsql_utilities/app_types
prompt &&subdir/arr_varchar2_udt.tps
@&&subdir/arr_varchar2_udt.tps
prompt &&subdir/arr_integer_udt.tps
@&&subdir/arr_integer_udt.tps
prompt &&subdir/arr_clob_udt.tps
@&&subdir/arr_clob_udt.tps
prompt &&subdir/arr_arr_clob_udt.tps
@&&subdir/arr_arr_clob_udt.tps
--
ALTER SESSION SET plsql_code_type = NATIVE;
ALTER SESSION SET plsql_optimize_level=3;
-- we have to allow these to fail if they are already present and another
-- type is already using them
whenever sqlerror continue
define subdir="plsql_utilities/app_dbms_sql"
prompt deploying &&subdir/install_app_dbms_sql.sql
@&&subdir/install_app_dbms_sql.sql
whenever sqlerror exit failure
define subdir=.
prompt deploying as_pdf3_4.sql
@as_pdf3_4.sql
ALTER SESSION SET PLSQL_CCFLAGS='use_app_log:&&use_app_log.';
prompt deploying PdfGen.pks
@PdfGen.pks
prompt deploying PdfGen.pkb
@PdfGen.pkb
ALTER SESSION SET plsql_optimize_level=2;
ALTER SESSION SET plsql_code_type = INTERPRETED;
--
prompt running compile_schema for invalid objects
BEGIN
    DBMS_UTILITY.compile_schema( schema => SYS_CONTEXT('userenv','current_schema')
                                ,compile_all => FALSE
                                ,reuse_settings => TRUE
                            );
END;
/
-- Uncomment to deploy the test case package
/*
define subdir=test
prompt deploying &&subdir/test_PdfGen.sql
@&&subdir/test_PdfGen.sql
*/
