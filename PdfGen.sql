CREATE OR REPLACE PACKAGE PdfGen
AS
    TYPE t_col_widths IS TABLE OF NUMBER INDEX BY BINARY_INTEGER;
    TYPE t_col_headers IS TABLE OF VARCHAR2(4000) INDEX BY BINARY_INTEGER;
    PROCEDURE init;
    PROCEDURE set_page_proc(p_sql_block CLOB);
    PROCEDURE set_footer(
        p_txt           VARCHAR2
        ,p_font_family  VARCHAR2    := 'helvetica'
        ,p_style        VARCHAR2    := 'n'
        ,p_fontsize_pt  NUMBER      := 8
    );
    PROCEDURE set_header(
        p_txt           VARCHAR2
        ,p_font_family  VARCHAR2    := 'helvetica'
        ,p_style        VARCHAR2    := 'b'
        ,p_fontsize_pt  NUMBER      := 18
    );
    PROCEDURE refcursor2table(
        p_src                       SYS_REFCURSOR
        ,p_widths                   t_col_widths    
        ,p_headers                  t_col_headers  
        ,p_bold_headers             BOOLEAN         := FALSE
        ,p_char_widths_conversion   BOOLEAN         := FALSE
        ,p_break_col                BINARY_INTEGER  := NULL
    );
    PROCEDURE refcursor2table(
        p_src                       SYS_REFCURSOR
        ,p_col_headers              BOOLEAN
        ,p_break_col                BINARY_INTEGER := NULL
    );

    FUNCTION get_pdf RETURN BLOB;
    PROCEDURE save_pdf(
        p_dir       VARCHAR2
        ,p_filename VARCHAR2
        ,p_freeblob BOOLEAN := TRUE
    );
