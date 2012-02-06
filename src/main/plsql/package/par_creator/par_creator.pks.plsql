create or replace package par_creator
as

    procedure new_par(p_name varchar2);
    
    procedure add_procedure(p_name varchar2);

    procedure add_function(p_name varchar2);
    
    procedure add_package(p_name varchar2, p_spec boolean default true, p_body boolean default true);
    
    procedure add_type(p_name varchar2, p_spec boolean default true, p_body boolean default true);
    
    procedure add_java_class(p_name varchar2);
    
    procedure add_java_source(p_name varchar2);
    
    procedure add_java_resource(p_name varchar2);
    
    procedure add_xdb_file(p_path varchar2, p_base_path varchar2 default '/');
    
    procedure close_par;
    
    function get_par_spec
    return dbms_sql.varchar2a;
    
    function get_par_body
    return dbms_sql.varchar2a;
    
    procedure compile_par;
    
end;
/