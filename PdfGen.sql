--
-- comment this out if you do not want to use applog. Uncomment or put this line in
-- your deploy script if you are going to deploy and use applog.
--ALTER SESSION SET PLSQL_CCFLAGS='use_applog:TRUE';
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

/* README.md -- do not put # in first char of line in this comment or sqlplus will puke
    # PdfGen.sql
    
    PdfGen extends and enhances (replaces) the *as_pdf3.cursor2table* functionality with
    respect to column headers and widths, plus the ability to capture a column page break value
    for the page_procs callbacks, and go to a new page when the break-column value changes.
    Everything is implemented using the *as_pdf3* public interface.
    
    ## Use Case
    The use case for this package is to replicate a small subset of the capability of
    sqlplus report generation for the scenario that you cannot (or do not want to) 
    run sqlplus,capture the output and convert it to pdf. You also gain font control
    and optional grid lines/cells for the column data values.
    
    An alternate name for this facility might be query2report.
    
    There are many report generators in the world. Most of them cost money.
    This is free, powerful enough for some common use cases,
    and a little easier than using *as_pdf3* directly.
    
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
                        ,SUM(salary) AS salary
                    FROM hr.employees e
                    INNER JOIN hr.departments d
                        ON d.department_id = e.department_id
                    GROUP BY GROUPING SETS(
                        (e.employee_id, e.last_name, e.first_name, d.department_name)
                        ,(d.department_name) -- subtotal on dept
                        ,() -- grand total
                    )
                ) SELECT employee_id
                    ,NVL(last_name, CASE WHEN department_name IS NULL
                                        THEN LPAD('GRAND TOTAL:',25)
                                        ELSE LPAD('DEPT TOTAL:',25)
                                    END
                    ) AS last_name
                    ,first_name
                    ,department_name
                    ,LPAD(TO_CHAR(salary,'$999,999,999.99'),16) -- leave one for sign even though we will not have one
                FROM a
                ORDER BY department_name NULLS LAST, a.last_name NULLS LAST, first_name
                ;
              RETURN l_src;
            END;
        BEGIN
            v_src := get_src;
            --
            v_headers(1) := 'Employee ID';
            v_widths(1)  := 11;
            v_headers(2) := 'Last Name';
            v_widths(2)  := 25;
            v_headers(3) := 'First Name';
            v_widths(3)  := 20;
            -- will not print this column, just capture it for column page break
            v_headers(4) := 'department_name';
            v_widths(4)  := 0;
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
            PdfGen.set_footer; -- 'Page #PAGE_NR# of "PAGE_COUNT#' is the default
            PdfGen.set_header(
                p_txt           => 'Employee Salary Report'
                ,p_font_family  => 'helvetica'
                ,p_style        => 'b'
                ,p_fontsize_pt  => 16
                ,p_centered     => TRUE
                ,p_txt_2        => 'Department: !PAGE_VAL#'
                ,p_fontsize_pt_2 => 12
                ,p_centered_2   => FALSE -- left align
            );
            --
            as_pdf3.set_font('courier', 'n', 10);
            PdfGen.refcursor2table(
                p_src => v_src
                ,p_widths => v_widths, p_headers => v_headers
                ,p_bold_headers => TRUE, p_char_widths_conversion => TRUE
                ,p_break_col => 4
                ,p_grid_lines => FALSE
            );
            v_blob := PdfGen.get_pdf;
            BEGIN
                CLOSE v_src;
            EXCEPTION WHEN invalid_cursor THEN NULL;
            END;
            RETURN v_blob;
        END test0;
    
    ## Retrieve Blob and View
    
    With SqlDeveloper or Toad *SELECT test0 FROM dual;* Double click on the BLOB value in the results grid. In SqlDeveloper you get a pencil icon. Click on that and choose *download* (toad is similar). Save the blob to a file named whatever.pdf. Open in a pdf viewer.
    
    ## Results
    
     ![test3_pg1](/images/test0_pg1.png)
    
     ![test0_pgx](/images/test0_pgx.png)
    
    ## A Few Details
    
    Column widths may be set to 0 for NOPRINT, so Break Columns where the value is captured
    and printed in the page header via a callback, can be captured, but optionally not printed with the record.
    Note that you can concatenate mulitple column values into a string for a single non-printing break-column,
    and parse those in your callback procedure.
    
    The *as_pdf3* "page_procs" callback facility is duplicated (both are called) so that
    the page break column value can be supplied in addition to the page number and page count
    that the original supported. One major difference is the use of bind placeholders instead
    of direct string substitution in your pl/sql block. We follow the same convention for
    substitution strings in the built-in header and footer procedures, but internally, and
    for your own custom callbacks, you will be providing positional bind placeholders 
    for EXECUTE IMMEDIATE. This eliminates a nagging problem with quoting values 
    in page_val as well as eliminating a potential source of sql injection. Example:
    
        set_page_proc(q'[BEGIN PdfGen.apply_footer(p_page_nr => :page_nr, p_page_count => :page_count, p_page_val => :page_val); END;]');
    
    That string is then executed with:
    
        EXECUTE IMMEDIATE g_page_procs(p) USING i, v_page_count, g_pagevals(i);
    
    where i is the page number.
    
    Also provided are simplified methods for generating semi-standard page header and footer.
    You can use these procedures as a template for building your own page_proc procedure if they
    do not meet your needs.
    
    You can mix and match calls to *as_pdf3* procedures and functions simultaneous with *PdfGen*. In fact
    you are expected to do so with procedures such as *as_pdf3.set_font*.
*/

    --
    -- not sure why plain table collections were used in the original. This is easier and apparently faster (not that it matters).
    -- It may be so that you can provide a default value of NULL which I don't think you can do for index by table variables.
    -- This version supplies two refcursor2table footprints that can resolve not providing widths so not an issue here.
    --
    TYPE t_col_widths IS TABLE OF NUMBER INDEX BY BINARY_INTEGER;
    TYPE t_col_headers IS TABLE OF VARCHAR2(4000) INDEX BY BINARY_INTEGER;

    -- you can put page specific values here for !PAGE_VAL# yourself, though it is 
    -- not the intended design which is for column breaks. 
    -- index is by page number 1..x, while as_pdf3 uses 0..x-1 for pages
    TYPE t_pagevals IS TABLE OF VARCHAR2(32767) INDEX BY BINARY_INTEGER;
    g_pagevals      t_pagevals;

    -- must call this init which also calls as_pdf3.init
    PROCEDURE init;

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
    -- strings #PAGE_NR#, "PAGE_COUNT# and !PAGE_VAL# are substituted in the block string
    -- before execute immediate on each page of the PDF after the grid is written.
    -- !!!!!!!!!!! Beware when your column can contain quote characters!!!!!!!!!!!!!!!!!!!!!!!
    -- Quote carefully in your page proc block
    PROCEDURE set_page_proc(p_sql_block CLOB);

    -- simple 1 line footer inside the bottom margin with page specific substitutions
    PROCEDURE set_footer(
        p_txt           VARCHAR2    := 'Page #PAGE_NR# of "PAGE_COUNT#'
        ,p_font_family  VARCHAR2    := 'helvetica'
        ,p_style        VARCHAR2    := 'n'
        ,p_fontsize_pt  NUMBER      := 8
        ,p_centered     BOOLEAN     := TRUE -- false give left align
    );
    -- callback proc. Not part of user interface
    PROCEDURE apply_footer(
        p_page_nr       NUMBER
        ,p_page_count   NUMBER
        ,p_page_val     VARCHAR2
    );
    -- simple 1 line header slightly into the top margin with page specific substitutions
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
    -- callback proc. Not part of user interface
    PROCEDURE apply_header (
        p_page_nr       NUMBER
        ,p_page_count   NUMBER
        ,p_page_val     VARCHAR2
    );
    PROCEDURE refcursor2table(
        p_src                       SYS_REFCURSOR
        -- if true, calculate the headers and widths from query column names
        ,p_col_headers              BOOLEAN         := FALSE 
        -- index to column to perform a page break upon value change
        ,p_break_col                BINARY_INTEGER  := NULL
        ,p_grid_lines               BOOLEAN         := TRUE
    );
    PROCEDURE refcursor2table(
        p_src                       SYS_REFCURSOR
        ,p_widths                   t_col_widths    
        ,p_headers                  t_col_headers  
        ,p_bold_headers             BOOLEAN         := FALSE
        ,p_char_widths_conversion   BOOLEAN         := FALSE
        -- index to column to perform a page break upon value change
        ,p_break_col                BINARY_INTEGER  := NULL
        ,p_grid_lines               BOOLEAN         := TRUE
    );

    -- use these instead of as_pdf3 versions (which are called by these).
    FUNCTION get_pdf RETURN BLOB;
    PROCEDURE save_pdf(
        p_dir       VARCHAR2
        ,p_filename VARCHAR2
        ,p_freeblob BOOLEAN := TRUE
    );

    -- returns current left margin
    FUNCTION x_left_justify RETURN NUMBER;
    -- returns x_value at which to start this string with this font to right justify it
    FUNCTION x_right_justify(p_txt VARCHAR2) RETURN NUMBER;
    -- returns x_value at which to start this string with this font to center it on the page (not between the margins)
    FUNCTION x_center(p_txt VARCHAR2) RETURN NUMBER;
    -- returns y_value of the top margin. Add to this to print a header line above the margin
    FUNCTION y_top_margin RETURN NUMBER;
