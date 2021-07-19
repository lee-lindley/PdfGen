prompt when all is over you will want to drop packages test_PdfGen and table test_PdfGen_t
whenever sqlerror continue
drop table test_pdfgen_t;
whenever sqlerror exit failure
create table test_pdfgen_t as 
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
        ) v
        ;
CREATE OR REPLACE PACKAGE test_PdfGen AS
    FUNCTION test_PdfGen1 RETURN BLOB;
    FUNCTION test_PdfGen2 RETURN BLOB;
    FUNCTION test_PdfGen_margins(p_page_format VARCHAR2, p_page_orientation VARCHAR2) RETURN BLOB;
    FUNCTION test_PdfGen_header(
        p_page_format VARCHAR2, p_page_orientation VARCHAR2
    ) RETURN BLOB;
    PROCEDURE apply_page_header(
        p_txt           VARCHAR2
        ,p_page_nr      VARCHAR2
        ,p_page_count   VARCHAR2
        ,p_page_val     VARCHAR2
    );

END test_PdfGen;
/
CREATE OR REPLACE PACKAGE BODY test_PdfGen AS
    PROCEDURE apply_page_header(
        p_txt           VARCHAR2
        ,p_page_nr      VARCHAR2
        ,p_page_count   VARCHAR2
        ,p_page_val     VARCHAR2
    ) IS
        v_txt           VARCHAR2(32767);
        v_half_width    NUMBER;
    BEGIN
        v_txt := REPLACE(
                    REPLACE(
                        REPLACE(p_txt, '#PAGE_NR#', p_page_nr)
                        ,'"PAGE_COUNT#', p_page_count)
                    ,'!PAGE_VAL#', p_page_val
                );
        as_pdf3.set_font('helvetica','b',18);
        v_half_width := as_pdf3.str_len(v_txt) / 2.0;
        as_pdf3.put_txt(p_txt => v_txt
            ,p_x => (as_pdf3.get(as_pdf3.c_get_page_width) / 2.0) - v_half_width
            ,p_y => (as_pdf3.get(as_pdf3.c_get_page_height) - as_pdf3.get(as_pdf3.c_get_margin_top)) + 18 + 14
        );
        v_txt := REPLACE(
                    REPLACE(
                        REPLACE('Page_Nr=#PAGE_NR# Page_Count="PAGE_COUNT# page_val=!PAGE_VAL#', '#PAGE_NR#', p_page_nr)
                        ,'"PAGE_COUNT#', p_page_count)
                    ,'!PAGE_VAL#', p_page_val
                );
        as_pdf3.set_font('helvetica','b',14);
        v_half_width := as_pdf3.str_len(v_txt) / 2.0;
        as_pdf3.put_txt(p_txt => v_txt
            ,p_x => (as_pdf3.get(as_pdf3.c_get_page_width) / 2.0) - v_half_width
            --,p_x => as_pdf3.get(as_pdf3.c_get_margin_left)
            ,p_y => (as_pdf3.get(as_pdf3.c_get_page_height) - as_pdf3.get(as_pdf3.c_get_margin_top)) + 14
        );
    END apply_page_header;

FUNCTION test_PdfGen1
RETURN BLOB
AS
    v_src   SYS_REFCURSOR;
    v_blob  BLOB;
BEGIN
    OPEN v_src FOR
        SELECT 
            view_name AS 
"Dictionary View Name          "
            ,SUBSTR(comments,1,30) AS 
