# PdfGen.sql

PdfGen extends and enhances (replaces) the _as_pdf3.cursor2table_ functionality with
respect to column headers and widths, plus the ability to capture a column page break value
for the page_procs callbacks, and go to a new page when the break-column value changes.
Everything is implemented using the _as_pdf3_ public interface.

## Use Case
The use case for this package is to replicate a small subset of the capability of
sqlplus report generation for the scenario that you cannot (or do not want to) 
run sqlplus,capture the output and convert it to pdf. You also gain font control
and optional grid lines/cells for the column data values.

An alternate name for this facility might be query2report.

## Example

    FUNCTION test3 RETURN BLOB
    IS
        v_src   SYS_REFCURSOR;
        v_blob  BLOB;
        v_widths PdfGen.t_col_widths;
        v_headers PdfGen.t_col_headers;
        FUNCTION get_src RETURN SYS_REFCURSOR IS
            l_src SYS_REFCURSOR;
        BEGIN
          OPEN l_src FOR
            SELECT 
                view_name 
                ,SUBSTR(comments,1,100) 
                ,grp
            FROM (
                SELECT v.*, FLOOR(rownum / 36) AS grp
                FROM (
                    SELECT /*+ no_parallel */
                        v.view_name 
                        ,c.comments 
                    FROM dictionary d
                    INNER JOIN all_views v
                        ON v.view_name = d.table_name
                    LEFT OUTER JOIN all_tab_comments c
                        ON c.table_name = v.view_name
                    WHERE d.table_name LIKE 'ALL%'
                    ORDER BY v.view_name
                    FETCH FIRST 40 ROWS ONLY
                ) v
            )
            ;
          RETURN l_src;
        END;
    BEGIN
        v_src := get_src;
        --
        v_headers(1) := 'DBA View Name';
        v_widths(1)  := 31;
        v_headers(2) := 'Dictionary Comments';
        v_widths(2)  := 102;
        -- will not print this column, just capture it for column page break
        v_headers(3) := NULL;
        v_widths(3)  := 0;
        --
        PdfGen.init;
        PdfGen.set_page_format('LEGAL','LANDSCAPE');
        PdfGen.set_footer('Page #PAGE_NR# of "PAGE_COUNT#');
        PdfGen.set_header('Data Dictionary Views for group !PAGE_VAL#');
        --
        -- just so we can see the margins. Not a general practice
        as_pdf3.rect(as_pdf3.get(as_pdf3.c_get_margin_left), as_pdf3.get(as_pdf3.c_get_margin_bottom)
                ,as_pdf3.get(as_pdf3.c_get_page_width) - as_pdf3.get(as_pdf3.c_get_margin_right) - as_pdf3.get(as_pdf3.c_get_margin_left)
                ,as_pdf3.get(as_pdf3.c_get_page_height) - as_pdf3.get(as_pdf3.c_get_margin_top) - as_pdf3.get(as_pdf3.c_get_margin_bottom)
            );
        --
        as_pdf3.set_font('courier', 'n', 10);
        PdfGen.refcursor2table(p_src => v_src
            ,p_widths => v_widths, p_headers => v_headers
            ,p_bold_headers => TRUE, p_char_widths_conversion => TRUE
            ,p_break_col => 3
            --,p_grid_lines => FALSE
        );
        v_blob := PdfGen.get_pdf;
        BEGIN
            CLOSE v_src;
        EXCEPTION WHEN invalid_cursor THEN NULL;
        END;
        RETURN v_blob;
    END test3;

## Retrieve Blob and View

With SqlDeveloper or Toad _SELECT test3 FROM dual;_ Double click on the BLOB value in the results grid. In SqlDeveloper you get a pencil icon. Click on that and choose _download_ (toad is similar). Save the blob to a file named whatever.pdf. Open in a pdf viewer.

## Results

 ![test3_pg1](/images/test3_pg1.png)

 ![test3_pg2](/images/test3_pg2.png)

## A Few Details

Column widths may be set to 0 for NOPRINT, so Break Columns where the value is captured
and printed in the page header via a callback can be captured, but not printed with the record.
Note that you can concatenate mulitple column values into a string for a single non-printing break-column,
and parse those in your callback procedure.

The _as_pdf3_ "page_procs" callback facility is duplicated (both are called) so that
the page break column value can be supplied in addition to the page number and page count
that the original supported.

Also provided are simplified methods for generating semi-standard page header and footer
that are less onerous than the quoting required for generating an anonymous pl/sql block string.
You can use these procedures as a template for building your own page_proc procedure if they
do not meet your needs.

You can mix and match calls to _as_pdf3_ procedures and functions simultaneous with _PdfGen_.

# as_pdf3_4.sql

This copy of the 2012 original release by Anton Scheffer (http://technology.amis.nl and http://technology.amis.nl/?p=17718
) 
has only two small changes. I added constant _c_get_page_count_ and an associated addition to the public function _get()_.
If you have already installed (and perhaps modified) your own version, you will have no trouble locating
these 2 changes and implementing them.

# applog.sql

A general purpose database application logging facility, the core is an object oriented
user defined type with methods for writing log records to a table.
Since the autonomous transactions write independently, you can get status
of the program before "succesful" completion that might be required for dbms_output.
In addition to generally useful logging, it (or something like it)
is indispensable for debugging and development.

You do not have to deploy this package and tables. There is a compile directive in _PdfGen.sql_
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
