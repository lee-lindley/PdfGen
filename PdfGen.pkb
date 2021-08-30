CREATE OR REPLACE PACKAGE BODY PdfGen
IS
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


    PROCEDURE set_page_footer(
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
    END set_page_footer;

    PROCEDURE set_footer(
        p_txt           VARCHAR2    := 'Page #PAGE_NR# of "PAGE_COUNT#'
        ,p_font_family  VARCHAR2    := 'helvetica'
        ,p_style        VARCHAR2    := 'n'
        ,p_fontsize_pt  NUMBER      := 8
        ,p_centered     BOOLEAN     := TRUE -- false give left align
    ) IS
    BEGIN  
        set_page_footer(
            p_font_family   => p_font_family
            ,p_style        => p_style
            ,p_fontsize_pt  => p_fontsize_pt
            ,p_txt_center   => CASE WHEN p_centered THEN p_txt END
            ,p_txt_left     => CASE WHEN NOT p_centered THEN p_txt END
        );
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
        set_page_header(
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
    END set_page_header;

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
         p_sql IN OUT NOCOPY        app_dbms_sql_str_udt
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
        v_col_cnt           BINARY_INTEGER;
        v_col_types         arr_integer_udt := p_sql.get_column_types;

        v_page_count        BINARY_INTEGER := as_pdf3.get(as_pdf3.c_get_page_count);
        v_col_widths        t_col_widths;
        -- new left marging for starting each line after calculating how to center the grid between the margins
        v_centered_left_margin  NUMBER;
        v_x                 NUMBER;
        v_y                 NUMBER;
        v_lineheight        NUMBER;
        v_txt               VARCHAR2(32767);
        v_arr_vals          arr_clob_udt;

        -- based on dbms_sql column info
        FUNCTION lookup_col_type(p_col_type INTEGER)
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
        v_col_cnt := v_col_types.COUNT;
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
            p_sql.get_next_column_values(p_arr_clob => v_arr_vals);
            EXIT WHEN v_arr_vals IS NULL;
            IF v_y < as_pdf3.get(as_pdf3.c_get_margin_bottom) THEN
                as_pdf3.new_page;
                v_page_count := as_pdf3.get(as_pdf3.c_get_page_count);
                v_y := y_top_margin - v_lineheight; 
                show_header;
            END IF;
            IF p_break_col IS NOT NULL THEN
                DECLARE
                    l_v             VARCHAR2(32767) := v_arr_vals(p_break_col);
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
                v_txt := v_arr_vals(c);
                IF v_txt IS NOT NULL THEN
                    IF lookup_col_type(v_col_types(c)) = 'N' 
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
        ,p_num_format               VARCHAR2        := 'tm9'
        ,p_date_format              VARCHAR2        := 'MM/DD/YYYY'
        ,p_interval_format          VARCHAR2        := NULL
    ) IS
        v_formats                   t_col_headers;
    BEGIN
        refcursor2table(
        p_src                       => p_src
        ,p_widths                   => p_widths                   
        ,p_headers                  => p_headers                  
        ,p_formats                  => v_formats
        ,p_bold_headers             => p_bold_headers             
        ,p_char_widths_conversion   => p_char_widths_conversion
        ,p_break_col                => p_break_col                
        ,p_grid_lines               => p_grid_lines               
        ,p_num_format               => p_num_format               
        ,p_date_format              => p_date_format              
        ,p_interval_format          => p_interval_format          
        );
    END refcursor2table
    ;

    PROCEDURE refcursor2table(
        p_src                       SYS_REFCURSOR
        ,p_widths                   t_col_widths    
        ,p_headers                  t_col_headers  
        ,p_formats                  t_col_headers
        ,p_bold_headers             BOOLEAN         := FALSE
        ,p_char_widths_conversion   BOOLEAN         := FALSE
        ,p_break_col                BINARY_INTEGER  := NULL
        ,p_grid_lines               BOOLEAN         := TRUE
        ,p_num_format               VARCHAR2        := 'tm9'
        ,p_date_format              VARCHAR2        := 'MM/DD/YYYY'
        ,p_interval_format          VARCHAR2        := NULL
    ) IS
        v_sql                       app_dbms_sql_str_udt;
    BEGIN
        v_sql := app_dbms_sql_str_udt(
            p_cursor                => p_src
            ,p_default_num_fmt      => p_num_format
            ,p_default_date_fmt     => p_date_format
            ,p_default_interval_fmt => p_interval_format
        );
        IF p_formats IS NOT NULL AND p_formats.COUNT > 0 THEN
            DECLARE
                l_i BINARY_INTEGER := p_formats.first;
            BEGIN
                WHILE l_i IS NOT NULL
                LOOP
                    v_sql.set_fmt(p_col_index => l_i, p_fmt => p_formats(l_i));
                    l_i := p_formats.next(l_i);
                END LOOP;
            END;
        END IF;
        cursor2table(v_sql, p_widths, p_headers, p_bold_headers, p_char_widths_conversion, p_break_col, p_grid_lines);
    END refcursor2table
    ;

    PROCEDURE refcursor2table(
        p_src                       SYS_REFCURSOR
        ,p_col_headers              BOOLEAN         := FALSE
        ,p_break_col                BINARY_INTEGER  := NULL
        ,p_grid_lines               BOOLEAN         := TRUE
        ,p_num_format               VARCHAR2        := 'tm9'
        ,p_date_format              VARCHAR2        := 'MM/DD/YYYY'
        ,p_interval_format          VARCHAR2        := NULL
    ) IS
        v_sql                       app_dbms_sql_str_udt;
        v_widths                    t_col_widths;
        v_headers                   t_col_headers;
        v_col_names                 arr_varchar2_udt;
    BEGIN
        v_sql := app_dbms_sql_str_udt(
            p_cursor                => p_src
            ,p_default_num_fmt      => p_num_format
            ,p_default_date_fmt     => p_date_format
            ,p_default_interval_fmt => p_interval_format
        );
        IF p_col_headers THEN
            v_col_names := v_sql.get_column_names;
            FOR i IN 1..v_col_names.COUNT
            LOOP
                v_widths(i) := LENGTH(v_col_names(i)) + 1;
                v_headers(i) := v_col_names(i);
            END LOOP;
        END IF;
        cursor2table(v_sql
                ,CASE WHEN p_col_headers THEN v_widths END
                ,CASE WHEN p_col_headers THEN v_headers END
                ,p_col_headers -- bold
                ,TRUE
                ,p_break_col, p_grid_lines
        );
    END refcursor2table
    ;
END PdfGen;
/
show errors
