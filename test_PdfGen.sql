-- Represents my test cases but also an example of how to use it.
-- Explorers margins and borders along with exercising callback, headers
-- footers and 0 width hidden column.
--
-- You may need to grant select on hr.employees and hr.departments to your schema owner
-- If you even have that schema installed.
-- This block checks and if available will compile test0 into the package.
--
set serveroutput on
DECLARE
    l_t varchar2(128);
BEGIN
    SELECT table_name INTO l_t FROM user_tab_privs WHERE owner = 'HR' AND table_name = 'DEPARTMENTS' AND privilege = 'SELECT';
    SELECT table_name INTO l_t FROM user_tab_privs WHERE owner = 'HR' AND table_name = 'EMPLOYEES' AND privilege = 'SELECT';
    DBMS_OUTPUT.put_line('found select on hr.departments and hr.employees so compiling test0 function');
    EXECUTE IMMEDIATE q'[ALTER SESSION SET PLSQL_CCFLAGS='have_hr_schema_select:TRUE']';
EXCEPTION WHEN OTHERS THEN
    DBMS_OUTPUT.put_line('grant select on hr.employees and hr.departments to your schema owner if you want to see test0');
END;
/
CREATE OR REPLACE PACKAGE test_PdfGen 
AS
-- select test_PdfGen.test1 from dual;
-- Double click on the BLOB column in the results in sqldeveloper (toad is similar).
-- click on the pencil icon. Choose Download. Save the file as "x.pdf" or whatever.pdf.
-- open in pdf viewer.
--
$if $$have_hr_schema_select $then
    FUNCTION test0 RETURN BLOB;
$end
    FUNCTION test1 RETURN BLOB;
    FUNCTION test2 RETURN BLOB;
    FUNCTION test3 RETURN BLOB;
    FUNCTION test_margins(p_page_format VARCHAR2, p_page_orientation VARCHAR2) RETURN BLOB;
    PROCEDURE apply_page_header(
        p_txt           VARCHAR2
        ,p_page_nr      NUMBER
        ,p_page_count   NUMBER
        ,p_page_val     VARCHAR2
    );
END test_PdfGen;
/
show errors
CREATE OR REPLACE PACKAGE BODY test_PdfGen AS
    PROCEDURE apply_page_header(
        p_txt           VARCHAR2
        ,p_page_nr      NUMBER
        ,p_page_count   NUMBER
        ,p_page_val     VARCHAR2
    ) IS
        --
        -- a callback procedure that produces a multi-line page header with page specific substitutions.
        -- It writes in the top "margin" which is overloaded to mean the section of the page that is
        -- above where the report rows are written. It is your responsibility to ensure you do not go
        -- off the page and that the margin is large enough. See set_page_format.
        --
        v_txt           VARCHAR2(400);
        c_padding   CONSTANT NUMBER := 2;
        c_rf        CONSTANT NUMBER := 0.2; -- raise factor. Anton uses the term. spacing for parts of font below 0?
    BEGIN
        v_txt := REPLACE(
                    REPLACE(
                        REPLACE(p_txt, '#PAGE_NR#', LTRIM(TO_CHAR(p_page_nr)))
                        ,'"PAGE_COUNT#', LTRIM(TO_CHAR(p_page_count)))
                    ,'!PAGE_VAL#', p_page_val
                );
        as_pdf3.set_font('helvetica','b',18);
        as_pdf3.put_txt(p_txt => v_txt
            ,p_x => PdfGen.x_center(v_txt)
            ,p_y => PdfGen.y_top_margin 
                + (14 * (1 + c_rf)) + c_padding + (18 * c_rf) + c_padding
        );
        v_txt := REPLACE(
                    REPLACE(
                        REPLACE('Page_Nr=#PAGE_NR# Page_Count="PAGE_COUNT# page_val=!PAGE_VAL#', '#PAGE_NR#', LTRIM(TO_CHAR(p_page_nr)))
                        ,'"PAGE_COUNT#', LTRIM(TO_CHAR(p_page_count)))
                    ,'!PAGE_VAL#', p_page_val
                );
        as_pdf3.set_font('helvetica','b',14);
        as_pdf3.put_txt(p_txt => v_txt
            ,p_x => PdfGen.x_center(v_txt)
            --,p_x => PdfGen.x_left_justify
            ,p_y => PdfGen.y_top_margin
                + (c_rf * 14) + c_padding
        );
    END apply_page_header;

$if $$have_hr_schema_select $then
   FUNCTION test0 RETURN BLOB
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
            ,p_centered_2    => FALSE -- left align
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
        BEGIN
            CLOSE v_src;
        EXCEPTION WHEN invalid_cursor THEN NULL;
        END;


        v_src := get_src;
        as_pdf3.new_page; 
        PdfGen.refcursor2table(
            p_src => v_src
            ,p_widths => v_widths, p_headers => v_headers
            ,p_bold_headers => FALSE, p_char_widths_conversion => TRUE
            ,p_break_col => 4
            ,p_grid_lines => TRUE
        );
        BEGIN
            CLOSE v_src;
        EXCEPTION WHEN invalid_cursor THEN NULL;
        END;

        v_blob := PdfGen.get_pdf;
        RETURN v_blob;
    END test0;
$end

