whenever sqlerror exit failure
set define on
define use_app_log="TRUE"
-- Comment this next section out if you set use_app_log to false
------------------------------------------------------
define subdir="plsql_utilities/app_log"
prompt deploying &&subdir/install_app_log.sql
@&&subdir/install_app_log.sql
------------------------------------------------------
--
define subdir=.
prompt deploying as_pdf3_4.sql
@as_pdf3_4.sql
ALTER SESSION SET PLSQL_CCFLAGS='use_app_log:&&use_app_log.';
prompt deploying PdfGen.pks
@PdfGen.pks
prompt deploying PdfGen.pkb
@PdfGen.pkb
-- Uncomment to deploy the test case package
/*
define subdir=test
prompt deploying &&subdir/test_PdfGen.sql
@&&subdir/test_PdfGen.sql
*/
