--
-- comment this out if you do not want to use applog
ALTER SESSION SET PLSQL_CCFLAGS='use_applog:TRUE';
--
CREATE OR REPLACE PACKAGE PdfGen
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
    -- The use case for this package is to replicate a small subset of the capability of
    -- sqlplus report generation for the scenario that you cannot (or do not want to) 
    -- run sqlplus, capture the output and convert it to pdf. You also gain font control
    -- and optional grid lines/cells for the column data values.
    --
    -- An alternate name for this facility might be query2report.
    --
    -- PdfGen relies entirely on as_pdf3 by Anton Scheffer. It uses only the
    -- public interface. There is no mucking with the internals. The only change
    -- to the original package published in 2012 found in the version in this repository
    -- is addition of 1 constant, c_get_page_count, 
    -- and associated return value from the public "get" function.
    --
    -- This package extends and enhances (replaces) the as_pdf3.cursor2table functionality with
    -- respect to colunn headers and widths, plus the ability to capture a column page break value
    -- for the page_procs callbacks, and go to a new page when the break-column value changes.
    --
    -- Column widths may also be set to 0 for NOPRINT. Break Columns where the value is captured
    -- and printed in the page header via a callback can be set to 0 width and not printed with the record.
    -- Note that you can concatenate mulitple column values into a string for a single non-printing break-column,
    -- and parse those in your callback procedure.
    --
    -- The as_pdf3 "page_procs" callback facility is duplicated (both are called) so that
    -- the page break column value can be supplied in addition to the page number and page count
    -- that the original supported.
    --
    -- Also provided are simplified methods for generating semi-standard page header and footer
    -- that are less onerous than the quoting required for generating an anonymous pl/sql block string.
    -- You can use these procedures as a template for building your own page_proc procedure.
    --
    -- When you use any part of this procedure, you must use init(), and either get_pdf() or save_pdf()
    -- from this package instead of the ones in as_pdf3. Those call the ones in as_pdf3 in
    -- addition to the added functionality.
    -- Other than that you should be able to use as_pdf3 public functionality directly,
    -- mixed in with calls to PdfGen. In particular you will probably be using as_pdf3.set_font.
    --
    -- The page x/y grid is first quadrant (i.e. 0,0 is bottom left of the page). "margin" is the area
    -- that the report grid is not supposed to print into, but the right margin is only respected by 
    -- the as_pdf3.write call, not put_text() which is used in the grid, headings and footers. 
    -- Up to you to keep printed record width short enough to fit or change the page size/orientation/margins.
    -- The lower left point of the grid print area is (0+left margin, 0+bottom margin).
    -- The top right point of the grid print area is ((page_height - margin_top), (page_width - margin right)).
    -- The grid printing starts at the top margin and will go to a new page before getting into the bottom margin.
    -- We write the page header and footer into the margin areas, so the word "margin" is overloaded a bit here
    -- because for printing the margin has nothing in it. We write in our margin. Up to you to make sure
    -- where you write will actually print.
    --
    --
    -- not sure why plain table collections were used in the original. This is easier and apparently faster (not that it matters).
    -- It may be so that you can provide a default value of NULL which I don't think you can do for index by table variables.
    -- This version supplies two refcursor2table footprints that can resolve not providing widths so not an issue here.
    --
    TYPE t_col_widths IS TABLE OF NUMBER INDEX BY BINARY_INTEGER;
    TYPE t_col_headers IS TABLE OF VARCHAR2(4000) INDEX BY BINARY_INTEGER;

    -- you can put page specific values here for !PAGE_VAL# yourself, though it is 
    -- not the intended design which is for column breaks. 
    -- Remember that the index starts at 0 for page 1.
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
        p_page_nr       VARCHAR2
        ,p_page_count   VARCHAR2
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
        p_page_nr       VARCHAR2
        ,p_page_count   VARCHAR2
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
END PdfGen;
/
show errors
CREATE OR REPLACE PACKAGE BODY PdfGen
AS
    -- pl/sql bloces given to execute immediate on every page at the very end
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
                    -- and a page specific value (set by break column in cursor2table) by replacing
                    -- string placeholders. Beware quoting in constructing the callback string
                    -- Remember that the callback has access to package global states but is not aware of
                    -- the local callstack or environment of this procedure. Must use fully qualified names
                    -- for any procedures/functions called
                    DECLARE
                        l_proc CLOB := REPLACE(
                                            REPLACE(
                                                REPLACE(g_page_procs(p), '#PAGE_NR#', i)
                                                ,'"PAGE_COUNT#', v_page_count)
                                            ,'!PAGE_VAL#', CASE WHEN g_pagevals.EXISTS(i-1) THEN g_pagevals(i-1) END
                                        )
                        ;
                    BEGIN
                        -- mypkg.function(p_page_nr => #PAGE_NR#, p_page_count => "PAGE_COUNT#, p_page_val => '!PAGE_VAL#');
$if $$use_applog $then
                        g_log.log_p('calling g_page_procs('||TO_CHAR(p)||') for page nr:'||TO_CHAR(i));
$end
                        EXECUTE IMMEDIATE l_proc;
                    EXCEPTION
                        WHEN OTHERS THEN -- we ignore the error, but at least we print it for debugging
$if $$use_applog $then
                            g_log.log_p(SQLERRM);
                            g_log.log_p(DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
                            g_log.log_p(DBMS_UTILITY.format_call_stack);
                            g_log.log_p(l_proc);
$else
                            DBMS_OUTPUT.put_line('sqlerrm : '||SQLERRM);
                            DBMS_OUTPUT.put_line('backtrace : '||DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
                            DBMS_OUTPUT.put_line('callstack : '||DBMS_UTILITY.format_call_stack);
                            DBMS_OUTPUT.put_line('p_page_procs(p): '||l_proc);
$end
                    END;
                END LOOP;
            END LOOP;
        END IF;
    END apply_page_procs;


    PROCEDURE apply_footer(
        p_page_nr       VARCHAR2
        ,p_page_count   VARCHAR2
        ,p_page_val     VARCHAR2
    ) IS
        v_txt           VARCHAR2(32767);
        v_half_width    NUMBER;
        c_padding       CONSTANT NUMBER := 5; --space beteen footer line and margin
    BEGIN
        v_txt := REPLACE(
                    REPLACE(
                        REPLACE(g_footer_txt, '#PAGE_NR#', p_page_nr)
                        ,'"PAGE_COUNT#', p_page_count)
                    ,'!PAGE_VAL#', p_page_val
                );
        as_pdf3.set_font(g_footer_font_family, g_footer_style, g_footer_fontsize_pt);
        v_half_width := as_pdf3.str_len(v_txt) / 2.0;
        as_pdf3.put_txt(p_txt => v_txt
            ,p_x => CASE WHEN g_footer_centered THEN (as_pdf3.get(as_pdf3.c_get_page_width) / 2.0) - v_half_width
                         ELSE as_pdf3.get(as_pdf3.c_get_margin_left)
                    END
            ,p_y => as_pdf3.get(as_pdf3.c_get_margin_bottom) - g_footer_fontsize_pt - c_padding
            --,p_y => 20
        );
    END apply_footer;

    PROCEDURE set_footer(
        p_txt           VARCHAR2
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
        set_page_proc(q'~BEGIN PdfGen.apply_footer(p_page_nr => '#PAGE_NR#', p_page_count => '"PAGE_COUNT#', p_page_val => '!PAGE_VAL#'); END;~');
    END set_footer;

    PROCEDURE apply_header (
        p_page_nr       VARCHAR2
        ,p_page_count   VARCHAR2
        ,p_page_val     VARCHAR2
    ) IS
        v_txt           VARCHAR2(32767);
        v_half_width    NUMBER;
        c_padding       CONSTANT NUMBER := 2; --space between heading line and margin
        c_rf            CONSTANT NUMBER := 0.2; -- raise factor. Anton uses the term. Spacing so bottom of font is not right on the line
    BEGIN
        v_txt := REPLACE(
                    REPLACE(
                        REPLACE(g_header_txt, '#PAGE_NR#', p_page_nr)
                        ,'"PAGE_COUNT#', p_page_count)
                    ,'!PAGE_VAL#', p_page_val
                );
        as_pdf3.set_font(g_header_font_family, g_header_style, g_header_fontsize_pt);
        v_half_width := as_pdf3.str_len(v_txt) / 2.0;
        as_pdf3.put_txt(p_txt => v_txt
            ,p_x => CASE WHEN g_header_centered THEN (as_pdf3.get(as_pdf3.c_get_page_width) / 2.0) - v_half_width
                         ELSE as_pdf3.get(as_pdf3.c_get_margin_left)
                    END
            ,p_y => (as_pdf3.get(as_pdf3.c_get_page_height) - as_pdf3.get(as_pdf3.c_get_margin_top)) 
                    + c_padding + (c_rf * g_header_fontsize_pt)
                -- go higer by line size of the 2nd line plus padding if needed
                + CASE WHEN g_header_txt_2 IS NULL THEN 0 ELSE c_padding + ((1 + c_rf) * g_header_fontsize_pt_2) END
        );
        IF g_header_txt_2 IS NOT NULL THEN
            v_txt := REPLACE(
                        REPLACE(
                            REPLACE(g_header_txt_2, '#PAGE_NR#', p_page_nr)
                            ,'"PAGE_COUNT#', p_page_count)
                        ,'!PAGE_VAL#', p_page_val
                    );
            as_pdf3.set_font(g_header_font_family, g_header_style, g_header_fontsize_pt_2);
            v_half_width := as_pdf3.str_len(v_txt) / 2.0;
            as_pdf3.put_txt(p_txt => v_txt
                ,p_x => CASE WHEN g_header_centered_2 THEN (as_pdf3.get(as_pdf3.c_get_page_width) / 2.0) - v_half_width
                            ELSE as_pdf3.get(as_pdf3.c_get_margin_left)
                        END
                ,p_y => (as_pdf3.get(as_pdf3.c_get_page_height) - as_pdf3.get(as_pdf3.c_get_margin_top)) 
                            + c_padding + (c_rf * g_header_fontsize_pt_2)
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
        set_page_proc(q'~BEGIN PdfGen.apply_header(p_page_nr => '#PAGE_NR#', p_page_count => '"PAGE_COUNT#', p_page_val => '!PAGE_VAL#'); END;~');
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
                v_x := as_pdf3.get(as_pdf3.c_get_margin_left);
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
                        as_pdf3.put_txt(v_x + c_padding, v_y + c_rf * v_lineheight, p_headers(c));
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
                    v_col_widths(c) := p_widths(c) * l_font_width;
                END LOOP;
            END;
        ELSE
            FOR c IN 1 .. p_widths.COUNT
            LOOP
                v_col_widths(c) := p_widths(c);
            END LOOP;
        END IF;

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
        v_lineheight := as_pdf3.get(as_pdf3.c_get_fontsize) * 1.2;
        v_y := COALESCE(as_pdf3.get(as_pdf3.c_get_y) - v_lineheight
                        ,as_pdf3.get(as_pdf3.c_get_page_height) - as_pdf3.get(as_pdf3.c_get_margin_top)
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
                    v_y := as_pdf3.get(as_pdf3.c_get_page_height) - as_pdf3.get(as_pdf3.c_get_margin_top) - v_lineheight; 
                    show_header;
                END IF;
                IF p_break_col IS NOT NULL THEN
                    DECLARE
                        l_v             VARCHAR2(32767) := get_col_val(p_break_col, i);
                        l_page_index    BINARY_INTEGER  := as_pdf3.get(as_pdf3.c_get_page_count) - 1;
                    BEGIN
                        IF l_page_index < 0 THEN
                            l_page_index := 0;
                        END IF;
                        IF NOT g_pagevals.EXISTS(l_page_index) THEN
                            g_pagevals(l_page_index) := l_v;
                        ELSIF g_pagevals(l_page_index) <> l_v THEN
$if $$use_applog $then
                            g_log.log_p('got column break event i='||TO_CHAR(i));
$end
                            as_pdf3.new_page;
                            l_page_index := as_pdf3.get(as_pdf3.c_get_page_count) - 1;
                            g_pagevals(l_page_index) := l_v;
                            v_y := as_pdf3.get(as_pdf3.c_get_page_height) - as_pdf3.get(as_pdf3.c_get_margin_top) - v_lineheight; 
                            show_header;
                        END IF;
                    END;
                END IF;
                v_x := as_pdf3.get(as_pdf3.c_get_margin_left);
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
                                                    ,v_y + c_rf * v_lineheight 
                                                    ,v_txt
                                                );
                            ELSE as_pdf3.put_txt(v_x + c_padding, v_y + c_rf * v_lineheight, v_txt);
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