END PdfGen;
/
show errors
CREATE OR REPLACE PACKAGE BODY PdfGen
AS
    -- pl/sql blocs given to execute immediate on every page at the very end
    TYPE t_page_procs IS TABLE OF CLOB INDEX BY BINARY_INTEGER;
    g_page_procs    t_page_procs;

    -- used internally for apply_footer/apply_header
    g_footer_txt            VARCHAR2(32767);
    g_footer_font_family    VARCHAR2(100);
    g_footer_style          VARCHAR2(2);
    g_footer_fontsize_pt    NUMBER;
    g_footer_centered       BOOLEAN;
    g_header_txt            VARCHAR2(32767);
    g_header_font_family    VARCHAR2(100);
    g_header_style          VARCHAR2(2);
    g_header_fontsize_pt    NUMBER;
    g_header_centered       BOOLEAN;
    g_header_txt_2          VARCHAR2(32767);
    g_header_fontsize_pt_2  NUMBER;
    g_header_centered_2     BOOLEAN;
    g_pageval_width         NUMBER;

$if $$use_applog $then
    g_log                   applog_udt;
$end

    PROCEDURE apply_page_procs
    -- get_pdf and save_pdf still call the as_pdf3 versions which call the as_pdf3 version of finish_pdf.
    -- that applies the as_pdf3 page procs which we are not using, but you might.
    IS
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
                as_pdf3.pr_goto_page(i); -- sets g_page_nr
                FOR p IN g_page_procs.FIRST .. g_page_procs.LAST
                LOOP
                    -- execute the callbacks on every page. Provide argument of page number, number of pages
                    -- and a page specific value (set by break column in cursor2table) as positional bind values to 
                    -- the dynamic sql block. The block should reference the bind values 1 time positionally
                    -- with :page_nr, :page_count, :pageval (the names do not matter. position of the : placeholders does).
                    -- Remember that the callback has access to package global states but is not aware of
                    -- the local callstack or environment of this procedure. Must use fully qualified names
                    -- for any procedures/functions called.
                    /*
                    DECLARE
                        l_proc CLOB := REPLACE(
                                            REPLACE(
                                                REPLACE(g_page_procs(p), '#PAGE_NR#', i)
                                                ,'"PAGE_COUNT#', v_page_count)
                                            ,'!PAGE_VAL#', CASE WHEN g_pagevals.EXISTS(i) 
                                                            THEN CASE WHEN g_pageval_width IS NULL
                                                                    THEN g_pagevals(i) 
                                                                    ELSE RPAD(g_pagevals(i),g_pageval_width,' ')
                                                                END
                                                            END
                                        )
                        ;
                    */
                    BEGIN
