--
-- comment this out if you do not want to use app_log. Uncomment or put this line in
-- your deploy script if you are going to deploy and use app_log.
--ALTER SESSION SET PLSQL_CCFLAGS='use_app_log:TRUE';
--
CREATE OR REPLACE PACKAGE PdfGen
-- This allows writes to a directory by calling as_pdf3.save_pdf. 
-- Think about who you give execute to. If you are going to give
-- it to public, you might want to use invoker rights.
--AUTHID CURRENT_USER
AS
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
-- https://github.com/lee-lindley/PdfGen
--
-- README.md -- do not put # in first char of line in this comment or sqlplus will puke.
-- :s/^--//
--# PdfGen.sql
--
--*PdfGen* extends and enhances (replaces) the *as_pdf3.cursor2table* functionality
--with respect to column headers and widths, plus the ability to capture a column
--page break value for the page_procs callbacks, and go to a new page when the 
--break-column value changes.  Everything is implemented using the *as_pdf3* 
--public interface.
--
--There are many report generators in the world. Most of them cost money.  This 
--is free, powerful enough for some common use cases, and a little easier than 
--using *as_pdf3* directly.
--
--## Use Case
--
--The use case for this package is to perform a small subset of sqlplus report 
--generation directly inside the database. 
--
--Required features include page headers and footers with page break column 
--values and hidden columns. (SQL already provides SUM Subtotals and Totals using 
--*GROUPING SETS*, so that feature of sqlplus reports is redundant.) Rather 
--than pulling the data out to a client sqlplus session on an ETL server, 
--converting to PDF, then loading it back into the database as a BLOB, we do 
--so directly in PL/SQL.
--
--We also gain page format, margins, and font control, plus optional grid 
--lines/cells for the column data values. We produce a more attractive finished 
--product than can be generated from sqlplus.
--
--There are enough similarties to sqlplus report generation that it should be 
--familiar and relatively easy to convert existing reports.
--
--## Example
--
--    CREATE OR REPLACE FUNCTION test0 RETURN BLOB
--    IS
--        v_src       SYS_REFCURSOR;
--        v_blob      BLOB;
--        v_widths    PdfGen.t_col_widths;
--        v_headers   PdfGen.t_col_headers;
--        FUNCTION get_src RETURN SYS_REFCURSOR IS
--            l_src SYS_REFCURSOR;
--        BEGIN
--          OPEN l_src FOR
--            WITH a AS (
--                SELECT e.employee_id, e.last_name, e.first_name, d.department_name
--                    ,SUM(salary) AS salary          -- emulate sqplus COMPUTE SUM
--                FROM hr.employees e
--                INNER JOIN hr.departments d
--                    ON d.department_id = e.department_id
--                GROUP BY GROUPING SETS (
--                                                    -- seemingly useless SUM on single record, 
--                                                    -- but required to get detail records
--                                                    -- in same query as the subtotal and total aggregates
--                    (e.employee_id, e.last_name, e.first_name, d.department_name)
--                    ,(d.department_name)            -- sqlplus COMPUTE SUM of salary ON department_name
--                    ,()                             -- sqlplus COMPUTE SUM of salary ON report - the grand total
--                )
--            ) SELECT employee_id
--                -- NULL last_name indicates an aggregate result.
--                -- NULL department_name indicates it was the grand total
--                -- Similar to the LABEL on COMPUTE SUM
--                ,NVL(last_name, CASE WHEN department_name IS NULL
--                                    THEN LPAD('GRAND TOTAL:',25)
--                                    ELSE LPAD('DEPT TOTAL:',25)
--                                END
--                ) AS last_name
--                ,first_name
--                ,department_name
--                ,LPAD(TO_CHAR(salary,'$999,999,999.99'),16) -- leave space for sign even though we will not have one
--            FROM a
--            ORDER BY department_name NULLS LAST     -- to get the aggregates after detail
--                ,a.last_name NULLS LAST             -- notice based on FROM column value, not the one we munged in resultset
--                ,first_name
--            ;
--          RETURN l_src;
--        END;
--    BEGIN
--                                                    -- Similar to the sqlplus COLUMN HEADING commands
--        v_headers(1) := 'Employee ID';
--        v_widths(1)  := 11;
--        v_headers(2) := 'Last Name';
--        v_widths(2)  := 25;
--        v_headers(3) := 'First Name';
--        v_widths(3)  := 20;
--                                                    -- will not print this column, 
--                                                    -- just capture it for column page break
--        v_headers(4) := NULL;                       --'Department Name'
--        v_widths(4)  := 0;                          -- sqlplus COLUMN NOPRINT 
--        v_headers(5) := 'Salary';
--        v_widths(5)  := 16;
--        --
--        PdfGen.init;
--        PdfGen.set_page_format(
--            p_format            => 'LETTER' 
--            ,p_orientation      => 'PORTRAIT'
--            ,p_top_margin       => 1
--            ,p_bottom_margin    => 1
--            ,p_left_margin      => 0.75
--            ,p_right_margin     => 0.75
--        );
--        PdfGen.set_footer;                          -- 'Page #PAGE_NR# of "PAGE_COUNT#' is the default
--                                                    -- sqlplus TITLE command
--        PdfGen.set_header(
--            p_txt               => 'Employee Salary Report'
--            ,p_font_family      => 'helvetica'
--            ,p_style            => 'b'
--            ,p_fontsize_pt      => 16
--            ,p_centered         => TRUE
--            ,p_txt_2            => 'Department: !PAGE_VAL#'
--            ,p_fontsize_pt_2    => 12
--            ,p_centered_2       => FALSE            -- left align
--        );
--        --
--        as_pdf3.set_font('courier', 'n', 10);
--        v_src := get_src;                           -- open the query cursor
--        PdfGen.refcursor2table(
--            p_src                       => v_src
--            ,p_widths                   => v_widths
--            ,p_headers                  => v_headers
--            ,p_bold_headers             => TRUE     -- also light gray background on headers
--            ,p_char_widths_conversion   => TRUE
--            ,p_break_col                => 4        -- sqlplus BREAK ON column
--            ,p_grid_lines               => FALSE
--        );
--        v_blob := PdfGen.get_pdf;
--        BEGIN
--            CLOSE v_src;                            -- likely redundant, but paranoid is good
--        EXCEPTION WHEN invalid_cursor THEN NULL;
--        END;
--        -- can insert into a table or add to a zip archive blob or attach to an email
--        RETURN v_blob;                              
--    END test0;
--
--## Retrieve Blob and View
--
--With SqlDeveloper or Toad 
--
--    SELECT test0 FROM dual;
--
--Double click on the BLOB value in the results grid. In SqlDeveloper you get a 
--pencil icon. Click on that and choose *download* (toad is similar). Save the 
--blob to a file named test0.pdf. Open in a pdf viewer.
--
--## Results
--
-- ![test0_pg1](/images/test0_pg1.png)
--
-- ![test0_pgx](/images/test0_pgx.png)
--
--Pdf files from test_PdfGen are in the *samples* folder. Github will display 
--them when selected.
--
--## A Few Details
--
--Column widths may be set to 0 for NOPRINT, so Break Columns where the value is 
--captured and printed in the page header via a callback can be captured, but 
--optionally not printed with the record. Note that if grouping/breaking on 
--multiple columns is needed you can concatenate values into a string for a
--single non-printing break-column, then parse it in your callback procedure.
--
--The *as_pdf3* "page_procs" callback facility is duplicated (both are called) 
--so that the page break column value can be supplied in addition to the page 
--number and page count that the original supported. One major difference is the 
--use of bind placeholders instead of direct string substitution in your PL/SQL 
--block. We follow the original convention for substitution strings in the 
--text provided to built-in header and footer procedures, but internally rather 
--than directly to the anonymous block. You will be providing positional bind 
--placeholders (:var1, :var2, :var3) for EXECUTE IMMEDIATE in the PL/SQL block 
--strings you add to page_procs. This solves a nagging problem with quoting 
--as well as eliminating potential sql injection.
--
--Example:
--
--    PdfGen.set_page_proc(
--        q'[BEGIN 
--            yourpkgname.apply_footer(
--                p_page_nr => :page_nr
--                ,p_page_count => :page_count
--                ,p_page_val => :page_val); 
--            END;
--        ]'
--    );
--
--That block (*g_page_procs(p)*) is then executed with:
--
--    EXECUTE IMMEDIATE g_page_procs(p) USING i, v_page_count
--        -- do not try to bind a non-existent collection element
--        ,CASE WHEN g_pagevals.EXISTS(i) THEN g_pagevals(i) ELSE NULL END
--    ;
--
--where *i* is the page number and *g_pagevals(i)* is the page specific column break
--value captured while the query result set was processed.
--
--Also provided are simplified methods for generating semi-standard page header
--and footer. You can use these procedures as a template for building your own 
--page_proc procedure if they do not meet your needs.
--
--You can mix and match calls to *as_pdf3* procedures and functions simultaneous
--with *PdfGen*. In fact you are expected to do so with procedures such 
--as *as_pdf3.set_font*.
--
--Be aware that the concept of *centered* in *as_pdf3* means centered on the page.
--*PdfGen* centers between the left and right margins. If you are using 
--*as_pdf3.write* with align=>'center' be aware of this difference. If your left
--and write margins are the same, it will not matter.

    --
    -- not sure why plain table collections were used in as_pdf3. I have some guesses, but 
    -- it does not matter. 
    --
    TYPE t_col_widths IS TABLE OF NUMBER INDEX BY BINARY_INTEGER;
    TYPE t_col_headers IS TABLE OF VARCHAR2(4000) INDEX BY BINARY_INTEGER;

    -- you can put page specific values here for !PAGE_VAL# yourself, though it is 
    -- not the intended design (which is for column breaks).  The values are not
    -- used until we "finish" the report which is during get_pdf() or save_pdf().
    -- Any point up to those calls you can muck with this table if you so desire.
    --
    -- index is by page number 1..x, while as_pdf3 uses 0..x-1 for indexes to the pages
    TYPE t_pagevals IS TABLE OF VARCHAR2(32767) INDEX BY BINARY_INTEGER;
    g_pagevals      t_pagevals;

    -- must call this init which also calls as_pdf3.init
    PROCEDURE init;

    -- mandator to use these instead of as_pdf3 versions (which are called by these).
    FUNCTION get_pdf RETURN BLOB;
    PROCEDURE save_pdf(
        p_dir       VARCHAR2
        ,p_filename VARCHAR2
        ,p_freeblob BOOLEAN := TRUE
    );

    -- combines functionality of mulitple as_pdf3 calls and uses American default values.
    -- not arguing those are better - just what I am accustomed to.
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

    -- two styles of report grid. The first either equal distances the columns across the printable area
    -- or if p_col_headers is true, uses your query column names to determine the width of each column. 
    -- Pad your names with spaces (i.e. colval AS "Column Header 1    ") to set the widths. This can be 
    -- a convenient shortcut for simple results.
    --
    -- Note that there are limitations to this and I would not try to use query column headers longer
    -- than 30 characters (though I suspect up to 128 MIGHT work). At some point it is just unweildly
    -- and you would be better off setting up the header/width arrays.
    --
    -- Both versions allow printing with or without rectangle grids around the column values (cells).
    --
    -- The grid is centered between the margins (not centered on the page, but between the margins).
    --
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
    -- the second style uses arrays of column header values and column widths you provide,
    -- again centering the results on the page.
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

    --
    -- register a callback procedure or simple anonymous block to finish off pages at the end.
    -- Normally used for page headers and footers. The dynamic SQL string is called with EXECUTE IMMEDIATE
    -- and is passed 3 bind values with the USING clause that you must consume whether you want them or not.
    --
    PROCEDURE set_page_proc(p_sql_block CLOB);
    -- Examples:
    -- a callback to a procedure in your own package
    -- set_page_proc(q'[BEGIN yourpkgname.xyz_apply_header(p_page_nr => :page_nr, p_page_count => :page_count, p_page_val => :page_val); END;]');
    --
    -- a custom footer:
    -- set_page_proc(
    --    q'[DECLARE
    --        p_page_nr     NUMBER :=       :page_nr;
    --        p_page_count  NUMBER :=       :page_count;
    --        -- have to bind page_val even though not using it
    --        p_page_val    VARCHAR2(4000)  := :page_val;
    --        -- we print below the margin by height of font and padding of 5 points
    --        v_y           NUMBER := as_pdf3.get(as_pdf3.c_get_margin_bottom) - 8 - 5;
    --        v_txt         VARCHAR2(4000);
    --    BEGIN
    --        as_pdf3.set_font('helvetica','n',8);
    --        -- left justified
    --        as_pdf3.put_txt(
    --            p_txt   => 'Report Date: '||TO_CHAR(SYSDATE,'MM/DD/YYYY')
    --            ,p_x    => PdfGen.x_left_justify
    --            ,p_y    => v_y
    --        );
    --        v_txt := 'Page '||LTRIM(TO_CHAR(p_page_nr))||' of '||LTRIM(TO_CHAR(p_page_count));
    --        -- centered on same line as prior text that was left justified
    --        as_pdf3.put_text(
    --            p_txt   => v_txt
    --            ,p_x    => PdfGen.x_center(v_txt)
    --            ,p_y    => v_y
    --        );
    --    END;]'
    --);
    
    -- simple 1 line footer inside the bottom margin 
    PROCEDURE set_footer(
        p_txt           VARCHAR2    := 'Page #PAGE_NR# of "PAGE_COUNT#'
        ,p_font_family  VARCHAR2    := 'helvetica'
        ,p_style        VARCHAR2    := 'n'
        ,p_fontsize_pt  NUMBER      := 8
        ,p_centered     BOOLEAN     := TRUE -- false give left align
    );
    PROCEDURE set_complex_footer(
         p_txt_center   VARCHAR2    := NULL
        ,p_txt_left     VARCHAR2    := NULL
        ,p_txt_right    VARCHAR2    := NULL
        ,p_font_family  VARCHAR2    := 'helvetica'
        ,p_style        VARCHAR2    := 'n'
        ,p_fontsize_pt  NUMBER      := 8
    );
    -- callback proc. Not part of user interface
    PROCEDURE apply_footer(
        p_page_nr       NUMBER
        ,p_page_count   NUMBER
        ,p_page_val     VARCHAR2
    );
    -- simple header slightly into the top margin with page specific substitutions
    -- Optionally can be two lines such as might be useful with column-break values on the
    -- second line.
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
    PROCEDURE set_complex_header(
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


    -- callback proc. Not part of user interface
    PROCEDURE apply_header (
        p_page_nr       NUMBER
        ,p_page_count   NUMBER
        ,p_page_val     VARCHAR2
    );

    --
    -- convenience functions for calculating where to start writing for as_pdf3.put_txt.
    --
    -- returns left margin
    FUNCTION x_left_justify RETURN NUMBER;
    -- returns x_value at which to start this string with this font to right justify it
    FUNCTION x_right_justify(p_txt VARCHAR2) RETURN NUMBER;
    -- returns x_value at which to start this string with this font to center it between the margins
    FUNCTION x_center(p_txt VARCHAR2) RETURN NUMBER;
    -- returns y_value of the top margin. Add to this value to print a header line above the margin
    FUNCTION y_top_margin RETURN NUMBER;

    -- Y value of the last line written by cursor2table
    FUNCTION get_y RETURN NUMBER;

END PdfGen;
/
show errors
CREATE OR REPLACE PACKAGE BODY PdfGen
AS
    -- pl/sql blocs given to execute immediate on every page at the very end.
    -- assigned via set_page_proc
    TYPE t_page_procs IS TABLE OF CLOB INDEX BY BINARY_INTEGER;
    g_page_procs    t_page_procs;

    TYPE t_ctx IS TABLE OF VARCHAR2(32767) INDEX BY VARCHAR2(64);
    g_footer    t_ctx;
    g_header    t_ctx;

    g_y                     NUMBER; -- the y value of the last grid line printed;

$if $$use_app_log $then
    g_log                   app_log_udt;
$end

    PROCEDURE apply_page_procs
    IS
    --
    -- Apply any provided PdfGen callbacks to every page
    --
    -- get_pdf and save_pdf still call the as_pdf3 versions of get_pdf and save_pdf,
    -- which call as_pdf3.finish_pdf that applies the as_pdf3 page procs. I do not know why
    -- you would use those as oppsed to PdfGen page procs, but you can.
    --
        v_page_count    BINARY_INTEGER;
    BEGIN
        IF g_page_procs.COUNT > 0
        THEN
            IF as_pdf3.get(as_pdf3.c_get_page_count) = 0
                THEN as_pdf3.new_page;
            END IF;
            v_page_count := as_pdf3.get(as_pdf3.c_get_page_count);
            FOR i IN 1..v_page_count
            LOOP
                as_pdf3.pr_goto_page(i); -- sets as_pdf3.g_page_nr
                FOR p IN g_page_procs.FIRST .. g_page_procs.LAST
                LOOP
                    --
                    -- execute the callbacks on every page. Provide argument of page number, number of pages
                    -- and a page specific value (set by break column in cursor2table) as positional bind values to 
                    -- the dynamic sql block. The block should reference the bind values 1 time positionally
                    -- with :page_nr, :page_count, :pageval (the names do not matter. position of the : placeholders does).
                    -- Remember that the callback has access to package global states but is not aware of
                    -- the local callstack or variables in the procedure that created and set it. Must use 
                    -- fully qualified names for any procedures/functions called, not the short names available 
                    -- to callers inside the same package. The anonymous block is not part of either package and only
                    -- has access to the public interface of any package it uses (but operates in the same session 
                    -- with the same privs, same package global variable values, and same transaction state). 
                    --
                    BEGIN
--$if $$use_app_log $then
--                        g_log.log_p('calling g_page_procs('||TO_CHAR(p)||') for page nr:'||TO_CHAR(i));
--$end
                        EXECUTE IMMEDIATE g_page_procs(p) USING i, v_page_count
                            -- do not try to bind a non-existent collection element
                            ,CASE WHEN g_pagevals.EXISTS(i) THEN g_pagevals(i) ELSE NULL END;

                    EXCEPTION
                        WHEN OTHERS THEN -- we ignore the error, but at least we print it for debugging
$if $$use_app_log $then
                            g_log.log_p(SQLERRM);
                            g_log.log_p(DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
                            g_log.log_p(DBMS_UTILITY.format_call_stack);
                            g_log.log_p(g_page_procs(p));
                            g_log.log_p('i='||TO_CHAR(i)||' page_count: '||TO_CHAR(v_page_count)||' page_val: '
                                ||CASE WHEN g_pagevals.EXISTS(i) THEN g_pagevals(i) ELSE NULL END
                            );
$else
                            DBMS_OUTPUT.put_line('sqlerrm : '||SQLERRM);
                            DBMS_OUTPUT.put_line('backtrace : '||DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
                            DBMS_OUTPUT.put_line('callstack : '||DBMS_UTILITY.format_call_stack);
                            DBMS_OUTPUT.put_line('p_page_procs(p): '||g_page_procs(p));
                            DBMS_OUTPUT.put_line('i='||TO_CHAR(i)||' page_count: '||TO_CHAR(v_page_count)||' page_val: '
                                ||CASE WHEN g_pagevals.EXISTS(i) THEN g_pagevals(i) ELSE NULL END
                            );
$end
                    END;
                END LOOP;
            END LOOP;
        END IF;
    END apply_page_procs;

    PROCEDURE apply_footer(
        p_page_nr       NUMBER
        ,p_page_count   NUMBER
        ,p_page_val     VARCHAR2
    ) IS
        v_txt               VARCHAR2(32767);
        c_padding           CONSTANT NUMBER := 5; --space beteen footer line and margin
        v_which             VARCHAR2(64);
    BEGIN
        as_pdf3.set_font(g_footer('font_family'), g_footer('style'), TO_NUMBER(g_footer('fontsize_pt')));
        FOR i IN 1..3
        LOOP
            v_which := CASE i WHEN 1 THEN 'txt_left' WHEN 2 THEN 'txt_center' WHEN 3 THEN 'txt_right' END;
            IF g_footer.EXISTS(v_which) THEN
                -- we use the original text substitution strings, but in a text variable, 
                -- not a pl/sql block.
                v_txt := REPLACE(
                            REPLACE(
                                REPLACE(g_footer(v_which), '#PAGE_NR#', LTRIM(TO_CHAR(p_page_nr)))
                                ,'"PAGE_COUNT#', LTRIM(TO_CHAR(p_page_count))
                            )
                            ,'!PAGE_VAL#', p_page_val
                        );
                as_pdf3.put_txt(
                     p_txt => v_txt
                    ,p_x    => CASE i
                                WHEN 1 THEN x_left_justify
                                WHEN 2 THEN x_center(v_txt)
                                WHEN 3 THEN x_right_justify(v_txt)
                               END
                    ,p_y    => as_pdf3.get(as_pdf3.c_get_margin_bottom) - TO_NUMBER(g_footer('fontsize_pt')) - c_padding
                );
            END IF;
        END LOOP;
    END apply_footer;


    PROCEDURE set_complex_footer(
         p_txt_center   VARCHAR2    := NULL
        ,p_txt_left     VARCHAR2    := NULL
        ,p_txt_right    VARCHAR2    := NULL
        ,p_font_family  VARCHAR2    := 'helvetica'
        ,p_style        VARCHAR2    := 'n'
        ,p_fontsize_pt  NUMBER      := 8
    ) IS
    BEGIN
        IF p_txt_center IS NOT NULL OR p_txt_left IS NOT NULL OR p_txt_right IS NOT NULL THEN
            g_footer('fontsize_pt')     := LTRIM(TO_CHAR(p_fontsize_pt));
            g_footer('font_family')     := p_font_family;
            g_footer('style')           := p_style;
            IF p_txt_center IS NOT NULL
                THEN g_footer('txt_center') := p_txt_center;
            END IF;
            IF p_txt_left IS NOT NULL
                THEN g_footer('txt_left') := p_txt_left;
            END IF;
            IF p_txt_right IS NOT NULL
                THEN g_footer('txt_right') := p_txt_right;
            END IF;

            set_page_proc(q'[BEGIN PdfGen.apply_footer(p_page_nr => :page_nr, p_page_count => :page_count, p_page_val => :page_val); END;]');
        END IF;
    END set_complex_footer;

    PROCEDURE set_footer(
        p_txt           VARCHAR2    := 'Page #PAGE_NR# of "PAGE_COUNT#'
        ,p_font_family  VARCHAR2    := 'helvetica'
        ,p_style        VARCHAR2    := 'n'
        ,p_fontsize_pt  NUMBER      := 8
        ,p_centered     BOOLEAN     := TRUE -- false give left align
    ) IS
    BEGIN  
        IF p_txt IS NOT NULL THEN
            g_footer('fontsize_pt')     := p_fontsize_pt;
            g_footer('font_family')     := p_font_family;
            g_footer('style')           := p_style;
            g_footer(CASE WHEN p_centered THEN 'txt_center' ELSE 'txt_left' END) := p_txt;
            set_page_proc(q'[BEGIN PdfGen.apply_footer(p_page_nr => :page_nr, p_page_count => :page_count, p_page_val => :page_val); END;]');
        END IF;
    END set_footer;

    PROCEDURE apply_header (
        p_page_nr       NUMBER
        ,p_page_count   NUMBER
        ,p_page_val     VARCHAR2
    ) IS
        v_txt           VARCHAR2(32767);
        c_y_padding     CONSTANT NUMBER := 8; --space between bottom heading line and margin
        c_y_padding2    CONSTANT NUMBER := 4; --space between 2 heading lines
        c_rf            CONSTANT NUMBER := 0.2; -- raise factor. Anton uses the term. Spacing so bottom of font is not right on the line
        v_which         VARCHAR2(64);
        v_y             NUMBER;
        v_fontsize_pt_2 NUMBER := TO_NUMBER(g_header('fontsize_pt_2'));
        v_fontsize_pt_3 NUMBER := TO_NUMBER(g_header('fontsize_pt_3'));
    BEGIN
        IF TO_NUMBER(g_header('fontsize_pt')) > 0  THEN
            as_pdf3.set_font(g_header('font_family'), g_header('style'), TO_NUMBER(g_header('fontsize_pt')));
            FOR i IN 1..3
            LOOP
                v_y := y_top_margin + c_y_padding + (c_rf * TO_NUMBER(g_header('fontsize_pt')))
                    + CASE WHEN v_fontsize_pt_2 > 0 THEN c_y_padding2 + ((1 + c_rf) * v_fontsize_pt_2) ELSE 0 END
                    + CASE WHEN v_fontsize_pt_3 > 0 THEN c_y_padding2 + ((1 + c_rf) * v_fontsize_pt_3) ELSE 0 END
                ;
                v_which := CASE i WHEN 1 THEN 'txt_left' WHEN 2 THEN 'txt_center' WHEN 3 THEN 'txt_right' END;
                IF g_header.EXISTS(v_which) THEN
                    v_txt := REPLACE(
                                REPLACE(
                                    REPLACE(g_header(v_which), '#PAGE_NR#', LTRIM(TO_CHAR(p_page_nr)))
                                    ,'"PAGE_COUNT#', LTRIM(TO_CHAR(p_page_count)))
                                ,'!PAGE_VAL#', p_page_val
                            );
                    -- line 1
                    as_pdf3.put_txt(
                        p_txt   => v_txt
                        ,p_x    => CASE i
                                    WHEN 1 THEN x_left_justify
                                    WHEN 2 THEN x_center(v_txt)
                                    WHEN 3 THEN x_right_justify(v_txt)
                                   END
                        ,p_y => v_y
                    );
                END IF;
            END LOOP;
        END IF;
        IF v_fontsize_pt_2 > 0 THEN
            as_pdf3.set_font(g_header('font_family_2'), g_header('style_2'), v_fontsize_pt_2);
            FOR i IN 1..3
            LOOP
                v_y := y_top_margin + c_y_padding + (c_rf * v_fontsize_pt_2)
                    + CASE WHEN v_fontsize_pt_3 > 0 THEN c_y_padding2 + ((1 + c_rf) * v_fontsize_pt_3) ELSE 0 END
                ;
                v_which := CASE i WHEN 1 THEN 'txt_left_2' WHEN 2 THEN 'txt_center_2' WHEN 3 THEN 'txt_right_2' END;
                IF g_header.EXISTS(v_which) THEN
                    v_txt := REPLACE(
                                REPLACE(
                                    REPLACE(g_header(v_which), '#PAGE_NR#', LTRIM(TO_CHAR(p_page_nr)))
                                    ,'"PAGE_COUNT#', LTRIM(TO_CHAR(p_page_count)))
                                ,'!PAGE_VAL#', p_page_val
                            );
                    -- line 1
                    as_pdf3.put_txt(
                        p_txt   => v_txt
                        ,p_x    => CASE i
                                    WHEN 1 THEN x_left_justify
                                    WHEN 2 THEN x_center(v_txt)
                                    WHEN 3 THEN x_right_justify(v_txt)
                                   END
                        ,p_y => v_y
                    );
                END IF;
            END LOOP;
        END IF;
        IF v_fontsize_pt_3 > 0 THEN
            as_pdf3.set_font(g_header('font_family_3'), g_header('style_3'), v_fontsize_pt_3);
            FOR i IN 1..3
            LOOP
                v_y := y_top_margin + c_y_padding + (c_rf * v_fontsize_pt_3);
                v_which := CASE i WHEN 1 THEN 'txt_left_3' WHEN 2 THEN 'txt_center_3' WHEN 3 THEN 'txt_right_3' END;
                IF g_header.EXISTS(v_which) THEN
                    v_txt := REPLACE(
                                REPLACE(
                                    REPLACE(g_header(v_which), '#PAGE_NR#', LTRIM(TO_CHAR(p_page_nr)))
                                    ,'"PAGE_COUNT#', LTRIM(TO_CHAR(p_page_count)))
                                ,'!PAGE_VAL#', p_page_val
                            );
                    -- line 1
                    as_pdf3.put_txt(
                        p_txt   => v_txt
                        ,p_x    => CASE i
                                    WHEN 1 THEN x_left_justify
                                    WHEN 2 THEN x_center(v_txt)
                                    WHEN 3 THEN x_right_justify(v_txt)
                                   END
                        ,p_y => v_y
                    );
                END IF;
            END LOOP;
        END IF;
    END apply_header;

    PROCEDURE set_header(
        p_txt               VARCHAR2
        ,p_font_family      VARCHAR2    := 'helvetica'
        ,p_style            VARCHAR2    := 'b'
        ,p_fontsize_pt      NUMBER      := 18
        ,p_centered         BOOLEAN     := TRUE -- false give left align
        ,p_txt_2            VARCHAR2    := NULL
        ,p_fontsize_pt_2    NUMBER      := 14
        ,p_centered_2       BOOLEAN     := TRUE -- false give left align
    ) IS
    BEGIN
        set_complex_header(
            p_txt_center    => CASE WHEN p_centered THEN p_txt END
            ,p_txt_right    => CASE WHEN NOT p_centered THEN p_txt END
            ,p_txt_left     => NULL
            ,p_fontsize_pt  => p_fontsize_pt
            ,p_font_family  => p_font_family
            ,p_style        => p_style
            ,p_txt_center_2 => CASE WHEN p_centered_2 THEN p_txt_2 END
            ,p_txt_left_2   => CASE WHEN NOT p_centered_2 THEN p_txt_2 END
            ,p_fontsize_pt_2    => p_fontsize_pt_2
        );
    END set_header;

    PROCEDURE set_complex_header(
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
    ) IS
    BEGIN
        IF p_txt_center IS NOT NULL
            OR p_txt_left IS NOT NULL
            OR p_txt_right IS NOT NULL
        THEN
            g_header('fontsize_pt') := LTRIM(TO_CHAR(p_fontsize_pt));
            g_header('font_family') := p_font_family;
            g_header('style') := p_style;
            IF p_txt_center IS NOT NULL
                THEN g_header('txt_center') := p_txt_center;
            END IF;
            IF p_txt_left IS NOT NULL
                THEN g_header('txt_left') := p_txt_left;
            END IF;
            IF p_txt_right IS NOT NULL
                THEN g_header('txt_right') := p_txt_right;
            END IF;
        ELSE
            g_header('fontsize_pt') := '0';
        END IF;

        IF p_txt_center_2 IS NOT NULL
            OR p_txt_left_2 IS NOT NULL
            OR p_txt_right_2 IS NOT NULL
        THEN
            g_header('fontsize_pt_2') := LTRIM(TO_CHAR(p_fontsize_pt_2));
            g_header('font_family_2') := p_font_family_2;
            g_header('style_2') := p_style_2;
            IF p_txt_center_2 IS NOT NULL
                THEN g_header('txt_center_2') := p_txt_center_2;
            END IF;
            IF p_txt_left_2 IS NOT NULL
                THEN g_header('txt_left_2') := p_txt_left_2;
            END IF;
            IF p_txt_right_2 IS NOT NULL
                THEN g_header('txt_right_2') := p_txt_right_2;
            END IF;
        ELSE
            g_header('fontsize_pt_2') := '0'; -- need for calculate y for line 1
        END IF;

        IF p_txt_center_3 IS NOT NULL
            OR p_txt_left_3 IS NOT NULL
            OR p_txt_right_3 IS NOT NULL
        THEN
            g_header('fontsize_pt_3') := LTRIM(TO_CHAR(p_fontsize_pt_3));
            g_header('font_family_3') := p_font_family_3;
            g_header('style_3') := p_style_3;
            IF p_txt_center_3 IS NOT NULL
                THEN g_header('txt_center_3') := p_txt_center_3;
            END IF;
            IF p_txt_left_3 IS NOT NULL
                THEN g_header('txt_left_3') := p_txt_left_3;
            END IF;
            IF p_txt_right_3 IS NOT NULL
                THEN g_header('txt_right_3') := p_txt_right_3;
            END IF;
        ELSE
            g_header('fontsize_pt_3') := '0'; -- need for calcualte y for lines 1 and 2
        END IF;

        IF g_header.COUNT > 3 THEN -- we got 3 of them in the else blocks
            set_page_proc(q'[BEGIN PdfGen.apply_header(p_page_nr => :page_nr, p_page_count => :page_count, p_page_val => :page_val); END;]');
        END IF;
    END set_complex_header;

    PROCEDURE set_page_proc(p_sql_block CLOB)
    IS
    BEGIN
        -- will start at index 0
        g_page_procs(g_page_procs.COUNT) := p_sql_block;
    END set_page_proc;

    FUNCTION get_pdf 
    RETURN BLOB
    IS
    BEGIN
        apply_page_procs;
        RETURN as_pdf3.get_pdf;
    END get_pdf;

    PROCEDURE save_pdf(
        p_dir       VARCHAR2
        ,p_filename VARCHAR2
        ,p_freeblob BOOLEAN := TRUE
    ) IS
    BEGIN
        apply_page_procs;
        as_pdf3.save_pdf(
            p_dir       => p_dir
            ,p_filename => p_filename
            ,p_freeblob => p_freeblob
        );
    END save_pdf;

    PROCEDURE init
    IS
    BEGIN
        g_pagevals.DELETE;
        g_page_procs.DELETE;
        g_footer.DELETE;
        g_header.DELETE;
$if $$use_app_log $then
        g_log := app_log_udt('PdfGen');
$end
        as_pdf3.init;
    END init;
    
    FUNCTION x_left_justify
    RETURN NUMBER
    IS
    BEGIN
        RETURN as_pdf3.get(as_pdf3.c_get_margin_left);
    END x_left_justify;

    FUNCTION x_right_justify(p_txt VARCHAR2)
    RETURN NUMBER
    IS
        c_x_padding CONSTANT NUMBER := 2;
    BEGIN
        RETURN as_pdf3.get(as_pdf3.c_get_page_width) 
                - as_pdf3.get(as_pdf3.c_get_margin_right)
                - as_pdf3.str_len(p_txt) 
                - c_x_padding
                ;
    END x_right_justify;

    FUNCTION x_center(p_txt VARCHAR2)
    RETURN NUMBER
    IS
        v_start_x       NUMBER;
        v_left_margin   NUMBER := as_pdf3.get(as_pdf3.c_get_margin_left);
    BEGIN
        v_start_x := (v_left_margin -- x of left margin
                        + ( (
                              (as_pdf3.get(as_pdf3.c_get_page_width) - as_pdf3.get(as_pdf3.c_get_margin_right)) -- x of right margin
                              - v_left_margin
                              )  -- width between margins
                              / 2.0
                          )
                     ) -- this gets us to the midpoint between the margins
                        - (as_pdf3.str_len(p_txt) / 2.0);
        IF v_start_x < v_left_margin THEN
$if $$use_app_log $then
            g_log.log_p('x_center: text length exceeds width between margins so starting at left margin. p_txt='||p_txt);
            g_log.log_p('v_start_x: '||TO_CHAR(v_start_x)||' v_left_margin: '||TO_CHAR(v_left_margin));
$else
            DBMS_OUTPUT.put_line('x_center: text length exceeds width between margins so starting at left margin. p_txt='||p_txt);
            DBMS_OUTPUT.put_line('v_start_x: '||TO_CHAR(v_start_x)||' v_left_margin: '||TO_CHAR(v_left_margin));
$end
            v_start_x := v_left_margin;
        END IF;
        RETURN v_start_x;
    END x_center;

    FUNCTION y_top_margin 
    RETURN NUMBER
    IS
    BEGIN
        RETURN as_pdf3.get(as_pdf3.c_get_page_height) - as_pdf3.get(as_pdf3.c_get_margin_top)
        ;
    END y_top_margin;

    FUNCTION get_y 
    RETURN NUMBER
    IS
    BEGIN
        RETURN g_y;
    END get_y;

    PROCEDURE set_page_format(
        p_format            VARCHAR2 := 'LETTER' --'LEGAL', 'A4', etc... See as_pdf3
        ,p_orientation      VARCHAR2 := 'PORTRAIT' -- or 'LANDSCAPE'
        -- these are inches. Use as_pdf3 procedures if you want other units
        ,p_top_margin       NUMBER := 1
        ,p_bottom_margin    NUMBER := 1
        ,p_left_margin      NUMBER := 0.75
        ,p_right_margin     NUMBER := 0.75
    ) IS
    BEGIN
        as_pdf3.set_page_format(p_format);
        as_pdf3.set_page_orientation(p_orientation);
        as_pdf3.set_margins(p_top_margin, p_left_margin, p_bottom_margin, p_right_margin, 'inch');
        g_y := y_top_margin;
    END set_page_format
    ;

    -- write the report grid onto the page objects creating new pages as needed
    PROCEDURE cursor2table ( 
        p_c integer
        -- count on these being continuous starting at index=1 and matching the query columns
        ,p_widths                   t_col_widths    
        ,p_headers                  t_col_headers  
        ,p_bold_headers             BOOLEAN         := FALSE
        ,p_char_widths_conversion   BOOLEAN         := FALSE
        ,p_break_col                BINARY_INTEGER  := NULL
        ,p_grid_lines               BOOLEAN         := TRUE
    )
    IS
        c_padding  CONSTANT NUMBER := 2;
        c_rf       CONSTANT NUMBER := 0.2; -- raise factor of text above cell bottom 
        v_col_cnt           INTEGER;
$IF DBMS_DB_VERSION.VER_LE_10 $THEN
        v_desc_tab          DBMS_SQL.desc_tab2;
$ELSE
        v_desc_tab          DBMS_SQL.desc_tab3;
$END
        v_date_tab          DBMS_SQL.date_table;
        v_number_tab        DBMS_SQL.number_table;
        v_string_tab        DBMS_SQL.varchar2_table;

        v_bulk_cnt          BINARY_INTEGER := 100;
        v_fetched_rows      BINARY_INTEGER;
        v_page_count        BINARY_INTEGER := as_pdf3.get(as_pdf3.c_get_page_count);
        v_col_widths        t_col_widths;
        -- new left marging for starting each line after calculating how to center the grid between the margins
        v_centered_left_margin  NUMBER;
        v_x                 NUMBER;
        v_y                 NUMBER;
        v_lineheight        NUMBER;
        v_txt               VARCHAR2(32767);

        -- based on dbms_sql column info
        FUNCTION lookup_col_type(p_col_type BINARY_INTEGER)
        RETURN VARCHAR2 -- D ate, N umber, C har
        IS
        BEGIN
            RETURN CASE WHEN p_col_type IN (1, 8, 9, 96, 112)
                        THEN 'C'
                        WHEN p_col_type IN (12, 178, 179, 180, 181 , 231)
                        THEN 'D'
                        WHEN p_col_type IN (2, 100, 101)
                        THEN 'N'
                        ELSE NULL
                   END;
        END;

--
        FUNCTION get_col_val(
            c BINARY_INTEGER -- column index starting at 1
            ,i BINARY_INTEGER -- record number for this bulk fetch
        )
        RETURN VARCHAR2
        IS
            v_str VARCHAR2(32767);
        BEGIN
            CASE lookup_col_type(v_desc_tab(c).col_type)
                WHEN 'N' THEN
                    v_number_tab.DELETE;
                    DBMS_SQL.column_value(p_c, c, v_number_tab);
                    v_str := TO_CHAR(v_number_tab( i + v_number_tab.FIRST()), 'tm9' );
                WHEN 'D' THEN
                    v_date_tab.DELETE;
                    DBMS_SQL.column_value(p_c, c, v_date_tab);
                    v_str := TO_CHAR(v_date_tab( i + v_date_tab.FIRST()), 'MM/DD/YYYY');
                WHEN 'C' THEN
                    v_string_tab.DELETE;
                    DBMS_SQL.column_value(p_c, c, v_string_tab);
                    v_str := v_string_tab(i + v_string_tab.FIRST());
                ELSE
                    NULL;
            END CASE;
            RETURN v_str;
        END;
--
        PROCEDURE show_header
        IS
        BEGIN
            IF p_headers IS NOT NULL AND p_headers.COUNT > 0 THEN
                IF p_bold_headers THEN
                    as_pdf3.set_font(p_family => NULL, p_style => 'B');
                END IF;
                v_x := v_centered_left_margin; 
                FOR c IN 1 .. v_col_cnt
                LOOP
                    CONTINUE WHEN v_col_widths(c) = 0;
                    IF p_bold_headers THEN
                        as_pdf3.rect(v_x, v_y, v_col_widths(c), v_lineheight, '000000', 'D3D3D3');
                    ELSE
                        as_pdf3.rect(v_x, v_y, v_col_widths(c), v_lineheight);
                    END IF;
                    IF c <= p_headers.COUNT
                    then
                        as_pdf3.put_txt(v_x + c_padding, v_y + (c_rf * v_lineheight), p_headers(c));
                    end if; 
                    v_x := v_x + v_col_widths(c); 
                END LOOP;
                v_y := v_y - v_lineheight;
                IF p_bold_headers THEN
                    as_pdf3.set_font(p_family => NULL, p_style => 'N');
                END IF;
            END IF;
        END;
    --
    -- Start procedcure body
    --
    BEGIN
$IF DBMS_DB_VERSION.VER_LE_10 $THEN
        DBMS_SQL.describe_columns2( p_c, v_col_cnt, v_desc_tab );
$ELSE
        DBMS_SQL.describe_columns3( p_c, v_col_cnt, v_desc_tab );
$END
--
        IF as_pdf3.get(as_pdf3.c_get_current_font) IS NULL THEN 
            as_pdf3.set_font('courier', 12);
        END IF;

        -- check for something wrong with widths array
        IF p_widths IS NOT NULL AND p_widths.COUNT <> v_col_cnt THEN
$if $$use_app_log $then
            g_log.log_p('cursor2table called with p_widths.COUNT='||TO_CHAR(p_widths.COUNT)||' but query column count is '||TO_CHAR(v_col_cnt)||', so p_widths is ignored');
$else
            DBMS_OUTPUT.put_line('cursor2table called with p_widths.COUNT='||TO_CHAR(p_widths.COUNT)||' but query column count is '||TO_CHAR(v_col_cnt)||', so p_widths is ignored');
$end
        END IF;

        -- 3 cases of widths
        If p_widths IS NULL OR p_widths.COUNT <> v_col_cnt THEN
            -- 1) widths not provided or not correctly. Split the start positions across the printable area.
            DECLARE
                l_col_width NUMBER := ROUND((as_pdf3.get(as_pdf3.c_get_page_width) - as_pdf3.get(as_pdf3.c_get_margin_left) - as_pdf3.get(as_pdf3.c_get_margin_right)) / v_col_cnt, 1);
            BEGIN
                FOR c IN 1 .. v_col_cnt
                LOOP
                    v_col_widths(c) := l_col_width;
                END LOOP;
            END;
        ELSIF p_char_widths_conversion THEN 
            -- 2) widths are provided in character string length numbers. We assume courier
            -- for the sake of estimating the width. Likely worst case.
            DECLARE
                l_font_width number := 0.61 * as_pdf3.get(as_pdf3.c_get_fontsize); -- assumes courier font width proportion
            BEGIN
                FOR c IN 1 .. p_widths.COUNT
                LOOP
                    v_col_widths(c) := (p_widths(c) * l_font_width) + CASE WHEN p_widths(c) = 0 THEN 0 ELSE c_padding END;
                END LOOP;
            END;
        ELSE
            -- 3) as in as_pdf3 the user gives absolute width in some units I never bothered to be sure about
            -- but I think is points.
            FOR c IN 1 .. p_widths.COUNT
            LOOP
                v_col_widths(c) := p_widths(c);
            END LOOP;
        END IF;

        -- Now add up the column widths and we refigure the left side of page starting point to
        -- center the grid
        DECLARE
            l_tot_width_cols    NUMBER := 0;
            l_left_margin       NUMBER := as_pdf3.get(as_pdf3.c_get_margin_left);
        BEGIN
            FOR c IN 1 ..v_col_widths.COUNT
            LOOP
                l_tot_width_cols := l_tot_width_cols + v_col_widths(c);
            END LOOP;
            v_centered_left_margin := 
                ( l_left_margin -- x of left margin
                    + ( (
                          (as_pdf3.get(as_pdf3.c_get_page_width) - as_pdf3.get(as_pdf3.c_get_margin_right)) -- x of right margin
                          - l_left_margin
                          )  -- width between margins
                          / 2.0
                      )
                 ) -- this gets us to the midpoint between the margins
                - (l_tot_width_cols / 2.0);

            IF v_centered_left_margin < l_left_margin THEN
