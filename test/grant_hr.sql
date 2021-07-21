create role hr_select;
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
            ||' to hr_select';
    end loop;
end;
/
prompt grant hr_select to yourschemaname;
--grant hr_select to lee;
grant select on hr.employees to lee;
grant select on hr.departments to lee;
--select * from dba_tab_privs where grantee = 'HR_SELECT';
