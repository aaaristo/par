create or replace package body par_template
as

      type vc_arr is table of varchar2(32767) index by binary_integer;
     
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
       
       dbms_lob.createtemporary(v_base64,true,dbms_lob.call);
       -- #CONTENT#
     
       return decode_base64(v_base64);
       
     end;
     
     procedure deploy
     as
     begin
       null;
     end;

end;
/