$if $$use_app_log $then
                g_log.log_p('cursor2table: grid width exceeds space between margins so starting at left margin and likely running off the edge of the page but maybe not. tot_width='
                    ||TO_CHAR(l_tot_width_cols)||' margin to margin is='
                    ||TO_CHAR((as_pdf3.get(as_pdf3.c_get_page_width) - as_pdf3.get(as_pdf3.c_get_margin_right)) - l_left_margin)
                );
$else
                DBMS_OUTPUT.put_line('cursor2table: grid width exceeds space between margins so starting at left margin and likely running off the edge of the page but maybe not. tot_width='
                    ||TO_CHAR(l_tot_width_cols)||' margin to margin is='
                    ||TO_CHAR((as_pdf3.get(as_pdf3.c_get_page_width) - as_pdf3.get(as_pdf3.c_get_margin_right)) - l_left_margin)
                );
$end
                v_centered_left_margin := l_left_margin;
            END IF;
        END;

        -- define the arrays for holding the column values from each bulk fetch
        FOR c IN 1 .. v_col_cnt
        LOOP
            CASE lookup_col_type(v_desc_tab(c).col_type)
                WHEN 'N' THEN
                    DBMS_SQL.define_array(p_c, c, v_number_tab, v_bulk_cnt, 1);
                WHEN 'D' THEN
                    DBMS_SQL.define_array(p_c, c, v_date_tab, v_bulk_cnt, 1);
                WHEN 'C' THEN
                    DBMS_SQL.define_array(p_c, c, v_string_tab, v_bulk_cnt, 1);
                ELSE
                    NULL;
            END CASE;
       END LOOP;

        v_lineheight := as_pdf3.get(as_pdf3.c_get_fontsize) * (1 + c_rf);
        v_y := COALESCE(as_pdf3.get(as_pdf3.c_get_y) ,y_top_margin) - v_lineheight; 

        IF v_page_count = 0 OR v_y < as_pdf3.get(as_pdf3.c_get_margin_bottom) 
        THEN -- either nothing done yet or already wrote a full page and need to start a new one
            as_pdf3.new_page;
            v_page_count := as_pdf3.get(as_pdf3.c_get_page_count);
            v_y := y_top_margin - v_lineheight; 
        END IF;

        show_header;
        --
        -- Now that all the prep is done, lets get this party started writing out
        -- the records from the cursor
        --
        LOOP
            v_fetched_rows := DBMS_SQL.fetch_rows(p_c);