FUNCTION test1
RETURN BLOB
-- use query column names for headers and column width.
-- use custom page header callback
AS
    v_src   SYS_REFCURSOR;
    v_blob  BLOB;
    FUNCTION l_getsrc RETURN SYS_REFCURSOR
    IS
        l_src SYS_REFCURSOR;
    BEGIN
      OPEN l_src FOR
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
        RETURN l_src;
    END;
BEGIN

    PdfGen.init;
    PdfGen.set_page_format('LETTER','PORTRAIT');
    PdfGen.set_footer('Page #PAGE_NR# of "PAGE_COUNT#', p_centered => FALSE);
    PdfGen.set_header(p_txt => 'Data Dictionary Views Letter Portrait'
                    ,p_txt_2 => 'For page=1 bold heders and not grid. Page2 has grid, no headers, no col widths so evenly distributed'
                    ,p_centered_2 => FALSE
                    ,p_fontsize_pt_2 => 8
    );

    -- just so we can see the margins
    as_pdf3.rect(as_pdf3.get(as_pdf3.c_get_margin_left), as_pdf3.get(as_pdf3.c_get_margin_bottom)
            ,as_pdf3.get(as_pdf3.c_get_page_width) - as_pdf3.get(as_pdf3.c_get_margin_right) - as_pdf3.get(as_pdf3.c_get_margin_left)
            ,as_pdf3.get(as_pdf3.c_get_page_height) - as_pdf3.get(as_pdf3.c_get_margin_top) - as_pdf3.get(as_pdf3.c_get_margin_bottom)
        );

    as_pdf3.set_font('courier', 'n', 10);
    v_src := l_getsrc;
    PdfGen.refcursor2table(p_src => v_src
        ,p_col_headers => TRUE
        ,p_grid_lines => FALSE
    );
    BEGIN
        CLOSE v_src;
    EXCEPTION WHEN invalid_cursor THEN NULL;
    END;

    v_src := l_getsrc;
    as_pdf3.new_page; 
    PdfGen.refcursor2table(p_src => v_src
        ,p_col_headers => FALSE
        ,p_grid_lines => TRUE
    );
    BEGIN
        CLOSE v_src;
    EXCEPTION WHEN invalid_cursor THEN NULL;

    END;
    v_blob := PdfGen.get_pdf;
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
    -- :page_val will come from a column break value named "GRP" in the query (column 3)
    PdfGen.set_page_proc(q'[BEGIN test_PdfGen.apply_page_header(p_txt => 'Data Dictionary Views Legal Landscape', p_page_nr => :page_nr, p_page_count => :page_count, p_page_val => :page_val); END;]');
    -- just so we can see the margins
    as_pdf3.rect(as_pdf3.get(as_pdf3.c_get_margin_left), as_pdf3.get(as_pdf3.c_get_margin_bottom)
            ,as_pdf3.get(as_pdf3.c_get_page_width) - as_pdf3.get(as_pdf3.c_get_margin_right) - as_pdf3.get(as_pdf3.c_get_margin_left)
            ,as_pdf3.get(as_pdf3.c_get_page_height) - as_pdf3.get(as_pdf3.c_get_margin_top) - as_pdf3.get(as_pdf3.c_get_margin_bottom)
        );

    as_pdf3.set_font('courier', 'n', 10);
    PdfGen.refcursor2table(p_src => v_src, p_widths => v_widths, p_headers => v_headers
        ,p_bold_headers => TRUE, p_char_widths_conversion => TRUE
        ,p_break_col => 3
        --,p_grid_lines => FALSE
    );
    v_blob := PdfGen.get_pdf;
    BEGIN
        CLOSE v_src;
    EXCEPTION WHEN invalid_cursor THEN NULL;
    END;
    RETURN v_blob;
END test2
;

   FUNCTION test3 RETURN BLOB
    IS
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
        --
        v_headers(1) := 'DBA View Name';
        v_widths(1)  := 31;
        v_headers(2) := 'Dictionary Comments';
        v_widths(2)  := 102;
        -- will not print this column, just capture it for column page break
        v_headers(3) := NULL;
        v_widths(3)  := 0;
        --
        PdfGen.init;
        PdfGen.set_page_format('LEGAL','LANDSCAPE');
        PdfGen.set_footer('Page #PAGE_NR# of "PAGE_COUNT#');
        PdfGen.set_header('Data Dictionary Views for group !PAGE_VAL#');
        --
        -- just so we can see the margins. Not a general practice
        as_pdf3.rect(as_pdf3.get(as_pdf3.c_get_margin_left), as_pdf3.get(as_pdf3.c_get_margin_bottom)
                ,as_pdf3.get(as_pdf3.c_get_page_width) - as_pdf3.get(as_pdf3.c_get_margin_right) - as_pdf3.get(as_pdf3.c_get_margin_left)
                ,as_pdf3.get(as_pdf3.c_get_page_height) - as_pdf3.get(as_pdf3.c_get_margin_top) - as_pdf3.get(as_pdf3.c_get_margin_bottom)
            );
        --
        as_pdf3.set_font('courier', 'n', 10);
        PdfGen.refcursor2table(p_src => v_src
            ,p_widths => v_widths, p_headers => v_headers
            ,p_bold_headers => TRUE, p_char_widths_conversion => TRUE
            ,p_break_col => 3
            --,p_grid_lines => FALSE
        );
        v_blob := PdfGen.get_pdf;
        BEGIN
            CLOSE v_src;
        EXCEPTION WHEN invalid_cursor THEN NULL;
        END;
        RETURN v_blob;
    END test3;


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
show errors
