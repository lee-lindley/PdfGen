prompt Enter name of schema where you will deploy test_PdfGen when prompted
GRANT SELECT ON hr.employees TO &&deploy_test_schema;
GRANT SELECT ON hr.departments TO &&deploy_test_schema;
/*
begin
    for r in (
        select 't' as t, table_name from dba_tables where owner = 'HR'
        union all
        select 'v' as t, view_name as table_name from dba_views where owner = 'HR'
    )
    loop
        execute immediate 'grant select'
            ||case when r.t = 't' then ',insert,update,delete' end
            ||' on hr.'
            ||r.table_name
            ||' to '||&deploy_test_schema;
    end loop;
end;
/
*/
