# PdfGen.sql

*PdfGen* extends and enhances (replaces) the *as_pdf3.cursor2table* functionality
with respect to column headers and widths, plus the ability to capture a column
page break value for the page_procs callbacks, and go to a new page when the 
break-column value changes.  Everything is implemented using the *as_pdf3* 
public interface.

There are many report generators in the world. Most of them cost money.  This 
is free, powerful enough for some common use cases, and a little easier than 
using *as_pdf3* directly.

## Use Case

The use case for this package is to perform a small subset of sqlplus report 
generation directly inside the database. 

Required features include page headers and footers with page break column 
values and hidden columns. (SQL already provides SUM Subtotals and Totals using 
*GROUPING SETS*, so that feature of sqlplus reports is redundant.) Rather 
than pulling the data out to a client sqlplus session on an ETL server, 
converting to PDF, then loading it back into the database as a BLOB, we do 
so directly in PL/SQL.

We also gain page format, margins, and font control, plus optional grid 
lines/cells for the column data values. We produce a more attractive finished 
product than can be generated from sqlplus.

There are enough similarties to sqlplus report generation that it should be 
familiar and relatively easy to convert existing reports.

## Example

    CREATE OR REPLACE FUNCTION test0 RETURN BLOB
    IS
        v_src       SYS_REFCURSOR;
        v_blob      BLOB;
        v_widths    PdfGen.t_col_widths;
        v_headers   PdfGen.t_col_headers;
        FUNCTION get_src RETURN SYS_REFCURSOR IS
            l_src SYS_REFCURSOR;
        BEGIN
          OPEN l_src FOR
            WITH a AS (
                SELECT e.employee_id, e.last_name, e.first_name, d.department_name
                    ,SUM(salary) AS salary          -- emulate sqplus COMPUTE SUM
                FROM hr.employees e
                INNER JOIN hr.departments d
                    ON d.department_id = e.department_id
                GROUP BY GROUPING SETS (
                                                    -- seemingly useless SUM on single record, 
                                                    -- but required to get detail records
                                                    -- in same query as the subtotal and total aggregates
                    (e.employee_id, e.last_name, e.first_name, d.department_name)
                    ,(d.department_name)            -- sqlplus COMPUTE SUM of salary ON department_name
                    ,()                             -- sqlplus COMPUTE SUM of salary ON report - the grand total
                )
            ) SELECT employee_id
                -- NULL last_name indicates an aggregate result.
                -- NULL department_name indicates it was the grand total
                -- Similar to the LABEL on COMPUTE SUM
                ,NVL(last_name, CASE WHEN department_name IS NULL
                                    THEN LPAD('GRAND TOTAL:',25)
                                    ELSE LPAD('DEPT TOTAL:',25)
                                END
                ) AS last_name
                ,first_name
                ,department_name
                -- right justify the formatted amount in the width of the column
                -- maybe next version will provide an array of format strings for numbers and dates
                -- but for now format your own if you do not want the defaults
                ,LPAD(TO_CHAR(salary,'$999,999,999.99'),16) -- leave space for sign even though we will not have one
            FROM a
            ORDER BY department_name NULLS LAST     -- to get the aggregates after detail
                ,a.last_name NULLS LAST             -- notice based on FROM column value, not the one we munged in resultset
                ,first_name
            ;
          RETURN l_src;
        END;
    BEGIN
                                                    -- Similar to the sqlplus COLUMN HEADING commands
        v_headers(1) := 'Employee ID';
        v_widths(1)  := 11;
        v_headers(2) := 'Last Name';
        v_widths(2)  := 25;
        v_headers(3) := 'First Name';
        v_widths(3)  := 20;
                                                    -- will not print this column, 
                                                    -- just capture it for column page break
        v_headers(4) := NULL;                       --'Department Name'
        v_widths(4)  := 0;                          -- sqlplus COLUMN NOPRINT 
        v_headers(5) := 'Salary';
        v_widths(5)  := 16;
        --
        PdfGen.init;
        PdfGen.set_page_format(
            p_format            => 'LETTER' 
            ,p_orientation      => 'PORTRAIT'
            ,p_top_margin       => 1
            ,p_bottom_margin    => 1
            ,p_left_margin      => 0.75
            ,p_right_margin     => 0.75
        );
        PdfGen.set_footer;                          -- 'Page #PAGE_NR# of "PAGE_COUNT#' is the default
                                                    -- sqlplus TITLE command
        PdfGen.set_header(
            p_txt               => 'Employee Salary Report'
            ,p_font_family      => 'helvetica'
            ,p_style            => 'b'
            ,p_fontsize_pt      => 16
            ,p_centered         => TRUE
            ,p_txt_2            => 'Department: !PAGE_VAL#'
            ,p_fontsize_pt_2    => 12
            ,p_centered_2       => FALSE            -- left align
        );
        --
        as_pdf3.set_font('courier', 'n', 10);
        v_src := get_src;                           -- open the query cursor
        PdfGen.refcursor2table(
            p_src                       => v_src
            ,p_widths                   => v_widths
            ,p_headers                  => v_headers
            ,p_bold_headers             => TRUE     -- also light gray background on headers
            ,p_char_widths_conversion   => TRUE
            ,p_break_col                => 4        -- sqlplus BREAK ON column
            ,p_grid_lines               => FALSE
        );
        v_blob := PdfGen.get_pdf;
        BEGIN
            CLOSE v_src;                            -- likely redundant, but paranoid is good
        EXCEPTION WHEN invalid_cursor THEN NULL;
        END;
        -- can insert into a table or add to a zip archive blob or attach to an email
        RETURN v_blob;                              
    END test0;

