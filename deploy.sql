whenever sqlerror exit failure
prompt deploying applog.sql
@applog.sql
prompt deploying as_pdf3_4.sql
@as_pdf3_4.sql
prompt deploying PdfGen.sql
ALTER SESSION SET PLSQL_CCFLAGS='use_applog:TRUE';
@PdfGen.sql
prompt deploying test/test_PdfGen.sql
@test/test_PdfGen.sql
