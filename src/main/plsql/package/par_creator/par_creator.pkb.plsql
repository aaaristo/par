create or replace package body par_creator
as

    v_name        varchar2(27);
    v_zip         blob;    

    procedure new_par(p_name varchar2)
    as
    begin
       v_name:= p_name;
       dbms_lob.createtemporary(v_zip,true,dbms_lob.call);
    end;
    
    procedure add_file(p_path varchar2, p_content blob)
    as
    begin
      as_zip.add1file(v_zip, p_path, p_content);
    end;
    
    procedure add_plsql(p_name varchar, p_type varchar2)
    as
      v_source  clob;
      
      function get_ext
      return varchar2
      as
      begin
      
         if p_type = 'procedure' then
           return 'prc';
         elsif p_type = 'function' then
           return 'fnc';
         elsif p_type = 'package' then
           return 'pks';
         elsif p_type = 'package body' then
           return 'pkb';
         elsif p_type = 'package' then
           return 'tps';
         elsif p_type = 'package body' then
           return 'tpb';
         else
           raise_application_error(-20001,'Unknown object type: '||p_type);
         end if;
         
      end;
    begin
    
      dbms_lob.createtemporary(v_source,true,dbms_lob.call);
      
      for c_cur in (select text, line
                      from user_source
                     where type= upper(p_type)
                       and name= upper(p_name)
                  order by line)
      loop
        dbms_lob.writeappend(v_source,length(c_cur.text),c_cur.text);
      end loop;

      
      declare
        v_content blob;
        v_doffset number:= 1;
        v_soffset number:= 1;
        v_lang_ctx integer := dbms_lob.default_lang_ctx;
        v_warning integer;
      begin
      
        dbms_lob.createtemporary(v_content,true,dbms_lob.call);
        
        dbms_lob.converttoblob(v_content,
                               v_source,
                               dbms_lob.getlength(v_source),
                               v_doffset,
                               v_soffset,
                               dbms_lob.default_csid,
                               v_lang_ctx,
                               v_warning);
        
        if p_type like 'package%' or p_type like 'type%' then
          add_file('plsql/'||replace(p_type,' body','')||'/'||p_name||'/'||p_name||'.'||get_ext||'.plsql',v_content);
        else
          add_file('plsql/'||p_type||'/'||p_name||'.'||get_ext||'.plsql',v_content);
        end if;
        
        dbms_lob.freetemporary(v_content);
        
      end;
      
    end;
    
    procedure add_procedure(p_name varchar2)
    as
    begin
      add_plsql(p_name, 'procedure');
    end;

    procedure add_function(p_name varchar2)
    as
    begin
      add_plsql(p_name, 'function');
    end;
    
    procedure add_package(p_name varchar2, p_spec boolean default true, p_body boolean default true)
    as
    begin
    
      if p_spec then
        add_plsql(p_name, 'package');
      end if;
      
      if p_body then
        add_plsql(p_name, 'package body');
      end if;
      
    end;
    
    procedure add_type(p_name varchar2, p_spec boolean default true, p_body boolean default true)
    as
    begin
    
      if p_spec then
        add_plsql(p_name, 'type');
      end if;
      
      if p_body then
        add_plsql(p_name, 'type body');
      end if;
      
    end;
    
    procedure add_java_class(p_name varchar2)
    as
      v_content  blob;
    begin
      dbms_lob.createtemporary(v_content,true,dbms_lob.call);    
      dbms_java.export_class(p_name, v_content);
      add_file('java/class/'||p_name||'.class',v_content);
      dbms_lob.freetemporary(v_content);      
    end;
    
    procedure add_java_source(p_name varchar2)
    as
      v_content  blob;
    begin
      dbms_lob.createtemporary(v_content,true,dbms_lob.call);    
      dbms_java.export_source(p_name, v_content);
      add_file('java/source/'||p_name||'.java',v_content);
      dbms_lob.freetemporary(v_content);      
    end;
    
    procedure add_java_resource(p_name varchar2)
    as
      v_content  blob;
    begin
      dbms_lob.createtemporary(v_content,true,dbms_lob.call);    
      dbms_java.export_resource(p_name, v_content);
      add_file('java/resource/'||p_name,v_content);
      dbms_lob.freetemporary(v_content);      
    end;
    
    procedure add_xdb_file(p_path varchar2, p_base_path varchar2 default par_template.DEFAULT_XDB_BASE)
    as
      v_content  blob;
    begin
      select XDBURIType(p_base_path||p_path).getBlob() into v_content from dual;
      if v_content is not null and dbms_lob.getlength(v_content) > 0 then
        add_file('xdb/'||p_path,v_content);
      end if;
    end;
    
    procedure close_par
    as
    begin
       as_zip.finish_zip(v_zip);
    end;
    
    function get_par_spec
    return dbms_sql.varchar2a
    as
       v_source       dbms_sql.varchar2a;
    begin
    
      v_source(v_source.count+1):= 'create or replace ';

      for c_cur in (select text
                      from user_source
                     where type= 'PACKAGE'
                       and name= 'PAR_TEMPLATE'
                  order by line)
      loop
        v_source(v_source.count+1):= replace(replace(c_cur.text,'par_template','par_'||v_name),chr(10),'');
      end loop;
    
      return v_source;
      
    end;
    
    function get_par_body
    return dbms_sql.varchar2a
    as
       v_content_lines   dbms_sql.varchar2a;
       v_source          dbms_sql.varchar2a;
       v_base64          clob;
       
       procedure process_base64
       as
          v_amount   number:= 2000;
          v_offset   number:= 1;
          v_buffer   varchar2(2000);
          
          procedure add_line
          as
          begin
            v_content_lines(v_content_lines.count+1):= '       dbms_lob.writeappend(v_base64, '||v_amount||', '''||v_buffer||''');';
          end;
          
       begin
       
         dbms_lob.read(v_base64,v_amount,v_offset,v_buffer);
         
         while v_amount = 2000 loop
            add_line;
            v_offset:= v_offset+v_amount;
            dbms_lob.read(v_base64,v_amount,v_offset,v_buffer);
         end loop;
         
         if v_amount > 0 then
            add_line;
         end if;
         
       end;
       
       procedure process_package
       as
       begin
          v_source(v_source.count+1):= 'create or replace ';
          
          for c_cur in (select text
                          from user_source
                         where type= 'PACKAGE BODY'
                           and name= 'PAR_TEMPLATE'
                      order by line)
          loop
            if c_cur.text like '%#CONTENT#%' then
                for i in 1..v_content_lines.count loop
                   v_source(v_source.count+1):= v_content_lines(i);
                end loop;
            else
                v_source(v_source.count+1):= replace(replace(c_cur.text,'par_template','par_'||v_name),chr(10),'');
            end if;
          end loop;
    
       end;
       
    begin
       v_base64:= utl_base64.encode_base64(v_zip);
       process_base64;
       process_package;
       return v_source;
    end;
    
    procedure compile_par
    as
       procedure dump_source(p_source dbms_sql.varchar2a)
       as
       begin
         for i in 1..p_source.count loop
          dbms_output.put_line(p_source(i));
         end loop;
       end;
       procedure compile_plsql(p_source dbms_sql.varchar2a)
       as
         v_cursor      pls_integer;
       begin
         dump_source(p_source);
         v_cursor := dbms_sql.open_cursor;
         dbms_sql.parse(v_cursor, p_source, p_source.first, p_source.last, true, dbms_sql.native);
         dbms_sql.close_cursor(v_cursor);
       exception
        when others then
           dbms_sql.close_cursor(v_cursor);
           raise;
       end;
    begin
       compile_plsql(get_par_spec);
       compile_plsql(get_par_body);
       dbms_lob.freetemporary(v_zip);
    end;
    
end;
/