## Retrieve Blob and View

With SqlDeveloper or Toad 

    SELECT test0 FROM dual;

Double click on the BLOB value in the results grid. In SqlDeveloper you get a 
pencil icon. Click on that and choose *download* (toad is similar). Save the 
blob to a file named test0.pdf. Open in a pdf viewer.

## Results

 ![test0_pg1](/images/test0_pg1.png)

 ![test0_pgx](/images/test0_pgx.png)

Pdf files from test_PdfGen are in the *samples* folder. Github will display 
them when selected.

## A Few Details

Column widths may be set to 0 for NOPRINT, so Break Columns where the value is 
captured and printed in the page header via a callback can be captured, but 
optionally not printed with the record. Note that if grouping/breaking on 
multiple columns is needed you can concatenate values into a string for a
single non-printing break-column, then parse it in your callback procedure.

The *as_pdf3* "page_procs" callback facility is duplicated (both are called) 
so that the page break column value can be supplied in addition to the page 
number and page count that the original supported. One major difference is the 
use of bind placeholders instead of direct string substitution in your PL/SQL 
block. We follow the original convention for substitution strings in the 
text provided to built-in header and footer procedures, but internally rather 
than directly to the anonymous block. You will be providing positional bind 
placeholders (:var1, :var2, :var3) for EXECUTE IMMEDIATE in the PL/SQL block 
strings you add to page_procs. This solves a nagging problem with quoting 
as well as eliminating potential sql injection.

Example:

    PdfGen.set_page_proc(
        q'[BEGIN 
            yourpkgname.apply_footer(
                p_page_nr       => :page_nr
                ,p_page_count   => :page_count
                ,p_page_val     => :page_val
            ); 
            END;
        ]'
    );

That block (*g_page_procs(p)*) is then executed with:

    EXECUTE IMMEDIATE g_page_procs(p) USING i, v_page_count
        -- do not try to bind a non-existent collection element
        ,CASE WHEN g_pagevals.EXISTS(i) THEN g_pagevals(i) ELSE NULL END
    ;

where *i* is the page number and *g_pagevals(i)* is the page specific column break
value captured while the query result set was processed. See *PdfGen* package
header for an example of a comprehensive anonymous block that does not require
you to provide a public procedure.

Also provided are simplified methods for generating semi-standard page header
and footer. You can use these procedures as a template for building your own 
page_proc procedure if they do not meet your needs.

You can mix and match calls to *as_pdf3* procedures and functions simultaneous
with *PdfGen*. In fact you are expected to do so with procedures such 
as *as_pdf3.set_font*.

Be aware that the concept of *centered* in *as_pdf3* means centered on the page.
*PdfGen* centers between the left and right margins. If you are using 
*as_pdf3.write* with align=>'center' be aware of this difference. If your left
and write margins are the same, it will not matter.

# as_pdf3_4.sql

This copy of the 2012 original release by Anton Scheffer 
(http://technology.amis.nl and http://technology.amis.nl/?p=17718) 
has only two small changes. I added constant *c_get_page_count* and an 
associated case/when to the public function *get()*.  If you have already 
installed (and perhaps modified) your own version, you will have no trouble 
locating these 2 changes and implementing them.

# applog.sql

A lightweight and fast general purpose database application logging facility, 
the core is an object oriented user defined type with methods for writing 
log records to a table.  Since the autonomous transactions write independently,
you can get status of the program before "succesful" completion that might be
required for dbms_output. In addition to generally useful logging, 
it (or something like it) is indispensable for debugging and development.

You do not have to deploy this User Defined Type and tables. There is a 
compile directive in *PdfGen.sql* that must be set to turn it on. If you
comment out the line in the deploy script that sets PLSQL_CCFLAGS
(along with the call to run applog.sql), *PdfGen.sql* will compile just 
fine without it.

# test_PdfGen.sql

A package containing my test cases as well as examples of how to use *PdfGen*.
There is no reason for you to deploy it except for study. Install it in your
development environment for reference. You can always drop it later.

Note: If your schema does not have SELECT priv directly (role doesn't count)
on the database sample *HR* schema tables *employees* and *departments*, 
then *test0* is not included. In the *test* folder is a script to add those 
grants (though it is simple enough to just do so manually).

# deploy.sql

Called from sqlplus, will deploy everything. You should comment out anything 
you do not want or just use it as a guide.
