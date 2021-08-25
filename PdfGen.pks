CREATE OR REPLACE PACKAGE PdfGen
AUTHID CURRENT_USER
IS
-- put this in your deploy if you want to use app_log --> ALTER SESSION SET PLSQL_CCFLAGS='use_app_log:TRUE';
-- Think about who you give execute to if you make it definer rights. They
-- will have the ability to inject code that executes as your schema owner
-- through callback facility. If you make this a definer rights package,
-- they also are writing to directories only your schema has write permission on, 
-- not their own. Keep it invoker rights.
/*
  Author: Lee Lindley
  Date: 08/25/2021
  https://github.com/lee-lindley/PdfGen

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
        ,p_num_format               VARCHAR2        := 'tm9'
        ,p_date_format              VARCHAR2        := 'MM/DD/YYYY'
        ,p_interval_format          VARCHAR2        := NULL

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
        ,p_num_format               VARCHAR2        := 'tm9'
        ,p_date_format              VARCHAR2        := 'MM/DD/YYYY'
        ,p_interval_format          VARCHAR2        := NULL
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
    -- legacy. unless you want all the defaults, use set_page_footer instead.
    PROCEDURE set_footer(
        p_txt           VARCHAR2    := 'Page #PAGE_NR# of "PAGE_COUNT#'
        ,p_font_family  VARCHAR2    := 'helvetica'
        ,p_style        VARCHAR2    := 'n'
        ,p_fontsize_pt  NUMBER      := 8
        ,p_centered     BOOLEAN     := TRUE -- false give left align
    );
    PROCEDURE set_page_footer(
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
    -- legacy procedure. Use set_page_header instead.
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

-- Example Usage:
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
--                -- right justify the formatted amount in the width of the column
--                -- maybe next version will provide an array of format strings for numbers and dates
--                -- but for now format your own if you do not want the defaults
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
--            ,p_txt_2            => 'Department: !PAGE_VAL#' -- TITLE column variable value
--            ,p_fontsize_pt_2    => 12
--            ,p_centered_2       => FALSE            -- left align
--        );
--        -- asking for trouble to use other than fixed width fault in the grid IMHO. YMMV.
--        as_pdf3.set_font('courier', 'n', 10);
--        v_src := get_src;                           -- open the query cursor
--        PdfGen.refcursor2table(
--            p_src                       => v_src
--            ,p_widths                   => v_widths
--            ,p_headers                  => v_headers
--            ,p_bold_headers             => TRUE     -- also light gray background on headers
--            ,p_char_widths_conversion   => TRUE
--            ,p_break_col                => 4        -- sqlplus BREAK ON column becomes !PAGE_VAL#
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
END PdfGen;
/
show errors