"Comments                      "
        FROM test_pdfgen_t
        ORDER BY view_name
        FETCH FIRST 40 ROWS ONLY
        ;
    PdfGen.init;
    PdfGen.set_page_format('LETTER','LANDSCAPE');
    PdfGen.set_footer('Page #PAGE_NR# of "PAGE_COUNT#');
    --PdfGen.set_header('Data Dictionary Views');
    PdfGen.set_page_proc(q'~BEGIN test_PdfGen.apply_page_header(p_txt => 'Data Dictionary Views Letter Portrait', p_page_nr => '#PAGE_NR#', p_page_count => '"PAGE_COUNT#', p_page_val => '!PAGE_VAL#'); END;~');
    as_pdf3.rect(as_pdf3.get(as_pdf3.c_get_margin_left), as_pdf3.get(as_pdf3.c_get_margin_bottom)
            ,as_pdf3.get(as_pdf3.c_get_page_width) - as_pdf3.get(as_pdf3.c_get_margin_right) - as_pdf3.get(as_pdf3.c_get_margin_left)
            ,as_pdf3.get(as_pdf3.c_get_page_height) - as_pdf3.get(as_pdf3.c_get_margin_top) - as_pdf3.get(as_pdf3.c_get_margin_bottom)
        );
    as_pdf3.set_font('courier', 'n', 10);
    PdfGen.refcursor2table(p_src => v_src, p_col_headers => TRUE);
    v_blob := PdfGen.get_pdf;
    BEGIN
        CLOSE v_src;
    EXCEPTION WHEN invalid_cursor THEN NULL;
    END;
    RETURN v_blob;
END test_PdfGen1;

FUNCTION test_PdfGen2
RETURN BLOB
AS
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
        FROM test_pdfgen_t
        ORDER BY view_name
        FETCH FIRST 55 ROWS ONLY
        ;
      RETURN l_src;
    END;
BEGIN
    v_src := get_src;

    v_headers(1) := 'DBA View Name';
    v_widths(1) := 31;
    v_headers(2) := 'Dictionary Comments';
    v_widths(2) := 102;
    v_headers(3) := 'Grp';
    v_widths(3) := 4;

    PdfGen.init;
    PdfGen.set_page_format('LEGAL','LANDSCAPE');
    PdfGen.set_footer('Page #PAGE_NR# of "PAGE_COUNT#');
    --PdfGen.set_header('Data Dictionary Views');
    PdfGen.set_page_proc(q'~BEGIN test_PdfGen.apply_page_header(p_txt => 'Data Dictionary Views Letter Portrait', p_page_nr => '#PAGE_NR#', p_page_count => '"PAGE_COUNT#', p_page_val => '!PAGE_VAL#'); END;~');
    as_pdf3.rect(as_pdf3.get(as_pdf3.c_get_margin_left), as_pdf3.get(as_pdf3.c_get_margin_bottom)
            ,as_pdf3.get(as_pdf3.c_get_page_width) - as_pdf3.get(as_pdf3.c_get_margin_right) - as_pdf3.get(as_pdf3.c_get_margin_left)
            ,as_pdf3.get(as_pdf3.c_get_page_height) - as_pdf3.get(as_pdf3.c_get_margin_top) - as_pdf3.get(as_pdf3.c_get_margin_bottom)
        );
    as_pdf3.set_font('courier', 'n', 10);

    PdfGen.refcursor2table(p_src => v_src, p_widths => v_widths, p_headers => v_headers
        ,p_bold_headers => TRUE, p_char_widths_conversion => TRUE
        ,p_break_col => 3
    );
    v_blob := PdfGen.get_pdf;
    BEGIN
        CLOSE v_src;
    EXCEPTION WHEN invalid_cursor THEN NULL;
    END;
    RETURN v_blob;
END test_PdfGen2;

FUNCTION test_PdfGen_margins(
    p_page_format VARCHAR2, p_page_orientation VARCHAR2
)
RETURN BLOB
AS
    v_blob  BLOB;
BEGIN
    PdfGen.init;
    PdfGen.set_page_format(p_page_format, p_page_orientation); 
    PdfGen.set_footer('Page #PAGE_NR# of "PAGE_COUNT#');
    PdfGen.set_header('Margin '||p_page_format||' '||p_page_orientation);
    as_pdf3.rect(as_pdf3.get(as_pdf3.c_get_margin_left), as_pdf3.get(as_pdf3.c_get_margin_bottom)
            ,as_pdf3.get(as_pdf3.c_get_page_width) - as_pdf3.get(as_pdf3.c_get_margin_right) - as_pdf3.get(as_pdf3.c_get_margin_left)
            ,as_pdf3.get(as_pdf3.c_get_page_height) - as_pdf3.get(as_pdf3.c_get_margin_top) - as_pdf3.get(as_pdf3.c_get_margin_bottom)
        );
    v_blob := PdfGen.get_pdf;
    RETURN v_blob;
END test_PdfGen_margins;

FUNCTION test_PdfGen_header(
    p_page_format VARCHAR2, p_page_orientation VARCHAR2
)
RETURN BLOB
AS
    v_blob  BLOB;
BEGIN
    PdfGen.init;
    PdfGen.set_page_format(p_page_format, p_page_orientation); 
    PdfGen.set_footer('Page #PAGE_NR# of "PAGE_COUNT#');
    PdfGen.set_page_proc(q'~BEGIN test_PdfGen.apply_page_header(p_txt => 'Margin ~'
        ||p_page_format||' '||p_page_orientation
        ||q'~', p_page_nr => '#PAGE_NR#', p_page_count => '"PAGE_COUNT#', p_page_val => '!PAGE_VAL#'); END;~');
    

    as_pdf3.rect(as_pdf3.get(as_pdf3.c_get_margin_left), as_pdf3.get(as_pdf3.c_get_margin_bottom)
            ,as_pdf3.get(as_pdf3.c_get_page_width) - as_pdf3.get(as_pdf3.c_get_margin_right) - as_pdf3.get(as_pdf3.c_get_margin_left)
            ,as_pdf3.get(as_pdf3.c_get_page_height) - as_pdf3.get(as_pdf3.c_get_margin_top) - as_pdf3.get(as_pdf3.c_get_margin_bottom)
        );
    v_blob := PdfGen.get_pdf;
    RETURN v_blob;
END test_PdfGen_header;

END test_PdfGen;
/
prompt when all is over you will want to drop packages test_PdfGen and table test_PdfGen_t
