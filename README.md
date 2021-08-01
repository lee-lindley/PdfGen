
# PdfGen - An Oracle PL/SQL PDF Generator

Create an attractive report from a SQL query with capabilities
similar to those available in sqlplus report generator, but with
control over fonts, margins, page size, and orientation. (See *samples*
directory for PDF files it produced.)

The package is built on *as_pdf3* by Anton Scheffer which is included in
this repository. Everything you need to deploy it is here.

There are many report generators in the world. Most of them cost money.  This 
is free, powerful enough for some common use cases, and a little easier than 
using *as_pdf3* directly.

# Installation

Clone this repository or download it as a zip archive.

Note: [plsql_utilties](https://github.com/lee-lindley/plsql_utilities) is provided as a submodule,
so use the clone command with recursive-submodules option:

`git clone --recursive-submodules https://github.com/lee-lindley/PdfGen.git`

or download it separately as a zip archive and extract the content of root folder
into *plsql_utilities* folder.

Follow the instructions in [install.sql](#installsql)

Note that you do not absolutely require the submodule. You can turn off
usage of *app_log* with a compile directive, and that is the only feature
required from *plsql_utilities*.

# PdfGen.sql

*PdfGen* extends and enhances (replaces) the *as_pdf3.cursor2table* functionality
with respect to column headers and widths, plus the ability to capture a 
column "page break" value for the page_procs callbacks, and go to a new page when the 
break-column value changes. Everything is implemented using the *as_pdf3* 
public interface.

# Content
1. [PdfGen.sql](#PdfGensql)
    - [Use Case](#use-case)
    - [Example](#example)
    - [Retrieve Blob and View](#retrieve-blob-and-view)
    - [Results](#results)
    - [A Few Details](#a-few-details)
        - [NOPRINT and BREAK](#noprint-and-break)
        - [Callbacks](#callbacks)
        - [Security](#security)
        - [General Purpose Headers and Footers](#general-purpose-headers-and-footers)
        - [Intermix Calls to as_pdf3](#intermix-calls-to-as_pdf3)
        - [Concept of Centered](#concept-of-centered)
2. [install.sql](#insallsql)
3. [as_pdf3.sql](#as_pdf3_4sql)
4. [app_log](#app_log)
5. [test/test_PdfGen.sql ](#testtest_pdfgensql)
6. [samples directory](#samples)
6. [Manual Page](#manual-page)

## Use Case

The use case for this package is to perform a small subset of sqlplus report 
generation directly inside the database. 

Required features include page headers (TITLE) and footers with page break column 
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

```sql
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
            ,p_txt_2            => 'Department: !PAGE_VAL#' -- TITLE column variable value
            ,p_fontsize_pt_2    => 12
            ,p_centered_2       => FALSE            -- left align
        );
        -- asking for trouble to use other than fixed width fault in the grid IMHO. YMMV.
        as_pdf3.set_font('courier', 'n', 10);
        v_src := get_src;                           -- open the query cursor
        PdfGen.refcursor2table(
            p_src                       => v_src
            ,p_widths                   => v_widths
            ,p_headers                  => v_headers
            ,p_bold_headers             => TRUE     -- also light gray background on headers
            ,p_char_widths_conversion   => TRUE
            ,p_break_col                => 4        -- sqlplus BREAK ON column becomes !PAGE_VAL#
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
```

## Retrieve Blob and View

With SqlDeveloper or Toad 

    SELECT test0 FROM dual;

Double click on the BLOB value in the results grid. In SqlDeveloper you get a 
pencil icon. Click on that and choose *download* (toad is similar). Save the 
blob to a file named test0.pdf. Open in a pdf viewer.

## Results

 ![test0_pg1](/images/test0_pg1.png)

 ![test0_pgx](/images/test0_pgx.png)

Pdf files from *test/test_PdfGen* are in the *samples* folder. Github will display 
them when selected.

## A Few Details

### NOPRINT and BREAK

Column widths may be set to 0 for NOPRINT, so BREAK Columns where the value is 
captured and printed in the page header via a callback can be captured, but 
optionally not printed with the record. Note that if grouping/breaking on 
multiple columns is needed you can concatenate values into a string for a
single non-printing break-column, then parse it in your callback procedure.

### Callbacks

You may never need to write your own callback procedure as *set_page_header*
and *set_page_footer* will generally be sufficient.

The *as_pdf3* "page_procs" callback facility is duplicated (both are called) 
so that the page break column value can be supplied in addition to the page 
number and page count that the original supported. One major difference is the 
use of bind placeholders instead of direct string substitution on your PL/SQL 
block string. You must provide positional bind placeholders for 
EXECUTE IMMEDIATE (:var1, :var2, :var3) in the PL/SQL block strings you add 
to page_procs. This solves a nagging problem with quoting as well as
eliminating a potential vector for sql injection that the page break column
values introduce over the original design of *as_pdf3* page procs.

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

where *i* is the page number and *g_pagevals(i)* is the page specific column 
break value captured while the query result set was processed. See *PdfGen* 
package header for an example of a comprehensive anonymous block that could do
all "the needful" in lieu of a public procedure.

### Security

If you will be granting EXECUTE to *PdfGen* and *as_pdf3* to other schema owners,
consider that they can inject code that will run as your schema owner unless
the packages are defined with Invoker Rights. This implementation does so
with **AUTHID CURRENT_USER**. You may have reasons to comment those out, such
as wanting the caller to have privs to write to a particular directory without
granting it directly. Just be aware that they can do ANYTHING in that callback
procedure that your schema owner can do.

### General Purpose Headers and Footers

Simplified methods for generating general purpose page headers
and footers are provided. You can use these procedures as a template for 
building your own page_proc procedure if they do not meet your needs.

We follow the original convention for substitution 
strings (#PAGE_NR#, "PAGE_COUNT#, !PAGE_VAL#) in the text provided to built-in
header and footer procedures, but it is done internally to text variables
rather than directly to the anonymous block. 

### Intermix Calls to *as_pdf3*

You can mix and match calls to *as_pdf3* procedures and functions simultaneous
with *PdfGen*. In fact you are expected to do so with procedures such 
as *as_pdf3.set_font*.

### Concept of Centered

Be aware that the concept of *centered* in *as_pdf3* means centered on the page.
*PdfGen* centers between the left and right margins. If you are using 
*as_pdf3.write* with align=>'center' be aware of this difference. If your left
and write margins are the same, it will not matter.

# install.sql

Called from sqlplus, will deploy everything. Edit it
to set one define variable to TRUE or FALSE depending on whether you want to 
include *app_log* in the compile of *PdfGen*.  The comments should be sufficient
to guide you.

# as_pdf3_4.sql

This copy of the 2012 original release by Anton Scheffer 

- https://technology.amis.nl/?p=17718
- https://technology.amis.nl/wp-content/uploads/2012/04/as_pdf3_4.txt

has only two small changes. I added constant *c_get_page_count* and an 
associated case/when to the public function *get()*.  If you have already 
installed (and perhaps modified) your own version, you will have no trouble 
locating these 2 changes and implementing them.

# app_log

See [plsql_utilities/README.md](https://github.com/lee-lindley/plsql_utilities#app_log)

You do not have to deploy this User Defined Type and tables. There is a 
compile directive in *PdfGen.sql* that must be set to turn it on. If you
set the define *use_app_log* to "FALSE" in [install.sql](#insallsql)
(along with commenting out the call to run install_app_log.sql), 
*PdfGen.sql* will compile just fine without it.

# test/test_PdfGen.sql

A package containing my test cases as well as examples of how to use *PdfGen*.
There is no reason for you to deploy it except for study. Perhaps install it 
in your development environment for reference. You can always drop it later.

Note: If your schema does not have SELECT priv directly (role doesn't count)
on the database sample *HR* schema tables *employees* and *departments*, 
then *test0* is not included. Assuming *HR* is installed, in the *test* 
folder is a script to add those grants (though it is simple enough to just 
do so manually).

# samples

A directory containing PDF files generated from *test_PdfGen.sql*.

# Manual Page

- [init](#pdfgeninit)
- [set_page_format](#pdfgenset_page_format)
- [set_footer](#pdfgenset_footer)
- [set_page_footer](#pdfgenset_page_footer)
- [set_header](#pdfgenset_header)
- [set_page_header](#pdfgenset_page_header)
- [set_page_proc](#pdfgenset_page_proc)
- [refcursor2table](#pdfgenrefcursor2table)
- [get_pdf](#pdfgenget_pdf)
- [save_pdf](#pdfgensave_pdf)

## PdfGen.init

Empties all global variables in preparation to generate a new report. Calls *as_pdf3.init*.

```sql
    PROCEDURE init;
```
## PdfGen.set_page_format

The units are in inches with the default page size of 'LETTER' rather than the European 'A4'.

```sql
    PROCEDURE set_page_format(
        p_format            VARCHAR2 := 'LETTER' --'LEGAL', 'A4', etc... See as_pdf3
        ,p_orientation      VARCHAR2 := 'PORTRAIT' -- or 'LANDSCAPE'
        -- these are inches. Use as_pdf3 procedures if you want other units
        -- Remember we write header/footer inside top/bottom margin areas
        ,p_top_margin       NUMBER := 1
        ,p_bottom_margin    NUMBER := 1
        ,p_left_margin      NUMBER := 0.75
        ,p_right_margin     NUMBER := 0.75
    );
```

## PdfGen.set_footer

A simple one line page footer where the text can be either centered or left justified. The default
puts 'Page 1 of 2' in the center in a small font just below the bottom margin. *set_footer*
is a convenient procedure to call when you want the defaults; otherwise *set_page_footer*
is a better choice.

```sql
    PROCEDURE set_footer(
        p_txt           VARCHAR2    := 'Page #PAGE_NR# of "PAGE_COUNT#'
        ,p_font_family  VARCHAR2    := 'helvetica'
        ,p_style        VARCHAR2    := 'n'
        ,p_fontsize_pt  NUMBER      := 8
        ,p_centered     BOOLEAN     := TRUE -- false give left align
    );
```

## PdfGen.set_page_footer

A one line page footer with text in any or all
of the justified left, centered and justified right locations.
The placeholder strings **#PAGE_NR#**, **"PAGE_COUNT#**, and **!PAGE_VAL#** in your
text parameters will be replaced with the values for each page.

See samples/test3.pdf.

```sql
    PROCEDURE set_page_footer(
         p_txt_center   VARCHAR2    := NULL
        ,p_txt_left     VARCHAR2    := NULL
        ,p_txt_right    VARCHAR2    := NULL
        ,p_font_family  VARCHAR2    := 'helvetica'
        ,p_style        VARCHAR2    := 'n'
        ,p_fontsize_pt  NUMBER      := 8
    );
```

## PdfGen.set_header

*set_header* is a legacy procedure. *set_page_header* is recommended instead.

A one or two line page header sitting slightly above the top margin. Both lines can be
centered or left justified independently.
The placeholder strings **#PAGE_NR#**, **"PAGE_COUNT#**, and **!PAGE_VAL#** in your
text parameters will be replaced with the values for each page.

```sql
    PROCEDURE set_header(
        p_txt               VARCHAR2
        ,p_font_family      VARCHAR2    := 'helvetica'
        ,p_style            VARCHAR2    := 'b'
        ,p_fontsize_pt      NUMBER      := 18
        ,p_centered         BOOLEAN     := TRUE -- false give left align
        ,p_txt_2            VARCHAR2    := NULL
        ,p_fontsize_pt_2    NUMBER      := 14
        ,p_centered_2       BOOLEAN     := TRUE -- false give left align
    );
```
## PdfGen.set_page_header

A one to three line header with one or more of left justified, centered and right justified text values
on each line.
You also have control over the font for each line, but not separately for each string on the line.
The placeholder strings **#PAGE_NR#**, **"PAGE_COUNT#**, and **!PAGE_VAL#** in your
text parameters will be replaced with the values for each page.

```sql
    PROCEDURE set_page_header(
         p_txt_center       VARCHAR2    := NULL
        ,p_txt_left         VARCHAR2    := NULL
        ,p_txt_right        VARCHAR2    := NULL
        ,p_fontsize_pt      NUMBER      := 18
        ,p_font_family      VARCHAR2    := 'helvetica'
        ,p_style            VARCHAR2    := 'b'
        ,p_txt_center_2     VARCHAR2    := NULL
        ,p_txt_left_2       VARCHAR2    := NULL
        ,p_txt_right_2      VARCHAR2    := NULL
        ,p_fontsize_pt_2    NUMBER      := 14
        ,p_font_family_2    VARCHAR2    := 'helvetica'
        ,p_style_2          VARCHAR2    := 'b'
        ,p_txt_center_3     VARCHAR2    := NULL
        ,p_txt_left_3       VARCHAR2    := NULL
        ,p_txt_right_3      VARCHAR2    := NULL
        ,p_fontsize_pt_3    NUMBER      := 14
        ,p_font_family_3    VARCHAR2    := 'helvetica'
        ,p_style_3          VARCHAR2    := 'b'
    );
```

## PdfGen.set_page_proc

When the *set_page_header* and *set_page_footer* procedures just won't do it,
you can build your own callback procedure that will be applied on every page.
The procedure *apply_header* can serve as a guide. 

```sql
    PROCEDURE set_page_proc(p_sql_block CLOB);
```

Note that your callback must be either completely implemented in the 
anonymous PL/SQL block or a public procedure called from it 
like *apply_header*. *p_sql_block* will be called as:

```sql
    EXECUTE IMMEDIATE variable_holding_p_sql_block USING v_page_number, v_page_count, v_page_val;
```

so you must provide three bind placeholders (:var1, :var2, :var3) in your *p_sql_block*
regardless of whether you use them.

## PdfGen.refcursor2table

Replaces *as_pdf3.refcursor2table*. The first form optionally obtains the column widths and headers
from the column "names" in the query result set. Grid line rectangles are by default drawn around
all of the cells as in *as_pdf3*, but it can be turned off. Both forms center the grid between
the left and right margins.

```sql
    PROCEDURE refcursor2table(
        p_src                       SYS_REFCURSOR
        -- if true, calculate the headers and widths from query column names
        -- if false, then there are no column headers printed and column start positions
        -- are equally spaced across the printable area
        ,p_col_headers              BOOLEAN         := FALSE 
        -- index to column to perform a page break upon value change
        ,p_break_col                BINARY_INTEGER  := NULL
        ,p_grid_lines               BOOLEAN         := TRUE
    );
```

The second form provides greater control over the column headers and column widths.
See the [Example](#example) above for declaring and populating the widths and headers collections.

```sql
    PROCEDURE refcursor2table(
        p_src                       SYS_REFCURSOR
        -- you can provide width values and NOT provide headers if you do not want them to print
        ,p_widths                   t_col_widths    
        ,p_headers                  t_col_headers  
        ,p_bold_headers             BOOLEAN         := FALSE
        ,p_char_widths_conversion   BOOLEAN         := FALSE -- you almost certainly want TRUE
        -- index to column to perform a newpage call upon value change
        ,p_break_col                BINARY_INTEGER  := NULL
        ,p_grid_lines               BOOLEAN         := TRUE
    );
```
## PdfGen.get_pdf

Although it calls *as_pdf3.get_pdf* to retrieve the BLOB, you must call the *PdfGen* version instead
to apply the callback procedures including the headers and footers. *get_pdf* "finishes"
the PDF file and generates the BLOB.

```sql
    FUNCTION get_pdf RETURN BLOB;
```

## PdfGen.save_pdf

Although it calls *as_pdf3.save_pdf* to write the file to the directory on the Oracle server
that you specify, you must call the *PdfGen* version instead to apply the callback
procedures including headers and footers. *save_pdf* "finishes" the PDF file, then writes it.

Note that anyone granted execute to the package *as_pdf3* or *PdfGen* can write to directories
that your schema has write access to, but not their own, unless defined with invoker rights.
The default implementation in this repository defines the packages with invoker 
rights (AUTHID CURRENT_USER). Think carefully before changing that.

```sql
    PROCEDURE save_pdf(
        p_dir       VARCHAR2
        ,p_filename VARCHAR2
        ,p_freeblob BOOLEAN := TRUE
    );
```