--$if $$use_applog $then
--                        g_log.log_p('calling g_page_procs('||TO_CHAR(p)||') for page nr:'||TO_CHAR(i));
--$end
                        --EXECUTE IMMEDIATE l_proc;
                        EXECUTE IMMEDIATE g_page_procs(p) USING i, v_page_count, g_pagevals(i);
                    EXCEPTION
                        WHEN OTHERS THEN -- we ignore the error, but at least we print it for debugging
$if $$use_applog $then
                            g_log.log_p(SQLERRM);
                            g_log.log_p(DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
                            g_log.log_p(DBMS_UTILITY.format_call_stack);
                            g_log.log_p(g_page_procs(p));
                            g_log.log_p('i='||TO_CHAR(i)||' page_count: '||TO_CHAR(v_page_count)||' page_val: '||g_pagevals(i));
$else
                            DBMS_OUTPUT.put_line('sqlerrm : '||SQLERRM);
                            DBMS_OUTPUT.put_line('backtrace : '||DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
                            DBMS_OUTPUT.put_line('callstack : '||DBMS_UTILITY.format_call_stack);
                            DBMS_OUTPUT.put_line('p_page_procs(p): '||g_page_procs(p));
                            DBMS_OUTPUT.put_line('i='||TO_CHAR(i)||' page_count: '||TO_CHAR(v_page_count)||' page_val: '||g_pagevals(i));
$end
                    END;
                END LOOP;
            END LOOP;
        END IF;
    END apply_page_procs;

    PROCEDURE set_pageval_width(p_width NUMBER)
    IS
    BEGIN
        g_pageval_width := p_width;
    END set_pageval_width;

    PROCEDURE apply_footer(
        p_page_nr       NUMBER
        ,p_page_count   NUMBER
        ,p_page_val     VARCHAR2
    ) IS
        v_txt           VARCHAR2(32767);
        c_padding       CONSTANT NUMBER := 5; --space beteen footer line and margin
    BEGIN
        v_txt := REPLACE(
                    REPLACE(
                        REPLACE(g_footer_txt, '#PAGE_NR#', LTRIM(TO_CHAR(p_page_nr)))
                        ,'"PAGE_COUNT#', LTRIM(TO_CHAR(p_page_count)))
                    ,'!PAGE_VAL#', p_page_val
                );
        as_pdf3.set_font(g_footer_font_family, g_footer_style, g_footer_fontsize_pt);
        as_pdf3.put_txt(p_txt => v_txt
            ,p_x => CASE WHEN g_footer_centered THEN x_center(v_txt)
                         ELSE x_left_justify
                    END
            ,p_y => as_pdf3.get(as_pdf3.c_get_margin_bottom) - g_footer_fontsize_pt - c_padding
            --,p_y => 20
        );
    END apply_footer;

    PROCEDURE set_footer(
        p_txt           VARCHAR2    := 'Page #PAGE_NR# of "PAGE_COUNT#'
        ,p_font_family  VARCHAR2    := 'helvetica'
        ,p_style        VARCHAR2    := 'n'
        ,p_fontsize_pt  NUMBER      := 8
        ,p_centered     BOOLEAN     := TRUE -- false give left align
    ) IS
    BEGIN  
        g_footer_txt            := p_txt;    
        g_footer_font_family    := p_font_family;
        g_footer_style          := p_style;
        g_footer_fontsize_pt    := p_fontsize_pt;
        g_footer_centered       := p_centered;
        set_page_proc(q'[BEGIN PdfGen.apply_footer(p_page_nr => :page_nr, p_page_count => :page_count, p_page_val => :page_val); END;]');
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
    BEGIN
        v_txt := REPLACE(
                    REPLACE(
                        REPLACE(g_header_txt, '#PAGE_NR#', LTRIM(TO_CHAR(p_page_nr)))
                        ,'"PAGE_COUNT#', LTRIM(TO_CHAR(p_page_count)))
                    ,'!PAGE_VAL#', p_page_val
                );
        -- line 1
        as_pdf3.set_font(g_header_font_family, g_header_style, g_header_fontsize_pt);
        as_pdf3.put_txt(p_txt => v_txt
            ,p_x => CASE WHEN g_header_centered THEN x_center(v_txt)
                         ELSE x_left_justify
                    END
            ,p_y => y_top_margin
                    + c_y_padding + (c_rf * g_header_fontsize_pt)
                -- go higer by line size of the 2nd line plus padding if needed
                + CASE WHEN g_header_txt_2 IS NULL THEN 0 ELSE c_y_padding2 + ((1 + c_rf) * g_header_fontsize_pt_2) END
        );
        IF g_header_txt_2 IS NOT NULL THEN
            v_txt := REPLACE(
                        REPLACE(
                            REPLACE(g_header_txt_2, '#PAGE_NR#', p_page_nr)
                            ,'"PAGE_COUNT#', p_page_count)
                        ,'!PAGE_VAL#', p_page_val
                    );
            as_pdf3.set_font(g_header_font_family, g_header_style, g_header_fontsize_pt_2);
            as_pdf3.put_txt(p_txt => v_txt
                ,p_x => CASE WHEN g_header_centered_2 THEN x_center(v_txt)
                            ELSE x_left_justify
                        END
                ,p_y => y_top_margin + c_y_padding + (c_rf * g_header_fontsize_pt_2)
            );
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
        g_header_txt            := p_txt;    
        g_header_font_family    := p_font_family;
        g_header_style          := p_style;
        g_header_fontsize_pt    := p_fontsize_pt;
        g_header_centered       := p_centered;
        g_header_txt_2          := p_txt_2;
        g_header_fontsize_pt_2  := p_fontsize_pt_2;
        g_header_centered_2     := p_centered_2;
        set_page_proc(q'[BEGIN PdfGen.apply_header(p_page_nr => :page_nr, p_page_count => :page_count, p_page_val => :page_val); END;]');
    END set_header;

    PROCEDURE set_page_proc(p_sql_block CLOB)
    IS
    BEGIN
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
$if $$use_applog $then
        g_log := applog_udt('PdfGen');
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
    BEGIN
        RETURN (as_pdf3.get(as_pdf3.c_get_page_width) / 2.0)
                - (as_pdf3.str_len(p_txt) / 2.0)
                ;
    END x_center;

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
    END set_page_format
    ;
    FUNCTION y_top_margin 
    RETURN NUMBER
    IS
    BEGIN
        RETURN as_pdf3.get(as_pdf3.c_get_page_height) 
                  - as_pdf3.get(as_pdf3.c_get_margin_top)
        ;
    END y_top_margin;

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
        v_col_widths        t_col_widths;
        v_centered_left_margin  NUMBER := as_pdf3.get(as_pdf3.c_get_margin_left);
        v_x                 NUMBER;
        v_y                 NUMBER;
        v_lineheight        NUMBER;
        v_txt               VARCHAR2(32767);

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
        FUNCTION get_col_val(c BINARY_INTEGER, i BINARY_INTEGER)
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
                v_x := v_centered_left_margin; --as_pdf3.get(as_pdf3.c_get_margin_left);
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
        IF p_widths IS NOT NULL AND p_widths.COUNT <> v_col_cnt THEN
$if $$use_applog $then
            g_log.log_p('cursor2table called with p_widths.COUNT='||TO_CHAR(p_widths.COUNT)||' but query column count is '||TO_CHAR(v_col_cnt)||', so p_widths is ignored');
$else
            DBMS_OUTPUT.put_line('cursor2table called with p_widths.COUNT='||TO_CHAR(p_widths.COUNT)||' but query column count is '||TO_CHAR(v_col_cnt)||', so p_widths is ignored');
$end
        END IF;
        If p_widths IS NULL OR p_widths.COUNT < v_col_cnt THEN
            DECLARE
                l_col_width NUMBER := ROUND((as_pdf3.get(as_pdf3.c_get_page_width) - as_pdf3.get(as_pdf3.c_get_margin_left) - as_pdf3.get(as_pdf3.c_get_margin_right)) / v_col_cnt, 1);
            BEGIN
                FOR c IN 1 .. v_col_cnt
                LOOP
                    v_col_widths(c) := l_col_width;
                END LOOP;
            END;
        ELSIF p_char_widths_conversion THEN 
            DECLARE
                l_font_width number := 0.61 * as_pdf3.get(as_pdf3.c_get_fontsize); -- assumes courier font width
            BEGIN
                FOR c IN 1 .. p_widths.COUNT
                LOOP
                    v_col_widths(c) := (p_widths(c) * l_font_width) + CASE WHEN p_widths(c) = 0 THEN 0 ELSE c_padding END;
                END LOOP;
            END;
        ELSE
            FOR c IN 1 .. p_widths.COUNT
            LOOP
                v_col_widths(c) := p_widths(c);
            END LOOP;
        END IF;

        DECLARE
            l_tot_width NUMBER := 0;
        BEGIN
            FOR c IN 1 ..v_col_widths.COUNT
            LOOP
                l_tot_width := l_tot_width + v_col_widths(c);
            END LOOP;
            v_centered_left_margin := (as_pdf3.get(as_pdf3.c_get_page_width) / 2.0) - (l_tot_width / 2.0);
        END;

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
--
        v_lineheight := as_pdf3.get(as_pdf3.c_get_fontsize) * (1 + c_rf);
        v_y := COALESCE(as_pdf3.get(as_pdf3.c_get_y) - v_lineheight
                        ,y_top_margin
                       ) - v_lineheight; 
--
        show_header;
--
        LOOP
            v_fetched_rows := DBMS_SQL.fetch_rows(p_c);
$if $$use_applog $then
            g_log.log_p('fetch '||TO_CHAR(v_fetched_rows)||' rows from cursor');
$end
            EXIT WHEN v_fetched_rows = 0;
            FOR i IN 0 .. v_fetched_rows - 1
            LOOP
                IF v_y < as_pdf3.get(as_pdf3.c_get_margin_bottom) THEN
                    as_pdf3.new_page;
                    v_y := y_top_margin - v_lineheight; 
                    show_header;
                END IF;
                IF p_break_col IS NOT NULL THEN
                    DECLARE
                        l_v             VARCHAR2(32767) := get_col_val(p_break_col, i);
                        l_page_index    BINARY_INTEGER  := as_pdf3.get(as_pdf3.c_get_page_count);
                    BEGIN
                        IF l_page_index < 1 THEN
                            l_page_index := 1;
                        END IF;
                        IF NOT g_pagevals.EXISTS(l_page_index) THEN
                            g_pagevals(l_page_index) := l_v;
                        ELSIF NVL(g_pagevals(l_page_index),'~#NULL#~') <> NVL(l_v,'~#NULL#~') THEN 
$if $$use_applog $then
                            g_log.log_p('got column break event i='||TO_CHAR(i));
$end
                            as_pdf3.new_page;
                            l_page_index := as_pdf3.get(as_pdf3.c_get_page_count);
                            g_pagevals(l_page_index) := l_v;
                            v_y := y_top_margin - v_lineheight; 
                            show_header;
                        END IF;
                    END;
                END IF;
                v_x := v_centered_left_margin; --as_pdf3.get(as_pdf3.c_get_margin_left);
                FOR c IN 1 .. v_col_cnt
                LOOP
                    CONTINUE WHEN v_col_widths(c) = 0;
                    IF p_grid_lines THEN
                        as_pdf3.rect(v_x, v_y, v_col_widths(c), v_lineheight);
                    END IF;
                    v_txt := get_col_val(c, i);
                    IF v_txt IS NOT NULL THEN
                        IF lookup_col_type(v_desc_tab(c).col_type) = 'N' 
                            THEN as_pdf3.put_txt(v_x + v_col_widths(c) - c_padding - as_pdf3.str_len( v_txt ) 
                                                    ,v_y + (c_rf * v_lineheight)
                                                    ,v_txt
                                                );
                            ELSE as_pdf3.put_txt(v_x + c_padding, v_y + (c_rf * v_lineheight), v_txt);
                        END IF;
                    END IF;
                    v_x := v_x + v_col_widths(c); 
                END LOOP; -- over columns
                v_y := v_y - v_lineheight;
            END LOOP; -- over array of rows fetched
            EXIT WHEN v_fetched_rows != v_bulk_cnt;
        END LOOP; -- main fetch loop      
        --g_y := v_y; --we cannot set g_y, but we are not writing anything else at this location
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
        cursor2table(v_cx, v_widths, v_headers, p_col_headers, TRUE, p_break_col, p_grid_lines);
        DBMS_SQL.close_cursor(v_cx);
    END refcursor2table
    ;
END PdfGen;
/
show errors
