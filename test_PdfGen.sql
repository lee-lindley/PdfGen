-- Represents my test cases but also an example of how to use it.
-- Explorers margins and borders along with exercising callback, headers
-- footers and 0 width hidden column.
CREATE OR REPLACE PACKAGE test_PdfGen AS
-- select test_PdfGen.test1 from dual;
-- Double click on the BLOB column in the results in sqldeveloper (toad is similar).
-- click on the pencil icon. Choose Download. Save the file as "x.pdf" or whatever.pdf.
-- open in pdf viewer.
--
    FUNCTION test1 RETURN BLOB;
    FUNCTION test2 RETURN BLOB;
    FUNCTION test_margins(p_page_format VARCHAR2, p_page_orientation VARCHAR2) RETURN BLOB;
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
        --
        -- a callback procedure that produces a multi-line page header with page specific substitutions.
        -- It writes in the top "margin" which is overloaded to mean the section of the page that is
        -- above where the report rows are written. It is your responsibility to ensure you do not go
        -- off the page and that the margin is large enough. See set_page_format.
        --
        v_txt           VARCHAR2(400);
        v_half_width    NUMBER;
        c_padding   CONSTANT NUMBER := 2;
        c_rf        CONSTANT NUMBER := 0.2; -- raise factor. Anton uses the term. spacing for parts of font below 0?
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
            ,p_y => (as_pdf3.get(as_pdf3.c_get_page_height) - as_pdf3.get(as_pdf3.c_get_margin_top)) 
                + (14 * (1 + c_rf)) + c_padding + (18 * c_rf) + c_padding
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
            ,p_y => (as_pdf3.get(as_pdf3.c_get_page_height) - as_pdf3.get(as_pdf3.c_get_margin_top)) 
                + (c_rf * 14) + c_padding
        );
    END apply_page_header;

FUNCTION test1
RETURN BLOB
-- use query column names for headers and column width.
-- use custom page header callback
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
            ,grp AS
"grp"
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
    PdfGen.init;
    PdfGen.set_page_format('LETTER','PORTRAIT');
    PdfGen.set_footer('Page #PAGE_NR# of "PAGE_COUNT#', p_centered => FALSE);
    PdfGen.set_header(p_txt => 'Data Dictionary Views Letter Portrait'
                    ,p_txt_2 => 'Page_Nr=#PAGE_NR# Page_Count="PAGE_COUNT# page_val=!PAGE_VAL#'
                    ,p_centered_2 => FALSE
    );

    -- just so we can see the margins
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
END test1
;
FUNCTION test2
RETURN BLOB
-- use explicit column headers and column widths
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

    v_headers(1) := 'DBA View Name';
    v_widths(1) := 31;
    v_headers(2) := 'Dictionary Comments';
    v_widths(2) := 102;
    -- will not print this column, just capture it for column page break
    v_headers(3) := NULL;
    v_widths(3) := 0;

    PdfGen.init;
    PdfGen.set_page_format('LEGAL','LANDSCAPE');
    PdfGen.set_footer('Page #PAGE_NR# of "PAGE_COUNT#');
    --PdfGen.set_header('Data Dictionary Views');
    -- !PAGE_VAL# will come from a column break value named "GRP" in the query (column 3)
    PdfGen.set_page_proc(q'[BEGIN test_PdfGen.apply_page_header(p_txt => 'Data Dictionary Views Legal Landscape', p_page_nr => '#PAGE_NR#', p_page_count => '"PAGE_COUNT#', p_page_val => q'~!PAGE_VAL#~'); END;]');
    -- just so we can see the margins
    as_pdf3.rect(as_pdf3.get(as_pdf3.c_get_margin_left), as_pdf3.get(as_pdf3.c_get_margin_bottom)
            ,as_pdf3.get(as_pdf3.c_get_page_width) - as_pdf3.get(as_pdf3.c_get_margin_right) - as_pdf3.get(as_pdf3.c_get_margin_left)
            ,as_pdf3.get(as_pdf3.c_get_page_height) - as_pdf3.get(as_pdf3.c_get_margin_top) - as_pdf3.get(as_pdf3.c_get_margin_bottom)
        );

    as_pdf3.set_font('courier', 'n', 10);
    PdfGen.refcursor2table(p_src => v_src, p_widths => v_widths, p_headers => v_headers
        ,p_bold_headers => TRUE, p_char_widths_conversion => TRUE
        ,p_break_col => 3
        ,p_grid_lines => FALSE
    );
    v_blob := PdfGen.get_pdf;
    BEGIN
        CLOSE v_src;
    EXCEPTION WHEN invalid_cursor THEN NULL;
    END;
    RETURN v_blob;
END test2
;

FUNCTION test_margins(
    p_page_format VARCHAR2, p_page_orientation VARCHAR2
)
RETURN BLOB
AS
    v_blob  BLOB;
BEGIN
    PdfGen.init;
    PdfGen.set_page_format(p_page_format, p_page_orientation); 
    PdfGen.set_footer;
    PdfGen.set_header('Margin '||p_page_format||' '||p_page_orientation);
    as_pdf3.rect(as_pdf3.get(as_pdf3.c_get_margin_left), as_pdf3.get(as_pdf3.c_get_margin_bottom)
            ,as_pdf3.get(as_pdf3.c_get_page_width) - as_pdf3.get(as_pdf3.c_get_margin_right) - as_pdf3.get(as_pdf3.c_get_margin_left)
            ,as_pdf3.get(as_pdf3.c_get_page_height) - as_pdf3.get(as_pdf3.c_get_margin_top) - as_pdf3.get(as_pdf3.c_get_margin_bottom)
        );
    v_blob := PdfGen.get_pdf;
    RETURN v_blob;
END test_margins;

END test_PdfGen;
/
