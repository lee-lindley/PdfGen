# PdfGen.sql

PdfGen extends and enhances (replaces) the *as_pdf3.cursor2table* functionality with
respect to column headers and widths, plus the ability to capture a column page break value
for the page_procs callbacks, and go to a new page when the break-column value changes.
Everything is implemented using the *as_pdf3* public interface.

The use case for this package is to replicate a small subset of the capability of
sqlplus report generation for the scenario that you cannot (or do not want to) 
run sqlplus,capture the output and convert it to pdf. You also gain font control
and optional grid lines/cells for the column data values.

An alternate name for this facility might be query2report.

Column widths may be set to 0 for NOPRINT, so Break Columns where the value is captured
and printed in the page header via a callback can be captured, but not printed with the record.
Note that you can concatenate mulitple column values into a string for a single non-printing break-column,
and parse those in your callback procedure.

The *as_pdf3* "page_procs" callback facility is duplicated (both are called) so that
the page break column value can be supplied in addition to the page number and page count
that the original supported.

Also provided are simplified methods for generating semi-standard page header and footer
that are less onerous than the quoting required for generating an anonymous pl/sql block string.
You can use these procedures as a template for building your own page_proc procedure if they
do not meet your needs.

You can mix and match calls to *as_pdf3* procedures and functions simultaneous with *PdfGen*.

# as_pdf3_4.sql

This copy of the 2012 original release by Anton Scheffer (http://technology.amis.nl and http://technology.amis.nl/?p=17718
) 
has only two small changes. I added constant *c_get_page_count* and an associated addition to the public function *get()*.
If you have already installed (and perhaps modified) your own version, you will have no trouble locating
these 2 changes and implementing them.

# applog.sql

A general purpose database application logging facility, the core is an object oriented
user defined type with methods for writing log records to a table.
Since the autonomous transactions write independently, you can get status
of the program before "succesful" completion that might be required for dbms_output.
In addition to generally useful logging, it (or something like it)
is indispensable for debugging and development.

You do not have to deploy this package and tables. There is a compile directive in *PdfGen.sql*
that must be set to turn it on. If you comment out that line in the deploy script (along with the call
to applog.sql), PdfGen.sql will compile just fine without it.

# test_PdfGen.sql

A package that represents my test cases as well as examples of how to use it. There is no reason
for you to deploy it except for study. Then by all means proceed. You can always drop it later.

# PdfGen_sample_pdf.zip

Output from test_PdfGen.sql in pdf format

# deploy.sql

Called from sqlplus, will deploy everything. You should comment out anything you do not want or just use it
as a guide.
