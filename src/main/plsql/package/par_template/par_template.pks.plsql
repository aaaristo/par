create or replace package par_template
as
     
     DEFAULT_XDB_BASE  constant varchar2(255):= '/public/'||lower(user)||'/';

     type file_list is table of clob;
     
     function get_file(p_path varchar2)
     return blob;
     
     function get_file_list
     return file_list;
     
     function get_content
     return blob;
     
     procedure deploy(p_skip_resolve  boolean default true, 
                      p_xdb_base_path varchar2 default DEFAULT_XDB_BASE);

     -- grants required to deploy:
     -- plsql procedures: grant create procedure to <user>
     -- java objects: grant create procedure, create table, javauserpriv to <user>
     -- xdb files: no privilege needed

end;
/
