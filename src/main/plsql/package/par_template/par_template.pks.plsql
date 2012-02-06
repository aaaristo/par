create or replace package par_template
as
     
     type file_list is table of clob;
     
     function get_file(p_path varchar2)
     return blob;
     
     function get_file_list
     return file_list;
     
     function get_content
     return blob;
     
     procedure deploy;

end;
/