--$if $$use_app_log $then
--            g_log.log_p('fetch '||TO_CHAR(v_fetched_rows)||' rows from cursor');
--$end
            EXIT WHEN v_fetched_rows = 0;
            FOR i IN 0 .. v_fetched_rows - 1
            LOOP
                IF v_y < as_pdf3.get(as_pdf3.c_get_margin_bottom) THEN
                    as_pdf3.new_page;
                    v_page_count := as_pdf3.get(as_pdf3.c_get_page_count);
                    v_y := y_top_margin - v_lineheight; 
                    show_header;
                END IF;
                IF p_break_col IS NOT NULL THEN
                    DECLARE
                        l_v             VARCHAR2(32767) := get_col_val(p_break_col, i);
                    BEGIN
                        IF NOT g_pagevals.EXISTS(v_page_count) THEN
                            g_pagevals(v_page_count) := l_v;
                        ELSIF NVL(g_pagevals(v_page_count),'~#NULL#~') <> NVL(l_v,'~#NULL#~') THEN 
--$if $$use_app_log $then
--                            g_log.log_p('got column break event i='||TO_CHAR(i)
--                                ||' LastVal: '||g_pagevals(v_page_count)
--                                ||' NewVal: '||l_v
--                            );
--$end
                            as_pdf3.new_page;
                            v_page_count := as_pdf3.get(as_pdf3.c_get_page_count);
                            g_pagevals(v_page_count) := l_v;
                            v_y := y_top_margin - v_lineheight; 
                            show_header;
                        END IF;
                    END;
                END IF;
                v_x := v_centered_left_margin; 
                FOR c IN 1 .. v_col_cnt
                LOOP
                    CONTINUE WHEN v_col_widths(c) = 0; -- skip hidden columns
                    IF p_grid_lines THEN
                        as_pdf3.rect(v_x, v_y, v_col_widths(c), v_lineheight);
                    END IF;
                    v_txt := get_col_val(c, i);
                    IF v_txt IS NOT NULL THEN
                        IF lookup_col_type(v_desc_tab(c).col_type) = 'N' 
                            -- need to right justify numbers.
                            THEN as_pdf3.put_txt(v_x + v_col_widths(c) - c_padding - as_pdf3.str_len( v_txt ) 
                                                    ,v_y + (c_rf * v_lineheight)
                                                    ,v_txt
                                                );
                            -- dates and strings left justify
                            ELSE as_pdf3.put_txt(v_x + c_padding, v_y + (c_rf * v_lineheight), v_txt);
                        END IF;
                    END IF;
                    v_x := v_x + v_col_widths(c); 
                END LOOP;                       -- over columns
                v_y := v_y - v_lineheight;      -- advance to the next line
            END LOOP;                           -- over array of rows fetched
            EXIT WHEN v_fetched_rows != v_bulk_cnt;
        END LOOP;                               -- main fetch loop      
        g_y := v_y; --we cannot set g_y in as_pdf3.
        -- as_pdf3 allowed for writing new text immediately after the grid without specifying x/y.
        -- To do this we would need a new public funtion as_pdf3.set_global_y.
        -- If you want to write after the grid, you must specify the x and y values with the
        -- first write or put_text. Use PdfGen.get_y to retrieve it, add your lineheight to it 
        -- and specify it in the write or put_text
        --
    END cursor2table;

    PROCEDURE refcursor2table(
        p_src                       SYS_REFCURSOR
        ,p_widths                   t_col_widths    
        ,p_headers                  t_col_headers  
        ,p_bold_headers             BOOLEAN         := FALSE
        ,p_char_widths_conversion   BOOLEAN         := FALSE
        ,p_break_col                BINARY_INTEGER  := NULL
        ,p_grid_lines               BOOLEAN         := TRUE
    ) IS
        v_cx                        INTEGER;
        v_src                       SYS_REFCURSOR := p_src;
    BEGIN
        v_cx := DBMS_SQL.to_cursor_number(v_src);
        cursor2table(v_cx, p_widths, p_headers, p_bold_headers, p_char_widths_conversion, p_break_col, p_grid_lines);
        DBMS_SQL.close_cursor(v_cx);
    END refcursor2table
    ;

    PROCEDURE refcursor2table(
        p_src                       SYS_REFCURSOR
        ,p_col_headers              BOOLEAN         := FALSE
        ,p_break_col                BINARY_INTEGER  := NULL
        ,p_grid_lines               BOOLEAN         := TRUE
    ) IS
        v_cx                        INTEGER;
        v_src                       SYS_REFCURSOR := p_src;
        v_widths                    t_col_widths;
        v_headers                   t_col_headers;
        v_col_cnt                   INTEGER;
$IF DBMS_DB_VERSION.VER_LE_10 $THEN
        v_desc_tab          DBMS_SQL.desc_tab2;
$ELSE
        v_desc_tab          DBMS_SQL.desc_tab3;
$END
    BEGIN
        v_cx := DBMS_SQL.to_cursor_number(v_src);
        IF p_col_headers THEN
$IF DBMS_DB_VERSION.VER_LE_10 $THEN
            DBMS_SQL.describe_columns2(v_cx, v_col_cnt, v_desc_tab);
$ELSE
            DBMS_SQL.describe_columns3(v_cx, v_col_cnt, v_desc_tab);
$END
            FOR i IN 1..v_col_cnt
            LOOP
                v_widths(i) := v_desc_tab(i).col_name_len + 1;
                v_headers(i) := v_desc_tab(i).col_name;
            END LOOP;
        END IF;
        cursor2table(v_cx
                ,CASE WHEN p_col_headers THEN v_widths END
                ,CASE WHEN p_col_headers THEN v_headers END
                ,p_col_headers -- bold
                , TRUE
                ,p_break_col, p_grid_lines
        );
        DBMS_SQL.close_cursor(v_cx);
    END refcursor2table
    ;
END PdfGen;
/
show errors
