create or replace package body par_template
as
       v_zip_content blob;
       
       type vc_arr is table of varchar2(32767) index by binary_integer;
     
       function split(p_buffer varchar2, p_sep varchar2)
       return vc_arr
       is
            idx      pls_integer;
            list     varchar2(32767) := p_buffer;
            splits   vc_arr;
            cnt      pls_integer:=1;
       begin
    
            if p_buffer is null then
              return splits;
            end if;
    
            loop
                idx := instr(list,p_sep);
                if idx > 0 then
                    splits(cnt):= substr(list,1,idx-1);
                    cnt:=cnt+1;
                    list := substr(list,idx+length(p_sep));
                else
                    splits(cnt):= list;
                    exit;
                end if;
            end loop;
            return splits;
       end split;
     
      --
      function blob2num( p_blob blob, p_len integer, p_pos integer )
      return number
      is
      begin
        return utl_raw.cast_to_binary_integer( dbms_lob.substr( p_blob, p_len, p_pos ), utl_raw.little_endian );
      end;
      --
      function raw2varchar2( p_raw raw, p_encoding varchar2 )
      return varchar2
      is
      begin
        return nvl( utl_i18n.raw_to_char( p_raw, p_encoding )
                  , utl_i18n.raw_to_char( p_raw, utl_i18n.map_charset( p_encoding, utl_i18n.GENERIC_CONTEXT, utl_i18n.IANA_TO_ORACLE ) )
                  );
      end;
      --
      function get_file_list
        ( p_zipped_blob blob
        , p_encoding varchar2 := null
        )
      return file_list
      is
        t_ind integer;
        t_hd_ind integer;
        t_rv file_list;
      begin
        t_ind := dbms_lob.getlength( p_zipped_blob ) - 21;
        loop
          exit when dbms_lob.substr( p_zipped_blob, 4, t_ind ) = hextoraw( '504B0506' ) or t_ind < 1;
          t_ind := t_ind - 1;
        end loop;
      --
        if t_ind <= 0
        then
          return null;
        end if;
      --
        t_hd_ind := blob2num( p_zipped_blob, 4, t_ind + 16 ) + 1;
        t_rv := file_list();
        t_rv.extend( blob2num( p_zipped_blob, 2, t_ind + 10 ) );
        for i in 1 .. blob2num( p_zipped_blob, 2, t_ind + 8 )
        loop
          t_rv( i ) := raw2varchar2
                         ( dbms_lob.substr( p_zipped_blob
                                          , blob2num( p_zipped_blob, 2, t_hd_ind + 28 )
                                          , t_hd_ind + 46
                                          )
                         , p_encoding
                         );
          t_hd_ind := t_hd_ind + 46
                    + blob2num( p_zipped_blob, 2, t_hd_ind + 28 )
                    + blob2num( p_zipped_blob, 2, t_hd_ind + 30 )
                    + blob2num( p_zipped_blob, 2, t_hd_ind + 32 );
        end loop;
      --
        return t_rv;
      end;
      --

      function get_file
        ( p_zipped_blob blob
        , p_file_name varchar2
        , p_encoding varchar2 := null
        )
      return blob
      is
        t_tmp blob;
        t_ind integer;
        t_hd_ind integer;
        t_fl_ind integer;
      begin
        t_ind := dbms_lob.getlength( p_zipped_blob ) - 21;
        loop
          exit when dbms_lob.substr( p_zipped_blob, 4, t_ind ) = hextoraw( '504B0506' ) or t_ind < 1;
          t_ind := t_ind - 1;
        end loop;
      --
        if t_ind <= 0
        then
          return null;
        end if;
      --
        t_hd_ind := blob2num( p_zipped_blob, 4, t_ind + 16 ) + 1;
        for i in 1 .. blob2num( p_zipped_blob, 2, t_ind + 8 )
        loop
          if p_file_name = raw2varchar2
                             ( dbms_lob.substr( p_zipped_blob
                                              , blob2num( p_zipped_blob, 2, t_hd_ind + 28 )
                                              , t_hd_ind + 46
                                              )
                             , p_encoding
                             )
          then
            if blob2num( p_zipped_blob, 4, t_hd_ind + 24 ) = 0 -- uncompressed length
            then
              if substr( p_file_name, -1 ) = '/'
              then  -- directory/folder
                return null;
              else -- empty file
                return empty_blob();
              end if;
            end if;
      --
            if dbms_lob.substr( p_zipped_blob, 2, t_hd_ind + 10 ) = hextoraw( '0800' ) -- deflate
            then
              t_fl_ind := blob2num( p_zipped_blob, 4, t_hd_ind + 42 );
              t_tmp := hextoraw( '1F8B0800000000000003' ); -- gzip header
              dbms_lob.copy( t_tmp
                           , p_zipped_blob
                           , blob2num( p_zipped_blob, 4, t_fl_ind + 19 )
                           , 11
                           , t_fl_ind + 31
                           + blob2num( p_zipped_blob, 2, t_fl_ind + 27 )
                           + blob2num( p_zipped_blob, 2, t_fl_ind + 29 )
                           );
              dbms_lob.append( t_tmp, dbms_lob.substr( p_zipped_blob, 4, t_fl_ind + 15 ) );
              dbms_lob.append( t_tmp, dbms_lob.substr( p_zipped_blob, 4, t_fl_ind + 23 ) );
              return utl_compress.lz_uncompress( t_tmp );
            end if;
      --
            if dbms_lob.substr( p_zipped_blob, 2, t_hd_ind + 10 ) = hextoraw( '0000' ) -- The file is stored (no compression)
            then
              t_fl_ind := blob2num( p_zipped_blob, 4, t_hd_ind + 42 );
              return dbms_lob.substr( p_zipped_blob
                                    , blob2num( p_zipped_blob, 4, t_fl_ind + 19 )
                                    , t_fl_ind + 31
                                    + blob2num( p_zipped_blob, 2, t_fl_ind + 27 )
                                    + blob2num( p_zipped_blob, 2, t_fl_ind + 29 )
                                    );
            end if;
          end if;
          t_hd_ind := t_hd_ind + 46
                    + blob2num( p_zipped_blob, 2, t_hd_ind + 28 )
                    + blob2num( p_zipped_blob, 2, t_hd_ind + 30 )
                    + blob2num( p_zipped_blob, 2, t_hd_ind + 32 );
        end loop;
      --
        return null;
      end;
      --
      
      function little_endian( p_big number, p_bytes pls_integer := 4 )
      return raw
      is
      begin
        return utl_raw.substr( utl_raw.cast_from_binary_integer( p_big, utl_raw.little_endian ), 1, p_bytes );
      end;
      --
  
     function decode_base64(p_clob_in in clob) 
     return blob 
     is
        v_blob blob;
        v_result blob;
        v_offset integer;
        v_buffer_size binary_integer := 48;
        v_buffer_varchar varchar2(48);
        v_buffer_raw raw(48);
      begin
        if p_clob_in is null then
          return null;
        end if;
        dbms_lob.createtemporary(v_blob, true);
        v_offset := 1;
        for i in 1 .. ceil(dbms_lob.getlength(p_clob_in) / v_buffer_size) loop
          dbms_lob.read(p_clob_in, v_buffer_size, v_offset, v_buffer_varchar);
          v_buffer_raw := utl_raw.cast_to_raw(v_buffer_varchar);
          v_buffer_raw := utl_encode.base64_decode(v_buffer_raw);
          dbms_lob.writeappend(v_blob, utl_raw.length(v_buffer_raw), v_buffer_raw);
          v_offset := v_offset + v_buffer_size;
        end loop;
        v_result := v_blob;
        dbms_lob.freetemporary(v_blob);
        return v_result;
      end decode_base64;
  
     function get_file_list
     return file_list
     as
     begin
       return get_file_list(get_content);
     end;
     
     function get_file(p_path varchar2)
     return blob
     as
     begin
       return get_file(get_content,p_path);
     end;
     
     function get_content
     return blob
     as
       v_base64    clob;
     begin
     
       if v_zip_content is not null then
         return v_zip_content;
       end if;
       
       dbms_lob.createtemporary(v_base64,true,dbms_lob.call);
       -- #CONTENT#
     
       v_zip_content:= decode_base64(v_base64);
       
       return v_zip_content;
       
     end;
     
     procedure deploy(p_skip_resolve  boolean default true, 
                      p_xdb_base_path varchar2 default '/')
     as
       v_files file_list:= get_file_list;
       v_file  varchar2(255);
       
       procedure deploy_plsql
       as
         v_content  blob:= get_file(v_file);

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
           --dump_source(p_source);
           v_cursor := dbms_sql.open_cursor;
           dbms_sql.parse(v_cursor, p_source, p_source.first, p_source.last, true, dbms_sql.native);
           dbms_sql.close_cursor(v_cursor);
         exception
          when others then
             dbms_sql.close_cursor(v_cursor);
             -- raise; no we resolve later
         end;
         
         procedure compile_source(p_source clob)
         as
            v_offset     number:= 1;
            v_pos        number;
            v_source     dbms_sql.varchar2a;
            v_length     number:= dbms_lob.getlength(p_source);
         begin
            
            v_pos:= dbms_lob.instr(p_source,chr(10),v_offset);
            
            if v_file like 'java/source/%' then
              v_source(v_source.count+1):= 'create or replace and resolve ';
            else
              v_source(v_source.count+1):= 'create or replace ';
            end if;            
            
            while v_pos > 0 loop
              v_source(v_source.count+1):= dbms_lob.substr(p_source,v_pos-v_offset,v_offset);
              v_offset:= v_pos+1;
              v_pos:= dbms_lob.instr(p_source,chr(10),v_offset);
            end loop;
            
            if v_offset < v_length then
              v_source(v_source.count+1):= dbms_lob.substr(p_source,v_length-v_offset+1,v_offset);
            end if;
            
            compile_plsql(v_source);
            
         end;
         
       begin
          
          declare
            v_content  blob:= get_file(v_file);
            v_doffset  number:= 1;
            v_soffset  number:= 1;
            v_lang_ctx integer := dbms_lob.default_lang_ctx;
            v_warning  integer;
            v_source   clob;
          begin
          
            dbms_lob.createtemporary(v_source,true,dbms_lob.call);
            
            dbms_lob.converttoclob(v_source,
                                   v_content,
                                   dbms_lob.getlength(v_content),
                                   v_doffset,
                                   v_soffset,
                                   dbms_lob.default_csid,
                                   v_lang_ctx,
                                   v_warning);
            
            compile_source(v_source);
            
            dbms_lob.freetemporary(v_source);
            
          end;
          
       end;
       
       procedure deploy_java
       as
       
          procedure create_java_lob_table
          as
            v_dummy number;
          begin
          
             select 1 
               into v_dummy
               from user_tables
              where table_name= 'CREATE$JAVA$LOB$TABLE';
              
          exception
            when no_data_found then
              execute immediate 'create table create$java$lob$table (name varchar2(700 byte) unique, lob blob, loadtime date)';
          end;
       
       begin
       
          create_java_lob_table;
       
          if v_file like 'java/class/%' then
            
            declare
              v_content blob:= get_file(v_file);
              v_length  number:= instr(v_file,'.class',-1)-13;
              v_name    varchar2(255):= substr(v_file,12,v_length);
            begin
               begin
                     execute immediate 'insert into create$java$lob$table (name, lob, loadtime)
                                        values (:name, :content, sysdate)'
                                 using v_name, v_content;
               exception
                 when dup_val_on_index then
                     execute immediate 'update create$java$lob$table set lob= :content, loadtime= sysdate where name= :name'
                                 using v_content, v_name;
               end;
               
               execute immediate 'create or replace java class using '''||v_name||'''';
               
            end;            
            
          else
            
            declare
              v_content blob:= get_file(v_file);
              v_name    varchar2(255):= substr(v_file,15);
            begin
               begin
                     execute immediate 'insert into create$java$lob$table (name, lob, loadtime)
                                        values (:name, :content, sysdate)'
                                 using v_name, v_content;
               exception
                 when dup_val_on_index then
                     execute immediate 'update create$java$lob$table set lob= :content, loadtime= sysdate where name= :name'
                                 using v_content, v_name;
               end;
               
               execute immediate 'create or replace java resource named "'||v_name||'" using '''||v_name||'''';
               
            end;            
            
          end if;
       
       end;
       
       procedure deploy_xdb
       as
       
          procedure recreate_resource(p_path varchar2, p_content blob)
          as
            v_splits  vc_arr:= split(p_path,'/');
            v_path    varchar2(2000):= '';
          begin
          
                  begin  
                    dbms_xdb.deleteresource(p_path);
                  exception
                   when others then
                     null;
                  end;          
                  
                  for i in 2..(v_splits.count-1) loop
                     v_path:= v_path||'/'||v_splits(i);
                     
                     begin
                       if not dbms_xdb.createfolder(v_path) then
                         dbms_output.put_line('create folder returned false for: '||v_path);
                       end if;
                     exception
                      when others then
                        null;
                     end;
                     
                  end loop;
          
          
                  if not dbms_xdb.createresource(p_path,p_content) then
                   dbms_output.put_line('create resource returned false for: '||p_path);
                  end if;
          end;
       
       begin
       
          recreate_resource(p_xdb_base_path||substr(v_file,5),get_file(v_file));
       
       end;
       
       procedure compile_and_resolve
       as
           procedure compile_plsql
           as
              v_type  varchar2(30):= substr(v_file,7,instr(v_file,'/',1,2)-1);
              v_body  boolean:= false;
              
              function get_name
              return varchar2
              as
                 v_start  pls_integer:= instr(v_file,'/',-1)+1;
                 v_end    pls_integer:= instr(v_file,'.',v_start)-1;
              begin
              
                 v_body:= (substr(v_file,v_end+2,3) in ('pkb','tpb'));
              
                 return substr(v_file,v_start,v_end-v_start);
              
              end;
              
           begin
              if not v_body then
                execute immediate 'alter '||v_type||' '||get_name||' compile';
              end if;
           end;
           
           procedure compile_java
           as
             v_start  pls_integer:= instr(v_file,'/',-1)+1;
             v_end    pls_integer:= instr(v_file,'.',-1)-1;
             v_name   varchar2(255):= substr(v_file,v_start,v_start-v_end);
           begin
             if v_file like 'java/class/%' then
               execute immediate 'alter java class "'||v_name||'" resolve';
             else
               execute immediate 'alter java source "'||v_name||'" compile';
               execute immediate 'alter java source "'||v_name||'" resolve';
             end if;
           end;
           
       begin
           for i in 1..v_files.count loop
           
             v_file:= v_files(i);
             
             if v_file like 'plsql/%' then
               compile_plsql;
             elsif v_file like 'java/%' then
               compile_java;
             end if;
           
           end loop;
       end;
       
     begin
       
       for i in 1..v_files.count loop
       
         v_file:= v_files(i);
         
         if v_file like 'plsql/%' or v_file like 'java/source/%' then
           deploy_plsql;
         elsif v_file like 'java/%' then
           deploy_java;
         elsif v_file like 'xdb/%' then
           deploy_xdb;
         end if;
       
       end loop;
       
       if not p_skip_resolve then
         compile_and_resolve;
       end if;
       
     end;

end;
/