END PdfGen;
/
CREATE OR REPLACE PACKAGE BODY PdfGen
AS
    TYPE t_pagevals IS TABLE OF VARCHAR2(32767) INDEX BY BINARY_INTEGER;
    g_pagevals      t_pagevals;
    TYPE t_page_procs IS TABLE OF CLOB INDEX BY BINARY_INTEGER;
    g_page_procs    t_page_procs;

    g_footer_txt            VARCHAR2(32767);
    g_footer_font_family    VARCHAR2(100);
    g_footer_style          VARCHAR2(2);
    g_footer_fontsize_pt    NUMBER;
    g_header_txt            VARCHAR2(32767);
    g_header_font_family    VARCHAR2(100);
    g_header_style          VARCHAR2(2);
    g_header_fontsize_pt    NUMBER;

    PROCEDURE apply_page_procs
    -- get_pdf and save_pdf still call the as_pdf3 versions which call the as_pdf3 version of finish_pdf.
    -- that applies the as_pdf3 page procs which we are not using
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
                    BEGIN
                        -- mypkg.function(p_page_nr => #PAGE_NR#, p_page_count => "PAGE_COUNT#, p_page_val => '!PAGE_VAL#');
                        EXECUTE IMMEDIATE REPLACE(
                                            REPLACE(
                                                REPLACE(g_page_procs(p), '#PAGE_NR#', i)
                                                ,'"PAGE_COUNT#', v_page_count)
                                            ,'!PAGE_VAL#', CASE WHEN g_pagevals.EXISTS(i-1) THEN g_pagevals(i-1) END
                                        )
                        ;
                    EXCEPTION
                        WHEN OTHERS THEN -- we ignore the error, but at least we print it for debugging
                            DBMS_OUTPUT.put_line('sqlerrm : '||SQLERRM);
                            DBMS_OUTPUT.put_line('backtrace : '||DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
                            DBMS_OUTPUT.put_line('callstack : '||DBMS_UTILITY.format_call_stack);
                            DBMS_OUTPUT.put_line('p_page_procs(p): '||g_page_procs(p));
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
            ,p_x => (as_pdf3.get(as_pdf3.c_get_page_width) / 2.0) - v_half_width
            ,p_y => 20
        );
    END apply_footer;

    PROCEDURE set_footer(
        p_txt           VARCHAR2
        ,p_font_family  VARCHAR2    := 'helvetica'
        ,p_style        VARCHAR2    := 'n'
        ,p_fontsize_pt  NUMBER      := 8
    ) IS
    BEGIN  
        g_footer_txt            := p_txt;    
        g_footer_font_family    := p_font_family;
        g_footer_style          := p_style;
        g_footer_fontsize_pt    := p_fontsize_pt;
        set_page_proc(q'~BEGIN PdfGen.apply_footer(p_page_nr => '#PAGE_NR#', p_page_count => '"PAGE_COUNT#', p_page_val => '!PAGE_VAL#'); END;~');
    END set_footer;

    PROCEDURE apply_header (
        p_page_nr       VARCHAR2
        ,p_page_count   VARCHAR2
        ,p_page_val     VARCHAR2
    ) IS
        v_txt           VARCHAR2(32767);
        v_half_width    NUMBER;
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
            ,p_x => (as_pdf3.get(as_pdf3.c_get_page_width) / 2.0) - v_half_width
            -- 1 line of header size into the top margin
            ,p_y => (as_pdf3.get(as_pdf3.c_get_page_height) - as_pdf3.get(as_pdf3.c_get_margin_top)) + g_header_fontsize_pt
        );
    END apply_header;

    PROCEDURE set_header(
        p_txt           VARCHAR2
        ,p_font_family  VARCHAR2    := 'helvetica'
        ,p_style        VARCHAR2    := 'b'
        ,p_fontsize_pt  NUMBER      := 18
    ) IS
    BEGIN
        g_header_txt            := p_txt;    
        g_header_font_family    := p_font_family;
        g_header_style          := p_style;
        g_header_fontsize_pt    := p_fontsize_pt;
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
        as_pdf3.init;
    END init;


    PROCEDURE cursor2table ( 
        p_c integer
        -- count on these being continuous starting at 1 and matching the query columns
        ,p_widths                   t_col_widths    
        ,p_headers                  t_col_headers  
        ,p_bold_headers             BOOLEAN         := FALSE
        ,p_char_widths_conversion   BOOLEAN         := FALSE
        ,p_break_col                BINARY_INTEGER  := NULL
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
        v_bulk_cnt          BINARY_INTEGER := 200;
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
            RETURN CASE WHEN p_col_type IN (1, 8, 9, 96, 112 )
                        THEN 'C'
                        WHEN p_col_type IN ( 12, 178, 179, 180, 181 , 231 )
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
                    v_date_tab.delete;
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
            DBMS_OUTPUT.put_line('cursor2table called with p_widths.COUNT='||TO_CHAR(p_widths.COUNT)||' but query column count is '||TO_CHAR(v_col_cnt)||', so p_widths is ignored');
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
                        IF NOT g_pagevals.EXISTS(l_page_index) THEN
                            g_pagevals(l_page_index) := l_v;
                        ELSIF g_pagevals(l_page_index) <> l_v THEN
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
                    as_pdf3.rect(v_x, v_y, v_col_widths(c), v_lineheight);
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
    ) IS
        v_cx                        INTEGER;
        v_src                       SYS_REFCURSOR := p_src;
    BEGIN
        v_cx := DBMS_SQL.to_cursor_number(v_src);
        cursor2table(v_cx, p_widths, p_headers, p_bold_headers, p_char_widths_conversion, p_break_col);
        DBMS_SQL.close_cursor(v_cx);
    END refcursor2table
    ;

    PROCEDURE refcursor2table(
        p_src                       SYS_REFCURSOR
        ,p_col_headers              BOOLEAN
        ,p_break_col                BINARY_INTEGER := NULL
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
        cursor2table(v_cx, v_widths, v_headers, p_col_headers, TRUE, p_break_col);
        DBMS_SQL.close_cursor(v_cx);
    END refcursor2table
    ;
END PdfGen;
/
